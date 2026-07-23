//! Habit `create` / `update` / `unarchive`: cue persistence, lookup
//! failure surfacing, and the active-lookup-key collision guard
//! that protects unarchive from blowing away an active duplicate.

use super::support::*;
use lorvex_domain::Patch;

#[test]
#[serial_test::serial(hlc)]
fn update_habit_surfaces_lookup_failures() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "habits",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let error = String::from(
        update_habit(
            &conn,
            UpdateHabitParams {
                id: "01966a3f-7c8b-7d4e-8f3a-000000000201",
                name: Some("Updated"),
                icon: Patch::Unset,
                color: Patch::Unset,
                cue: Patch::Unset,
                frequency_type: None,
                weekdays: None,
                per_period_target: None,
                day_of_month: None,
                target_count: None,
                archived: None,
            },
        )
        .expect_err("habit lookup failure should surface"),
    );
    assert!(
        error.contains("internal error") || error.contains("Please try again"),
        "unexpected error: {error}"
    );
    assert!(
        !error.contains("habit not found"),
        "database failure must not degrade into not-found error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn create_habit_persists_cue() {
    let conn = open_temp_db();

    let created = create_habit(
        &conn,
        CreateHabitParams {
            name: "Deep Work",
            icon: Some("brain"),
            color: Some("#123456"),
            cue: Some("After coffee"),
            frequency_type: Some("daily"),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: Some(1),
        },
    )
    .expect("create habit");

    let created: Habit = serde_json::from_str(&created).expect("decode created habit");
    assert_eq!(created.name, "Deep Work");
    assert_eq!(created.cue.as_deref(), Some("After coffee"));
    assert_eq!(created.icon.as_deref(), Some("brain"));
    assert_eq!(created.color.as_deref(), Some("#123456"));
}

#[test]
#[serial_test::serial(hlc)]
fn update_habit_updates_and_clears_cue() {
    let conn = open_temp_db();
    let created = create_habit(
        &conn,
        CreateHabitParams {
            name: "Stretch",
            icon: None,
            color: None,
            cue: Some("After lunch"),
            frequency_type: Some("daily"),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: Some(1),
        },
    )
    .expect("create habit");
    let created: Habit = serde_json::from_str(&created).expect("decode created habit");

    let updated = update_habit(
        &conn,
        UpdateHabitParams {
            id: &created.id,
            name: None,
            icon: Patch::Unset,
            color: Patch::Unset,
            cue: Patch::Set("After standup"),
            frequency_type: None,
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: None,
            archived: None,
        },
    )
    .expect("update habit");
    let updated: Habit = serde_json::from_str(&updated).expect("decode updated habit");
    assert_eq!(updated.cue.as_deref(), Some("After standup"));

    let cleared = update_habit(
        &conn,
        UpdateHabitParams {
            id: &created.id,
            name: None,
            icon: Patch::Unset,
            color: Patch::Unset,
            cue: Patch::Clear,
            frequency_type: None,
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: None,
            archived: None,
        },
    )
    .expect("clear cue");
    let cleared: Habit = serde_json::from_str(&cleared).expect("decode cleared habit");
    assert_eq!(cleared.cue, None);
}

#[test]
#[serial_test::serial(hlc)]
fn unarchive_habit_rejects_active_lookup_key_collision_before_db_write() {
    let conn = open_temp_db();
    let active = create_habit(
        &conn,
        CreateHabitParams {
            name: "Hydrate",
            icon: None,
            color: Some("#112233"),
            cue: None,
            frequency_type: Some("daily"),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: Some(1),
        },
    )
    .expect("create active habit");
    let active: Habit = serde_json::from_str(&active).expect("decode active habit");
    let key = lorvex_domain::tag::normalize_lookup_key(&active.name);
    conn.execute(
        "INSERT INTO habits (id, name, color, frequency_type, target_count, archived,
                 lookup_key, created_at, updated_at, version)
             VALUES ('archived-habit', 'Hydrate', '#445566', 'daily', 1, 1,
                 ?1, '2026-04-24T00:00:00Z', '2026-04-24T00:00:00Z',
                 '0000000000001_0000_0000000000000000')",
        params![key],
    )
    .expect("seed archived duplicate habit");

    let error = update_habit(
        &conn,
        UpdateHabitParams {
            id: "archived-habit",
            name: None,
            icon: Patch::Unset,
            color: Patch::Unset,
            cue: Patch::Unset,
            frequency_type: None,
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: None,
            archived: Some(false),
        },
    )
    .expect_err("unarchive should reject active lookup_key collision");
    let error = String::from(error);

    assert!(
        error.contains("already exists"),
        "error should explain the duplicate habit name: {error}"
    );

    let archived: bool = conn
        .query_row(
            "SELECT archived FROM habits WHERE id = 'archived-habit'",
            [],
            |row| row.get(0),
        )
        .expect("read archived state");
    assert!(archived, "failed unarchive must leave the row archived");
}
