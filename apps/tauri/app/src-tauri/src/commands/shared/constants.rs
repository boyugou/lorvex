/// column allowlists are owned by
/// [`lorvex_store::repositories::columns`]. The aliases here are kept
/// so existing call sites (`format!("SELECT {TASK_COLS} FROM tasks
/// …")`) keep compiling without churn; new callers should reach for
/// `lorvex_store::repositories::columns::TASKS.select_clause()`
/// directly.
pub const TASK_COLS: &str = lorvex_store::repositories::columns::TASKS.select_clause;

/// the Tauri `lists` row mapper does not read
/// `version`, so this alias deliberately uses the without-version
/// flavor. The MCP server / store side reads the column from the
/// canonical [`lorvex_store::repositories::columns::LISTS`] entry
/// directly.
pub const LIST_COLS: &str =
    lorvex_store::repositories::columns::LISTS.select_clause_without_version;

pub(crate) const MAX_CHANGELOG_LIMIT: i64 = 1_000;
pub(crate) fn ai_changelog_where_clause() -> String {
    lorvex_store::repositories::ai_changelog_actor_filter::ai_changelog_assistant_actor_filter_sql()
}

pub(crate) fn ai_changelog_where_clause_for_alias(alias: &str) -> String {
    lorvex_store::repositories::ai_changelog_actor_filter::ai_changelog_assistant_actor_filter_sql_for_alias(alias)
}
pub(crate) const MAX_ERROR_LOG_LIMIT: i64 = 5_000;
pub(crate) const MAX_UPCOMING_DAYS: i64 = 365;
/// Maximum query-window length (in seconds) accepted by
/// `get_upcoming_reminders` for adaptive polling.
///
/// The name carries `_QUERY_` to disambiguate from the domain-level
/// `lorvex_domain::validation::MAX_REMINDER_WINDOW_SECONDS` (365
/// days, the cap on how far in the future a reminder can be
/// SCHEDULED). The two constants encode entirely different
/// concepts, and a future caller reaching for the unqualified name
/// could pick the wrong one. The 1-day cap reflects the polling
/// cadence the UI actually drives.
pub(crate) const MAX_REMINDER_QUERY_WINDOW_SECONDS: i64 = 86_400;
pub(crate) const MAX_SYNC_EVENTS_LIMIT: i64 = 1_000;
pub(crate) const SYNC_GC_RETENTION_DAYS: i64 = 90;

pub(crate) fn is_syncable_entity_type(entity_type: &str) -> bool {
    lorvex_domain::naming::is_syncable_type(entity_type)
}
pub(crate) const SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY: &str =
    "filesystem_bridge_last_pull_cursor";
pub(crate) const SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_KEY: &str =
    "filesystem_bridge_lookback_known_id_skipped_last_run";
pub(crate) const SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_AT_KEY: &str =
    "filesystem_bridge_lookback_known_id_skipped_last_run_at";
pub(crate) const FILESYSTEM_BRIDGE_CURSOR_LOOKBACK_SECONDS: i64 = 86_400;
pub(crate) const FILESYSTEM_BRIDGE_CURSOR_LOOKBACK_CAP_MULTIPLIER: usize = 2;

/// IPC-boundary cap for bulk-mutation Vec inputs.
///
/// an unbounded `Vec<T>` arriving over IPC lets a
/// runaway frontend bug (or a hostile MCP-style caller) drive the
/// writer transaction into a multi-megabyte UPDATE storm before the
/// writer-side validators ever see the rows. 1 000 entries comfortably
/// exceeds every legitimate UI-driven bulk action (a focus-day
/// schedule has dozens of blocks; a checklist has tens of items; a
/// list shelve handles all open tasks in one list, in practice
/// hundreds at most) while still bounding the worst case to something
/// the writer transaction can handle without locking out the rest of
/// the app.
pub(crate) const MAX_IPC_BATCH_ITEMS: usize = 1_000;
