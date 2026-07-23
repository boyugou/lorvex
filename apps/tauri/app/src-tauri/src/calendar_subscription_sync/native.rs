//! Tauri command bridges for OS-native calendar adapters.
//!
//! These are thin wrappers around the per-platform readers in
//! `crate::platform::{linux_calendar, windows_calendar}`.
//! They share residency with the ICS subscription module because
//! both surfaces feed `provider_calendar_events` rows — the storage
//! contract is identical, only the source layer differs.
//!
//! ## Sync vs. async dispatch asymmetry
//!
//! `sync_linux_calendars` is a sync `#[tauri::command]` function;
//! `sync_windows_calendars` is an `async fn` that wraps the WinRT
//! reader in `spawn_blocking`. The split is deliberate, not
//! accidental:
//!
//! * Tauri 2 dispatches a sync `#[tauri::command]` onto its dedicated
//!   IPC worker pool (see `tauri::ipc::Invoke` runtime), so a blocking
//!   call (the Linux ICS scanner walks
//!   `~/.local/share/evolution/calendar/`) doesn't stall the renderer
//!   message loop.
//! * The Windows `IAppointmentStore` API runs through WinRT's
//!   asynchronous projection. Each per-collection enumeration call
//!   composes an internal timeout, and the natural shape is `await`-
//!   based; making the outer `#[tauri::command]` `async fn` lets it
//!   compose those `IAsyncOperation`s without re-blocking on a
//!   `Runtime::block_on` reentry from the IPC worker thread. The
//!   `spawn_blocking` shifts the actual `query_calendars()` call to a
//!   dedicated blocking pool so it doesn't starve Tauri's async
//!   executor regardless of how Windows schedules the WinRT broker.
//!
//! Future refactors must not "homogenize" the pair — the Linux
//! variant relies on Tauri's blocking worker pool to absorb its
//! filesystem-scan latency, and the Windows variant relies on the
//! explicit `spawn_blocking` to bridge the WinRT/async +
//! blocking-broker divide.
//!
//! `clear_native_calendar_events` is the disable-side counterpart:
//! when the user toggles a native source off in Settings the cached
//! `provider_calendar_events` for that source must drop, otherwise
//! stale entries linger in the timeline forever.

use crate::error::{AppError, AppResult};
use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct ClearNativeCalendarEventsResult {
    pub deleted: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct NativeCalendarSyncChangeCounts {
    events_imported: i64,
    events_updated: i64,
    events_removed: i64,
}

trait NativeCalendarSyncCounts {
    fn native_calendar_sync_change_counts(&self) -> NativeCalendarSyncChangeCounts;
}

const fn native_calendar_sync_changed(counts: NativeCalendarSyncChangeCounts) -> bool {
    counts.events_imported > 0 || counts.events_updated > 0 || counts.events_removed > 0
}

fn should_emit_native_calendar_sync_changed(result: &impl NativeCalendarSyncCounts) -> bool {
    native_calendar_sync_changed(result.native_calendar_sync_change_counts())
}

fn maybe_emit_native_calendar_sync_changed(result: &impl NativeCalendarSyncCounts) {
    maybe_emit_native_calendar_sync_changed_with(result, || {
        crate::event_bus::emit_data_changed(crate::event_bus::Entity::CalendarEvent);
    });
}

fn maybe_emit_native_calendar_sync_changed_with(
    result: &impl NativeCalendarSyncCounts,
    emit: impl FnOnce(),
) {
    if should_emit_native_calendar_sync_changed(result) {
        emit();
    }
}

impl NativeCalendarSyncCounts for crate::platform::linux_calendar::reader::LinuxCalendarSyncResult {
    fn native_calendar_sync_change_counts(&self) -> NativeCalendarSyncChangeCounts {
        NativeCalendarSyncChangeCounts {
            events_imported: self.events_imported,
            events_updated: self.events_updated,
            events_removed: self.events_removed,
        }
    }
}

impl NativeCalendarSyncCounts
    for crate::platform::windows_calendar::reader::WindowsCalendarSyncResult
{
    fn native_calendar_sync_change_counts(&self) -> NativeCalendarSyncChangeCounts {
        NativeCalendarSyncChangeCounts {
            events_imported: self.events_imported,
            events_updated: self.events_updated,
            events_removed: self.events_removed,
        }
    }
}

/// Remove all provider calendar events from a native source (Linux ICS or Windows Appointments).
/// Called when the user disables native calendar sync in Settings.
#[tauri::command]
pub fn clear_native_calendar_events(
    source: String,
) -> Result<ClearNativeCalendarEventsResult, String> {
    clear_native_calendar_events_inner(source).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn clear_native_calendar_events_inner(
    source: String,
) -> AppResult<ClearNativeCalendarEventsResult> {
    let valid_sources = ["linux_ics", "windows_appointments"];
    if !valid_sources.contains(&source.as_str()) {
        return Err(AppError::Validation(format!(
            "Invalid source: {source}. Must be one of: {valid_sources:?}"
        )));
    }
    let conn = crate::db::get_conn()?;
    let deleted =
        lorvex_store::repositories::provider_repo::clear_provider_events_by_kind(&conn, &source)?;
    if deleted > 0 {
        crate::event_bus::emit_data_changed(crate::event_bus::Entity::CalendarEvent);
    }
    Ok(ClearNativeCalendarEventsResult { deleted })
}

#[tauri::command]
pub fn sync_linux_calendars(
) -> Result<crate::platform::linux_calendar::reader::LinuxCalendarSyncResult, String> {
    sync_linux_calendars_inner().map_err(String::from)
}

fn sync_linux_calendars_inner(
) -> AppResult<crate::platform::linux_calendar::reader::LinuxCalendarSyncResult> {
    let result = crate::platform::linux_calendar::reader::sync_linux_calendars()
        .map_err(|error| AppError::Internal(error.to_string()))?;
    maybe_emit_native_calendar_sync_changed(&result);
    Ok(result)
}

/// Sync the Windows Appointments store into `provider_calendar_events`.
///
/// The reader makes blocking WinRT `IAsyncOperation::get()` calls
/// internally — see `platform::windows_calendar::reader` for details
/// and #2837 for the corporate-broker stall that motivated bounding
/// each wait. The reader itself owns per-op timeouts; this command
/// additionally dispatches the whole synchronous reader onto a
/// blocking worker via `tauri::async_runtime::spawn_blocking` so the
/// IPC dispatch thread is never parked on a WinRT signaler, even for
/// the (now bounded) duration of a healthy sync. The two layers
/// compose: `spawn_blocking` keeps the IPC thread responsive, and the
/// inner per-op timeouts cap the worst-case wall-clock cost of a
/// single sync.
#[tauri::command]
pub async fn sync_windows_calendars(
) -> Result<crate::platform::windows_calendar::reader::WindowsCalendarSyncResult, String> {
    tauri::async_runtime::spawn_blocking(sync_windows_calendars_inner)
        .await
        .map_err(|join_err| format!("Windows calendar sync task join error: {join_err}"))?
        .map_err(String::from)
}

fn sync_windows_calendars_inner(
) -> AppResult<crate::platform::windows_calendar::reader::WindowsCalendarSyncResult> {
    // Pass the typed `AppError` through unchanged so an `AppError::Timeout`
    // surfaced from inside the WinRT-bounded waits stays distinguishable
    // from a generic `Internal` error all the way to the IPC boundary.
    // Collapsing to `Internal(error.to_string())` here would erase the
    // variant the `From<AppError> for String` impl uses to render a
    // user-facing recovery hint instead of the sanitized "An internal
    // error occurred" fallback.
    let result = crate::platform::windows_calendar::reader::sync_windows_calendars()?;
    maybe_emit_native_calendar_sync_changed(&result);
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn linux_result(
        events_imported: i64,
        events_updated: i64,
        events_removed: i64,
    ) -> crate::platform::linux_calendar::reader::LinuxCalendarSyncResult {
        crate::platform::linux_calendar::reader::LinuxCalendarSyncResult {
            events_imported,
            events_updated,
            events_removed,
            files_scanned: 0,
            available: true,
            error: None,
        }
    }

    fn windows_result(
        events_imported: i64,
        events_updated: i64,
        events_removed: i64,
    ) -> crate::platform::windows_calendar::reader::WindowsCalendarSyncResult {
        crate::platform::windows_calendar::reader::WindowsCalendarSyncResult {
            events_imported,
            events_updated,
            events_removed,
            calendars_scanned: 0,
            available: true,
            error: None,
        }
    }

    #[test]
    fn native_calendar_sync_emits_when_any_provider_row_changed() {
        for result in [
            windows_result(1, 0, 0),
            windows_result(0, 1, 0),
            windows_result(0, 0, 1),
        ] {
            assert!(should_emit_native_calendar_sync_changed(&result));
        }
    }

    #[test]
    fn native_calendar_sync_emit_helper_calls_emitter_only_for_visible_changes() {
        let mut emit_count = 0;
        maybe_emit_native_calendar_sync_changed_with(&windows_result(0, 0, 0), || {
            emit_count += 1;
        });
        assert_eq!(emit_count, 0);

        maybe_emit_native_calendar_sync_changed_with(&windows_result(0, 1, 0), || {
            emit_count += 1;
        });
        assert_eq!(emit_count, 1);
    }

    #[test]
    fn native_calendar_sync_skips_emit_when_no_provider_rows_changed() {
        assert!(!should_emit_native_calendar_sync_changed(&windows_result(
            0, 0, 0
        )));
    }

    #[test]
    fn native_calendar_sync_counts_cover_every_native_result_type() {
        assert!(native_calendar_sync_changed(
            linux_result(0, 1, 0).native_calendar_sync_change_counts()
        ));
        assert!(native_calendar_sync_changed(
            windows_result(0, 0, 1).native_calendar_sync_change_counts()
        ));
    }
}
