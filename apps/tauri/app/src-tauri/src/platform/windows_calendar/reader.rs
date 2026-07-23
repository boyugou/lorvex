//! Windows native calendar reading — reads from Windows Appointments API.
//!
//! Uses the `windows` crate to access `Windows.ApplicationModel.Appointments`
//! and mirrors events into `provider_calendar_events` with
//! `provider_kind = 'windows_appointments'`.
#[cfg(target_os = "windows")]
use crate::error::AppError;
use crate::error::AppResult;
use serde::Serialize;

#[cfg(target_os = "windows")]
mod attendees;
mod properties;
mod recurrence;
#[cfg(target_os = "windows")]
mod request_store;
mod source_time;
#[cfg(test)]
mod tests;

#[cfg(target_os = "windows")]
use attendees::extract_windows_attendees;
#[cfg_attr(not(target_os = "windows"), allow(unused_imports))]
use properties::{optional_windows_string, required_windows_value};
#[cfg(target_os = "windows")]
use recurrence::extract_windows_recurrence;
#[cfg(target_os = "windows")]
use request_store::{classify_request_store_error, denied_result, record_permission_denied};
#[cfg_attr(not(target_os = "windows"), allow(unused_imports))]
use source_time::resolve_source_time_semantics;

#[derive(Debug, Serialize)]
pub struct WindowsCalendarSyncResult {
    pub events_imported: i64,
    pub events_updated: i64,
    pub events_removed: i64,
    pub calendars_scanned: i64,
    pub available: bool,
    pub error: Option<String>,
}

/// Sync events from the Windows Appointments API.
///
/// Reads all calendars via `AppointmentManager::RequestStoreAsync` with
/// read-only access, fetches appointments for the provider window, and
/// upserts them into `provider_calendar_events`.
#[cfg(target_os = "windows")]
pub fn sync_windows_calendars() -> AppResult<WindowsCalendarSyncResult> {
    use crate::db::get_conn;
    use crate::platform::winrt_async::{run_winrt_with_timeout, WINRT_DEFAULT_TIMEOUT};
    use std::collections::HashSet;
    use windows::ApplicationModel::Appointments::*;
    use windows::Foundation::{DateTime, TimeSpan};

    // 1. Request read-only access to the appointment store.
    //    This may trigger a system consent dialog on first call.
    //    The WinRT `RequestStoreAsync` op is the most stall-prone of
    //    the three calls in this function (it talks to the calendar
    //    broker which Group Policy may delay) — wrap it with the
    //    standard timeout so we recover instead of holding the IPC
    //    thread forever.
    let store_op = match AppointmentManager::RequestStoreAsync(
        AppointmentStoreAccessType::AllCalendarsReadOnly,
    ) {
        Ok(op) => op,
        Err(e) => {
            // classify so the user gets a
            // distinct remediation hint for "permission denied"
            // vs "Group Policy disabled" vs other errors.
            record_permission_denied()?;
            return Ok(denied_result(&classify_request_store_error(&e)));
        }
    };
    let store_op_for_cancel = store_op.clone();
    let store_op_for_get = store_op;
    let store = match run_winrt_with_timeout(
        "Windows AppointmentManager.RequestStoreAsync",
        WINRT_DEFAULT_TIMEOUT,
        move || store_op_for_get.get(),
        move || {
            let _ = store_op_for_cancel.Cancel();
        },
    ) {
        Ok(s) => s,
        Err(AppError::Timeout(msg)) => {
            // A broker stall is its own distinct cause and gets its
            // own remediation hint ("retry; if persistent, restart
            // the calendar broker"). Collapsing it into the same
            // string as a declined consent prompt would point the
            // user at Settings → Privacy & Security where they would
            // find calendar access already enabled, with no recourse.
            //
            // Record this as a transient refresh error rather than a
            // sticky `permission_denied`. Persisting the same
            // `PermissionDenied` transition that an actual
            // user-declined consent would emit causes the renderer
            // to surface "Calendar access denied" with no path back
            // even after the broker recovers. A `RefreshError` keeps
            // the scope `enabled` so the next sync attempt re-runs
            // the consent path, and the user-visible state tracks
            // reality (the broker stalled; permissions are unknown).
            let conn = get_conn()?;
            let now_ts = lorvex_domain::sync_timestamp_now();
            let _ = crate::platform::provider_scope_state::record_refresh_error(
                &conn,
                "windows_appointments",
                "",
                &now_ts,
                &msg,
                "broker_timeout",
            );
            return Ok(denied_result(&format!(
                "The Windows Calendar broker did not respond \
                 within the timeout. Group Policy can sometimes \
                 stall the broker on first launch — retry, and \
                 if the failure persists, sign out and back in \
                 to refresh the broker. ({msg})"
            )));
        }
        Err(AppError::Internal(msg)) => {
            // The WinRT op surfaced a synchronous error AFTER
            // the async dispatcher started the operation
            // (typically access denied / user declined / GP
            // disabled). Re-classify so the remediation copy
            // matches the actual cause. We don't have the raw
            // `windows::core::Error` here (it was already
            // stringified into `msg` by the timeout wrapper), so
            // pattern-match the embedded HRESULT text.
            record_permission_denied()?;
            let lower = msg.to_lowercase();
            let detail = if lower.contains("0x80070005")
                || lower.contains("e_accessdenied")
                || lower.contains("access is denied")
            {
                format!(
                    "Calendar access not granted. Open Windows \
                     Settings → Privacy & Security → Calendar \
                     and enable access for Lorvex, then try \
                     again. ({msg})"
                )
            } else if lower.contains("0x80070032") || lower.contains("group policy") {
                format!(
                    "Calendar access is disabled by Group Policy \
                     or unavailable on this Windows edition. \
                     Contact your IT administrator to allow \
                     Calendar access for Lorvex. ({msg})"
                )
            } else {
                format!(
                    "Calendar access denied. Grant access in \
                     Windows Settings → Privacy & Security → \
                     Calendar. ({msg})"
                )
            };
            return Ok(denied_result(&detail));
        }
        Err(other) => return Err(other),
    };

    // 2. Get all calendars for counting.
    let calendars_op = store
        .FindAppointmentCalendarsAsync()
        .map_err(|e| AppError::Internal(format!("Failed to find calendars: {e}")))?;
    let calendars_op_for_cancel = calendars_op.clone();
    let calendars_op_for_get = calendars_op;
    let calendars = run_winrt_with_timeout(
        "Windows AppointmentStore.FindAppointmentCalendarsAsync",
        WINRT_DEFAULT_TIMEOUT,
        move || calendars_op_for_get.get(),
        move || {
            let _ = calendars_op_for_cancel.Cancel();
        },
    )?;
    let calendars_scanned = required_windows_value(
        calendars.Size(),
        "read appointment calendar collection size",
    )? as i64;

    // Query a -30/+90 day window. Starting the range at "now"
    // would silently drop any appointment whose start was earlier
    // today (e.g. an all-day event the user wants to mark complete
    // in the timeline view, or a multi-day conference that started
    // yesterday). A uniform window across native-calendar readers
    // keeps the cross-platform timeline consistent and gives the
    // renderer the same
    // lookback context regardless of which device sourced the
    // appointments.
    const PROVIDER_LOOKBACK_DAYS: i64 = 30;
    const PROVIDER_LOOKAHEAD_DAYS: i64 = 90;
    let now_unix = chrono::Utc::now().timestamp();
    let lookback_secs = PROVIDER_LOOKBACK_DAYS * 24 * 60 * 60;
    let range_start_unix = now_unix - lookback_secs;
    let range_start = DateTime {
        UniversalTime: range_start_unix * crate::platform::provider_time::WINDOWS_TICKS_PER_SECOND
            + crate::platform::provider_time::UNIX_TO_FILETIME_OFFSET,
    };

    // (lookback + lookahead) days in 100-nanosecond ticks
    let total_days_ticks: i64 = (PROVIDER_LOOKBACK_DAYS + PROVIDER_LOOKAHEAD_DAYS)
        * 24
        * 60
        * 60
        * crate::platform::provider_time::WINDOWS_TICKS_PER_SECOND;
    let range_duration = TimeSpan {
        Duration: total_days_ticks,
    };

    // 4. Fetch appointments within the window.
    //
    //    We use the 2-parameter FindAppointmentsAsync(DateTime, TimeSpan)
    //    which returns all appointments in the range. The 3-parameter
    //    overload (with FindAppointmentsOptions) can be used when the
    //    exact method name for the `windows` crate version is verified on
    //    a Windows build — it allows requesting specific properties like
    //    Subject, Details, Location, AllDay and setting a MaxCount.
    //    The 2-param version populates all standard properties.
    let appointments_op = store
        .FindAppointmentsAsync(range_start, range_duration)
        .map_err(|e| AppError::Internal(format!("Failed to find appointments: {e}")))?;
    let appointments_op_for_cancel = appointments_op.clone();
    let appointments_op_for_get = appointments_op;
    let appointments = run_winrt_with_timeout(
        "Windows AppointmentStore.FindAppointmentsAsync",
        WINRT_DEFAULT_TIMEOUT,
        move || appointments_op_for_get.get(),
        move || {
            let _ = appointments_op_for_cancel.Cancel();
        },
    )?;

    // 6. Upsert each appointment into the provider event cache.
    let conn = get_conn()?;
    let now_ts = lorvex_domain::sync_timestamp_now();
    let mut imported = 0i64;
    let mut updated = 0i64;
    let mut synced_keys: HashSet<String> = HashSet::new();

    let mut device_tz: Option<String> = None;

    let count = required_windows_value(appointments.Size(), "read appointment collection size")?;
    // Per-event failures land in error_logs (so users see why a
    // specific appointment is missing) and the loop continues —
    // mirroring the linux_calendar log-and-skip resilience contract.
    // Aborting the entire 90-day sync on a single failing event
    // would let one Outlook plugin pushing a malformed appointment,
    // a transient WinRT property read failure, or a single bad
    // timezone projection blow away the in-progress upsert results
    // AND the stale-cleanup pass downstream.
    for i in 0..count {
        let event_outcome: AppResult<bool> = (|| {
            let appt = appointments.GetAt(i).map_err(|e| {
                AppError::Validation(format!(
                    "Windows appointment store returned unreadable row at index {i}: {e}"
                ))
            })?;

            // Use LocalId as the stable per-device key.
            // RoamingId may be empty for local-only calendars.
            let local_id = appt.LocalId().map(|id| id.to_string()).map_err(|e| {
                AppError::Validation(format!(
                    "Windows appointment missing stable LocalId at index {i}: {e}"
                ))
            })?;

            let title = optional_windows_string(
                appt.Subject(),
                &format!("Windows appointment {local_id} has unreadable Subject"),
            )?;
            let details = optional_windows_string(
                appt.Details(),
                &format!("Windows appointment {local_id} has unreadable Details"),
            )?;
            let location = optional_windows_string(
                appt.Location(),
                &format!("Windows appointment {local_id} has unreadable Location"),
            )?;
            let all_day = required_windows_value(
                appt.AllDay(),
                &format!("Windows appointment {local_id} has unreadable AllDay"),
            )?;

            let start_filetime = appt.StartTime().map(|dt| dt.UniversalTime).map_err(|e| {
                AppError::Validation(format!(
                    "Windows appointment {local_id} has unreadable StartTime: {e}"
                ))
            })?;

            let duration_ticks = appt.Duration().map(|ts| ts.Duration).map_err(|e| {
                AppError::Validation(format!(
                    "Windows appointment {local_id} has unreadable Duration: {e}"
                ))
            })?;
            let time_projection =
                crate::platform::provider_time::project_windows_filetime_range_to_local(
                    start_filetime,
                    duration_ticks,
                    all_day,
                )?;

            synced_keys.insert(local_id.clone());

            // Windows Appointments times are converted to chrono::Local above,
            // so the stored date/time values are in the device's local IANA
            // timezone. All-day events are "floating" per RFC 5545.
            let source_time = resolve_source_time_semantics(&mut device_tz, all_day, || {
                crate::platform::provider_time::current_provider_source_timezone_name()
            })?;
            let source_time_kind = source_time.kind;
            let source_tzid = source_time.tzid.as_deref();

            // Extract organizer email if available.
            let organizer_email = optional_windows_string(
                appt.Organizer().and_then(|o| o.Address()),
                &format!("Windows appointment {local_id} organizer address"),
            )
            .unwrap_or(None);

            // Extract attendees (invitees) from the appointment.
            let attendees_json = extract_windows_attendees(&appt, &local_id);

            // Extract recurrence info. Windows uses `AppointmentRecurrence` objects
            // which describe the pattern. We convert to an RRULE-compatible JSON string.
            let recurrence_json = extract_windows_recurrence(&appt);

            // align the recurrence_exceptions
            // contract with the create-side path (see
            // `commands/calendar_events/mutations/create.rs`,
            // which seeds an empty JSON array for any event that
            // has a recurrence). The previous Windows extractor
            // emitted `None` for both "no recurrence" and "recurring
            // but no exceptions yet", which the renderer's
            // expansion code couldn't disambiguate from a corrupt
            // row. Mirror the convention: when we have a
            // recurrence pattern, write `"[]"`; otherwise leave
            // `None`. The full per-occurrence override
            // enumeration (via `AppointmentCalendar::
            // GetAppointmentInstanceAsync` + `IsCanceledMeeting`)
            // would let us populate real EXDATE entries; that
            // requires a separate Windows-runtime test pass to
            // prove the LocalId-vs-instance keying behaves the
            // way the docs claim, so it's deferred here. Issue
            // tracked alongside the rest of the WIN-H8 audit.
            let recurrence_exceptions_json: Option<String> =
                recurrence_json.as_deref().map(|_| "[]".to_string());

            // Extract online meeting URI if available.
            let video_call_url = optional_windows_string(
                appt.OnlineMeetingLink(),
                &format!("Windows appointment {local_id} online meeting link"),
            )
            .unwrap_or(None);

            let outcome = lorvex_store::repositories::provider_repo::upsert_provider_event(
                &conn,
                &lorvex_store::repositories::provider_repo::ProviderEventData {
                    provider_kind: "windows_appointments",
                    provider_scope: "",
                    provider_event_key: &local_id,
                    title: title.as_deref(),
                    description: details.as_deref(),
                    start_date: &time_projection.start_date,
                    start_time: time_projection.start_time.as_deref(),
                    end_date: Some(&time_projection.end_date),
                    end_time: time_projection.end_time.as_deref(),
                    all_day,
                    location: location.as_deref(),
                    organizer_email: organizer_email.as_deref(),
                    source_time_kind,
                    source_tzid,
                    recurrence: recurrence_json.as_deref(),
                    recurrence_exceptions: recurrence_exceptions_json.as_deref(),
                    color: None,
                    attendees_json: attendees_json.as_deref(),
                    video_call_url: video_call_url.as_deref(),
                },
                &now_ts,
            )?;
            Ok(outcome)
        })();

        match event_outcome {
            Ok(lorvex_store::repositories::provider_repo::ProviderEventUpsertOutcome::Inserted) => {
                imported += 1
            }
            Ok(lorvex_store::repositories::provider_repo::ProviderEventUpsertOutcome::Updated) => {
                updated += 1
            }
            Ok(
                lorvex_store::repositories::provider_repo::ProviderEventUpsertOutcome::Unchanged,
            ) => {}
            Err(e) => {
                if let Ok(diag_conn) = crate::db::get_conn() {
                    let _ = crate::commands::diagnostics::append_error_log_internal(
                        &diag_conn,
                        "platform.windows_calendar",
                        &format!(
                            "skipping appointment at index {i} due to extraction failure: {e}"
                        ),
                        None,
                        Some("warn".to_string()),
                    );
                }
            }
        }
    }

    // 7. Record successful refresh so shared timeline/blocking queries
    //    include events from this provider.
    crate::platform::provider_scope_state::record_refresh_success(
        &conn,
        "windows_appointments",
        "",
        &now_ts,
    )?;

    // 8. Remove stale events no longer present in the Appointments store.
    //    Only check events within the sync window — events outside
    //    the window are not fetched so their absence is not
    //    meaningful. Cleanup window now starts
    //    at `today - PROVIDER_LOOKBACK_DAYS` to match the new
    //    lookback range; otherwise stale rows in [today-30, today)
    //    would never be GCed because the cleanup floor was today.
    let mut removed = 0i64;
    let cleanup_floor_str = (chrono::Local::now() - chrono::Duration::days(PROVIDER_LOOKBACK_DAYS))
        .format("%Y-%m-%d")
        .to_string();
    let cached_keys = lorvex_store::repositories::provider_repo::get_provider_event_keys(
        &conn,
        "windows_appointments",
        None,
        Some(&cleanup_floor_str),
    )?;

    for key in &cached_keys {
        if !synced_keys.contains(key) {
            lorvex_store::repositories::provider_repo::delete_provider_event(
                &conn,
                "windows_appointments",
                "",
                key,
            )?;
            removed += 1;
        }
    }

    Ok(WindowsCalendarSyncResult {
        events_imported: imported,
        events_updated: updated,
        events_removed: removed,
        calendars_scanned,
        available: true,
        error: None,
    })
}

/// Non-Windows stub: returns unavailable.
#[cfg(not(target_os = "windows"))]
pub fn sync_windows_calendars() -> AppResult<WindowsCalendarSyncResult> {
    Ok(WindowsCalendarSyncResult {
        events_imported: 0,
        events_updated: 0,
        events_removed: 0,
        calendars_scanned: 0,
        available: false,
        error: Some("Windows calendar reading is only available on Windows.".to_string()),
    })
}
