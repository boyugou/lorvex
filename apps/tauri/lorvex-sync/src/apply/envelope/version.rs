//! Local-version lookup helpers used by apply dispatch and LWW gates.

use rusqlite::Connection;

use lorvex_domain::naming;

use crate::composite_edge::split_composite_edge_id;

/// Look up the current local version (HLC string) for an entity.
///
/// Returns `None` if the entity does not exist locally.
pub(crate) fn get_local_version(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<Option<String>, rusqlite::Error> {
    // dispatch to a literal SQL string so the version
    // lookup never goes through `format!` interpolation. Same
    // pattern as `version_stamp::SimplePkSql` (#2857) and the
    // `row_exists` table-pair dispatch above.
    // dispatch on `EntityKind` so adding a new
    // syncable variant fails to compile here unless its version
    // lookup arm is wired in. Unrecognized strings still resolve to
    // `Ok(None)` — the legacy fall-through behavior.
    let Some(kind) = naming::EntityKind::parse(entity_type) else {
        return Ok(None);
    };
    let sql: &'static str = match kind {
        // Aggregate roots
        naming::EntityKind::Task => "SELECT version FROM tasks WHERE id = ?1",
        naming::EntityKind::List => "SELECT version FROM lists WHERE id = ?1",
        naming::EntityKind::Habit => "SELECT version FROM habits WHERE id = ?1",
        naming::EntityKind::Tag => "SELECT version FROM tags WHERE id = ?1",
        naming::EntityKind::CalendarEvent => "SELECT version FROM calendar_events WHERE id = ?1",
        naming::EntityKind::Preference => "SELECT version FROM preferences WHERE key = ?1",
        naming::EntityKind::Memory => "SELECT version FROM memories WHERE key = ?1",
        naming::EntityKind::MemoryRevision => "SELECT version FROM memory_revisions WHERE id = ?1",
        naming::EntityKind::DailyReview => "SELECT version FROM daily_reviews WHERE date = ?1",
        naming::EntityKind::CurrentFocus => "SELECT version FROM current_focus WHERE date = ?1",
        naming::EntityKind::FocusSchedule => "SELECT version FROM focus_schedule WHERE date = ?1",
        naming::EntityKind::CalendarSubscription => {
            "SELECT version FROM calendar_subscriptions WHERE id = ?1"
        }
        // Independent children
        naming::EntityKind::TaskReminder => "SELECT version FROM task_reminders WHERE id = ?1",
        naming::EntityKind::TaskChecklistItem => {
            "SELECT version FROM task_checklist_items WHERE id = ?1"
        }
        naming::EntityKind::HabitReminderPolicy => {
            "SELECT version FROM habit_reminder_policies WHERE id = ?1"
        }
        // Edges (composite keys — version query is different)
        naming::EntityKind::TaskTag => {
            return get_edge_version(conn, "task_tags", entity_id);
        }
        naming::EntityKind::TaskDependency => {
            return get_edge_version(conn, "task_dependencies", entity_id);
        }
        naming::EntityKind::TaskCalendarEventLink => {
            return get_edge_version(conn, "task_calendar_event_links", entity_id);
        }
        naming::EntityKind::HabitCompletion => {
            return get_edge_version(conn, "habit_completions", entity_id);
        }
        // Audit stream (`AiChangelog`, append-only — not LWW) and
        // local-only kinds (`TaskProviderEventLink`, `DeviceState`,
        // `SavedQuery`, `ImportSession` — caller never invokes
        // `get_local_version`, the arms exist for exhaustiveness)
        // all skip the version
        // lookup with `Ok(None)`.
        naming::EntityKind::AiChangelog
        | naming::EntityKind::TaskProviderEventLink
        | naming::EntityKind::DeviceState
        | naming::EntityKind::SavedQuery
        | naming::EntityKind::ImportSession => return Ok(None),
    };

    let mut stmt = conn.prepare_cached(sql)?;
    let mut rows = stmt.query_map([entity_id], |row| row.get::<_, Option<String>>(0))?;

    match rows.next() {
        Some(result) => Ok(result?),
        None => Ok(None),
    }
}

/// Look up the version for an edge entity.
///
/// Edge entity_ids in sync envelopes use the format "part1:part2" for
/// composite keys. This function splits on ":" and queries the two-column
/// primary key.
fn get_edge_version(
    conn: &Connection,
    table: &str,
    composite_id: &str,
) -> Result<Option<String>, rusqlite::Error> {
    let Ok((left_id, right_id)) = split_composite_edge_id(composite_id) else {
        return Ok(None);
    };
    // dispatch on `table` to a literal SQL string so
    // edge-version lookup never goes through `format!`.
    let sql: &'static str = match table {
        "task_tags" => "SELECT version FROM task_tags WHERE task_id = ?1 AND tag_id = ?2",
        "task_dependencies" => {
            "SELECT version FROM task_dependencies \
             WHERE task_id = ?1 AND depends_on_task_id = ?2"
        }
        "task_calendar_event_links" => {
            "SELECT version FROM task_calendar_event_links \
             WHERE task_id = ?1 AND calendar_event_id = ?2"
        }
        "habit_completions" => {
            "SELECT version FROM habit_completions \
             WHERE habit_id = ?1 AND completed_date = ?2"
        }
        _ => return Ok(None),
    };
    let mut stmt = conn.prepare_cached(sql)?;
    let mut rows = stmt.query_map(rusqlite::params![left_id, right_id], |row| {
        row.get::<_, Option<String>>(0)
    })?;

    match rows.next() {
        Some(Ok(v)) => Ok(v),
        Some(Err(e)) => Err(e),
        None => Ok(None),
    }
}
