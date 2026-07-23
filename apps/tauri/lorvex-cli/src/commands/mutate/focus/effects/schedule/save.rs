use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::naming::{ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE};
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::repositories::preference_repo;
use rusqlite::{Connection, OptionalExtension};
use serde_json::json;

use crate::hlc_guard::lock_shared;
use crate::models::FocusScheduleView;

use super::super::current_focus::load_current_focus_view_for_date;
use super::super::outbox::{
    enqueue_current_focus_payload_upsert, enqueue_focus_schedule_payload_upsert,
};
use super::parse::parse_focus_schedule_blocks_json;
use super::queries::load_focus_schedule_view_for_date;
use crate::commands::mutate::preferences::effects as preferences;
use crate::commands::shared::effects as shared;
use crate::commands::shared::{anchored_timezone_name_for_conn, log_cli_changelog_with_state};

pub(crate) fn save_focus_schedule_with_conn(
    conn: &mut Connection,
    date: Option<&str>,
    blocks_json: &str,
    rationale: Option<&str>,
) -> Result<FocusScheduleView, crate::error::CliError> {
    const MAX_SCHEDULE_BLOCKS: usize = 100;
    const MAX_RATIONALE_CHARS: usize = 10_000;

    let blocks = parse_focus_schedule_blocks_json(blocks_json)?;
    if blocks.is_empty() {
        return Err(crate::error::CliError::Validation(
            "focus schedule blocks must contain at least 1 item".to_string(),
        ));
    }
    if blocks.len() > MAX_SCHEDULE_BLOCKS {
        return Err(crate::error::CliError::Validation(format!(
            "focus schedule blocks exceeds maximum count ({} items, limit {MAX_SCHEDULE_BLOCKS})",
            blocks.len()
        )));
    }
    if let Some(rationale) = rationale {
        let char_count = rationale.chars().count();
        if char_count > MAX_RATIONALE_CHARS {
            return Err(crate::error::CliError::Validation(format!(
                "rationale exceeds maximum length ({char_count} chars, limit {MAX_RATIONALE_CHARS})"
            )));
        }
    }

    let device_id = get_or_create_device_id(conn)?;
    let schedule_date = shared::resolve_date_or_today(conn, date)?;
    let timezone = anchored_timezone_name_for_conn(conn)?;
    let now = lorvex_domain::sync_timestamp_now();
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let task_ids = task_block_ids_in_order(&blocks);
    lorvex_store::validate_task_ids_live(&tx, &task_ids, "focus schedule blocks[].task_id")?;

    // hoist a single `lock_shared` guard for the
    // whole save path. Without one guard, this function and
    // `apply_focus_schedule_to_current_focus` would each mint multiple
    // HLCs via `next_hlc_version`, and
    // `enqueue_focus_schedule_payload_upsert`,
    // `ensure_dashboard_schedule_section`, and `log_cli_changelog`
    // would each re-lock the process-wide HLC mutex independently —
    // five separate lock acquisitions per save. Threading one guard
    // ensures every emitted version (header, child rebuild,
    // current_focus mirror, dashboard preference, audit row) shares
    // the same counter run and sorts strictly-monotonically on peers.
    let mut hlc_guard = lock_shared(&tx)?;
    let version = hlc_guard.generate().to_string();
    lorvex_store::focus_schedule_blocks::upsert_focus_schedule_header(
        &tx,
        &schedule_date,
        rationale,
        &timezone,
        &version,
        &now,
    )?;
    lorvex_store::focus_schedule_blocks::materialize_schedule_blocks(&tx, &schedule_date, &blocks)?;

    let mut schedule =
        load_focus_schedule_view_for_date(&tx, &schedule_date)?.ok_or_else(|| {
            crate::error::CliError::Internal(format!(
                "failed to load focus schedule '{schedule_date}' after save"
            ))
        })?;

    let task_ids_applied = apply_focus_schedule_to_current_focus(
        &tx,
        &mut hlc_guard,
        &device_id,
        &schedule_date,
        task_ids,
        &timezone,
    )?;
    schedule.task_ids_applied = Some(task_ids_applied.clone());
    enqueue_focus_schedule_payload_upsert(&tx, &mut hlc_guard, &device_id, &schedule)?;
    // ship the post-save schedule so the audit row
    // captures the materialized blocks.
    let after_json = Some(serde_json::to_value(&schedule)?);
    log_cli_changelog_with_state(
        &tx,
        &mut hlc_guard,
        crate::commands::shared::CliChangelogParams {
            operation: "focus_schedule",
            entity_type: ENTITY_FOCUS_SCHEDULE,
            entity_id: &schedule_date,
            summary: &format!(
                "Saved focus schedule for {schedule_date} with {} task block(s)",
                task_ids_applied.len()
            ),
            before_json: None,
            after_json,
        },
    )?;
    ensure_dashboard_schedule_section(&tx, &mut hlc_guard, &device_id)?;
    drop(hlc_guard);
    bump_local_change_seq(&tx)?;
    tx.commit()?;

    Ok(schedule)
}

fn apply_focus_schedule_to_current_focus(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    date: &str,
    task_ids: Vec<String>,
    timezone: &str,
) -> Result<Vec<String>, crate::error::CliError> {
    let applied = task_ids;
    let before_focus = load_current_focus_view_for_date(conn, date)?;
    let briefing = before_focus
        .as_ref()
        .and_then(|focus| focus.briefing.as_deref());
    let now = lorvex_domain::sync_timestamp_now();
    let version = hlc_state.generate().to_string();
    if before_focus.is_some() {
        lorvex_store::current_focus_items::touch_current_focus_header(
            conn,
            date,
            Some(&version),
            &now,
        )?;
    } else {
        lorvex_store::current_focus_items::upsert_current_focus_header(
            conn, date, briefing, timezone, &version, &now,
        )?;
    }
    // bake parent header bump into materialize. The
    // touch/upsert above already wrote `version`; the helper re-stamps
    // at the same string so every local-write path is uniform.
    lorvex_store::current_focus_items::materialize_focus_items_with_header_bump(
        conn, date, &applied, &version, &now,
    )?;
    let focus = load_current_focus_view_for_date(conn, date)?.ok_or_else(|| {
        crate::error::CliError::Internal(format!(
            "failed to load current focus '{date}' after schedule apply"
        ))
    })?;
    enqueue_current_focus_payload_upsert(conn, hlc_state, device_id, &focus)?;
    let before_json = before_focus
        .as_ref()
        .map(serde_json::to_value)
        .transpose()?;
    let after_json = Some(serde_json::to_value(&focus)?);
    log_cli_changelog_with_state(
        conn,
        hlc_state,
        crate::commands::shared::CliChangelogParams {
            operation: if before_focus.is_some() {
                "update"
            } else {
                "create"
            },
            entity_type: ENTITY_CURRENT_FOCUS,
            entity_id: date,
            summary: &format!(
                "Applied focus schedule to current focus for {date} with {} task(s)",
                applied.len()
            ),
            before_json,
            after_json,
        },
    )?;
    Ok(applied)
}

fn task_block_ids_in_order(
    blocks: &[lorvex_store::focus_schedule_blocks::ScheduleBlockEntry],
) -> Vec<String> {
    let mut task_ids = Vec::new();
    for block in blocks {
        if block.block_type == "task" {
            if let Some(task_id) = block.task_id.as_ref() {
                if !task_ids.contains(task_id) {
                    task_ids.push(task_id.clone());
                }
            }
        }
    }
    task_ids
}

fn ensure_dashboard_schedule_section(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
) -> Result<(), crate::error::CliError> {
    let key = lorvex_domain::preference_keys::PREF_DASHBOARD_LAYOUT;
    let raw: Option<String> = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = ?1",
            rusqlite::params![key],
            |row| row.get(0),
        )
        .optional()?;
    let mut layout = match raw.as_deref() {
        Some(raw) => {
            let parsed = serde_json::from_str::<serde_json::Value>(raw).map_err(|_| {
                crate::error::CliError::Validation(
                    "dashboard_layout must be valid JSON".to_string(),
                )
            })?;
            if parsed
                .get("sections")
                .and_then(|value| value.as_array())
                .is_some()
            {
                parsed
            } else {
                return Err(crate::error::CliError::Validation(
                    "dashboard_layout sections missing".to_string(),
                ));
            }
        }
        None => json!({
            "sections": [
                { "type": "ai_briefing" },
                { "type": "focus" },
                { "type": "habits" },
                { "type": "overdue_alert", "limit": 4 },
                { "type": "priority" },
                { "type": "recently_completed" }
            ],
            "updated_by": "ai"
        }),
    };
    let sections = layout
        .get_mut("sections")
        .and_then(|value| value.as_array_mut())
        .ok_or_else(|| {
            crate::error::CliError::Internal("dashboard_layout sections missing".to_string())
        })?;
    if sections
        .iter()
        .any(|section| section.get("type").and_then(|value| value.as_str()) == Some("schedule"))
    {
        return Ok(());
    }
    let insert_at = sections
        .iter()
        .position(|section| section.get("type").and_then(|value| value.as_str()) == Some("focus"))
        .map_or(1, |index| index + 1)
        .min(sections.len());
    sections.insert(insert_at, json!({ "type": "schedule" }));

    let value_json = serde_json::to_string(&layout)?;
    let version = hlc_state.generate().to_string();
    let now = lorvex_domain::sync_timestamp_now();
    preference_repo::set_preference(conn, key, &value_json, &version, &now)?;
    preferences::enqueue_preference_upsert(conn, device_id, key, &value_json, &version, &now)
}
