//! .ics subscription IPC surface and Tauri-side glue.
//!
//! The cross-surface primitives — TZID resolution, URL safety / SSRF,
//! VTIMEZONE parsing, ICS parser, scheduling math, mutation
//! descriptors, and the sync orchestrator with its `FetchBackend`
//! trait — all live in [`lorvex_workflow::calendar_subscription`].
//! This module is the Tauri surface adapter only:
//!
//! - [`errors`] — Tauri-side fetch / truncation error enums plus the
//!   `From<CalendarSubscriptionError> for AppError` bridge that lets
//!   workflow primitives keep `?`-flowing through Tauri command
//!   bodies.
//! - [`fetch`] — pinned reqwest client construction, size-capped +
//!   idle-timeout body reader, redirect-chain SSRF revalidation,
//!   captive portal heuristic. Also exposes `TauriFetchBackend`,
//!   the [`FetchBackend`] impl this surface threads into the
//!   workflow orchestrator.
//! - [`native`] — Tauri bridges for OS-native calendar sources
//!   (Linux ICS import, Windows Appointments).
//! - The IPC commands at the bottom of this file plus the
//!   `_with_conn` helpers used by the in-tree test module — both
//!   route through the workflow mutation descriptors and surface
//!   adapter helpers (outbox enqueue, event-bus broadcast,
//!   `local_change_seq` bump).

use lorvex_domain::naming::{ENTITY_CALENDAR_SUBSCRIPTION, OP_DELETE, OP_UPSERT};
use lorvex_sync::outbox_enqueue::{
    enqueue_payload_delete, enqueue_payload_upsert, OutboxWriteContext,
};
use lorvex_workflow::calendar_subscription::{
    add_response, list_calendar_subscriptions as workflow_list_calendar_subscriptions,
    remove_payload_was_present, upsert_payload_matched, AddCalendarSubscriptionMutation,
    RemoveCalendarSubscriptionMutation, ToggleCalendarSubscriptionMutation,
    UpdateCalendarSubscriptionColorMutation,
};
use lorvex_workflow::mutation::MutationExecution;
use rusqlite::params;
use serde_json::Value;

use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;
use crate::commands::sync_timestamp_now;
use crate::commands::with_immediate_transaction;
use crate::db::get_conn;
use crate::error::{AppError, AppResult};

mod errors;
mod fetch;
pub(crate) mod native;

#[cfg(test)]
pub(crate) use errors::IcsBodyReadError;
#[cfg(test)]
pub(crate) use lorvex_workflow::calendar_subscription::truncation::detect_ics_truncation;
#[cfg(test)]
pub(crate) use lorvex_workflow::calendar_subscription::truncation::{
    IcsTruncationReason, ICS_TRUNCATION_MESSAGE,
};
#[cfg(test)]
pub(crate) use lorvex_workflow::calendar_subscription::CalendarSubscriptionSyncHealth;
#[cfg(test)]
pub(crate) use lorvex_workflow::calendar_subscription::{
    clear_subscription_next_retry, record_subscription_failure, record_subscription_success,
};
pub use lorvex_workflow::calendar_subscription::{
    CalendarSubscription, RemoveCalendarSubscriptionResult, SubscriptionSyncResult,
    ToggleCalendarSubscriptionResult, UpdateCalendarSubscriptionColorResult,
};

pub(crate) use fetch::TauriFetchBackend;

// ── Subscription CRUD IPC ─────────────────────────────────────────

#[tauri::command]
pub fn list_calendar_subscriptions() -> Result<Vec<CalendarSubscription>, String> {
    let conn = get_conn().map_err(String::from)?;
    workflow_list_calendar_subscriptions(&conn).map_err(|e| e.to_string())
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn add_calendar_subscription(
    name: String,
    url: String,
    color: Option<String>,
) -> Result<CalendarSubscription, String> {
    let conn = get_conn().map_err(String::from)?;
    add_calendar_subscription_with_conn(&conn, &name, &url, color.as_deref()).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn remove_calendar_subscription(
    id: String,
) -> Result<RemoveCalendarSubscriptionResult, String> {
    let conn = get_conn().map_err(String::from)?;
    remove_calendar_subscription_with_conn(&conn, &id).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn toggle_calendar_subscription(
    id: String,
    enabled: bool,
) -> Result<ToggleCalendarSubscriptionResult, String> {
    let conn = get_conn().map_err(String::from)?;
    toggle_calendar_subscription_with_conn(&conn, &id, enabled).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn update_calendar_subscription_color(
    id: String,
    color: Option<String>,
) -> Result<UpdateCalendarSubscriptionColorResult, String> {
    let conn = get_conn().map_err(String::from)?;
    update_calendar_subscription_color_with_conn(&conn, &id, color.as_deref()).map_err(String::from)
}

// ── Sync IPC ──────────────────────────────────────────────────────

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn sync_calendar_subscription(id: String) -> Result<SubscriptionSyncResult, String> {
    let conn = get_conn().map_err(String::from)?;
    lorvex_workflow::calendar_subscription::sync_calendar_subscription(
        &conn,
        &TauriFetchBackend,
        &log_unknown_tzid,
        &id,
    )
    .map_err(|e| e.to_string())
}

/// user-facing "Retry now" — clear the backoff gate for a
/// single subscription and run a fresh sync immediately. Distinct
/// from [`sync_calendar_subscription`] (which ignores the scheduler
/// gate but still walks the provider_scope_runtime_state 429
/// cooldown): "Retry now" is explicit user intent — they want the
/// feed probed right now regardless of the backoff schedule, and
/// any failure resets the exponential clock from 1 minute rather
/// than continuing from where it was.
#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn retry_calendar_subscription_now(id: String) -> Result<SubscriptionSyncResult, String> {
    let conn = get_conn().map_err(String::from)?;
    lorvex_workflow::calendar_subscription::retry_calendar_subscription_now(
        &conn,
        &TauriFetchBackend,
        &log_unknown_tzid,
        &id,
    )
    .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn sync_all_calendar_subscriptions() -> Result<Vec<SubscriptionSyncResult>, String> {
    let conn = get_conn().map_err(String::from)?;
    lorvex_workflow::calendar_subscription::sync_all_calendar_subscriptions(
        &conn,
        &TauriFetchBackend,
        &log_unknown_tzid,
    )
    .map_err(|e| e.to_string())
}

// ── Mutation surface (workflow descriptor + Tauri finalizer) ──────

pub(crate) fn add_calendar_subscription_with_conn(
    conn: &rusqlite::Connection,
    name: &str,
    url: &str,
    color: Option<&str>,
) -> AppResult<CalendarSubscription> {
    with_immediate_transaction(conn, |conn| {
        let mutation = AddCalendarSubscriptionMutation::new(
            name.to_string(),
            url.to_string(),
            color.map(str::to_string),
        );
        let id = mutation.id().to_string();
        let output = execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, execution| {
            enqueue_subscription_payload(conn, &id, execution)
        })?;

        let created_at = output
            .after
            .get("created_at")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
        let updated_at = output
            .after
            .get("updated_at")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
        Ok(add_response(
            id,
            name.to_string(),
            url.to_string(),
            color.map(str::to_string),
            created_at,
            updated_at,
        ))
    })
}

pub(crate) fn remove_calendar_subscription_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
) -> AppResult<RemoveCalendarSubscriptionResult> {
    with_immediate_transaction(conn, |conn| {
        let mutation = RemoveCalendarSubscriptionMutation::new(id.to_string());
        execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, execution| {
            // an absent row produces a placeholder `after` lacking
            // the synced columns; skip the outbox enqueue so we
            // don't ship a malformed delete tombstone for a row
            // that never existed.
            if !remove_payload_was_present(&execution.output.after) {
                return Ok(());
            }
            enqueue_subscription_payload(conn, id, execution)
        })?;
        Ok(RemoveCalendarSubscriptionResult {
            deleted: id.to_string(),
        })
    })
}

pub(crate) fn toggle_calendar_subscription_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
    enabled: bool,
) -> AppResult<ToggleCalendarSubscriptionResult> {
    with_immediate_transaction(conn, |conn| {
        let mutation = ToggleCalendarSubscriptionMutation::new(id.to_string(), enabled);
        execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, execution| {
            if !upsert_payload_matched(&execution.output.after) {
                return Ok(());
            }
            enqueue_subscription_payload(conn, id, execution)
        })?;
        Ok(ToggleCalendarSubscriptionResult {
            id: id.to_string(),
            enabled,
        })
    })
}

pub(crate) fn update_calendar_subscription_color_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
    color: Option<&str>,
) -> AppResult<UpdateCalendarSubscriptionColorResult> {
    with_immediate_transaction(conn, |conn| {
        let mutation =
            UpdateCalendarSubscriptionColorMutation::new(id.to_string(), color.map(str::to_string));
        execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, execution| {
            if !upsert_payload_matched(&execution.output.after) {
                return Ok(());
            }
            enqueue_subscription_payload(conn, id, execution)
        })?;
        Ok(UpdateCalendarSubscriptionColorResult {
            id: id.to_string(),
            color: color.map(str::to_string),
        })
    })
}

/// Ship the freshly-written subscription payload to the sync outbox.
/// Reads the operation and entity id off the staged
/// [`MutationExecution`]; the descriptor already populated
/// `output.after` with the canonical payload shape from
/// [`lorvex_store::payload_loaders`].
fn enqueue_subscription_payload(
    conn: &rusqlite::Connection,
    id: &str,
    execution: &MutationExecution,
) -> AppResult<()> {
    let Some(device_id) = crate::hlc::try_device_id() else {
        return Err(AppError::Internal(
            "calendar_subscription outbox write failed: HLC not initialized".to_string(),
        ));
    };
    let version = execution
        .output
        .after
        .get("version")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            AppError::Internal(format!(
                "calendar_subscription '{id}' apply produced payload without 'version'"
            ))
        })?;
    let ctx = OutboxWriteContext { version, device_id };
    let payload = &execution.output.after;
    if execution.operation == OP_DELETE {
        enqueue_payload_delete(conn, ENTITY_CALENDAR_SUBSCRIPTION, id, payload, ctx)
            .map_err(AppError::from)
    } else {
        debug_assert_eq!(execution.operation, OP_UPSERT);
        enqueue_payload_upsert(conn, ENTITY_CALENDAR_SUBSCRIPTION, id, payload, ctx)
            .map_err(AppError::from)
    }
}

// ── Tauri-side TZID diagnostic sink ───────────────────────────────

/// Record a `warn`-level row in `error_logs` when an ICS feed uses a
/// TZID that chrono-tz cannot resolve and that the Windows→IANA map
/// does not cover. Best-effort — logging failures are swallowed so a
/// transient DB contention cannot cascade into subscription-sync
/// failures.
///
/// Plumbed into the workflow orchestrator as the `unknown_tzid_sink`
/// callback so the parse phase can surface unrecognised TZIDs without
/// having to know about the Tauri-side schema.
pub(crate) fn log_unknown_tzid(tzid: &str) {
    let Ok(conn) = get_conn() else {
        return;
    };
    let id = lorvex_domain::new_entity_id_string();
    let now = sync_timestamp_now();
    let message = format!("Unknown TZID in ICS feed: `{tzid}` — falling back to UTC");
    let _ = conn.execute(
        "INSERT INTO error_logs (id, source, level, message, created_at) \
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![id, "sync.ics.unknown_tzid", "warn", message, now],
    );
}

#[cfg(test)]
mod tests;
