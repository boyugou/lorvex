//! Cached SQL string builders for the dependency graph repository.
//!
//! via `format!` on every call to [`super::graph::get_dependency_graph`]
//! — both the 4-way scope branching and the `include_inactive` toggle
//! baked in the static `ACTIVE_STATUS_SQL_LIST` constant via a runtime
//! template substitution. Each call therefore allocated up to two
//! short-lived `String`s before reaching `prepare_cached`. The strings
//! depend only on a 3-bit shape `(has_task_id, has_list_id,
//! include_inactive)` so the eight edge variants and the single
//! center-node SQL are memoizable behind `OnceLock`. Init runs at most
//! 8 + 1 = 9 times per process; thereafter each call resolves to a
//! `&'static str` without allocation.

use lorvex_domain::naming;

const ACTIVE_FILTER_INACTIVE: &str = " AND t1.archived_at IS NULL AND t2.archived_at IS NULL";

fn active_filter_for(include_inactive: bool) -> std::borrow::Cow<'static, str> {
    if include_inactive {
        std::borrow::Cow::Borrowed(ACTIVE_FILTER_INACTIVE)
    } else {
        // Active = "open or someday" — see
        // `lorvex_domain::naming::status::ACTIVE_STATUS_SQL_LIST` for
        // the canonical literal list shared with every other site
        // that gates on actionable tasks.
        std::borrow::Cow::Owned(format!(
            "{ACTIVE_FILTER_INACTIVE} \
             AND t1.status IN ({list}) AND t2.status IN ({list})",
            list = naming::status::ACTIVE_STATUS_SQL_LIST,
        ))
    }
}

/// Return the `&'static str` SQL for the requested edge query shape.
///
/// Eight variants total: 4 scope branches (`task_id` × `list_id`) ×
/// 2 `include_inactive` toggles. Each variant is built once and lives
/// in its own `OnceLock<&'static str>` slot via `String::leak` so
/// `prepare_cached` can pin the same key on every subsequent call
/// without re-running the template substitution.
///
/// Centered queries (cases with `task_id`) split the
/// `(td.task_id = :center_id OR td.depends_on_task_id = :center_id)`
/// OR-predicate into a `UNION ALL` of two single-index legs. SQLite
/// cannot OR-merge across the PK on `task_id` and the secondary index
/// on `depends_on_task_id` in the OR shape; a dependency table with a
/// few thousand edges fell back to a full scan + tasks-JOIN per
/// envelope. The schema CHECK constraint prevents
/// `task_id = depends_on_task_id`, so UNION ALL never double-counts a
/// self-loop edge.
pub(super) fn edges_sql_for_shape(
    has_task_id: bool,
    has_list_id: bool,
    include_inactive: bool,
) -> &'static str {
    use std::sync::OnceLock;
    static SLOTS: [OnceLock<&'static str>; 8] = [
        OnceLock::new(),
        OnceLock::new(),
        OnceLock::new(),
        OnceLock::new(),
        OnceLock::new(),
        OnceLock::new(),
        OnceLock::new(),
        OnceLock::new(),
    ];
    let idx = (usize::from(has_task_id) << 2)
        | (usize::from(has_list_id) << 1)
        | usize::from(include_inactive);
    SLOTS[idx].get_or_init(|| {
        let active = active_filter_for(include_inactive);
        let active = active.as_ref();
        let s: String = match (has_task_id, has_list_id) {
            (true, true) => format!(
                "SELECT td.task_id, td.depends_on_task_id \
                 FROM task_dependencies td \
                 JOIN tasks t1 ON td.task_id = t1.id AND t1.list_id = :list_id \
                 JOIN tasks t2 ON td.depends_on_task_id = t2.id AND t2.list_id = :list_id \
                 WHERE td.task_id = :center_id{active} \
                 UNION ALL \
                 SELECT td.task_id, td.depends_on_task_id \
                 FROM task_dependencies td \
                 JOIN tasks t1 ON td.task_id = t1.id AND t1.list_id = :list_id \
                 JOIN tasks t2 ON td.depends_on_task_id = t2.id AND t2.list_id = :list_id \
                 WHERE td.depends_on_task_id = :center_id{active} \
                 ORDER BY 1 ASC, 2 ASC \
                 LIMIT :edge_fetch_limit"
            ),
            (true, false) => format!(
                "SELECT td.task_id, td.depends_on_task_id \
                 FROM task_dependencies td \
                 JOIN tasks t1 ON td.task_id = t1.id \
                 JOIN tasks t2 ON td.depends_on_task_id = t2.id \
                 WHERE td.task_id = :center_id{active} \
                 UNION ALL \
                 SELECT td.task_id, td.depends_on_task_id \
                 FROM task_dependencies td \
                 JOIN tasks t1 ON td.task_id = t1.id \
                 JOIN tasks t2 ON td.depends_on_task_id = t2.id \
                 WHERE td.depends_on_task_id = :center_id{active} \
                 ORDER BY 1 ASC, 2 ASC \
                 LIMIT :edge_fetch_limit"
            ),
            (false, true) => format!(
                "SELECT td.task_id, td.depends_on_task_id \
                 FROM task_dependencies td \
                 JOIN tasks t1 ON td.task_id = t1.id AND t1.list_id = :list_id \
                 JOIN tasks t2 ON td.depends_on_task_id = t2.id AND t2.list_id = :list_id \
                 WHERE 1=1{active} \
                 ORDER BY td.task_id ASC, td.depends_on_task_id ASC \
                 LIMIT :edge_fetch_limit"
            ),
            (false, false) => format!(
                "SELECT td.task_id, td.depends_on_task_id \
                 FROM task_dependencies td \
                 JOIN tasks t1 ON td.task_id = t1.id \
                 JOIN tasks t2 ON td.depends_on_task_id = t2.id \
                 WHERE 1=1{active} \
                 ORDER BY td.task_id ASC, td.depends_on_task_id ASC \
                 LIMIT :edge_fetch_limit"
            ),
        };
        // `String::leak` returns a `&'static mut str` that coerces
        // to `&'static str`. The slot is initialized at most once
        // per shape over the process lifetime — bounded at 8 leaks.
        &*s.leak()
    })
}

/// Single-row SELECT used when the center task has no edges in the
/// requested scope. The only template input is the static
/// `ACTIVE_STATUS_SQL_LIST` constant, so cache the rendered SQL once
/// and hand out a `&'static str` to every subsequent call.
pub(super) fn center_node_sql() -> &'static str {
    use std::sync::OnceLock;
    static SQL: OnceLock<&'static str> = OnceLock::new();
    SQL.get_or_init(|| {
        let s = format!(
            "SELECT t.id, t.title, t.status, t.priority, t.due_date, t.planned_date, t.list_id \
             FROM tasks t \
             WHERE t.id = ?1 \
               AND t.archived_at IS NULL \
               AND (?2 IS NULL OR t.list_id = ?2) \
               AND (?3 = 1 OR t.status IN ({active_list}))",
            active_list = naming::status::ACTIVE_STATUS_SQL_LIST,
        );
        &*s.leak()
    })
}
