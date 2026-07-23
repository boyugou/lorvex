//! Generic list-tasks query — the multi-filter, multi-sort listing surface
//! used by the CLI / app filter UIs.

use std::cell::RefCell;
use std::fmt::Write as _;

use lorvex_domain::{escape_like, tag::normalize_lookup_key};
use rusqlite::{params_from_iter, types::Value as SqlValue, Connection};

use crate::error::StoreError;

use super::{
    task_from_row, DateFilter, ListTasksQuery, ListTasksResult, SortDirection, TaskDateRange,
    TaskListSortBy, TaskStatusListFilter, TASK_COLUMNS,
};

// Per-thread reusable buffers for SQL-fragment assembly so the hot
// per-keystroke filter UI path doesn't burn allocations rebuilding the
// WHERE clause every call (#3367). `where_buf` accumulates the joined
// `WHERE …` predicate; `count_sql` and `tasks_sql` get cleared and
// rewritten via `write!` per call. The `RefCell` wrappers are safe
// because `list_tasks` is non-reentrant on a given thread and we always
// drop the borrow before any callback that could re-enter (we never
// touch them across the FFI boundary into rusqlite callbacks).
thread_local! {
    static SQL_BUFFERS: RefCell<SqlBuffers> = RefCell::new(SqlBuffers::default());
}

#[derive(Default)]
struct SqlBuffers {
    where_clause: String,
    count_sql: String,
    tasks_sql: String,
}

pub fn list_tasks(
    conn: &Connection,
    query: &ListTasksQuery,
) -> Result<ListTasksResult, StoreError> {
    let mut values: Vec<SqlValue> = Vec::new();

    SQL_BUFFERS.with(|cell| {
        let mut buf = cell.borrow_mut();
        let SqlBuffers {
            where_clause,
            count_sql,
            tasks_sql,
        } = &mut *buf;
        where_clause.clear();
        count_sql.clear();
        tasks_sql.clear();

        build_where_clause(where_clause, &mut values, query);

        // COUNT and SELECT bodies share the WHERE — assemble both once.
        count_sql.push_str("SELECT COUNT(*) FROM tasks ");
        count_sql.push_str(where_clause);

        let order_by_sql = list_tasks_order_by(query.sort_by, query.sort_direction);
        tasks_sql.push_str("SELECT ");
        tasks_sql.push_str(TASK_COLUMNS);
        tasks_sql.push_str(" FROM tasks ");
        tasks_sql.push_str(where_clause);
        tasks_sql.push_str(" ORDER BY ");
        tasks_sql.push_str(&order_by_sql);
        tasks_sql.push_str(" LIMIT ? OFFSET ?");

        // route the COUNT through `prepare_cached` so the
        // per-keystroke filter UI reuses the prepared statement when the
        // filter shape (status / list / priority / dates / tags / blocking
        // predicates) is stable across keystrokes (#3027-M3). Mirrors the
        // FTS / trigram / LIKE search helpers that already cache. The
        // data-fetching SELECT below was already cached.
        let total_matching: i64 = {
            let mut count_stmt = conn.prepare_cached(count_sql)?;
            count_stmt.query_row(params_from_iter(values.iter()), |row| row.get(0))?
        };

        let mut task_values = std::mem::take(&mut values);
        task_values.push(SqlValue::Integer(i64::from(query.limit)));
        task_values.push(SqlValue::Integer(i64::from(query.offset)));

        // (#3034-M2) the OFFSET-based pagination here drifts on
        // insert-between-pages: see the canonical comment kept in
        // history; keyset pagination tracked under #3034-M2.
        let mut stmt = conn.prepare_cached(tasks_sql)?;
        let rows = stmt.query_map(params_from_iter(task_values.iter()), task_from_row)?;
        let rows = rows.collect::<Result<Vec<_>, _>>()?;

        Ok(ListTasksResult {
            rows,
            total_matching,
        })
    })
}

/// Build the `WHERE …` predicate into `out` and push the bind values
/// into `values`. Pulled out of `list_tasks` so the thread-local buffer
/// closure body stays readable.
fn build_where_clause(out: &mut String, values: &mut Vec<SqlValue>, query: &ListTasksQuery) {
    out.push_str("WHERE tasks.archived_at IS NULL");

    if let Some(status) = status_filter_to_sql(query.status) {
        out.push_str(" AND status = ?");
        values.push(SqlValue::Text(status.to_string()));
    }

    if let Some(list_id) = query.list_id.as_deref() {
        out.push_str(" AND list_id = ?");
        values.push(SqlValue::Text(list_id.to_string()));
    }

    if let Some(priority) = query.priority {
        out.push_str(" AND priority = ?");
        values.push(SqlValue::Integer(i64::from(priority)));
    }

    push_date_range(out, values, "due_date", query.due_range.as_ref());
    push_date_range(out, values, "planned_date", query.planned_range.as_ref());
    push_datetime_range(out, values, "completed_at", query.completed_range.as_ref());
    push_datetime_range(out, values, "created_at", query.created_range.as_ref());

    push_date_presence(out, "due_date", query.due_presence);
    push_date_presence(out, "planned_date", query.planned_presence);

    if let Some(text) = query
        .text
        .as_deref()
        .map(str::trim)
        .filter(|text| !text.is_empty())
    {
        out.push_str(
            " AND (title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\' OR ai_notes LIKE ? ESCAPE '\\')",
        );
        let pattern = format!("%{}%", escape_like(text));
        values.push(SqlValue::Text(pattern.clone()));
        values.push(SqlValue::Text(pattern.clone()));
        values.push(SqlValue::Text(pattern));
    }

    for tag in &query.tags {
        out.push_str(
            " AND EXISTS (\
                SELECT 1 FROM task_tags tt \
                JOIN tags tg ON tg.id = tt.tag_id \
                WHERE tt.task_id = tasks.id AND tg.lookup_key = ?\
            )",
        );
        values.push(SqlValue::Text(normalize_lookup_key(tag)));
    }

    // route the four valid (blocked, blocking) combos
    // through `BlockingFilter`'s exhaustive helpers so adding a new
    // adjacency mode is a single match arm rather than a shotgun edit
    // across CLI/MCP/store flag pairs.
    let active_list = lorvex_domain::naming::status::ACTIVE_STATUS_SQL_LIST;
    if query.blocking.requires_blocked() {
        // SAFETY: `active_list` is `&'static str` from a domain constant,
        // not user input.
        let _ = write!(
            out,
            " AND EXISTS (\
                SELECT 1 FROM task_dependencies td \
                JOIN tasks AS blocker ON blocker.id = td.depends_on_task_id \
                WHERE td.task_id = tasks.id \
                  AND blocker.status IN ({active_list}) \
                  AND blocker.archived_at IS NULL\
            )"
        );
    }

    if query.blocking.requires_blocking_others() {
        let _ = write!(
            out,
            " AND EXISTS (\
                SELECT 1 FROM task_dependencies td \
                JOIN tasks AS dependent ON dependent.id = td.task_id \
                WHERE td.depends_on_task_id = tasks.id \
                  AND dependent.status IN ({active_list}) \
                  AND dependent.archived_at IS NULL\
            )"
        );
    }
}

fn push_date_presence(out: &mut String, column: &'static str, filter: DateFilter) {
    match filter {
        DateFilter::Any => {}
        DateFilter::Present => {
            let _ = write!(out, " AND {column} IS NOT NULL");
        }
        DateFilter::Absent => {
            let _ = write!(out, " AND {column} IS NULL");
        }
    }
}

const fn status_filter_to_sql(status: TaskStatusListFilter) -> Option<&'static str> {
    match status {
        TaskStatusListFilter::Open => Some("open"),
        TaskStatusListFilter::Completed => Some("completed"),
        TaskStatusListFilter::Cancelled => Some("cancelled"),
        TaskStatusListFilter::Someday => Some("someday"),
        TaskStatusListFilter::All => None,
    }
}

/// Whether [`add_range_conditions`] should widen a bare `YYYY-MM-DD`
/// upper bound to the end-of-day microsecond timestamp.
///
/// `Date` callers pass plain `YYYY-MM-DD` columns where bare-string
/// equality is the right inclusive semantic. `Datetime` callers
/// (e.g. `completed_at`) need the widened form so a row written at
/// `…23:59:59.123456Z` falls inside the range when the user picks
/// that day as the upper bound — see `add_range_conditions` for the
/// full rationale.
#[derive(Copy, Clone)]
enum RangeUpperWidening {
    Date,
    Datetime,
}

fn push_range(
    out: &mut String,
    values: &mut Vec<SqlValue>,
    // The `'static` lifetime on `column` blocks user-controlled input
    // from reaching the SQL fragment builder.
    column: &'static str,
    range: Option<&TaskDateRange>,
    widening: RangeUpperWidening,
) {
    if let Some(from) = range.and_then(|range| range.from.as_deref()) {
        let _ = write!(out, " AND {column} >= ?");
        values.push(SqlValue::Text(from.to_string()));
    }
    if let Some(to) = range.and_then(|range| range.to.as_deref()) {
        let _ = write!(out, " AND {column} <= ?");
        // For `Datetime` ranges, callers may pass either a bare
        // `YYYY-MM-DD` (in which case we widen to end-of-day so the
        // inclusive UI semantic matches what users expect) or a full
        // RFC3339 timestamp (which we must pass through verbatim).
        // Naively appending `T23:59:59Z` to a full timestamp yields
        // `…ZT23:59:59Z`, lex-compares to nothing, and silently returns
        // zero rows.
        //
        // When widening a bare YMD we must use the microsecond-Z form
        // `T23:59:59.999999Z`. A naive `T23:59:59Z` cap would exclude
        // rows whose timestamp has microsecond precision (e.g.
        // `2026-04-01T23:59:59.123456Z`) because lex compare of `.`
        // (U+002E) vs `Z` (U+005A) puts `.` first, so a row at
        // `…23:59:59.123456Z` falls outside `<= '…23:59:59Z'`. The
        // `completed_at` / `due_date` columns are written in
        // microsecond form (#2926-H8 fixed this as the canonical
        // persistence shape), so the inclusive end-of-day semantic the
        // caller expects only holds when we widen to the largest
        // microsecond timestamp in the day.
        let widened = match widening {
            RangeUpperWidening::Datetime if is_bare_ymd(to) => format!("{to}T23:59:59.999999Z"),
            RangeUpperWidening::Date | RangeUpperWidening::Datetime => to.to_string(),
        };
        values.push(SqlValue::Text(widened));
    }
}

fn push_date_range(
    out: &mut String,
    values: &mut Vec<SqlValue>,
    column: &'static str,
    range: Option<&TaskDateRange>,
) {
    push_range(out, values, column, range, RangeUpperWidening::Date);
}

fn push_datetime_range(
    out: &mut String,
    values: &mut Vec<SqlValue>,
    column: &'static str,
    range: Option<&TaskDateRange>,
) {
    push_range(out, values, column, range, RangeUpperWidening::Datetime);
}

/// `true` if `s` is exactly `YYYY-MM-DD` (10 chars, ASCII digits + dashes).
fn is_bare_ymd(s: &str) -> bool {
    let bytes = s.as_bytes();
    if bytes.len() != 10 {
        return false;
    }
    for (i, b) in bytes.iter().enumerate() {
        let ok = match i {
            4 | 7 => *b == b'-',
            _ => b.is_ascii_digit(),
        };
        if !ok {
            return false;
        }
    }
    true
}

fn list_tasks_order_by(sort_by: TaskListSortBy, direction: SortDirection) -> String {
    let direction = match direction {
        SortDirection::Asc => "ASC",
        SortDirection::Desc => "DESC",
    };
    match sort_by {
        // Emit `NULLS LAST` on `priority_effective` so that
        // unprioritized tasks (NULL priority, sentinel `4` from the
        // VIRTUAL generated column) sort AFTER prioritized ones under
        // BOTH ascending and descending requests. Relying on the
        // sentinel sorting in the desired direction implicitly works
        // only under ASC: `1 < 2 < 3 < 4` pushes the sentinel last.
        // Under DESC the sentinel becomes `4 > 3 > 2 > 1`, which would
        // surface unprioritized tasks FIRST — the exact opposite of
        // what the UI's "highest priority first" toggle expects. Using
        // `NULLIF(priority_effective, 4)` to lift the sentinel back to
        // NULL lets `NULLS LAST` enforce the same tail ordering
        // uniformly in either direction. Sibling sorts apply the same
        // pattern (see `DueDate`/`PlannedDate` arms).
        TaskListSortBy::PriorityDue => {
            format!(
                "NULLIF(priority_effective, 4) {direction} NULLS LAST, \
                 due_date {direction} NULLS LAST, id ASC"
            )
        }
        TaskListSortBy::DueDate => {
            format!(
                "due_date {direction} NULLS LAST, \
                 NULLIF(priority_effective, 4) ASC NULLS LAST, id ASC"
            )
        }
        TaskListSortBy::PlannedDate => {
            format!(
                "planned_date {direction} NULLS LAST, \
                 NULLIF(priority_effective, 4) ASC NULLS LAST, id ASC"
            )
        }
        TaskListSortBy::UpdatedAt => format!("updated_at {direction}, id ASC"),
        TaskListSortBy::CreatedAt => format!("created_at {direction}, id ASC"),
        TaskListSortBy::Title => format!("LOWER(title) {direction}, id ASC"),
    }
}

#[cfg(test)]
mod datetime_range_tests {
    use super::{is_bare_ymd, push_datetime_range, SqlValue, TaskDateRange};

    fn run(range: &TaskDateRange) -> (String, Vec<SqlValue>) {
        let mut sql = String::new();
        let mut values = Vec::new();
        push_datetime_range(&mut sql, &mut values, "completed_at", Some(range));
        (sql, values)
    }

    #[test]
    fn bare_ymd_to_widens_to_end_of_day() {
        // Widen to the largest microsecond timestamp in the day so a
        // row at e.g. `2026-04-26T23:59:59.123456Z` still satisfies
        // the inclusive-end-of-day cap. A naive `T23:59:59Z` form
        // would sort lex-before any `.`-bearing microsecond timestamp
        // (`.` < `Z`), silently excluding microsecond-precision rows.
        let (sql, vals) = run(&TaskDateRange {
            from: None,
            to: Some("2026-04-26".to_string()),
        });
        assert_eq!(sql, " AND completed_at <= ?");
        assert_eq!(
            vals,
            vec![SqlValue::Text("2026-04-26T23:59:59.999999Z".to_string())]
        );
    }

    /// regression — a row written with
    /// microsecond-Z precision must be included in the inclusive
    /// end-of-day window.
    #[test]
    fn bare_ymd_cap_includes_microsecond_rows() {
        let (_, vals) = run(&TaskDateRange {
            from: None,
            to: Some("2026-04-26".to_string()),
        });
        let cap = match &vals[0] {
            SqlValue::Text(s) => s.clone(),
            other => panic!("expected text cap, got {other:?}"),
        };
        let row_with_micros = "2026-04-26T23:59:59.123456Z";
        assert!(
            row_with_micros.as_bytes() <= cap.as_bytes(),
            "row {row_with_micros:?} must lex-compare <= cap {cap:?}"
        );
    }

    #[test]
    fn rfc3339_to_passes_through_verbatim() {
        let (sql, vals) = run(&TaskDateRange {
            from: None,
            to: Some("2026-04-26T10:00:00Z".to_string()),
        });
        assert_eq!(sql, " AND completed_at <= ?");
        // Crucially NOT "2026-04-26T10:00:00ZT23:59:59Z".
        assert_eq!(
            vals,
            vec![SqlValue::Text("2026-04-26T10:00:00Z".to_string())]
        );
    }

    #[test]
    fn from_is_passed_through_unchanged() {
        let (sql, vals) = run(&TaskDateRange {
            from: Some("2026-04-01T00:00:00Z".to_string()),
            to: None,
        });
        assert_eq!(sql, " AND completed_at >= ?");
        assert_eq!(
            vals,
            vec![SqlValue::Text("2026-04-01T00:00:00Z".to_string())]
        );
    }

    #[test]
    fn is_bare_ymd_recognizes_only_canonical_form() {
        assert!(is_bare_ymd("2026-04-26"));
        assert!(is_bare_ymd("0000-00-00"));
        assert!(!is_bare_ymd("2026-04-26 "));
        assert!(!is_bare_ymd("2026-04-26T"));
        assert!(!is_bare_ymd("2026-04-26T00:00:00Z"));
        assert!(!is_bare_ymd("2026-4-26"));
        assert!(!is_bare_ymd("2026/04/26"));
        assert!(!is_bare_ymd(""));
        assert!(!is_bare_ymd("2026-04-2"));
    }
}
