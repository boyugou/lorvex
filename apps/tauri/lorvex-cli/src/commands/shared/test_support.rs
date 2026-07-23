#![cfg(test)]
//! Shared in-tree test helpers used across the `commands::mutate` submodules.

use lorvex_domain::{EventId, HabitId, HabitReminderPolicyId, ReminderId, TaskId};
use rusqlite::Connection;
use std::sync::MutexGuard;

/// Convenience: build a `TaskId` from a `&str` literal in tests, since
/// production helpers now take `&TaskId` after issue #3285. Tests can
/// keep their short `"task-id"` string literals and wrap on the call
/// boundary via `tid("…")`.
pub(crate) fn tid(s: &str) -> TaskId {
    TaskId::from_trusted(s.to_string())
}

/// Sibling of [`tid`] for `ReminderId`.
pub(crate) fn rid(s: &str) -> ReminderId {
    ReminderId::from_trusted(s.to_string())
}

/// Sibling of [`tid`] for `HabitId`.
pub(crate) fn hid(s: &str) -> HabitId {
    HabitId::from_trusted(s.to_string())
}

/// Sibling of [`tid`] for `EventId`.
pub(crate) fn eid(s: &str) -> EventId {
    EventId::from_trusted(s.to_string())
}

/// Sibling of [`tid`] for `HabitReminderPolicyId`.
pub(crate) fn hrpid(s: &str) -> HabitReminderPolicyId {
    HabitReminderPolicyId::from_trusted(s.to_string())
}

/// Insert a minimal task row into the test DB.
///
/// Thin wrapper over [`lorvex_store::test_support::fixtures::TaskBuilder`]
/// so the CLI suite shares one fixture shape with the rest of the
/// workspace. The CLI previously kept a parallel hand-rolled INSERT —
/// every schema change had to be applied in two places. The wrapper
/// preserves the legacy CLI behavior (`list_id = 'inbox'`) by
/// explicitly setting it; `defer_count` falls through to the schema's
/// `NOT NULL DEFAULT 0`, identical to the value the legacy helper
/// bound by hand.
pub(crate) fn seed_task(conn: &Connection, id: &str, title: &str, status: &str) {
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(title)
        .status(status)
        .list_id(Some("inbox"))
        .insert(conn);
}

/// RAII guard returned by [`acquire_hlc_test_state`]. Holds the
/// process-wide HLC test mutex for the entire test scope so a parallel
/// test that also mutates `HLC_STATE` cannot interleave between our
/// reset and our first `next_hlc_version` call. Drop releases the
/// mutex AND resets the HLC state again so the next test starts from
/// a clean slate regardless of how this one exited.
///
/// Pattern mirrors `crate::hlc_guard::tests` self-tests, lifted into shared
/// test-support so every `commands::mutate` test that transitively reaches
/// `next_hlc_version` (any seed/write helper that constructs a typed
/// task / list / habit / event / reminder / etc. in the in-memory db)
/// observes the same pollution-safe contract.
#[must_use = "the HLC test guard must be bound to a name for the entire test \
              body; binding to `_` releases the lock immediately and the \
              process-wide HLC_STATE pollution-safe contract is broken"]
pub(crate) struct HlcTestState {
    _guard: MutexGuard<'static, ()>,
}

impl Drop for HlcTestState {
    fn drop(&mut self) {
        // re-reset on the way out so that even a passing
        // test does not leave the previous binary's HLC state alive
        // for the next test to inherit. Tests run in parallel by
        // default; without this every test must remember to manually
        // reset both at entry and exit. Centralizing the post-test
        // reset means the call site only has to remember to acquire.
        crate::hlc_guard::reset_hlc_state_for_tests();
    }
}

/// Acquire the process-wide HLC test mutex AND reset the shared
/// `HLC_STATE` to `None`. Call this at the top of every `commands::mutate` test
/// that performs a mutation (seed / write / sync) — those mutations
/// transitively trigger `next_hlc_version`, which lazily initializes
/// from `sync_checkpoints.device_id`. Without the reset, a prior
/// test's far-future HLC pollutes the state and downstream LWW gates
/// reject the current test's writes with `VersionSuperseded`.
pub(crate) fn acquire_hlc_test_state() -> HlcTestState {
    let guard = crate::hlc_guard::hlc_test_mutex()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    crate::hlc_guard::reset_hlc_state_for_tests();
    HlcTestState { _guard: guard }
}
