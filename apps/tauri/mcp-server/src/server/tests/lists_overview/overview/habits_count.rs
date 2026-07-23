use super::super::*;

/// #2750 — the overview response exposes habit aggregate counts under
/// the canonical field name `count` (not `total`), matching calendar,
/// memory, and task read responses across the MCP surface.
#[test]
#[serial_test::serial(hlc)]
fn get_overview_exposes_habit_count_under_canonical_field_name() {
    let server = make_server();

    // Seed two habits directly — `create_habit` validates names but we
    // just need existence for the overview aggregate.
    server
        .with_conn(|conn| {
            crate::habits::create_habit(
                conn,
                crate::habits::CreateHabitParams {
                    name: "Meditate",
                    icon: None,
                    color: None,
                    cue: None,
                    frequency_type: None,
                    weekdays: None,
                    per_period_target: None,
                    day_of_month: None,
                    target_count: None,
                },
            )
            .map_err(crate::system::handler_support::to_error_message)?;
            crate::habits::create_habit(
                conn,
                crate::habits::CreateHabitParams {
                    name: "Exercise",
                    icon: None,
                    color: None,
                    cue: None,
                    frequency_type: None,
                    weekdays: None,
                    per_period_target: None,
                    day_of_month: None,
                    target_count: None,
                },
            )
            .map_err(crate::system::handler_support::to_error_message)?;
            Ok(())
        })
        .expect("seed habits");

    let payload = server.get_overview().expect("get_overview should succeed");
    let value: Value = serde_json::from_str(&payload).expect("valid json");

    let habits = &value["habits"];
    assert_eq!(
        habits["count"], 2,
        "canonical `count` = non-archived habits"
    );
    assert_eq!(habits["completed_today"], 0);
    // Legacy `total` must not resurface.
    assert!(
        habits.get("total").is_none(),
        "legacy `total` field should be renamed to `count`"
    );
}
