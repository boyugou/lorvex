//! Empty-list hint copy for the task list/collection renderers.
//!
//! The hints are selected by substring-matching a small, stable set of
//! caller-supplied titles/labels so a rename in the caller still falls
//! back to a generic suggestion rather than emitting a wall of
//! identical hints.

/// Pick the empty-list hint shown beneath an empty
/// `render_task_section` header. The shared dashboard / focus / TUI
/// surfaces pass a small, stable set of titles ("Focus tasks", "Due
/// today", "Upcoming", "Recently completed", …); match those by
/// substring so a section header rename in the caller still falls
/// back to a generic suggestion rather than a wall of identical hints.
pub(super) fn empty_hint_for_section(title: &str) -> &'static str {
    let lowered = title.to_ascii_lowercase();
    if lowered.contains("focus") {
        "No focus tasks set — `lorvex focus set <task-id>` or let your assistant call `focus_set` to pin one."
    } else if lowered.contains("due") {
        "Nothing due today — pick the next task with `lorvex task ls --due-by today`."
    } else if lowered.contains("upcoming") {
        "No upcoming items in this window — try widening with `lorvex task ls --due-by <date>`."
    } else if lowered.contains("complete") {
        "No tasks completed yet — finish one with `lorvex task complete <task-id>`."
    } else {
        "Nothing here yet — capture a task with `lorvex task capture \"<title>\"`."
    }
}

/// Pick the empty-list hint shown beneath an empty
/// `render_task_collection` banner. The shared dispatchers feed a
/// small, stable set of labels ("Today", "Inbox", "Trash",
/// "Someday", …); substring-match those so a rename in the caller
/// still falls back to a generic suggestion.
pub(super) fn empty_hint_for_collection(label: &str) -> &'static str {
    let lowered = label.to_ascii_lowercase();
    if lowered.contains("today") {
        "Nothing scheduled for today — pull from upcoming with `lorvex task plan <task-id> --date today`."
    } else if lowered.contains("inbox") {
        "Inbox empty — capture a quick task with `lorvex task capture \"<title>\"`."
    } else if lowered.contains("trash") {
        "Trash is empty — deleted tasks reach this view before permanent removal."
    } else if lowered.contains("someday") || lowered.contains("later") {
        "Nothing parked here — shelve a task with `lorvex task defer <task-id> --to someday`."
    } else {
        "No tasks in this view — capture one with `lorvex task capture \"<title>\"`."
    }
}
