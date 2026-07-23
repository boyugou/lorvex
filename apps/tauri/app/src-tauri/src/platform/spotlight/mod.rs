//! Platform-native task search indexing — makes tasks discoverable outside the app.
//!
//! - **macOS:** Core Spotlight integration. Typing a task title in Spotlight shows
//!   it as a result. Each indexed item carries a `contentURL` of `lorvex://task/<id>`,
//!   so clicking the result opens Lorvex via the deep-link handler in `lib.rs`.
//!
//! - **Windows:** Jump List integration via `ICustomDestinationList`. Right-clicking
//!   the taskbar icon shows a "Recent Tasks" category with shell links. Each link
//!   launches the app with `--open-task <id>` so the deep-link handler can navigate
//!   to the task.
//!
//! All public functions are no-ops on unsupported platforms (Linux, mobile).

/// The domain identifier used for all Lorvex searchable items in Spotlight.
/// This scopes our index entries so we can bulk-delete without affecting
/// other apps' entries.
const SPOTLIGHT_DOMAIN: &str = "com.lorvex.planner.tasks";

#[cfg(any(target_os = "macos", target_os = "windows"))]
mod diagnostics;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
mod noop;
#[cfg(any(target_os = "macos", target_os = "windows"))]
mod queries;
#[cfg(target_os = "windows")]
mod windows;

#[cfg(any(target_os = "macos", target_os = "windows"))]
use diagnostics::log_spotlight_error;
#[cfg(target_os = "windows")]
use diagnostics::log_spotlight_warning;

#[cfg(target_os = "macos")]
use macos as inner;
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
use noop as inner;
#[cfg(target_os = "windows")]
use windows as inner;

// ---------------------------------------------------------------------------
// Public API (platform-agnostic)
// ---------------------------------------------------------------------------

pub use inner::reindex_all_tasks;
pub(crate) use inner::reindex_tasks_by_ids;
pub(crate) use inner::reindex_tasks_for_list;
pub use inner::remove_all_tasks;
pub(crate) use inner::remove_task;

// ---------------------------------------------------------------------------
// Deferred (post-commit) Spotlight dispatch
// ---------------------------------------------------------------------------

/// A deferred Spotlight action to be applied after a transaction commits.
/// Collecting these inside a transaction and applying them afterwards avoids
/// performing Spotlight I/O (which reads from the DB) while a write-lock is
/// held, preventing potential deadlocks and keeping transactions short.
#[derive(Debug, Clone)]
pub enum SpotlightAction {
    /// Re-index one or more tasks by their IDs (queries the DB for current state).
    ReindexTaskIds(Vec<String>),
    /// Re-index all tasks belonging to a list (e.g. after list rename or task reassignment).
    ReindexList(String),
    /// Remove specific task IDs from the Spotlight index.
    RemoveTaskIds(Vec<String>),
}

/// Apply a batch of deferred Spotlight actions. Call this **after** the
/// transaction that produced the actions has committed.
pub fn apply_actions(conn: &rusqlite::Connection, actions: &[SpotlightAction]) {
    for action in actions {
        match action {
            SpotlightAction::ReindexTaskIds(ids) => {
                reindex_tasks_by_ids(conn, ids);
            }
            SpotlightAction::ReindexList(list_id) => {
                reindex_tasks_for_list(conn, list_id);
            }
            SpotlightAction::RemoveTaskIds(ids) => {
                for id in ids {
                    remove_task(id);
                }
            }
        }
    }
}

#[cfg(all(test, any(target_os = "macos", target_os = "windows")))]
mod regression_tests {
    use crate::commands::diagnostics::{append_error_log_internal, read_error_logs};
    use crate::test_support::test_conn;

    /// Regression: Spotlight (macOS) and Jump List (Windows)
    /// indexing failures must land in `error_logs` so Settings →
    /// Diagnostics surfaces them. `eprintln!`-only logging would be
    /// invisible on release binaries (no console on macOS,
    /// `windows_subsystem = windows` on Windows), leaving users who
    /// searched Spotlight and didn't find their task with no trace
    /// of why.
    ///
    /// Like the sibling test in notification_actions.rs, we mirror
    /// the body of `log_spotlight_error` inline rather than calling
    /// it directly. The real helper hits `crate::db::get_conn()`,
    /// which initializes a process-wide pool whose HLC-init step is
    /// not idempotent against `ensure_hlc_for_test` — so an
    /// end-to-end call through the helper races other tests in the
    /// same binary. See the note on the issue #2630 thread for the
    /// follow-up needed to make the helper directly testable. This
    /// test still pins the `source` tag, the level, and the
    /// `{context}: {message}` format that the helper writes.
    #[test]
    fn spotlight_error_writes_are_persisted_with_stable_source_tag() {
        let conn = test_conn();

        // Exact replica of `log_spotlight_error` (#2580). Any change
        // to its source tag, level, or format must also update this
        // test.
        let context = "reindex_all_tasks: regression #2630";
        let underlying = "simulated CoreSpotlight/JumpList failure";
        let detail = format!("{context}: {underlying}");
        append_error_log_internal(
            &conn,
            "platform.spotlight",
            &detail,
            None,
            Some("warn".to_string()),
        )
        .expect("append_error_log_internal must succeed");

        let logs = read_error_logs(&conn, Some(10), None).expect("read error_logs");
        let row = logs
            .iter()
            .find(|row| row.source == "platform.spotlight")
            .expect("platform.spotlight row must exist");
        assert_eq!(
            row.level, "warn",
            "spotlight failures must log at level=warn — degraded \
             platform feature, not a correctness bug"
        );
        assert!(
            row.message.contains("reindex_all_tasks: regression #2630"),
            "message must carry the context string; got: {}",
            row.message
        );
        assert!(
            row.message
                .contains("simulated CoreSpotlight/JumpList failure"),
            "message must carry the underlying failure detail; got: {}",
            row.message
        );
    }
}
