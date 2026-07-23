//! Process-wide pending diagnostics queue. Filled by `resolve_db_path`
//! (which discards the diagnostics field on the resolver output) and
//! drained by app/CLI bootstrap via `take_db_location_diagnostics`.
//!
//! The queue is bounded so a non-app embedding (test harness, CLI
//! integration test) that calls `resolve_db_path` repeatedly without
//! ever draining cannot grow it without bound for the process
//! lifetime.

use std::sync::{Mutex, OnceLock};

use super::types::DbLocationDiagnostic;

static PENDING_DB_LOCATION_DIAGNOSTICS: OnceLock<Mutex<Vec<DbLocationDiagnostic>>> =
    OnceLock::new();

/// Hard cap on the pending-diagnostics queue. The bootstrap path is
/// supposed to drain it via `take_db_location_diagnostics` once at app
/// boot, but a non-app embedding (test harness, CLI integration test)
/// that calls `resolve_db_path` repeatedly without ever draining
/// would otherwise grow the queue without bound for the process
/// lifetime. 64 entries fits any realistic single-boot diagnostic
/// fan-out (each call site enqueues ≤2 entries) while keeping the
/// worst-case memory footprint trivially small.
const PENDING_DB_DIAGNOSTICS_CAP: usize = 64;

pub(super) fn enqueue_db_location_diagnostics(diagnostics: Vec<DbLocationDiagnostic>) {
    if diagnostics.is_empty() {
        return;
    }
    let mut guard = pending_db_location_diagnostics()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    // Cap the queue. If we're already at or above the cap, drop the
    // newest enqueue silently — the pre-existing diagnostics are
    // strictly more useful (closer to the actual boot resolution that
    // the operator wants to inspect) than the stragglers from a
    // long-lived embedding that never drains.
    let remaining = PENDING_DB_DIAGNOSTICS_CAP.saturating_sub(guard.len());
    if remaining == 0 {
        return;
    }
    if diagnostics.len() <= remaining {
        guard.extend(diagnostics);
    } else {
        guard.extend(diagnostics.into_iter().take(remaining));
    }
}

pub(super) fn take_db_location_diagnostics_inner() -> Vec<DbLocationDiagnostic> {
    let mut guard = pending_db_location_diagnostics()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    std::mem::take(&mut *guard)
}

fn pending_db_location_diagnostics() -> &'static Mutex<Vec<DbLocationDiagnostic>> {
    PENDING_DB_LOCATION_DIAGNOSTICS.get_or_init(|| Mutex::new(Vec::new()))
}
