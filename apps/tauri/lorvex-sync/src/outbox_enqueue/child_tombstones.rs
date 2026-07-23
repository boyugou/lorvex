use rusqlite::{params, Connection};
use serde_json::Value;

use lorvex_domain::ids::{EventId, HabitId, HabitReminderPolicyId, TaskId};
use lorvex_domain::naming;

use super::{enqueue_payload_delete, EnqueueError, OutboxWriteContext};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeletedHabitCompletionSnapshot {
    pub habit_id: HabitId,
    pub completed_date: String,
    pub value: i64,
    pub note: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub version: String,
}

impl DeletedHabitCompletionSnapshot {
    pub fn entity_id(&self) -> String {
        format!("{}:{}", self.habit_id, self.completed_date)
    }

    pub fn payload(&self) -> Value {
        // Delegate to the spb primitive so the upsert (row → payload)
        // and delete (snapshot struct → payload) shapes are guaranteed
        // identical.
        lorvex_store::payload_loaders::habit_completion_payload(
            &self.habit_id,
            &self.completed_date,
            self.value,
            self.note.as_deref(),
            &self.version,
            &self.created_at,
            &self.updated_at,
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeletedHabitReminderPolicySnapshot {
    pub id: HabitReminderPolicyId,
    pub habit_id: HabitId,
    pub reminder_time: String,
    pub enabled: bool,
    pub created_at: String,
    pub updated_at: String,
    pub version: String,
}

impl DeletedHabitReminderPolicySnapshot {
    pub fn payload(&self) -> Value {
        lorvex_store::payload_loaders::habit_reminder_policy_payload(
            &self.id,
            &self.habit_id,
            &self.reminder_time,
            self.enabled,
            &self.version,
            &self.created_at,
            &self.updated_at,
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeletedTaskCalendarEventLinkSnapshot {
    pub task_id: TaskId,
    pub calendar_event_id: EventId,
    pub created_at: String,
    pub updated_at: String,
    pub version: String,
}

impl DeletedTaskCalendarEventLinkSnapshot {
    pub fn entity_id(&self) -> String {
        format!("{}:{}", self.task_id, self.calendar_event_id)
    }

    pub fn payload(&self) -> Value {
        lorvex_store::payload_loaders::task_calendar_event_link_payload(
            &self.task_id,
            &self.calendar_event_id,
            &self.version,
            &self.created_at,
            &self.updated_at,
        )
    }
}

/// 1. Enqueues a DELETE envelope for the edge so peers remove the link.
/// 2. Relies on `enqueue_payload_delete` to record the matching tombstone,
///    so a late-arriving upsert for the edge (e.g. one that raced with the
///    cascade) is correctly rejected.
///
/// Returns the full pre-delete edge snapshots whose rows were enqueued
/// for delete — callers use them for logging or result construction.
///
/// The caller MUST run this BEFORE the `DELETE FROM calendar_events`
/// statement, so SQLite's cascade has not yet wiped the link rows.
/// each edge tombstone needs its own freshly-minted
/// HLC.
/// every iteration of the loop reused its `version`, breaking the
/// strictly-monotonic-version-per-envelope invariant: peers replayed
/// the same `version` for N distinct edge tombstones, and at LWW
/// resolution time the second envelope onward looked stale (same
/// HLC as the first means "not strictly newer"), so peers dropped
/// every tombstone after the first. The cascade-delete invariant
/// then silently broke for tasks linked to N>=2 calendar events.
///
/// The signature accepts a `mint_version` closure so callers thread
/// their surface-specific HLC generator (Tauri's `crate::hlc::
/// generate_version_result`, the CLI's `next_hlc_version`, etc.)
/// without lorvex-sync having to know about each surface's HLC
/// state.
pub fn enqueue_edge_tombstones_for_calendar_event_delete<F>(
    conn: &Connection,
    event_id: &EventId,
    device_id: &str,
    mut mint_version: F,
) -> Result<Vec<DeletedTaskCalendarEventLinkSnapshot>, EnqueueError>
where
    F: FnMut() -> Result<String, EnqueueError>,
{
    let snapshots = collect_calendar_event_link_snapshots(conn, event_id)?;

    if snapshots.is_empty() {
        return Ok(snapshots);
    }

    for snapshot in &snapshots {
        let entity_id = snapshot.entity_id();
        let payload = snapshot.payload();
        let version = mint_version()?;
        enqueue_payload_delete(
            conn,
            naming::EDGE_TASK_CALENDAR_EVENT_LINK,
            &entity_id,
            &payload,
            OutboxWriteContext {
                version: &version,
                device_id,
            },
        )?;
    }
    Ok(snapshots)
}

/// Issue #2350 (MCP variant): same intent as
/// `enqueue_edge_tombstones_for_calendar_event_delete`, but records only
/// the tombstones. The caller is expected to emit the DELETE envelope +
/// ai_changelog entry for each edge via its own changelog-aware writer
/// (for the MCP server that is `log_change_and_enqueue_sync`, which
/// otherwise would issue a duplicate outbox entry if the envelope was
/// enqueued here too).
///
/// Must also run BEFORE the calendar_events DELETE so the live edge
/// rows are still visible for the SELECT.
pub fn tombstone_edges_for_calendar_event_delete(
    conn: &Connection,
    event_id: &EventId,
    tombstone_version: &str,
) -> Result<Vec<DeletedTaskCalendarEventLinkSnapshot>, EnqueueError> {
    let snapshots = collect_calendar_event_link_snapshots(conn, event_id)?;

    if snapshots.is_empty() {
        return Ok(snapshots);
    }

    let deleted_at = lorvex_domain::sync_timestamp_now();
    for snapshot in &snapshots {
        let entity_id = snapshot.entity_id();
        crate::tombstone::create_tombstone(
            conn,
            naming::EDGE_TASK_CALENDAR_EVENT_LINK,
            &entity_id,
            tombstone_version,
            &deleted_at,
            None,
            None,
        )?;
    }
    Ok(snapshots)
}

fn collect_calendar_event_link_snapshots(
    conn: &Connection,
    event_id: &EventId,
) -> Result<Vec<DeletedTaskCalendarEventLinkSnapshot>, EnqueueError> {
    let mut stmt = conn.prepare_cached(
        "SELECT task_id, calendar_event_id, created_at, updated_at, version
         FROM task_calendar_event_links
         WHERE calendar_event_id = ?1
         ORDER BY created_at, task_id",
    )?;
    let rows = stmt
        .query_map(params![event_id], |row| {
            Ok(DeletedTaskCalendarEventLinkSnapshot {
                task_id: row.get(0)?,
                calendar_event_id: row.get(1)?,
                created_at: row.get(2)?,
                updated_at: row.get(3)?,
                version: row.get(4)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

/// `habits` has `ON DELETE CASCADE` on `habit_completions`
/// and `habit_reminder_policies`, so SQLite drops those rows silently on
/// the local side and never produces per-row sync envelopes. Peers that
/// already received a completion upsert envelope before the habit delete
/// envelope arrives would otherwise keep the orphan completion locally.
///
/// Mirror the #2350 calendar_event edge fix: stamp a tombstone per
/// completion before the cascade so a late-arriving upsert is rejected
/// locally, and let the caller emit DELETE envelopes + ai_changelog rows
/// for each completion via its own changelog-aware writer (for the MCP
/// server that is `log_change_and_enqueue_sync`).
///
/// Returns full pre-delete row snapshots so callers can emit per-row
/// DELETE envelopes and changelog entries without losing typed child fields.
///
/// Must run BEFORE the habits DELETE so the live completion rows are
/// still visible for the SELECT.
pub fn tombstone_completions_for_habit_delete(
    conn: &Connection,
    habit_id: &HabitId,
    tombstone_version: &str,
) -> Result<Vec<DeletedHabitCompletionSnapshot>, EnqueueError> {
    let mut stmt = conn.prepare_cached(
        "SELECT habit_id, completed_date, value, note, created_at, updated_at, version
         FROM habit_completions WHERE habit_id = ?1",
    )?;
    let completions: Vec<DeletedHabitCompletionSnapshot> = stmt
        .query_map(params![habit_id], |row| {
            Ok(DeletedHabitCompletionSnapshot {
                habit_id: row.get(0)?,
                completed_date: row.get(1)?,
                value: row.get(2)?,
                note: row.get(3)?,
                created_at: row.get(4)?,
                updated_at: row.get(5)?,
                version: row.get(6)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    if completions.is_empty() {
        return Ok(completions);
    }

    let deleted_at = lorvex_domain::sync_timestamp_now();
    for completion in &completions {
        let entity_id = completion.entity_id();
        crate::tombstone::create_tombstone(
            conn,
            naming::EDGE_HABIT_COMPLETION,
            &entity_id,
            tombstone_version,
            &deleted_at,
            None,
            None,
        )?;
    }
    Ok(completions)
}

/// companion to `tombstone_completions_for_habit_delete`
/// for the `habit_reminder_policies` child table. Same cascade problem,
/// same fix — stamp a tombstone per policy row before the cascade so
/// peers reject late upserts and the per-row audit trail survives.
///
/// Returns full pre-delete policy snapshots so the caller can emit per-row
/// DELETE envelopes + ai_changelog rows.
///
/// Must run BEFORE the habits DELETE so the live policy rows are still
/// visible for the SELECT.
pub fn tombstone_reminder_policies_for_habit_delete(
    conn: &Connection,
    habit_id: &HabitId,
    tombstone_version: &str,
) -> Result<Vec<DeletedHabitReminderPolicySnapshot>, EnqueueError> {
    let mut stmt = conn.prepare_cached(
        "SELECT id, habit_id, reminder_time, enabled, created_at, updated_at, version
         FROM habit_reminder_policies WHERE habit_id = ?1",
    )?;
    let policies: Vec<DeletedHabitReminderPolicySnapshot> = stmt
        .query_map(params![habit_id], |row| {
            Ok(DeletedHabitReminderPolicySnapshot {
                id: row.get(0)?,
                habit_id: row.get(1)?,
                reminder_time: row.get(2)?,
                enabled: row.get::<_, i64>(3)? != 0,
                created_at: row.get(4)?,
                updated_at: row.get(5)?,
                version: row.get(6)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    if policies.is_empty() {
        return Ok(policies);
    }

    let deleted_at = lorvex_domain::sync_timestamp_now();
    for policy in &policies {
        crate::tombstone::create_tombstone(
            conn,
            naming::ENTITY_HABIT_REMINDER_POLICY,
            policy.id.as_str(),
            tombstone_version,
            &deleted_at,
            None,
            None,
        )?;
    }
    Ok(policies)
}
