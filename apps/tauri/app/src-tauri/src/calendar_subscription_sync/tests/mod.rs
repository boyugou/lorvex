use rusqlite::params;

use super::fetch::{
    looks_like_captive_portal_body, read_body_capped, read_body_capped_with_idle_timeout,
};
use super::*;
use super::{
    add_calendar_subscription_with_conn, log_unknown_tzid, remove_calendar_subscription_with_conn,
    toggle_calendar_subscription_with_conn, update_calendar_subscription_color_with_conn,
};
use crate::error::AppError;
use crate::test_support::test_conn;

/// In-tree adapter that forwards to the workflow orchestrator's
/// [`lorvex_workflow::calendar_subscription::sync_subscription_content`]
/// using the Tauri-side TZID diagnostic sink. The Tauri-runtime tests
/// in this tree pre-date the workflow lift and call the helper at
/// its historical shape (no `unknown_tzid_sink` parameter); this
/// wrapper keeps that surface intact and converts the workflow error
/// back into the local `AppResult` shape.
fn sync_subscription_content_inner(
    conn: &rusqlite::Connection,
    id: &str,
    name: &str,
    ics_content: &str,
    sub_color: Option<&str>,
) -> AppResult<SubscriptionSyncResult> {
    lorvex_workflow::calendar_subscription::sync_subscription_content(
        conn,
        id,
        name,
        ics_content,
        sub_color,
        &log_unknown_tzid,
    )
    .map_err(AppError::from)
}

/// In-tree adapter for the truncation-rejection helper. Same purpose
/// as [`sync_subscription_content_inner`] above — converts the
/// workflow error into the local `AppResult` shape so the existing
/// truncation-preservation test in `tests/sync.rs` doesn't have to
/// rebuild its assertion plumbing.
fn record_ics_truncation_rejection(
    conn: &rusqlite::Connection,
    id: &str,
    name: &str,
    now: &str,
    reason: IcsTruncationReason,
    safe_url: &str,
) -> AppResult<SubscriptionSyncResult> {
    lorvex_workflow::calendar_subscription::record_ics_truncation_rejection(
        conn, id, name, now, reason, safe_url,
    )
    .map_err(AppError::from)
}

fn setup() -> rusqlite::Connection {
    test_conn()
}

mod fetch;
mod fetch_body;
mod mutations;
mod source_contract;
mod sync;
