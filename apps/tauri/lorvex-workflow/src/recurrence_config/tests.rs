use super::*;

fn state(
    recurrence: Option<&str>,
    group_id: Option<&str>,
    anchor: Option<&str>,
    due: Option<&str>,
) -> RecurrenceState {
    RecurrenceState {
        recurrence: recurrence.map(str::to_string),
        recurrence_group_id: group_id.map(str::to_string),
        canonical_occurrence_date: anchor.map(str::to_string),
        due_date: due.map(str::to_string),
        due_time: None,
    }
}

#[test]
fn enable_generates_all_active_series_fields() {
    let old = state(None, None, None, Some("2026-04-15"));
    let (transition, actions) =
        plan_recurrence_transition(&old, Some("{\"FREQ\":\"DAILY\"}"), "2026-04-01");
    assert!(matches!(transition, RecurrenceTransition::Enable));
    assert!(actions.set_recurrence_group_id.is_some());
    assert_eq!(
        actions.set_canonical_occurrence_date,
        lorvex_domain::Patch::Set("2026-04-15".to_string())
    );
    assert!(actions.set_due_date.is_none()); // already has due_date
}

#[test]
fn enable_without_due_date_assigns_today() {
    let old = state(None, None, None, None);
    let (transition, actions) =
        plan_recurrence_transition(&old, Some("{\"FREQ\":\"DAILY\"}"), "2026-04-01");
    assert!(matches!(transition, RecurrenceTransition::Enable));
    assert_eq!(actions.set_due_date, Some("2026-04-01".to_string()));
    assert_eq!(
        actions.set_canonical_occurrence_date,
        lorvex_domain::Patch::Set("2026-04-01".to_string())
    );
}

#[test]
fn update_rule_preserves_series_identity() {
    let old = state(
        Some("{\"FREQ\":\"DAILY\"}"),
        Some("grp-1"),
        Some("2026-04-15"),
        Some("2026-04-15"),
    );
    let (transition, actions) =
        plan_recurrence_transition(&old, Some("{\"FREQ\":\"WEEKLY\"}"), "2026-04-01");
    assert!(matches!(transition, RecurrenceTransition::UpdateRule));
    assert!(actions.set_recurrence_group_id.is_none());
    assert!(actions.set_canonical_occurrence_date.is_unset());
}

#[test]
fn disable_clears_active_series_config() {
    let old = state(
        Some("{\"FREQ\":\"DAILY\"}"),
        Some("grp-1"),
        Some("2026-04-15"),
        Some("2026-04-15"),
    );
    let (transition, actions) = plan_recurrence_transition(&old, None, "2026-04-01");
    assert!(matches!(transition, RecurrenceTransition::Disable));
    assert!(actions.clear_recurrence_group_id);
    assert!(actions.clear_canonical_occurrence_date);
}

#[test]
fn duplicate_creates_new_series_with_source_due_date() {
    let source = state(
        Some("{\"FREQ\":\"MONTHLY\"}"),
        Some("grp-old"),
        Some("2026-03-15"),
        Some("2026-03-20"),
    );
    let actions = plan_duplicate_recurrence(&source);
    assert!(actions.set_recurrence_group_id.is_some());
    assert_ne!(actions.set_recurrence_group_id.as_deref(), Some("grp-old"));
    // Anchor is source due_date (current visible schedule), not canonical_occurrence_date
    assert_eq!(
        actions.set_canonical_occurrence_date,
        lorvex_domain::Patch::Set("2026-03-20".to_string())
    );
}

#[test]
fn duplicate_non_recurring_is_noop() {
    let source = state(None, None, None, Some("2026-03-20"));
    let actions = plan_duplicate_recurrence(&source);
    assert!(actions.set_recurrence_group_id.is_none());
    assert!(actions.set_canonical_occurrence_date.is_unset());
}

#[test]
fn apply_rejects_clearing_due_date_while_due_time_remains() {
    let conn = lorvex_store::open_db_in_memory().expect("in-memory db");
    lorvex_store::test_support::TaskBuilder::new("time-with-date")
        .due_date(Some("2026-04-15"))
        .due_time(Some("09:30"))
        .insert(&conn);

    let task_id = lorvex_domain::TaskId::from_trusted("time-with-date".to_string());
    let Err(error) = apply_recurrence_change(
        &conn,
        &task_id,
        lorvex_domain::Patch::Unset,
        DueAtPatch::new(lorvex_domain::Patch::Clear, lorvex_domain::Patch::Unset),
        "2026-04-01",
        "9999999999999_0000_a0a0a0a0a0a0a0a0",
        "2026-04-01T00:00:00Z",
    ) else {
        panic!("clearing due_date must not leave due_time behind");
    };

    assert!(
        error.to_string().contains("due_time without due_date"),
        "unexpected validation error: {error}"
    );
}
