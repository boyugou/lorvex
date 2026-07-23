//! Lightweight event bus for broadcasting data-change notifications to all
//! Tauri webview windows.

use crate::event_channels;
use lorvex_domain::naming::EntityKind;
use serde::Serialize;
use std::sync::OnceLock;
use tauri::{AppHandle, Emitter};

static APP_HANDLE: OnceLock<AppHandle> = OnceLock::new();

#[cfg(test)]
static TEST_EMITTED_DATA_CHANGED: std::sync::Mutex<Vec<Entity>> = std::sync::Mutex::new(Vec::new());

pub fn init(handle: AppHandle) {
    // `OnceLock::set` returns `Err` only if the slot
    // was already populated. The Tauri `setup` callback runs exactly
    // once per process and is the sole caller, so the second-set case
    // happens only in test re-entry. Treating it as a no-op is
    // intentional — the first-installed handle stays authoritative
    // and emits remain routed to the live webview.
    let _ = APP_HANDLE.set(handle);
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Entity {
    Task,
    List,
    CalendarEvent,
    Habit,
    DailyReview,
    Preference,
    Changelog,
    AiMemory,
    DataImport,
    Planning,
}

impl Entity {
    /// Map a workflow-layer `entity_kind()` wire tag to the bus
    /// variant whose React Query invalidation it should drive.
    ///
    /// This is the canonical mapping every `Mutation` descriptor
    /// inherits via the executor — callers no longer pass a parallel
    /// `event_bus::Entity` argument that could disagree with the
    /// descriptor's own `entity_kind()`. The mapping mirrors the
    /// sync-apply side's private helper (peer writes funnel to the
    /// same React Query channels as local writes); both route through
    /// [`Self::from_parsed_entity_kind`] so adding a new `ENTITY_*`
    /// constant forces an explicit classification at the compile-time
    /// `match` rather than silently falling through to `None`.
    ///
    /// Returns `None` for entity kinds that have no UI surface to
    /// invalidate (audit-only / local-only kinds). Mutation
    /// descriptors that target these kinds must call
    /// `event_bus::emit_data_changed` explicitly with the right
    /// variant, or skip the emit entirely.
    pub fn from_entity_kind(entity_kind: &str) -> Option<Self> {
        let parsed = EntityKind::try_parse(entity_kind).ok()?;
        Self::from_parsed_entity_kind(parsed)
    }

    pub(crate) const fn from_parsed_entity_kind(kind: EntityKind) -> Option<Self> {
        Some(match kind {
            EntityKind::Task
            | EntityKind::TaskChecklistItem
            | EntityKind::TaskReminder
            | EntityKind::TaskCalendarEventLink
            | EntityKind::TaskProviderEventLink
            | EntityKind::Tag
            | EntityKind::TaskTag
            | EntityKind::TaskDependency => Self::Task,
            EntityKind::List => Self::List,
            EntityKind::CalendarEvent => Self::CalendarEvent,
            EntityKind::Habit | EntityKind::HabitCompletion | EntityKind::HabitReminderPolicy => {
                Self::Habit
            }
            EntityKind::DailyReview => Self::DailyReview,
            EntityKind::FocusSchedule | EntityKind::CurrentFocus => Self::Planning,
            EntityKind::Preference | EntityKind::DeviceState => Self::Preference,
            EntityKind::Memory | EntityKind::MemoryRevision => Self::AiMemory,
            EntityKind::AiChangelog => Self::Changelog,
            EntityKind::CalendarSubscription => Self::CalendarEvent,
            EntityKind::SavedQuery | EntityKind::ImportSession => return None,
        })
    }
}

#[derive(Debug, Clone, Serialize)]
struct DataChangedPayload {
    entity: Entity,
}

pub fn emit_data_changed(entity: Entity) {
    #[cfg(test)]
    {
        TEST_EMITTED_DATA_CHANGED
            .lock()
            .expect("lock emitted data_changed test buffer")
            .push(entity);
    }
    if let Some(handle) = APP_HANDLE.get() {
        // `Emitter::emit` returns `tauri::Result` only
        // because payload serialization can fail. `DataChangedPayload`
        // is a tiny `Copy`-friendly struct of `serde`-derived primitives
        // — serialization is total — and the underlying IPC fan-out is
        // already best-effort (a closed webview channel is not an error
        // worth surfacing). Suppressing the Result keeps the contract
        // crisp: data-changed notifications are fire-and-forget.
        let _ = handle.emit(event_channels::DATA_CHANGED, DataChangedPayload { entity });
    }
}

/// Severity of a sync-notice toast bubbled up to the UI.
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
#[allow(dead_code)] // frontend keeps the sync-notice channel; no producer is active in local-only Tauri.
pub enum SyncNoticeKind {
    /// Informational — sync succeeded after an automatic recovery step.
    Info,
}

#[derive(Debug, Clone, Serialize)]
#[allow(dead_code)] // serialized only when emit_sync_notice is re-enabled for provider-neutral sync recovery.
struct SyncNoticePayload {
    kind: SyncNoticeKind,
    /// i18n key; the frontend resolves this against the active locale.
    i18n_key: String,
}

/// Emit a sync-recovery notice toast. The frontend subscribes to
/// `lorvex://sync-notice` and resolves `i18n_key` against its active
/// locale bundle (see `app/src/locales`).
#[allow(dead_code)] // reserved event surface; current Tauri build has no cloud-sync recovery producer.
pub fn emit_sync_notice(kind: SyncNoticeKind, i18n_key: &str) {
    if let Some(handle) = APP_HANDLE.get() {
        // same fire-and-forget contract as
        // `emit_data_changed`. The payload is serde-derived from a
        // primitive enum + `String`, so `emit`'s only failure mode is
        // closed-channel — non-actionable for a transient toast hint.
        let _ = handle.emit(
            event_channels::SYNC_NOTICE,
            SyncNoticePayload {
                kind,
                i18n_key: i18n_key.to_string(),
            },
        );
    }
}

/// surface a "reset all data" hard failure to the UI so
/// the toast path can distinguish it from the success path.
///
/// Fires when the reset transaction itself rolled back (DB-side reset
/// failed or the `catch_unwind` body panicked). The frontend leaves the
/// user in an unambiguous "reset failed, your data is intact" state;
/// without this typed event the only signal would be the unconditional
/// success `data-changed` events, and the UI would claim everything was
/// wiped when nothing was.
#[derive(Debug, Clone, Serialize)]
pub struct DataResetFailedPayload {
    /// Human-readable failure reason. Surfaced verbatim in the toast.
    pub reason: String,
    /// `true` when the DB-side reset rolled back and no data was wiped.
    pub rolled_back: bool,
}

pub fn emit_data_reset_failed(payload: DataResetFailedPayload) {
    if let Some(handle) = APP_HANDLE.get() {
        // same fire-and-forget contract. The
        // command-level result already carries the actionable error
        // (the IPC caller observes the failure), so the parallel
        // event emit is purely a UX nicety — surfacing a toast even
        // when the command result has already been consumed by
        // upstream code.
        let _ = handle.emit(event_channels::DATA_RESET_FAILED, payload);
    }
}

#[cfg(test)]
pub fn clear_test_emitted_data_changed() {
    TEST_EMITTED_DATA_CHANGED
        .lock()
        .expect("lock emitted data_changed test buffer")
        .clear();
}

#[cfg(test)]
pub fn take_test_emitted_data_changed() -> Vec<Entity> {
    std::mem::take(
        &mut *TEST_EMITTED_DATA_CHANGED
            .lock()
            .expect("lock emitted data_changed test buffer"),
    )
}

// sync progress channel.
#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
#[allow(dead_code)] // Pull/Apply are part of the progress wire shape; local-only flows currently emit Push/Idle.
pub enum SyncProgressPhase {
    Push,
    Pull,
    Apply,
    Idle,
}

#[derive(Debug, Clone, Serialize)]
struct SyncProgressPayload {
    phase: SyncProgressPhase,
    current: i64,
    total: i64,
    cycle_id: String,
}

// the cycle id is a logical scope (one sync cycle at a
// time, process-wide), not a thread scope. The earlier `thread_local!`
// implementation silently dropped progress events whenever sync code
// crossed a thread boundary — `tokio::spawn`, `spawn_blocking`,
// `rayon::spawn`, the fs-bridge watcher coalescer thread, or even an
// `await` that resumed on a different worker. A process-wide `RwLock`
// is the right shape: emit_sync_progress is hot but only reads, and
// the begin/Drop pair writes once at cycle boundaries. `RwLock` over
// `Mutex` so concurrent emits across spawned tasks don't serialize.
static ACTIVE_SYNC_CYCLE_ID: std::sync::RwLock<Option<String>> = std::sync::RwLock::new(None);

#[cfg(test)]
static TEST_EMITTED_SYNC_PROGRESS: std::sync::Mutex<Vec<(String, SyncProgressPhase, i64, i64)>> =
    std::sync::Mutex::new(Vec::new());

/// `#[must_use]` so binding the guard to `_`
/// or letting it become a temporary fires a compiler warning. The
/// guard MUST live for the duration of the sync cycle; dropping it
/// immediately clears `ACTIVE_SYNC_CYCLE_ID` and silently routes
/// every subsequent `emit_sync_progress` event into the void.
#[must_use = "binding the guard to `_` immediately ends the sync cycle; \
              keep it bound to a name for the cycle's full lifetime"]
pub struct SyncCycleGuard {
    /// snapshot the value the cycle slot held BEFORE we
    /// installed our cycle id, and restore it on drop. Today the
    /// orchestrator forbids nesting, but recording the predecessor
    /// makes the Drop semantics obviously correct under any future
    /// caller that nests intentionally — the inner guard's drop will
    /// reinstate the outer cycle rather than nulling it out.
    previous: Option<String>,
}

impl Drop for SyncCycleGuard {
    fn drop(&mut self) {
        match ACTIVE_SYNC_CYCLE_ID.write() {
            Ok(mut slot) => *slot = self.previous.take(),
            Err(poisoned) => {
                // The lock is poisoned because some other emit panicked
                // mid-write. Recover the inner slot and restore the
                // previous cycle id anyway — losing progress events on
                // a subsequent cycle is worse than retaining a poisoned
                // lock.
                let mut slot = poisoned.into_inner();
                *slot = self.previous.take();
                ACTIVE_SYNC_CYCLE_ID.clear_poison();
            }
        }
    }
}

/// start a new sync-progress cycle in the
/// current process. The returned guard restores the previous cycle id
/// on drop (including via `?`-style unwind), so any intentionally
/// nested cycle re-surfaces correctly. Emit helpers below no-op when
/// no cycle is active — auto-sync cycles that omit this guard never
/// surface progress events in the UI.
pub fn begin_sync_cycle() -> SyncCycleGuard {
    let cycle_id = uuid::Uuid::now_v7().simple().to_string();
    let previous = match ACTIVE_SYNC_CYCLE_ID.write() {
        Ok(mut slot) => slot.replace(cycle_id),
        Err(poisoned) => {
            let mut slot = poisoned.into_inner();
            let previous = slot.replace(cycle_id);
            ACTIVE_SYNC_CYCLE_ID.clear_poison();
            previous
        }
    };
    SyncCycleGuard { previous }
}

fn current_sync_cycle_id() -> Option<String> {
    match ACTIVE_SYNC_CYCLE_ID.read() {
        Ok(slot) => slot.clone(),
        Err(poisoned) => {
            // Read-side recovery: the writer panicked, but the value
            // we'd read is still meaningful. Drop poison so the next
            // legitimate access doesn't have to re-clear it.
            let snapshot = poisoned.into_inner().clone();
            ACTIVE_SYNC_CYCLE_ID.clear_poison();
            snapshot
        }
    }
}

/// best-effort emit of a sync-progress event. Silently
/// drops the event when no cycle is active; never blocks the caller.
pub fn emit_sync_progress(phase: SyncProgressPhase, current: i64, total: i64) {
    let Some(cycle_id) = current_sync_cycle_id() else {
        return;
    };
    #[cfg(test)]
    {
        TEST_EMITTED_SYNC_PROGRESS
            .lock()
            .expect("lock emitted sync_progress test buffer")
            .push((cycle_id.clone(), phase, current, total));
    }
    if let Some(handle) = APP_HANDLE.get() {
        // progress events are inherently best-effort
        // — the UI re-renders from the next progress tick, so a
        // single dropped emit (closed channel, transient IPC hiccup)
        // is invisible to the user. The actionable signal is whether
        // the cycle completes; this emit feeds only the progress bar.
        let _ = handle.emit(
            event_channels::SYNC_PROGRESS,
            SyncProgressPayload {
                phase,
                current,
                total,
                cycle_id,
            },
        );
    }
}

#[cfg(test)]
fn take_test_emitted_sync_progress() -> Vec<(String, SyncProgressPhase, i64, i64)> {
    std::mem::take(
        &mut *TEST_EMITTED_SYNC_PROGRESS
            .lock()
            .expect("lock emitted sync_progress test buffer"),
    )
}

#[cfg(test)]
mod sync_progress_tests {
    use super::*;

    /// serialize cycle-state tests so concurrent runs
    /// don't trample one another's slot.
    ///
    /// the explicit
    /// `clear_poison()` before `into_inner()` is deliberate. Other
    /// poison-recovery sites in the codebase (HLC, focus session,
    /// streak cache) just call `into_inner()` and let the lock stay
    /// flagged-as-poisoned for diagnostic value. Here, the lock is
    /// the test-isolation primitive itself — a stale poison flag
    /// would confuse any future test author who instruments the lock
    /// for "why did the previous test panic?" diagnostics. Clearing
    /// the flag lets each test start from a clean slate; we still
    /// recover with `into_inner()` so a panic in test N does not
    /// wedge tests N+1..N+M.
    fn cycle_test_lock() -> std::sync::MutexGuard<'static, ()> {
        static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
        LOCK.lock().unwrap_or_else(|p| {
            LOCK.clear_poison();
            p.into_inner()
        })
    }

    fn reset_cycle_state() {
        if let Ok(mut slot) = ACTIVE_SYNC_CYCLE_ID.write() {
            *slot = None;
        }
    }

    #[test]
    fn emit_is_noop_when_no_cycle_is_active() {
        let _serial = cycle_test_lock();
        reset_cycle_state();
        let _ = take_test_emitted_sync_progress();
        emit_sync_progress(SyncProgressPhase::Push, 0, 10);
        let events = take_test_emitted_sync_progress();
        assert!(
            events.is_empty(),
            "emit outside a cycle must be a silent no-op, got {events:?}"
        );
    }

    #[test]
    fn guard_scopes_emissions_to_its_lifetime() {
        let _serial = cycle_test_lock();
        reset_cycle_state();
        let _ = take_test_emitted_sync_progress();
        {
            let _guard = begin_sync_cycle();
            emit_sync_progress(SyncProgressPhase::Push, 1, 5);
            emit_sync_progress(SyncProgressPhase::Apply, 3, 5);
        }
        emit_sync_progress(SyncProgressPhase::Pull, 0, 0);
        let events = take_test_emitted_sync_progress();
        assert_eq!(events.len(), 2, "only in-cycle emits should record");
        assert_eq!(events[0].1, SyncProgressPhase::Push);
        assert_eq!(events[0].2, 1);
        assert_eq!(events[0].3, 5);
        assert_eq!(events[1].1, SyncProgressPhase::Apply);
    }

    /// the previous `thread_local!` implementation
    /// silently dropped any emit that crossed a thread boundary
    /// (`tokio::spawn`, `spawn_blocking`, the fs-bridge watcher
    /// coalescer, etc.). The process-wide RwLock makes the cycle id
    /// visible from any thread; this test pins the contract.
    #[test]
    fn emits_cross_thread_under_active_cycle() {
        let _serial = cycle_test_lock();
        reset_cycle_state();
        let _ = take_test_emitted_sync_progress();
        let _cycle = begin_sync_cycle();
        let snapshot = std::thread::spawn(|| {
            emit_sync_progress(SyncProgressPhase::Push, 1, 1);
            current_sync_cycle_id()
        })
        .join()
        .expect("spawned thread joined");
        assert!(
            snapshot.is_some(),
            "spawned thread must observe the active cycle id"
        );
        let events = take_test_emitted_sync_progress();
        assert_eq!(events.len(), 1, "spawned-thread emit must reach the buffer");
        assert_eq!(events[0].1, SyncProgressPhase::Push);
    }

    /// the guard's `Drop` saves and restores the previous
    /// cycle id. A naive `*slot = None` drop would null out an outer
    /// cycle when an inner guard drops. Today the orchestrator forbids
    /// nesting, but pinning the restore semantics keeps that future
    /// safe.
    #[test]
    fn nested_guard_restores_outer_cycle_id() {
        let _serial = cycle_test_lock();
        reset_cycle_state();
        let outer = begin_sync_cycle();
        let outer_id = current_sync_cycle_id().expect("outer id present");
        {
            let _inner = begin_sync_cycle();
            let inner_id = current_sync_cycle_id().expect("inner id present");
            assert_ne!(inner_id, outer_id, "inner cycle id must differ from outer");
        }
        assert_eq!(
            current_sync_cycle_id().as_deref(),
            Some(outer_id.as_str()),
            "outer cycle id must be restored after inner guard drops"
        );
        drop(outer);
        assert!(
            current_sync_cycle_id().is_none(),
            "outer drop must clear the slot"
        );
    }
}
