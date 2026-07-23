//! CLI mirrors of the MCP `get_setup_status` and
//! `complete_setup` tools, used by assistant-driven onboarding to
//! query whether the prerequisites for normal task creation are met
//! and to mark the setup wizard as completed.
//!
//! `get_setup_status_with_conn` is a pure read — delegates to
//! [`lorvex_store::load_setup_status`].
//!
//! `complete_setup_with_conn` writes three preferences under one
//! immediate transaction (`setup_completed`, `setup_summary`,
//! `setup_state`), enqueues the resulting upsert envelopes for sync,
//! and emits an `ai_changelog` row so peers see the milestone.

use lorvex_domain::naming::ENTITY_PREFERENCE;
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::repositories::preference_repo;
use lorvex_store::{load_setup_status, SetupStatus};
use lorvex_sync::outbox_enqueue::enqueue_entity_upsert;
use rusqlite::Connection;
use serde_json::json;

use crate::error::CliError;
use crate::hlc_guard::lock_shared;

use crate::commands::shared::log_cli_changelog_with_state;

/// Maximum chars for the user-typed onboarding `summary` (parity with
/// `MAX_LONG_TEXT_LENGTH` in the MCP server).
const MAX_SETUP_SUMMARY_LENGTH: usize = lorvex_domain::validation::MAX_BODY_LENGTH;

#[derive(Debug, Clone, serde::Serialize)]
pub(crate) struct SetupStatusSnapshot {
    pub(crate) status: SetupStatus,
    pub(crate) list_count: i64,
    pub(crate) task_count: i64,
}

pub(crate) fn get_setup_status_with_conn(
    conn: &Connection,
) -> Result<SetupStatusSnapshot, CliError> {
    let status = load_setup_status(conn)?;
    let list_count: i64 = conn.query_row("SELECT COUNT(*) FROM lists", [], |row| row.get(0))?;
    let task_count: i64 = conn.query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get(0))?;
    Ok(SetupStatusSnapshot {
        status,
        list_count,
        task_count,
    })
}

#[derive(Debug, Clone, serde::Serialize)]
pub(crate) struct SetupCompletionResult {
    pub(crate) setup_completed: bool,
    pub(crate) summary: String,
    pub(crate) status: SetupStatus,
}

pub(crate) fn complete_setup_with_conn(
    conn: &mut Connection,
    summary: &str,
) -> Result<SetupCompletionResult, CliError> {
    let summary = lorvex_domain::sanitize_user_text(summary);
    let trimmed = summary.trim();
    if trimmed.is_empty() {
        return Err(CliError::Validation(
            "summary must not be empty".to_string(),
        ));
    }
    let summary_chars = summary.chars().count();
    if summary_chars > MAX_SETUP_SUMMARY_LENGTH {
        return Err(CliError::Validation(format!(
            "summary too long ({summary_chars} chars, max {MAX_SETUP_SUMMARY_LENGTH})"
        )));
    }

    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let now = lorvex_domain::sync_timestamp_now();

    let setup_completed_key = lorvex_domain::preference_keys::PREF_SETUP_COMPLETED;
    let setup_summary_key = lorvex_domain::preference_keys::PREF_SETUP_SUMMARY;
    let setup_state_key = lorvex_domain::preference_keys::PREF_SETUP_STATE;

    let mut hlc_guard = lock_shared(&tx)?;

    // Mint three distinct HLC stamps (one per row) so each preference
    // upsert lands at a strictly-greater version than its prior value.
    let v_completed = hlc_guard.generate().to_string();
    preference_repo::set_preference(&tx, setup_completed_key, "true", &v_completed, &now)?;

    let v_summary = hlc_guard.generate().to_string();
    let summary_value = serde_json::to_string(&summary)?;
    preference_repo::set_preference(&tx, setup_summary_key, &summary_value, &v_summary, &now)?;

    let v_state = hlc_guard.generate().to_string();
    let state_value = json!({
        "completed_at": now,
        "completed_summary": summary,
        "completed_via": "cli_setup_complete",
    });
    let state_value_str = serde_json::to_string(&state_value)?;
    preference_repo::set_preference(&tx, setup_state_key, &state_value_str, &v_state, &now)?;

    // Sync envelopes for each preference row.
    enqueue_entity_upsert(
        &tx,
        ENTITY_PREFERENCE,
        setup_completed_key,
        &mut hlc_guard,
        &device_id,
    )?;
    enqueue_entity_upsert(
        &tx,
        ENTITY_PREFERENCE,
        setup_summary_key,
        &mut hlc_guard,
        &device_id,
    )?;
    enqueue_entity_upsert(
        &tx,
        ENTITY_PREFERENCE,
        setup_state_key,
        &mut hlc_guard,
        &device_id,
    )?;

    // emit one `ai_changelog` row per preference
    // key the setup writes.
    // three preference rows (`setup_completed`, `setup_summary`,
    // `setup_state`) but emitted a single audit row referencing only
    // `setup_completed`. The two other rows were invisible to the
    // Restore/Undo affordance the desktop UI builds on top of
    // `ai_changelog`, and consumers that filter the audit stream by
    // `entity_id = setup_summary` (or `setup_state`) saw the writes
    // not happen at all. Mirror the MCP server's per-write logging
    // shape so each preference change is independently auditable.
    log_cli_changelog_with_state(
        &tx,
        &mut hlc_guard,
        crate::commands::shared::CliChangelogParams {
            operation: "update",
            entity_type: ENTITY_PREFERENCE,
            entity_id: setup_completed_key,
            summary: &format!("Completed initial setup: {trimmed}"),
            before_json: None,
            after_json: Some(json!({
                "key": setup_completed_key,
                "value": "true",
                "version": v_completed,
                "updated_at": now,
            })),
        },
    )?;
    log_cli_changelog_with_state(
        &tx,
        &mut hlc_guard,
        crate::commands::shared::CliChangelogParams {
            operation: "update",
            entity_type: ENTITY_PREFERENCE,
            entity_id: setup_summary_key,
            summary: &format!("Recorded setup summary: {trimmed}"),
            before_json: None,
            after_json: Some(json!({
                "key": setup_summary_key,
                "value": summary_value,
                "version": v_summary,
                "updated_at": now,
            })),
        },
    )?;
    log_cli_changelog_with_state(
        &tx,
        &mut hlc_guard,
        crate::commands::shared::CliChangelogParams {
            operation: "update",
            entity_type: ENTITY_PREFERENCE,
            entity_id: setup_state_key,
            summary: "Recorded setup_state milestone via cli_setup_complete",
            before_json: None,
            after_json: Some(json!({
                "key": setup_state_key,
                "value": state_value_str,
                "version": v_state,
                "updated_at": now,
            })),
        },
    )?;
    drop(hlc_guard);
    bump_local_change_seq(&tx)?;
    tx.commit()?;

    let status = load_setup_status(conn)?;
    Ok(SetupCompletionResult {
        setup_completed: status.setup_completed,
        summary,
        status,
    })
}
