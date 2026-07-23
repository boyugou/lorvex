#[cfg(test)]
use super::super::*;
#[cfg(test)]
use crate::error::{AppError, AppResult};
use lorvex_domain::naming::{EntityKind, OP_UPSERT};

/// Compare two HLC version strings lexicographically.
///
/// HLC versions have the format `{ms}_{counter}_{node}` and are designed
/// to be lexicographically sortable. No multi-field tiebreaker is needed.
pub(crate) fn compare_sync_versions(left_version: &str, right_version: &str) -> std::cmp::Ordering {
    left_version.cmp(right_version)
}

/// Compare two HLC version strings with an outbox ID tiebreaker.
///
/// Used when multiple outbox entries may share the same version (edge case).
pub(crate) fn compare_sync_versions_with_outbox_id(
    left_version: &str,
    left_event_id: &str,
    right_version: &str,
    right_event_id: &str,
) -> std::cmp::Ordering {
    compare_sync_versions(left_version, right_version)
        .then_with(|| left_event_id.cmp(right_event_id))
}

/// Topological priority for the apply ordering. Lower numbers apply
/// first so a parent (e.g. `list`) lands before any child that
/// references it (e.g. `task` with `list_id` FK), and aggregate
/// roots land before their per-row children (e.g. `task` before
/// `task_reminder`, `habit` before `habit_completion`).
///
/// this comparator is now the PRIMARY sort key in
/// `remote/core.rs`'s apply-ordering, not a tiebreaker as it was before.
///
/// explicitly enumerate every syncable entity_type
/// rather than letting children fall through to the default `4`
/// bucket. Reminders, checklist items, and reminder policies are
/// children of root entities (FK to `task_id` / `habit_id`) and
/// must land AFTER their parent, so they belong at priority 3.
/// Composite-edge types stay at priority 3 too — they're already
/// children of two roots, and when both roots are at priority 2
/// the edges naturally serialize after.
///
/// dispatches on [`EntityKind`] (single source of
/// truth for entity classification) so adding a new syncable kind
/// forces an explicit priority assignment at compile time. Unknown
/// strings (forward-compat envelopes from a newer peer) and deletes
/// still land in bucket 4.
pub(crate) fn sync_entity_apply_priority(entity_type: &str, operation: &str) -> i32 {
    if operation != OP_UPSERT {
        // Deletes / unknown ops: the apply pipeline handles them
        // independently of priority ordering.
        return 4;
    }
    let Some(kind) = EntityKind::parse(entity_type) else {
        return 4;
    };
    match kind {
        // Pure parent — no FK to anything else; must land first.
        EntityKind::List => 0,

        // Day-scoped / singleton aggregates with no parent FKs but
        // referenced by children (e.g. tasks may live in
        // current_focus.task_ids; daily_reviews link to lists).
        EntityKind::CurrentFocus
        | EntityKind::DailyReview
        | EntityKind::Preference
        | EntityKind::Memory
        | EntityKind::FocusSchedule => 1,

        // Aggregate roots that depend on parents at priority 0–1
        // (e.g. task → list, calendar_event → list-implicit).
        EntityKind::Task | EntityKind::CalendarEvent | EntityKind::Habit | EntityKind::Tag => 2,

        // Children + edges — must land after every priority 0–2
        // entity they reference. Composite edges naturally serialize
        // here too because both endpoints land at priority ≤ 2.
        EntityKind::TaskReminder
        | EntityKind::TaskChecklistItem
        | EntityKind::HabitReminderPolicy
        | EntityKind::TaskCalendarEventLink
        | EntityKind::HabitCompletion
        | EntityKind::TaskTag
        | EntityKind::TaskDependency => 3,

        // Anything else — audit stream, memory revisions, calendar
        // subscriptions, local-only kinds — lands last. These either
        // carry no FK constraints that the apply ordering needs to
        // satisfy or are not routed through the upsert path at all.
        EntityKind::AiChangelog
        | EntityKind::MemoryRevision
        | EntityKind::CalendarSubscription
        | EntityKind::TaskProviderEventLink
        | EntityKind::DeviceState
        | EntityKind::SavedQuery
        | EntityKind::ImportSession => 4,
    }
}

#[cfg(test)]
pub(crate) fn latest_entity_sync_version(
    conn: &rusqlite::Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<Option<(String, String, String)>, String> {
    latest_entity_sync_version_inner(conn, entity_type, entity_id).map_err(String::from)
}

#[cfg(test)]
fn latest_entity_sync_version_inner(
    conn: &rusqlite::Connection,
    entity_type: &str,
    entity_id: &str,
) -> AppResult<Option<(String, String, String)>> {
    // Only consider synced outbox entries (synced_at IS NOT NULL). Unsynced outgoing
    // entries must NOT participate in the LWW comparison — they represent local
    // writes that haven't been confirmed by the sync transport yet. Including
    // them would cause a locally-written-but-unsynced entry to block valid
    // incoming remote updates.
    let mut stmt = conn
        .prepare(
            "SELECT id, version, device_id
             FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND synced_at IS NOT NULL",
        )
        .map_err(AppError::from)?;

    let mut rows = stmt
        .query_map(params![entity_type, entity_id], |row| {
            Ok((
                row.get::<_, i64>(0)?.to_string(),
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
            ))
        })
        .map_err(AppError::from)?;

    let mut latest: Option<(String, String, String)> = None;
    for row in rows.by_ref() {
        let (id, version, device_id) = row.map_err(AppError::from)?;
        if let Some((ref latest_id, ref latest_version, _)) = latest {
            if compare_sync_versions_with_outbox_id(&version, &id, latest_version, latest_id)
                .is_gt()
            {
                latest = Some((id, version, device_id));
            }
        } else {
            latest = Some((id, version, device_id));
        }
    }

    // Fallback: if sync_outbox has no history (e.g., after GC pruned old entries),
    // check the entity table directly. This aligns the filesystem bridge LWW check with
    // the manual sync path, preventing stale events from overwriting newer local data.
    if latest.is_none() {
        if let Some(entity_version) = get_entity_table_version(conn, entity_type, entity_id)? {
            latest = Some((
                "__entity_table__".to_string(),
                entity_version,
                "local".to_string(),
            ));
        }
    }

    Ok(latest)
}

/// Query the entity's version directly from its source table.
///
/// dispatches via [`EntityKind::table_pk`] for
/// every simple-PK kind so the SELECT is derived from the canonical
/// `(table, pk_col)` registry. Composite-edge kinds keep their
/// hand-written SELECT because the `entity_id` carries `a:b` parts
/// that must be split into separate bindings.
#[cfg(test)]
fn get_entity_table_version(
    conn: &rusqlite::Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<Option<String>, String> {
    let Some(kind) = EntityKind::parse(entity_type) else {
        return Ok(None);
    };

    // Composite-PK edges need to split `entity_id` into two binds
    // — those can't go through the single-bind simple-PK helper.
    match kind {
        EntityKind::HabitCompletion => {
            let parts: Vec<&str> = entity_id.splitn(2, ':').collect();
            if parts.len() != 2 {
                return Ok(None);
            }
            return Ok(conn
                .query_row(
                    "SELECT version FROM habit_completions WHERE habit_id = ?1 AND completed_date = ?2",
                    rusqlite::params![parts[0], parts[1]],
                    |row| row.get(0),
                )
                .ok());
        }
        EntityKind::TaskCalendarEventLink => {
            let parts: Vec<&str> = entity_id.splitn(2, ':').collect();
            if parts.len() != 2 {
                return Ok(None);
            }
            return Ok(conn
                .query_row(
                    "SELECT version FROM task_calendar_event_links WHERE task_id = ?1 AND calendar_event_id = ?2",
                    rusqlite::params![parts[0], parts[1]],
                    |row| row.get(0),
                )
                .ok());
        }
        EntityKind::TaskTag => {
            let parts: Vec<&str> = entity_id.splitn(2, ':').collect();
            if parts.len() != 2 {
                return Ok(None);
            }
            return Ok(conn
                .query_row(
                    "SELECT version FROM task_tags WHERE task_id = ?1 AND tag_id = ?2",
                    rusqlite::params![parts[0], parts[1]],
                    |row| row.get(0),
                )
                .ok());
        }
        EntityKind::TaskDependency => {
            let parts: Vec<&str> = entity_id.splitn(2, ':').collect();
            if parts.len() != 2 {
                return Ok(None);
            }
            return Ok(conn
                .query_row(
                    "SELECT version FROM task_dependencies WHERE task_id = ?1 AND depends_on_task_id = ?2",
                    rusqlite::params![parts[0], parts[1]],
                    |row| row.get(0),
                )
                .ok());
        }
        _ => {}
    }

    let Some((table, pk_col)) = kind.table_pk() else {
        return Ok(None);
    };
    lorvex_domain::assert_safe_sql_identifier(table);
    lorvex_domain::assert_safe_sql_identifier(pk_col);
    let query = format!("SELECT version FROM {table} WHERE {pk_col} = ?1");
    Ok(conn.query_row(&query, [entity_id], |row| row.get(0)).ok())
}
