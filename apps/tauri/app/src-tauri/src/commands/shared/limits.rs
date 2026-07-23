//! shared IPC payload caps for task-list endpoints.
//!
//! `GET_ALL_TASKS_LIMIT` (in `task_queries.rs`) and
//! `GET_LIST_TASKS_LIMIT` (in `lists.rs`) carried the same value
//! (10_000) but lived in two different files with overlapping
//! comments. The next time someone tuned the cap they had to
//! remember to edit both — exactly the bookkeeping error this
//! audit pass was meant to flag. Consolidate the canonical value
//! here; both call sites now re-export it.

/// Hard upper bound on the row count returned by the task-list IPC
/// endpoints (`get_all_tasks`, `get_list_with_tasks`). Anything
/// beyond this clamps the result set; the UI surfaces a "showing
/// K of N" message via the `total_matching` field on the response.
///
/// 10_000 is well above the largest realistic single-list size
/// (a power user with three years of history) and well below the
/// SQLite `LIMIT` performance cliff. Bump only if a profiled real-
/// world workload demonstrates the truncation is meaningfully
/// hiding data the user wants to see.
pub(crate) const TASK_LIST_RESULT_LIMIT: u32 = 10_000;
