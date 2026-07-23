use super::*;

#[test]
fn complete_from_open() {
    let actions = status_transition_columns(
        TaskStatus::Open,
        TaskStatus::Completed,
        "2026-03-26T10:00:00Z",
    );
    assert!(actions.contains(&ColumnAction::SetText(
        "completed_at",
        "2026-03-26T10:00:00Z".into()
    )));
    assert!(actions.contains(&ColumnAction::SetNull("last_deferred_at")));
    assert!(actions.contains(&ColumnAction::SetNull("last_defer_reason")));
}

#[test]
fn cancel_from_open() {
    let actions = status_transition_columns(
        TaskStatus::Open,
        TaskStatus::Cancelled,
        "2026-03-26T10:00:00Z",
    );
    assert!(actions.contains(&ColumnAction::SetNull("completed_at")));
    assert!(actions.contains(&ColumnAction::SetNull("last_deferred_at")));
    assert!(actions.contains(&ColumnAction::SetNull("last_defer_reason")));
}

#[test]
fn reopen_from_completed() {
    let actions = status_transition_columns(
        TaskStatus::Completed,
        TaskStatus::Open,
        "2026-03-26T10:00:00Z",
    );
    assert!(actions.contains(&ColumnAction::SetNull("completed_at")));
    assert!(actions.contains(&ColumnAction::SetNull("planned_date")));
    assert!(actions.contains(&ColumnAction::SetNull("last_deferred_at")));
    assert!(actions.contains(&ColumnAction::SetNull("last_defer_reason")));
    assert!(actions.contains(&ColumnAction::SetInt("defer_count", 0)));
}

#[test]
fn no_change_same_status() {
    assert!(status_transition_columns(TaskStatus::Open, TaskStatus::Open, "now").is_empty());
    assert!(
        status_transition_columns(TaskStatus::Completed, TaskStatus::Completed, "now").is_empty()
    );
    assert!(status_transition_columns(TaskStatus::Someday, TaskStatus::Someday, "now").is_empty());
}

#[test]
fn open_to_someday_no_metadata_changes() {
    // Moving to someday doesn't clear or set any metadata — it's a soft park
    let actions = status_transition_columns(
        TaskStatus::Open,
        TaskStatus::Someday,
        "2026-03-26T10:00:00Z",
    );
    assert!(actions.is_empty());
}

#[test]
fn someday_to_open_clears_deferral_and_planned_date() {
    let actions = status_transition_columns(
        TaskStatus::Someday,
        TaskStatus::Open,
        "2026-03-26T10:00:00Z",
    );
    assert!(actions.contains(&ColumnAction::SetNull("completed_at")));
    assert!(actions.contains(&ColumnAction::SetNull("planned_date")));
    assert!(actions.contains(&ColumnAction::SetNull("last_deferred_at")));
    assert!(actions.contains(&ColumnAction::SetNull("last_defer_reason")));
    assert!(actions.contains(&ColumnAction::SetInt("defer_count", 0)));
}

#[test]
fn someday_to_completed_sets_completed_at() {
    let actions = status_transition_columns(
        TaskStatus::Someday,
        TaskStatus::Completed,
        "2026-03-26T10:00:00Z",
    );
    assert!(actions.contains(&ColumnAction::SetText(
        "completed_at",
        "2026-03-26T10:00:00Z".into()
    )));
}

#[test]
fn completed_to_someday_clears_completed_at() {
    let actions = status_transition_columns(
        TaskStatus::Completed,
        TaskStatus::Someday,
        "2026-03-26T10:00:00Z",
    );
    assert!(actions.contains(&ColumnAction::SetNull("completed_at")));
    // Should NOT clear planned_date or defer state (no transition to open)
    assert!(!actions.contains(&ColumnAction::SetNull("planned_date")));
}

#[test]
fn typed_entry_point_covers_every_status_pair() {
    for old in [
        TaskStatus::Open,
        TaskStatus::Completed,
        TaskStatus::Cancelled,
        TaskStatus::Someday,
    ] {
        for new in [
            TaskStatus::Open,
            TaskStatus::Completed,
            TaskStatus::Cancelled,
            TaskStatus::Someday,
        ] {
            let _ = status_transition_columns(old, new, "ts");
        }
    }
}
