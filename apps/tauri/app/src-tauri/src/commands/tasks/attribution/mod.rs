use crate::db::get_read_conn;
use crate::error::{AppError, AppResult};
use lorvex_domain::naming::{OP_DELETE, STATUS_CANCELLED};
use rusqlite::params;
use serde::{Deserialize, Serialize};

use crate::commands::{parse_rfc3339_utc, OptionalExt};

const ATTRIBUTION_TS_TOLERANCE_SECONDS: i64 = 5;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct AttributionActor {
    pub kind: String,
    pub name: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct TaskAttribution {
    pub created_by: AttributionActor,
    pub deleted_by: Option<AttributionActor>,
    pub last_modified_by: AttributionActor,
}

#[derive(Debug, Clone)]
struct TaskChangeEvent {
    timestamp: String,
    operation: String,
    initiated_by: String,
}

fn actor_human() -> AttributionActor {
    AttributionActor {
        kind: "human".to_string(),
        name: "human".to_string(),
    }
}

fn actor_from_initiated_by(raw: &str) -> AttributionActor {
    // `initiated_by` is peer-supplied — the
    // `ai_changelog` row may have been written by a remote MCP host,
    // a synced peer device, or a sloppy CLI script. Without scrubbing,
    // a label containing bidi marks (`U+202E`), zero-width
    // characters (`U+200B`/`U+FEFF`), or stray control bytes would
    // render verbatim in the task-detail attribution panel,
    // letting an attacker forge plausible-looking actor names that
    // visually impersonate trusted entries. Route through
    // `lorvex_domain::sanitize_user_text` (the same scrubber every
    // other peer-text path uses) so the displayed name carries only
    // safe characters.
    let scrubbed = lorvex_domain::sanitize_user_text(raw);
    let normalized = scrubbed.trim().to_ascii_lowercase();
    // Non-assistant actors render as the human actor, never as a named AI.
    // This set must match the `initiated_by` filter used by the changelog
    // retention/export/query views and the import guard ({human, system, user,
    // manual}); omitting "system" here would misattribute a system-written row
    // as an AI actor literally named "system".
    if matches!(
        normalized.as_str(),
        "" | "human" | "system" | "user" | "manual"
    ) {
        actor_human()
    } else {
        AttributionActor {
            kind: "ai".to_string(),
            name: scrubbed.trim().to_string(),
        }
    }
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_task_attribution(id: String) -> Result<Option<TaskAttribution>, String> {
    // task ids are UUIDv7 — shape-check before the
    // read so the renderer can't smuggle a malformed id back into a
    // later writer (the attribution panel feeds task-detail edit
    // flows).
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    let conn = get_read_conn()?;
    get_task_attribution_with_conn(&conn, &id).map_err(String::from)
}

fn get_task_attribution_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
) -> AppResult<Option<TaskAttribution>> {
    let task_meta = conn
        .query_row(
            "SELECT updated_at, status FROM tasks WHERE id = ?1",
            params![id],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
        )
        .optional()
        .map_err(AppError::from)?;

    let Some((task_updated_at, task_status)) = task_meta else {
        return Ok(None);
    };

    // `ai_changelog_entities` (#4613) replaced the JSON-array
    // `entity_ids` column with a normalized `(entity_id, changelog_id)`
    // PK. The two attribution paths each use an index:
    //   * Branch A — `idx_changelog_entity(entity_type, entity_id)`
    //     for the single-entity write case.
    //   * Branch B — join through `ai_changelog_entities` keyed by
    //     the leftmost `entity_id` so batch-row membership resolves
    //     to an indexed PK seek instead of a `json_each` scan.
    // `UNION ALL` (not `UNION`) is safe because the two branches
    // partition: single-entity rows carry `entity_id IS NOT NULL`
    // and have no `ai_changelog_entities` row; batch rows carry
    // `entity_id IS NULL` and have the registry. No row matches
    // both branches, so DISTINCT would be needless overhead.
    let mut stmt = conn
        .prepare_cached(
            "SELECT timestamp, operation, initiated_by
             FROM ai_changelog
             WHERE entity_type = 'task' AND entity_id = ?1
             UNION ALL
             SELECT ac.timestamp, ac.operation, ac.initiated_by
             FROM ai_changelog ac
             JOIN ai_changelog_entities ace ON ace.changelog_id = ac.id
             WHERE ac.entity_type = 'task' AND ace.entity_id = ?1
             ORDER BY timestamp ASC",
        )
        .map_err(AppError::from)?;

    let rows = stmt
        .query_map(params![&id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
            ))
        })
        .map_err(AppError::from)?;

    let mut events: Vec<TaskChangeEvent> = Vec::new();
    for row in rows {
        let (timestamp, operation, initiated_by) = row.map_err(AppError::from)?;
        events.push(TaskChangeEvent {
            timestamp,
            operation,
            initiated_by,
        });
    }

    let created_by = events
        .iter()
        .find(|event| matches!(event.operation.as_str(), "create" | "batch_create"))
        .map_or_else(actor_human, |event| {
            actor_from_initiated_by(&event.initiated_by)
        });

    let deleted_by = if task_status == STATUS_CANCELLED {
        events
            .iter()
            .rev()
            .find(|event| {
                matches!(
                    event.operation.as_str(),
                    OP_DELETE | "cancel" | "batch_cancel"
                )
            })
            .map(|event| actor_from_initiated_by(&event.initiated_by))
            .or_else(|| Some(actor_human()))
    } else {
        None
    };

    let task_updated_at = parse_rfc3339_utc(&task_updated_at);
    let last_modified_by = events
        .iter()
        .rev()
        .find_map(|event| {
            let event_ts = parse_rfc3339_utc(&event.timestamp)?;
            let task_ts = task_updated_at.as_ref()?;
            let delta = (task_ts.timestamp() - event_ts.timestamp()).abs();
            if delta <= ATTRIBUTION_TS_TOLERANCE_SECONDS {
                Some(actor_from_initiated_by(&event.initiated_by))
            } else {
                None
            }
        })
        .unwrap_or_else(actor_human);

    Ok(Some(TaskAttribution {
        created_by,
        deleted_by,
        last_modified_by,
    }))
}

#[cfg(test)]
mod tests;
