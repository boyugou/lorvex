//! Layer-1 device-identity collision detection for the apply pipeline.
//!
//! A clone-DB scenario (remote restore, filesystem copy, backup-and-
//! rename) produces two peers that share the same HLC `device_suffix`
//! but disagree on the full `sync_checkpoints.device_id`. The detector
//! here surfaces that catastrophic-but-silent state via an
//! `error_logs` row, throttled by a process-global `AtomicBool` so a
//! sync batch doesn't drown the diagnostics feed.
//!
//! The sibling `device_identity.rs` module hosts the read-side helpers
//! used elsewhere in the apply pipeline (`read_local_device_hlc_suffix`).
//! This module is kept distinct because the collision-guard machinery
//! also owns a process-global state cell + its test reset hook, which
//! are unrelated to the read-side helpers.

use rusqlite::Connection;

use lorvex_domain::hlc::HlcSurface;
use lorvex_runtime::device_id_to_hlc_suffix;

use crate::envelope::SyncEnvelope;

/// Guard to log the device-identity collision warning at most once
/// per process — a clone-DB scenario would otherwise produce one
/// `error_logs` row per envelope during a sync batch, drowning the
/// diagnostic feed.
pub(super) static DEVICE_IDENTITY_COLLISION_LOGGED: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

/// serialize tests that mutate the
/// [`DEVICE_IDENTITY_COLLISION_LOGGED`] guard so their reset+seed+
/// observe roundtrips don't interleave with a parallel test's.
/// Sibling reset helper is `reset_device_identity_collision_guard_for_testing`
/// further down the file.
#[cfg(test)]
pub(crate) fn collision_test_mutex() -> &'static std::sync::Mutex<()> {
    use std::sync::{Mutex, OnceLock};
    static M: OnceLock<Mutex<()>> = OnceLock::new();
    M.get_or_init(|| Mutex::new(()))
}

/// layer 1: compare the incoming envelope's device_id
/// against the local `sync_checkpoints.device_id` when their HLC
/// suffixes match. A match on suffix + mismatch on full id is
/// overwhelmingly a cloned DB (not a random 1-in-2^32 collision on
/// an unrelated peer's `rand_b`). Write a loud error_logs entry and
/// set the guard so the rest of the sync batch stays quiet.
pub(crate) fn check_device_identity_collision(conn: &Connection, envelope: &SyncEnvelope) {
    // Cheap short-circuit: if we already logged, skip the DB read.
    //
    // the load uses
    // `Ordering::Relaxed` deliberately — this is a fast-path probe
    // that is paired with a `compare_exchange` further down the
    // function whose `AcqRel` success ordering provides the actual
    // happens-before edge for the log-once invariant. Two
    // concurrent envelopes that both observe the flag as `false`
    // here will then both contend on the CAS; exactly one wins
    // and writes the log, the other returns. A stronger ordering
    // on this load would just emit a fence on every envelope on
    // the apply hot path with no correctness benefit.
    if DEVICE_IDENTITY_COLLISION_LOGGED.load(std::sync::atomic::Ordering::Relaxed) {
        return;
    }
    let Some((local_device_id, local_suffixes)) = read_local_device_identity(conn) else {
        return;
    };
    // `envelope.version` is now typed `Hlc` at the wire
    // boundary, so this read site no longer needs a parse step.
    let envelope_hlc = &envelope.version;
    // one device produces three surface-tagged suffixes
    // (`app`, `mcp`, `cli`). A suffix collision means the envelope's
    // suffix matches **any** of the three — any of them indicates a
    // cloned DB if the full device_id then disagrees.
    if !local_suffixes
        .iter()
        .any(|s| s == envelope_hlc.device_suffix())
    {
        return;
    }
    if envelope.device_id == local_device_id {
        return;
    }
    let local_suffix = envelope_hlc.device_suffix().to_string();
    // Use compare_exchange to guarantee a single log even if two
    // threads race (the apply layer can be called concurrently by the
    // multi-backend sync runtime).
    //
    // the asymmetric
    // ordering pair is intentional. The success ordering is
    // `AcqRel` so the log-write side effects that follow this CAS
    // happen-after every prior load that observed the flag as
    // `false`; the failure ordering is `Relaxed` because a losing
    // thread immediately returns and observes nothing further. The
    // `reset_device_identity_collision_guard_for_testing` helper
    // matches with `Ordering::Release` on the reset side so a test
    // that deliberately re-arms the guard between fixtures sees a
    // happens-before edge with the next CAS attempt.
    if DEVICE_IDENTITY_COLLISION_LOGGED
        .compare_exchange(
            false,
            true,
            std::sync::atomic::Ordering::AcqRel,
            std::sync::atomic::Ordering::Relaxed,
        )
        .is_err()
    {
        return;
    }
    // soften the diagnostic copy. The "Fix: reset
    // sync_checkpoints.device_id on the cloned install" wording was
    // dangerously prescriptive — applying it to the wrong side would
    // discard whichever device the user actually wanted to keep
    // (the "original" install is unknown to us). The 3-of-3 surfaces
    // tightened in `read_local_device_identity` makes a real `rand_b`
    // collision vanishingly rare (~3 / 2^32 per envelope), so when
    // this fires it's overwhelmingly a cloned DB; still, frame the
    // remediation as advisory and require the user to identify which
    // side is the clone before resetting.
    let details = format!(
        "device_suffix={local_suffix} is shared by at least two peers. \
         local device_id={local_device_id} but envelope carries device_id={}. \
         Almost certainly a cloned/forked DB (remote restore, filesystem copy, \
         backup-and-rename). LWW ties will silently drop writes, and HLC \
         seeding will pull in the other device's max. Suggested next step: \
         identify which install is the clone (the one whose history you do \
         NOT want to keep) and regenerate `sync_checkpoints.device_id` on \
         THAT side only. Resetting the wrong side discards its writes.",
        envelope.device_id
    );
    crate::error_log::log_sync_error(
        conn,
        "sync.apply.device_collision",
        "HLC device_suffix collision between peers — sync LWW is unsafe",
        Some(&details),
    );
}

/// Read the local `sync_checkpoints.device_id` and the full set of
/// HLC suffixes this device can emit — one per [`HlcSurface`] (app,
/// mcp, cli). The collision guard at `check_device_identity_collision`
/// needs all three because a suffix collision on any surface is
/// diagnostic of a cloned DB.
pub(crate) fn read_local_device_identity(conn: &Connection) -> Option<(String, Vec<String>)> {
    let device_id: String = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'device_id'",
            [],
            |row| row.get(0),
        )
        .ok()?;
    if device_id.is_empty() {
        return None;
    }
    let suffixes: Vec<String> = HlcSurface::all()
        .iter()
        .map(|s| device_id_to_hlc_suffix(&device_id, *s))
        .collect();
    Some((device_id, suffixes))
}

#[cfg(test)]
pub(crate) fn reset_device_identity_collision_guard_for_testing() {
    DEVICE_IDENTITY_COLLISION_LOGGED.store(false, std::sync::atomic::Ordering::Release);
}
