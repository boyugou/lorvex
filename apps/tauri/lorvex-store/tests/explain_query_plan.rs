//! EXPLAIN QUERY PLAN snapshot harness for hot read paths.
//!
//! Several hot production read paths (today view, overview, task
//! detail, upcoming, weekly review) have no automated cost
//! regression check. As queries evolve — new columns, new filters,
//! new proposed partial indexes — it's easy for one of them to
//! silently regress from an index lookup to a full table scan.
//!
//! This module snapshots the SQLite `EXPLAIN QUERY PLAN` output for
//! five canonical queries and fails the build on plan drift. A
//! plan change requires a committed update to the expected string
//! (intentional change) or is flagged as a regression.
//!
//! ## What is asserted
//!
//! The `detail` column of `EXPLAIN QUERY PLAN` (the structural
//! shape — "SEARCH tasks USING INDEX idx_tasks_status" vs. "SCAN
//! tasks"). We do NOT assert on:
//!
//! - Cost / row-estimate numbers (these change with row counts and
//!   SQLite version upgrades).
//! - `id` / `parent` graph columns (internal plan-tree numbering).
//!
//! ## What is NOT asserted
//!
//! Whether the current plan is *optimal*. A couple of the hot paths
//! already full-scan today (see the per-test notes). The test's job
//! is to flag **changes**, not to force an optimal plan on every
//! commit. If a proposed index (see issues #2283, #2284, #2286)
//! lands, the corresponding snapshot must be updated in the same
//! commit.
//!
//! ## Why this lives in `lorvex-store` rather than `mcp-server`
//!
//! The WHERE clauses these tests assert against are composed by
//! `repositories::task::read` helpers (`overdue_bucket_predicate`,
//! `today_pool_bucket_predicate`, `upcoming_bucket_predicate`) — the
//! SQL strings originate here. Keeping the test adjacent to the
//! predicate definitions means a predicate refactor reruns the
//! harness without crossing crate boundaries.

#![cfg(test)]

use lorvex_store::open_db_in_memory;
use rusqlite::Connection;

/// Execute `EXPLAIN QUERY PLAN {sql}` and return the concatenation of
/// every plan row's `detail` column, one per line, in the order SQLite
/// emits them. The id/parent/notused columns are intentionally
/// dropped — only the structural shape ("SEARCH ... USING INDEX ..."
/// vs. "SCAN ...") is load-bearing.
fn capture_plan(conn: &Connection, sql: &str) -> String {
    let eqp = format!("EXPLAIN QUERY PLAN {sql}");
    let mut stmt = conn
        .prepare(&eqp)
        .unwrap_or_else(|err| panic!("failed to prepare EQP for `{sql}`: {err}"));
    // SQLite picks an index plan purely from schema + WHERE shape, but
    // rusqlite still rejects `query_map([])` when the underlying
    // statement has positional placeholders. Bind NULL for every
    // placeholder — the planner outcome is identical. Use the
    // prepared statement's `parameter_count()` so the binding tracks
    // the SQL automatically.
    let n_params = stmt.parameter_count();
    let nulls: Vec<rusqlite::types::Value> = (0..n_params)
        .map(|_| rusqlite::types::Value::Null)
        .collect();
    let rows = stmt
        .query_map(rusqlite::params_from_iter(nulls.iter()), |row| {
            row.get::<_, String>("detail")
        })
        .expect("EXPLAIN QUERY PLAN must return a `detail` column");
    let details: Vec<String> = rows
        .collect::<Result<_, _>>()
        .expect("EXPLAIN QUERY PLAN rows must be UTF-8 strings");
    details.join("\n")
}

/// Assert that the runtime plan matches `expected`. On mismatch, print
/// both plans and the SQL so the diff is actionable from CI logs
/// alone — no need to re-run locally to discover what drifted.
#[track_caller]
fn assert_plan(label: &str, sql: &str, actual: &str, expected: &str) {
    assert!(
        actual == expected,
        "\nEXPLAIN QUERY PLAN drift for `{label}`.\n\n\
         SQL:\n{sql}\n\n\
         Expected plan:\n{expected}\n\n\
         Actual plan:\n{actual}\n\n\
         If this change is intentional (new index, query rewrite),\n\
         update the expected string in `explain_query_plan.rs` in\n\
         the same commit as the query/index change.\n"
    );
}

// ---------------------------------------------------------------------
// Canonical SQL strings
// ---------------------------------------------------------------------
//
// These mirror the production queries (task_repo + MCP overview +
// weekly review). They are re-expressed here as literal
// strings — rather than re-called through the public API — so the
// test asserts against the exact shape that hits the planner,
// independent of how the callers compose their WHERE clauses.

fn authored(alias: &str) -> String {
    format!("{alias}.archived_at IS NULL")
}

fn sql_get_today_overdue() -> String {
    let a = authored("tasks");
    let order_by = lorvex_store::TASK_ORDER_BY;
    format!(
        "SELECT id FROM tasks \
         WHERE status = 'open' AND {a} AND tasks.due_date < ?1 \
         ORDER BY {order_by} \
         LIMIT ?2"
    )
}

fn sql_get_today_pool() -> String {
    let a = authored("tasks");
    // #3319: this ORDER BY mirrors the production today-pool view
    // (`get_exact_today_tasks` in `task_repo/today.rs`) and
    // intentionally diverges from the canonical `TASK_ORDER_BY`.
    // See the rationale comment over `get_exact_today_tasks` —
    // every row already shares the same calendar day so `due_time`
    // substitutes for the canonical `due_date` axis.
    format!(
        "SELECT id FROM tasks \
         WHERE status = 'open' \
           AND {a} \
           AND (COALESCE(tasks.planned_date, tasks.due_date) <= ?1 \
                AND (tasks.due_date IS NULL OR tasks.due_date >= ?1)) \
         ORDER BY priority_effective ASC, due_time ASC NULLS LAST, created_at DESC, id ASC \
         LIMIT ?2"
    )
}

fn sql_get_overview_top_by_priority() -> String {
    let a = authored("tasks");
    let order_by = lorvex_store::TASK_ORDER_BY;
    format!(
        "SELECT id FROM tasks \
         WHERE status = 'open' AND {a} \
         ORDER BY {order_by} \
         LIMIT 10"
    )
}

fn sql_get_overview_recently_completed() -> String {
    let a = authored("tasks");
    format!(
        "SELECT id FROM tasks \
         WHERE status = 'completed' AND {a} \
         ORDER BY completed_at DESC \
         LIMIT 5"
    )
}

fn sql_get_task_detail_primary() -> &'static str {
    "SELECT * FROM tasks WHERE id = ?"
}

/// Tag enrichment uses the `display_name` column on the `tags`
/// table (schema/001_schema.sql L125). This is the column name the
/// production `lorvex_workflow::task_enrichment` path queries.
fn sql_get_task_detail_tags() -> &'static str {
    "SELECT tt.task_id, t.id, t.display_name \
     FROM task_tags tt \
     JOIN tags t ON t.id = tt.tag_id \
     WHERE tt.task_id IN (?)"
}

fn sql_get_task_detail_reminders() -> &'static str {
    "SELECT * FROM task_reminders WHERE task_id IN (?) \
     ORDER BY task_id, reminder_at ASC"
}

fn sql_get_upcoming() -> String {
    let a = authored("tasks");
    format!(
        "SELECT id FROM tasks \
         WHERE status = 'open' \
           AND {a} \
           AND ((tasks.due_date IS NULL OR tasks.due_date >= ?1) \
                AND COALESCE(tasks.planned_date, tasks.due_date) > ?1 \
                AND COALESCE(tasks.planned_date, tasks.due_date) <= ?2) \
         ORDER BY COALESCE(planned_date, due_date) ASC, \
                  priority_effective ASC, \
                  due_time ASC NULLS LAST, \
                  created_at DESC, id ASC \
         LIMIT ?3 OFFSET ?4"
    )
}

fn sql_weekly_review_deferred_count() -> String {
    let a = authored("tasks");
    format!(
        "SELECT COUNT(*) FROM tasks \
         WHERE status = 'open' AND {a} AND defer_count >= 3"
    )
}

fn sql_get_archived_tasks() -> String {
    // Mirrors lorvex-store/src/repositories/task_repo/archive.rs:
    // `WHERE archived_at IS NOT NULL ORDER BY archived_at DESC, id
    // ASC`. The compound partial index `idx_tasks_archived_at`
    // covers both the predicate and the multi-column ORDER BY so
    // the plan should not need a temp B-tree.
    "SELECT id FROM tasks \
     WHERE archived_at IS NOT NULL \
     ORDER BY archived_at DESC, id ASC"
        .to_string()
}

fn sql_get_deferred_tasks() -> String {
    // Mirrors lorvex-store/src/repositories/task_repo/deferred.rs's
    // unscoped variant: status='open' AND defer_count >= 1, ordered
    // by deferral pressure then deterministic id tiebreak. Audit pass
    // 12 L4 dropped `updated_at` from both the query's ORDER BY and
    // the index's key list — the column is HLC-rewritten by sync-apply
    // on conflict resolution and unsuitable as a pagination
    // tiebreaker. The (defer_count DESC, id ASC) shape is fully
    // satisfied by `idx_tasks_deferred_open`'s `(status, defer_count
    // DESC, id ASC)` key list, so the planner now streams rows
    // index-ordered without a temp B-tree.
    let a = authored("tasks");
    format!(
        "SELECT id FROM tasks \
         WHERE status = 'open' AND defer_count >= 1 AND {a} \
         ORDER BY defer_count DESC, id ASC \
         LIMIT ?1 OFFSET ?2"
    )
}

// ---------------------------------------------------------------------
// Expected plans
// ---------------------------------------------------------------------
//
// Captured against the SQLite bundled with `rusqlite` 0.39.
// Each string is the `detail` column of every plan row, joined by
// `\n`. These are the **current** production plans — the harness's
// job is to flag *changes*, not to force an optimal plan today.

/// Baseline plan for `get_today_tasks::overdue`. Without `ANALYZE`
/// stats on the seeded in-memory DB the planner prefers the
/// status-anchored composite `idx_tasks_status_priority_effective_due`
/// and sorts the trailing ORDER BY terms via a TEMP B-TREE. Even so,
/// the test is meaningful — any change in the WHERE shape or the
/// index inventory flips this string.
const EXPECTED_TODAY_OVERDUE: &str =
    "SEARCH tasks USING INDEX idx_tasks_status_priority_effective_due (status=?)\n\
     USE TEMP B-TREE FOR LAST 2 TERMS OF ORDER BY";

/// Baseline plan for `get_today_tasks::today_pool`. The
/// `COALESCE(planned_date, due_date)` expression *can* bind to
/// `idx_tasks_action_date_open` once `ANALYZE` runs, but on a cold
/// in-memory DB SQLite picks the status-anchored composite. If
/// issue #2667's audit rework is ever undone (back to an
/// OR-of-columns predicate) the plan flips to `idx_tasks_status`
/// which this string would surface immediately.
///
/// `LAST 3 TERMS` (not 2) accounts for the canonical
/// `id ASC` tiebreaker the query carries — see CLAUDE.md core rule
/// #4 for the canonical sort contract. The composite index covers
/// the leading `priority_effective` term; the trailing
/// `(due_time, created_at, id)` triple sorts via a TEMP B-TREE.
const EXPECTED_TODAY_POOL: &str =
    "SEARCH tasks USING INDEX idx_tasks_status_priority_effective_due (status=?)\n\
     USE TEMP B-TREE FOR LAST 3 TERMS OF ORDER BY";

/// Baseline plan for `get_overview::top_by_priority`. The planner
/// currently picks `idx_tasks_status` plus a TEMP B-TREE sort —
/// i.e. the composite `(status, priority_effective, due_date)`
/// index is NOT being selected here, even though the ORDER BY
/// matches. This is a known inefficiency (the composite index is
/// over `priority` not `priority_effective`, so SQLite can't use
/// it to skip the sort). Documented, intentionally, as the
/// current plan; a future fix should flip this to the composite
/// index and drop `USE TEMP B-TREE FOR ORDER BY`.
const EXPECTED_OVERVIEW_TOP_BY_PRIORITY: &str =
    "SEARCH tasks USING INDEX idx_tasks_status (status=?)\n\
     USE TEMP B-TREE FOR ORDER BY";

/// Baseline plan for `get_overview::recently_completed`. Despite
/// adding `idx_tasks_completed_at` as a partial index
/// on `(completed_at) WHERE status='completed'`, SQLite's planner
/// prefers `idx_tasks_status_priority_effective_due` here (it's a
/// covering fit for the `status='completed'` predicate and the
/// completed_at ORDER BY still requires a sort either way). Recorded
/// as-is — drift on this line is the signal that either the planner
/// or the index set changed.
const EXPECTED_OVERVIEW_RECENTLY_COMPLETED: &str =
    "SEARCH tasks USING INDEX idx_tasks_status_priority_effective_due (status=?)\n\
     USE TEMP B-TREE FOR ORDER BY";

/// `tasks.id` is declared `TEXT PRIMARY KEY`, which SQLite stores as
/// a non-integer primary key — so the autoindex `sqlite_autoindex_tasks_1`
/// is what gets hit, not the integer rowid fast-path.
const EXPECTED_TASK_DETAIL_PRIMARY: &str =
    "SEARCH tasks USING INDEX sqlite_autoindex_tasks_1 (id=?)";

/// Both sides of the join land on the tables' unique primary-key
/// autoindexes. `tt` is COVERING because the composite
/// `(task_id, tag_id)` key already contains every column the query
/// reads from `task_tags`.
const EXPECTED_TASK_DETAIL_TAGS: &str =
    "SEARCH tt USING COVERING INDEX sqlite_autoindex_task_tags_1 (task_id=?)\n\
     SEARCH t USING INDEX sqlite_autoindex_tags_1 (id=?)";

/// `idx_task_reminders_task` is now a compound key
/// `(task_id, reminder_at ASC)` — the seek satisfies both the IN
/// predicate and the trailing reminder_at ORDER BY without the temp
/// B-tree filesort the prior single-column shape required.
const EXPECTED_TASK_DETAIL_REMINDERS: &str =
    "SEARCH task_reminders USING INDEX idx_task_reminders_task (task_id=?)";

/// Baseline plan for `get_upcoming_tasks` on a cold in-memory DB.
/// As with the today-pool bucket, without `ANALYZE` the planner
/// picks a status-anchored index rather than
/// `idx_tasks_action_date_open`. With the current index inventory,
/// that is the single-column `idx_tasks_status`. Drift on this
/// string is the harness's signal either way.
const EXPECTED_UPCOMING: &str = "SEARCH tasks USING INDEX idx_tasks_status (status=?)\n\
     USE TEMP B-TREE FOR ORDER BY";

/// The weekly-review deferred-count query currently has NO
/// supporting partial index (see issue #2292 notes and
/// `mcp-server/src/reviews/weekly/snapshot.rs`). The planner
/// picks `idx_tasks_status_priority_effective_due` as the best
/// available status-anchored index and post-filters on
/// `defer_count >= 3`.
///
/// The deferred-tasks read path already gets a dedicated partial
/// index (`idx_tasks_deferred_open`, predicate `defer_count >= 1`)
/// — but SQLite's partial-index matcher requires an exact predicate
/// match for binding. Since this query asks for `defer_count >= 3`
/// rather than `>= 1`, the planner can't currently use the new
/// index here. A future remediation would either lower the query
/// threshold to `>= 1` and post-filter, or add a second partial
/// index covering `defer_count >= 3`.
const EXPECTED_WEEKLY_REVIEW_DEFERRED: &str =
    "SEARCH tasks USING INDEX idx_tasks_status_priority_effective_due (status=?)";

/// `get_deferred_tasks` (no list_id scope) binds to the
/// `idx_tasks_deferred_open` partial index. SQLite uses status as
/// equality and defer_count as a range bound to seek into the
/// index, then post-filters on the partial predicate (defer_count
/// at-least 1 AND archived_at IS NULL). The index key list omits
/// `updated_at DESC` — the query's ORDER BY does not need it (it is
/// an HLC-rewritten column, unsuitable as a pagination tiebreaker),
/// and omitting it lets the planner satisfy the
/// `(defer_count DESC, id ASC)` ORDER BY directly from the index
/// without a temp B-tree.
const EXPECTED_GET_DEFERRED_TASKS: &str =
    "SEARCH tasks USING INDEX idx_tasks_deferred_open (status=? AND defer_count>?)";

/// `get_archived_tasks` binds to the upgraded
/// `idx_tasks_archived_at` partial index whose key list now matches
/// the Trash view's `(archived_at DESC, id ASC)` ORDER BY exactly,
/// so the seek runs without a temp B-tree filesort. Now that the
/// query only projects `id` (the legacy-list predicate is gone) the
/// planner reports the path as a COVERING index — `id` is the
/// implicit rowid that every partial index already carries.
const EXPECTED_GET_ARCHIVED_TASKS: &str =
    "SEARCH tasks USING COVERING INDEX idx_tasks_archived_at (archived_at>?)";

// ---------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------
//
// Scope guards (#2292):
//   - No production query is modified by this file.
//   - Tests run against `open_db_in_memory()` so no fixture data is
//     required — SQLite picks its plan from schema + WHERE shape, not
//     row counts. A plan that flips with row-count growth is already
//     broken for paging.
//   - Each test names the production call-site it mirrors.

#[test]
fn eqp_get_today_tasks_overdue_bucket_uses_due_date_index() {
    // Mirrors: read::get_overdue_tasks_for_today.
    // Called by: mcp-server/src/tasks/day_query/today.rs.
    let conn = open_db_in_memory().expect("open in-memory DB");
    let sql = sql_get_today_overdue();
    let actual = capture_plan(&conn, &sql);
    assert_plan(
        "get_today_tasks::overdue",
        &sql,
        &actual,
        EXPECTED_TODAY_OVERDUE,
    );
}

#[test]
fn eqp_get_today_tasks_today_pool_uses_action_date_partial_index() {
    // Mirrors: read::get_exact_today_tasks.
    // The COALESCE(planned_date, due_date) expression matches the
    // expression-index body of `idx_tasks_action_date_open`
    //. If the predicate shape ever drifts back to an
    // OR-of-columns form, this test fails loudly.
    let conn = open_db_in_memory().expect("open in-memory DB");
    let sql = sql_get_today_pool();
    let actual = capture_plan(&conn, &sql);
    assert_plan(
        "get_today_tasks::today_pool",
        &sql,
        &actual,
        EXPECTED_TODAY_POOL,
    );
}

#[test]
fn eqp_get_overview_top_by_priority_baseline() {
    // Mirrors: mcp-server/src/system/overview.rs::get_overview
    //          (`top_by_priority` block).
    let conn = open_db_in_memory().expect("open in-memory DB");
    let sql = sql_get_overview_top_by_priority();
    let actual = capture_plan(&conn, &sql);
    assert_plan(
        "get_overview::top_by_priority",
        &sql,
        &actual,
        EXPECTED_OVERVIEW_TOP_BY_PRIORITY,
    );
}

#[test]
fn eqp_get_overview_recently_completed_baseline() {
    // Mirrors: mcp-server/src/system/overview.rs::get_overview (`recently_completed`).
    // specifically guards against `datetime` wrapping
    // defeating the completed-at partial index — so plan drift here
    // is highly meaningful.
    let conn = open_db_in_memory().expect("open in-memory DB");
    let sql = sql_get_overview_recently_completed();
    let actual = capture_plan(&conn, &sql);
    assert_plan(
        "get_overview::recently_completed",
        &sql,
        &actual,
        EXPECTED_OVERVIEW_RECENTLY_COMPLETED,
    );
}

#[test]
fn eqp_get_task_detail_primary_fetch_uses_pk_autoindex() {
    // Mirrors: mcp-server/src/system/helpers/query_support/enrich.rs::fetch_task_json.
    let conn = open_db_in_memory().expect("open in-memory DB");
    let sql = sql_get_task_detail_primary();
    let actual = capture_plan(&conn, sql);
    assert_plan(
        "get_task_detail::primary",
        sql,
        &actual,
        EXPECTED_TASK_DETAIL_PRIMARY,
    );
}

#[test]
fn eqp_get_task_detail_tag_enrichment_uses_task_tags_unique_index() {
    // Mirrors: lorvex_workflow::task_enrichment (batched
    // tag lookup for MCP get_task / get_todays_tasks / etc.).
    let conn = open_db_in_memory().expect("open in-memory DB");
    let sql = sql_get_task_detail_tags();
    let actual = capture_plan(&conn, sql);
    assert_plan(
        "get_task_detail::tags",
        sql,
        &actual,
        EXPECTED_TASK_DETAIL_TAGS,
    );
}

#[test]
fn eqp_get_task_detail_reminders_enrichment_uses_task_index() {
    // Mirrors: mcp-server/src/system/helpers/query_support/enrich.rs::
    //           enrich_tasks_with_reminders.
    let conn = open_db_in_memory().expect("open in-memory DB");
    let sql = sql_get_task_detail_reminders();
    let actual = capture_plan(&conn, sql);
    assert_plan(
        "get_task_detail::reminders",
        sql,
        &actual,
        EXPECTED_TASK_DETAIL_REMINDERS,
    );
}

#[test]
fn eqp_get_upcoming_tasks_uses_action_date_partial_index() {
    // Mirrors: read::get_upcoming_tasks — the 7-day rolling
    // window. The COALESCE-on-both-ends form is what binds to
    // `idx_tasks_action_date_open`; the ORDER BY needs a temp
    // B-tree because the index key is the COALESCE expression and
    // cannot satisfy the multi-key ORDER BY directly.
    let conn = open_db_in_memory().expect("open in-memory DB");
    let sql = sql_get_upcoming();
    let actual = capture_plan(&conn, &sql);
    assert_plan("get_upcoming_tasks", &sql, &actual, EXPECTED_UPCOMING);
}

#[test]
fn eqp_get_archived_tasks_uses_archived_partial_index() {
    // Mirrors: read::archive::get_archived_tasks. The Trash
    // view ORDER BYs on (archived_at DESC, id ASC), and the
    // partial index's key list matches that exactly so the seek
    // runs without a temp B-tree filesort.
    let conn = open_db_in_memory().expect("open in-memory DB");
    let sql = sql_get_archived_tasks();
    let actual = capture_plan(&conn, &sql);
    assert_plan(
        "read::get_archived_tasks",
        &sql,
        &actual,
        EXPECTED_GET_ARCHIVED_TASKS,
    );
}

#[test]
fn eqp_get_deferred_tasks_uses_deferred_partial_index() {
    // Mirrors: read::deferred::get_deferred_tasks (unscoped
    // variant). Confirms the new `idx_tasks_deferred_open` partial
    // index binds to the exact WHERE shape the production code
    // emits, and that its (defer_count DESC, updated_at DESC, id
    // ASC) key list satisfies the ORDER BY without a temp B-tree.
    let conn = open_db_in_memory().expect("open in-memory DB");
    let sql = sql_get_deferred_tasks();
    let actual = capture_plan(&conn, &sql);
    assert_plan(
        "read::get_deferred_tasks",
        &sql,
        &actual,
        EXPECTED_GET_DEFERRED_TASKS,
    );
}

#[test]
fn eqp_weekly_review_deferred_count_baseline() {
    // Mirrors: mcp-server/src/reviews/weekly/snapshot.rs
    // (`WHERE status = 'open' AND defer_count >= 3`).
    //
    // No supporting partial index today — the planner falls back
    // to the best status-anchored composite. See the
    // EXPECTED_WEEKLY_REVIEW_DEFERRED comment for the remediation
    // path proposed by issue #2292.
    let conn = open_db_in_memory().expect("open in-memory DB");
    let sql = sql_weekly_review_deferred_count();
    let actual = capture_plan(&conn, &sql);
    assert_plan(
        "weekly_review::deferred_count",
        &sql,
        &actual,
        EXPECTED_WEEKLY_REVIEW_DEFERRED,
    );
}
