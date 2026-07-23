//! Per-section loaders that feed compact summaries into
//! [`super::types::OverviewSnapshot`].
//!
//! Each loader either returns `None` (focus has no row for the day),
//! a fixed-shape summary struct (habits), or a cap-paged
//! list (the per-list open counts). The snapshot assembler in
//! [`super::snapshot`] threads these into the final wire shape.

use lorvex_store::repositories::list_repo;
use lorvex_store::StoreError;
use rusqlite::{params, Connection, OptionalExtension};

use super::types::{OverviewCurrentFocusSummary, OverviewHabitSummary, OverviewList};

pub(super) struct OverviewListsPage {
    pub rows: Vec<OverviewList>,
    pub total: i64,
    pub truncated: bool,
}

pub(super) fn load_overview_lists(
    conn: &Connection,
    limit: Option<usize>,
) -> Result<OverviewListsPage, StoreError> {
    let page = list_repo::get_lists_with_counts_page(conn, limit)?;
    let total = page.total_matching;
    let rows: Vec<OverviewList> = page
        .rows
        .into_iter()
        .map(|row| OverviewList {
            id: row.list.id,
            name: row.list.name,
            color: row.list.color,
            icon: row.list.icon,
            description: row.list.description,
            ai_notes: row.list.ai_notes,
            created_at: row.list.created_at.as_string(),
            updated_at: row.list.updated_at.as_string(),
            version: row.list.version,
            open_count: row.open_count,
        })
        .collect();
    Ok(OverviewListsPage {
        truncated: total > rows.len() as i64,
        total,
        rows,
    })
}

pub(super) fn load_current_focus_summary(
    conn: &Connection,
    today: &str,
) -> Result<Option<OverviewCurrentFocusSummary>, StoreError> {
    let focus_row = conn
        .prepare_cached("SELECT briefing, timezone FROM current_focus WHERE date = ?1")?
        .query_row(params![today], |row| {
            Ok((
                row.get::<_, Option<String>>(0)?,
                row.get::<_, Option<String>>(1)?,
            ))
        })
        .optional()?;

    let Some((briefing, timezone)) = focus_row else {
        return Ok(None);
    };

    let task_count: i64 = conn
        .prepare_cached("SELECT COUNT(*) FROM current_focus_items WHERE date = ?1")?
        .query_row(params![today], |row| row.get(0))?;

    Ok(Some(OverviewCurrentFocusSummary {
        task_count: task_count as usize,
        briefing,
        timezone,
    }))
}

pub(super) fn load_habit_summary(
    conn: &Connection,
    today: &str,
) -> Result<OverviewHabitSummary, StoreError> {
    let (count, completed_today) = conn.query_row(
        "SELECT
           (SELECT COUNT(*) FROM habits WHERE archived = 0),
           (SELECT COUNT(DISTINCT h.id) FROM habits h
            INNER JOIN habit_completions hc ON h.id = hc.habit_id AND hc.completed_date = ?1
            WHERE h.archived = 0 AND hc.value >= h.target_count)",
        [today],
        |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?)),
    )?;
    Ok(OverviewHabitSummary {
        count,
        completed_today,
    })
}
