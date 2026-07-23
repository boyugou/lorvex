//! Acquire / release / boundary semantics for `try_acquire_sync_owner`
//! and `release_sync_owner`. Includes the strict-less-than expiry
//! boundary, concurrent-race determinism, stale-lease recovery, the
//! per-process owner-id isolation contract, and the wall-clock
//! constructor's empty-lease path.

use super::support::*;

#[test]
fn first_owner_acquires_empty_lease() {
    let conn = test_conn();

    let acquired = try_acquire_sync_owner(&conn, "sync_transport", "app", 1_000, 500)
        .expect("acquire sync owner");
    assert!(acquired);
    assert_eq!(
        current_sync_owner(&conn, "sync_transport")
            .expect("load owner")
            .expect("owner present")
            .owner_id,
        "app"
    );
}

#[test]
fn non_owner_cannot_take_live_lease() {
    let conn = test_conn();
    try_acquire_sync_owner(&conn, "sync_transport", "app", 1_000, 500).expect("seed owner");

    let acquired = try_acquire_sync_owner(&conn, "sync_transport", "cli", 1_200, 500)
        .expect("attempt competing owner");
    assert!(!acquired);
}

#[test]
fn expired_lease_can_be_taken_by_new_owner() {
    let conn = test_conn();
    try_acquire_sync_owner(&conn, "filesystem_bridge", "app", 1_000, 100).expect("seed owner");

    let acquired = try_acquire_sync_owner(&conn, "filesystem_bridge", "cli", 1_101, 100)
        .expect("take expired lease");
    assert!(acquired);
    assert_eq!(
        current_sync_owner(&conn, "filesystem_bridge")
            .expect("load owner")
            .expect("owner present")
            .owner_id,
        "cli"
    );
}

#[test]
fn same_owner_can_renew_lease() {
    let conn = test_conn();
    try_acquire_sync_owner(&conn, "filesystem_bridge", "app", 1_000, 500).expect("initial acquire");

    // Same owner renews before expiry
    let acquired =
        try_acquire_sync_owner(&conn, "filesystem_bridge", "app", 1_200, 500).expect("renew lease");
    assert!(acquired);

    let lease = current_sync_owner(&conn, "filesystem_bridge")
        .expect("load owner")
        .expect("owner present");
    assert_eq!(lease.owner_id, "app");
    assert_eq!(lease.expires_at_epoch_ms, 1_700); // 1200 + 500
}

#[test]
fn release_removes_lease() {
    let conn = test_conn();
    try_acquire_sync_owner(&conn, "filesystem_bridge", "app", 1_000, 500).expect("acquire");

    let released = release_sync_owner(&conn, "filesystem_bridge", "app").expect("release");
    assert!(released);

    let owner = current_sync_owner(&conn, "filesystem_bridge").expect("load");
    assert!(owner.is_none());
}

#[test]
fn release_by_wrong_owner_does_nothing() {
    let conn = test_conn();
    try_acquire_sync_owner(&conn, "filesystem_bridge", "app", 1_000, 500).expect("acquire");

    let released = release_sync_owner(&conn, "filesystem_bridge", "cli")
        .expect("attempt release by wrong owner");
    assert!(!released);

    // Original owner still holds
    let owner = current_sync_owner(&conn, "filesystem_bridge")
        .expect("load")
        .expect("still held");
    assert_eq!(owner.owner_id, "app");
}

#[test]
fn independent_leases_do_not_interfere() {
    let conn = test_conn();
    try_acquire_sync_owner(&conn, "sync_transport", "app", 1_000, 500)
        .expect("acquire sync transport");
    try_acquire_sync_owner(&conn, "filesystem_bridge", "cli", 1_000, 500)
        .expect("acquire fs bridge");

    let transport = current_sync_owner(&conn, "sync_transport")
        .expect("load sync transport")
        .expect("present");
    let fs = current_sync_owner(&conn, "filesystem_bridge")
        .expect("load fs bridge")
        .expect("present");

    assert_eq!(transport.owner_id, "app");
    assert_eq!(fs.owner_id, "cli");
}

#[test]
fn concurrent_acquirers_race_resolves_deterministically() {
    // Cross-process TOCTOU regression: two surfaces each observe no
    // current owner, both call `try_acquire_sync_owner`. The first
    // call's INSERT wins; the second must see the freshly-inserted
    // row and return false because the owner_id differs. Pre-fix,
    // both returned true and the row was clobbered by the loser.
    let conn = test_conn();

    let first =
        try_acquire_sync_owner(&conn, "sync_transport", "app", 1_000, 500).expect("first acquirer");
    let second = try_acquire_sync_owner(&conn, "sync_transport", "cli", 1_000, 500)
        .expect("second acquirer (same ms)");

    assert!(first);
    assert!(!second);
    let held = current_sync_owner(&conn, "sync_transport")
        .expect("load")
        .expect("owner present");
    assert_eq!(held.owner_id, "app");
}

/// the expiry predicate is strict-less-than.
/// At `expires_at_epoch_ms == now_ms` the prior owner still holds
/// the lease — a competing acquire at the exact boundary must
/// report failure.
#[test]
fn boundary_expiry_belongs_to_prior_owner() {
    let conn = test_conn();
    try_acquire_sync_owner(&conn, "filesystem_bridge", "app", 1_000, 100).expect("seed");

    // Expiry is at 1_100; competitor at exactly 1_100 must lose.
    let acquired = try_acquire_sync_owner(&conn, "filesystem_bridge", "cli", 1_100, 100)
        .expect("competitor acquire at boundary");
    assert!(
        !acquired,
        "at exactly expires_at_epoch_ms == now, the prior owner still holds"
    );

    let lease = current_sync_owner(&conn, "filesystem_bridge")
        .expect("load")
        .expect("present");
    assert_eq!(lease.owner_id, "app");
}

/// Issue #2982-RT-H9 companion: one tick past expiry, the
/// competitor MUST be able to take the lease.
#[test]
fn one_ms_past_expiry_admits_competitor() {
    let conn = test_conn();
    try_acquire_sync_owner(&conn, "filesystem_bridge", "app", 1_000, 100).expect("seed");

    let acquired = try_acquire_sync_owner(&conn, "filesystem_bridge", "cli", 1_101, 100)
        .expect("competitor at boundary + 1");
    assert!(acquired);
    assert_eq!(
        current_sync_owner(&conn, "filesystem_bridge")
            .expect("load")
            .expect("present")
            .owner_id,
        "cli"
    );
}

/// the production-wired
/// `try_acquire_sync_owner_now` constructor reads the wall clock
/// internally and never trusts a caller-supplied timestamp.
/// First-call acquisition must succeed against an empty row.
#[test]
fn try_acquire_sync_owner_now_acquires_empty_lease() {
    let conn = test_conn();
    let acquired = try_acquire_sync_owner_now(&conn, "sync_transport", "app", 500)
        .expect("acquire via wall clock");
    assert!(acquired);
}

///: two acquirers that compose
/// `<role>:<UUIDv7>` via `process_owner_id` must NOT collide on
/// release the way two static-string `"desktop_app"` acquirers
/// would. This test simulates the race where process A's RAII
/// `Drop` fires after process B has already re-acquired the
/// expired lease — without the per-process suffix, A's release
/// would delete B's freshly-installed row.
#[test]
fn distinct_process_owner_ids_isolate_release_to_their_own_acquire() {
    let conn = test_conn();
    // Two distinct process-instance ids — what `process_owner_id`
    // produces for two separate desktop-app processes.
    let process_a = "desktop_app:proc-a";
    let process_b = "desktop_app:proc-b";

    // Process A acquires, lease expires (TTL 100 ms, now + 200 ms
    // is past expiry).
    try_acquire_sync_owner(&conn, "sync_transport", process_a, 1_000, 100)
        .expect("process A acquires");

    // Process B re-acquires the expired lease.
    let acquired_b = try_acquire_sync_owner(&conn, "sync_transport", process_b, 1_200, 600)
        .expect("process B re-acquires expired lease");
    assert!(acquired_b);

    // Process A's stale `Drop` fires NOW: release using process A's
    // owner id. Pre-fix this DELETE matched the row regardless of
    // expiry (the static-string `"desktop_app"` collision); the
    // per-process owner id makes the WHERE arm reject because the
    // row's `owner_id` is now process B's.
    let released_a =
        release_sync_owner(&conn, "sync_transport", process_a).expect("process A stale release");
    assert!(
        !released_a,
        "process A's stale Drop must not delete process B's row"
    );

    // Process B's lease must still be alive.
    let lease = current_sync_owner(&conn, "sync_transport")
        .expect("load lease")
        .expect("process B's lease must survive");
    assert_eq!(lease.owner_id, process_b);
}

#[test]
fn stale_lease_recovery_after_crash() {
    let conn = test_conn();
    // App acquired but then crashed (lease expired, never released)
    try_acquire_sync_owner(&conn, "filesystem_bridge", "app", 1_000, 100)
        .expect("app acquires before crash");

    // Much later, CLI comes up and takes over the stale lease
    let acquired = try_acquire_sync_owner(&conn, "filesystem_bridge", "cli", 5_000, 500)
        .expect("cli takes stale lease");
    assert!(acquired);
    assert_eq!(
        current_sync_owner(&conn, "filesystem_bridge")
            .expect("load")
            .expect("present")
            .owner_id,
        "cli"
    );
}
