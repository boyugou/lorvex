use super::*;
use crate::commands::shared::test_support::{hid, hrpid};
use lorvex_domain::naming::{EDGE_HABIT_COMPLETION, ENTITY_HABIT, ENTITY_HABIT_REMINDER_POLICY};
use lorvex_domain::Patch;
use lorvex_runtime::read_local_change_seq;

#[test]
fn create_update_and_delete_habit_syncs_rows_children_and_changelog() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    let habit = create_habit_with_conn(
        &mut conn,
        "  Morning pages  ",
        Some("M"),
        Some("#A1b2C3"),
        Some("After coffee"),
        Some(lorvex_domain::habits::HabitCadence::Daily),
        Some(2),
    )
    .expect("create habit");
    assert_eq!(habit.name, "Morning pages");
    assert_eq!(habit.target_count, 2);

    let created_outbox: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'upsert'",
            [ENTITY_HABIT, habit.id.as_str()],
            |row| row.get(0),
        )
        .expect("count habit create outbox");
    assert_eq!(created_outbox, 1);

    // Cadence replacement is atomic: switching to a weekly cadence
    // rewrites the typed columns and rebuilds the `habit_weekdays` child
    // from the weekday set (mon/wed/fri → Mon-first 0/2/4).
    let updated = update_habit_with_conn(
        &mut conn,
        &hid(&habit.id),
        HabitUpdateFields {
            name: Some("Morning writing"),
            icon: Patch::Clear,
            frequency: Some(lorvex_domain::habits::HabitCadence::Weekly {
                days: Some(vec![
                    lorvex_domain::habits::WeekDay::Mon,
                    lorvex_domain::habits::WeekDay::Wed,
                    lorvex_domain::habits::WeekDay::Fri,
                ]),
            }),
            archived: Some(true),
            ..HabitUpdateFields::default()
        },
    )
    .expect("update habit");
    assert_eq!(updated.name, "Morning writing");
    assert_eq!(updated.icon, None);
    assert_eq!(updated.frequency_type, "weekly");
    assert_eq!(updated.weekdays, vec![0, 2, 4]);
    assert!(updated.archived);

    conn.execute(
        "INSERT INTO habit_completions (habit_id, completed_date, value, note, version, created_at, updated_at)
             VALUES (?1, '2026-04-24', 2, 'Read appendix', '0000000000001_0000_0000000000000000', '2026-04-24T00:00:00Z', '2026-04-24T00:30:00Z')",
        [&habit.id],
    )
    .expect("seed habit completion");
    let policy_id = "018f4b55-cb10-7cc0-bc2d-123456789abc";
    conn.execute(
        "INSERT INTO habit_reminder_policies (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
             VALUES (?1, ?2, '09:00', 0, '0000000000001_0000_0000000000000000', '2026-04-23T00:00:00Z', '2026-04-23T00:30:00Z')",
        [policy_id, &habit.id],
    )
    .expect("seed habit reminder policy");

    let deleted = delete_habit_with_conn(&mut conn, &hid(&habit.id)).expect("delete habit");
    assert_eq!(deleted.id, habit.id);
    assert_eq!(deleted.completions_destroyed, 1);
    assert_eq!(deleted.reminder_policies_destroyed, 1);

    let remaining_habit: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM habits WHERE id = ?1",
            [&deleted.id],
            |row| row.get(0),
        )
        .expect("count remaining habit");
    assert_eq!(remaining_habit, 0);

    let habit_payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'delete'",
            [ENTITY_HABIT, deleted.id.as_str()],
            |row| row.get(0),
        )
        .expect("read habit delete payload");
    let habit_payload: serde_json::Value =
        serde_json::from_str(&habit_payload).expect("parse habit payload");
    assert_eq!(habit_payload["id"], deleted.id);
    assert_eq!(habit_payload["name"], "Morning writing");
    assert_eq!(habit_payload["frequency_type"], "weekly");
    assert_eq!(habit_payload["target_count"], deleted.previous.target_count);
    assert_eq!(habit_payload["created_at"], deleted.previous.created_at);
    assert_eq!(habit_payload["updated_at"], deleted.previous.updated_at);
    assert_eq!(habit_payload["version"], deleted.previous.version);

    let child_delete_outbox: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
                 WHERE (entity_type = ?1 AND entity_id = ?2 AND operation = 'delete')
                    OR (entity_type = ?3 AND entity_id = ?4 AND operation = 'delete')",
            [
                EDGE_HABIT_COMPLETION,
                format!("{}:2026-04-24", deleted.id).as_str(),
                ENTITY_HABIT_REMINDER_POLICY,
                policy_id,
            ],
            |row| row.get(0),
        )
        .expect("count child delete outbox rows");
    assert_eq!(child_delete_outbox, 2);

    let completion_payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'delete'",
            [
                EDGE_HABIT_COMPLETION,
                format!("{}:2026-04-24", deleted.id).as_str(),
            ],
            |row| row.get(0),
        )
        .expect("read completion delete payload");
    let completion_payload: serde_json::Value =
        serde_json::from_str(&completion_payload).expect("parse completion payload");
    assert_eq!(completion_payload["habit_id"], deleted.id);
    assert_eq!(completion_payload["completed_date"], "2026-04-24");
    assert_eq!(completion_payload["value"], 2);
    assert_eq!(completion_payload["note"], "Read appendix");
    assert_eq!(completion_payload["created_at"], "2026-04-24T00:00:00Z");
    assert_eq!(completion_payload["updated_at"], "2026-04-24T00:30:00Z");
    assert!(completion_payload["version"].as_str().is_some());

    let policy_payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'delete'",
            [ENTITY_HABIT_REMINDER_POLICY, policy_id],
            |row| row.get(0),
        )
        .expect("read policy delete payload");
    let policy_payload: serde_json::Value =
        serde_json::from_str(&policy_payload).expect("parse policy payload");
    assert_eq!(policy_payload["id"], policy_id);
    assert_eq!(policy_payload["habit_id"], deleted.id);
    assert_eq!(policy_payload["reminder_time"], "09:00");
    assert_eq!(policy_payload["enabled"], false);
    assert_eq!(policy_payload["created_at"], "2026-04-23T00:00:00Z");
    assert_eq!(policy_payload["updated_at"], "2026-04-23T00:30:00Z");
    assert!(policy_payload["version"].as_str().is_some());

    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_HABIT, deleted.id.as_str()],
            |row| row.get(0),
        )
        .expect("count habit changelog");
    assert_eq!(changelog_count, 3);

    let seq = read_local_change_seq(&conn).expect("read local change seq");
    assert_eq!(seq, 3);
}

#[test]
fn create_habit_rejects_invalid_color_before_side_effects() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    let error = create_habit_with_conn(
        &mut conn,
        "Hydrate",
        None,
        Some("red"),
        None,
        Some(lorvex_domain::habits::HabitCadence::Daily),
        Some(1),
    )
    .expect_err("invalid habit color should be rejected");

    assert!(
        matches!(error, crate::error::CliError::Validation(_)),
        "expected validation error, got {error:?}"
    );
    assert!(
        error.to_string().contains("color"),
        "error should identify the color field: {error}"
    );

    let habit_rows: i64 = conn
        .query_row("SELECT COUNT(*) FROM habits", [], |row| row.get(0))
        .expect("count habit rows");
    assert_eq!(habit_rows, 0, "invalid color must not insert a habit");

    let outbox_rows: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
        .expect("count outbox rows");
    assert_eq!(outbox_rows, 0, "invalid color must not enqueue sync");
}

#[test]
fn update_habit_rejects_invalid_color_and_accepts_hex_color() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let habit = create_habit_with_conn(
        &mut conn,
        "Hydrate",
        None,
        Some("#112233"),
        None,
        Some(lorvex_domain::habits::HabitCadence::Daily),
        Some(1),
    )
    .expect("valid initial habit color should be accepted");

    let error = update_habit_with_conn(
        &mut conn,
        &hid(&habit.id),
        HabitUpdateFields {
            color: Patch::Set("red"),
            ..HabitUpdateFields::default()
        },
    )
    .expect_err("invalid habit update color should be rejected");

    assert!(
        matches!(error, crate::error::CliError::Validation(_)),
        "expected validation error, got {error:?}"
    );
    assert!(
        error.to_string().contains("color"),
        "error should identify the color field: {error}"
    );

    let stored_color: Option<String> = conn
        .query_row(
            "SELECT color FROM habits WHERE id = ?1",
            [&habit.id],
            |row| row.get(0),
        )
        .expect("read stored color");
    assert_eq!(stored_color.as_deref(), Some("#112233"));

    let updated = update_habit_with_conn(
        &mut conn,
        &hid(&habit.id),
        HabitUpdateFields {
            color: Patch::Set("#AABBCC"),
            ..HabitUpdateFields::default()
        },
    )
    .expect("canonical hex habit update color should be accepted");
    assert_eq!(updated.color.as_deref(), Some("#AABBCC"));
}

#[test]
fn unarchive_habit_rejects_active_lookup_key_collision_before_db_write() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    let active = create_habit_with_conn(
        &mut conn,
        "Hydrate",
        None,
        Some("#112233"),
        None,
        Some(lorvex_domain::habits::HabitCadence::Daily),
        Some(1),
    )
    .expect("create active habit");
    let key = lorvex_domain::tag::normalize_lookup_key(&active.name);
    conn.execute(
        "INSERT INTO habits (id, name, color, frequency_type, target_count, archived,
                 lookup_key, created_at, updated_at, version)
             VALUES ('archived-habit', 'Hydrate', '#445566', 'daily', 1, 1,
                 ?1, '2026-04-24T00:00:00Z', '2026-04-24T00:00:00Z',
                 '0000000000001_0000_0000000000000000')",
        [&key],
    )
    .expect("seed archived duplicate habit");

    let error = update_habit_with_conn(
        &mut conn,
        &hid("archived-habit"),
        HabitUpdateFields {
            archived: Some(false),
            ..HabitUpdateFields::default()
        },
    )
    .expect_err("unarchive should reject active lookup_key collision");

    assert!(
        matches!(error, crate::error::CliError::Conflict(_)),
        "expected conflict error, got {error:?}"
    );
    assert!(
        error.to_string().contains("already exists"),
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

/// Schema-layer dedup enforcement. Two habits whose names differ only by
/// Unicode normalization must collide at the partial unique index, not only at
/// the CLI pre-check.
#[test]
fn habit_unique_index_rejects_unicode_duplicates_at_schema_layer() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    use lorvex_domain::tag::normalize_lookup_key;

    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    create_habit_with_conn(&mut conn, "Café", None, None, None, None, Some(1))
        .expect("first create should succeed");

    let conflict =
        create_habit_with_conn(&mut conn, "Cafe\u{0301}", None, None, None, None, Some(1))
            .expect_err("decomposed Unicode duplicate must be rejected");
    assert!(
        matches!(conflict, crate::error::CliError::Conflict(_)),
        "expected Conflict, got {conflict:?}"
    );

    let key = normalize_lookup_key("Cafe\u{0301}");
    let raw_id = uuid::Uuid::now_v7().to_string();
    let now = lorvex_domain::sync_timestamp_now();
    let raw_err = conn
        .execute(
            "INSERT INTO habits (id, name, frequency_type, target_count, archived, \
                     lookup_key, created_at, updated_at, version) \
                 VALUES (?1, ?2, 'daily', 1, 0, ?3, ?4, ?4, '0000000000001_0000_lookupkeydup')",
            rusqlite::params![raw_id, "Cafe\u{0301}", key, now],
        )
        .expect_err("partial UNIQUE index must reject the raw INSERT");
    let message = raw_err.to_string();
    assert!(
        message.contains("UNIQUE") || message.contains("unique"),
        "expected UNIQUE constraint violation, got: {message}"
    );
}

#[test]
fn habit_reminder_policy_crud_syncs_and_logs() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let habit = create_habit_with_conn(&mut conn, "Read", None, None, None, None, Some(1))
        .expect("create habit");

    let habit_id_typed = hid(&habit.id);
    let created =
        upsert_habit_reminder_policy_with_conn(&mut conn, None, &habit_id_typed, "07:30", true)
            .expect("create reminder policy");
    assert_eq!(created.habit_id, habit.id);
    assert_eq!(created.reminder_time, "07:30");
    assert!(created.enabled);

    let policy_id_typed = hrpid(&created.id);
    let updated = upsert_habit_reminder_policy_with_conn(
        &mut conn,
        Some(&policy_id_typed),
        &habit_id_typed,
        "08:00",
        false,
    )
    .expect("update reminder policy");
    assert_eq!(updated.id, created.id);
    assert_eq!(updated.reminder_time, "08:00");
    assert!(!updated.enabled);

    let policies = list_habit_reminder_policies_with_conn(&conn).expect("list policies");
    assert_eq!(policies.len(), 1);
    assert_eq!(policies[0].id, created.id);

    let deleted = delete_habit_reminder_policy_with_conn(&mut conn, &policy_id_typed)
        .expect("delete reminder policy");
    assert!(deleted.deleted);
    assert_eq!(deleted.before.as_ref().expect("before row").id, created.id);

    let remaining: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM habit_reminder_policies WHERE id = ?1",
            [&created.id],
            |row| row.get(0),
        )
        .expect("count remaining policies");
    assert_eq!(remaining, 0);

    let policy_changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_HABIT_REMINDER_POLICY, created.id.as_str()],
            |row| row.get(0),
        )
        .expect("count policy changelog");
    assert_eq!(policy_changelog_count, 3);

    let policy_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_HABIT_REMINDER_POLICY, created.id.as_str()],
            |row| row.get(0),
        )
        .expect("count policy outbox");
    assert_eq!(policy_outbox_count, 1);
}

#[test]
fn habit_reminder_policy_missing_delete_does_not_emit_side_effects() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let policy_id = hrpid("01900000-0000-7000-8000-00000000aa10");
    let before_seq = read_local_change_seq(&conn).expect("read local change seq before delete");

    let deleted = delete_habit_reminder_policy_with_conn(&mut conn, &policy_id)
        .expect("delete missing reminder policy");

    assert!(!deleted.deleted);
    assert!(deleted.before.is_none());
    assert_eq!(
        read_local_change_seq(&conn).expect("read local change seq after delete"),
        before_seq,
        "missing reminder policy delete must not bump local change seq",
    );
    let side_effect_rows: i64 = conn
        .query_row(
            "SELECT
                (SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1)
              + (SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?1)",
            [ENTITY_HABIT_REMINDER_POLICY],
            |row| row.get(0),
        )
        .expect("count reminder policy side effects");
    assert_eq!(side_effect_rows, 0);
}

#[test]
fn complete_and_uncomplete_habit_support_explicit_date_note_and_edge_changelog() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let habit = create_habit_with_conn(&mut conn, "Read", None, None, None, None, Some(2))
        .expect("create habit");

    let habit_id_typed = hid(&habit.id);
    let (_habit_name, first_completion) = complete_habit_with_conn(
        &mut conn,
        &habit_id_typed,
        Some("2026-04-24"),
        Some("Finished chapter 1"),
    )
    .expect("complete habit with note");
    assert_eq!(first_completion.value, 1);
    assert_eq!(first_completion.note.as_deref(), Some("Finished chapter 1"));

    let (_habit_name, second_completion) =
        complete_habit_with_conn(&mut conn, &habit_id_typed, Some("2026-04-24"), None)
            .expect("increment habit completion");
    assert_eq!(second_completion.value, 2);
    assert_eq!(
        second_completion.note.as_deref(),
        Some("Finished chapter 1")
    );

    let removed = uncomplete_habit_with_conn(&mut conn, &habit_id_typed, Some("2026-04-24"))
        .expect("uncomplete habit");
    assert!(removed.deleted);
    assert_eq!(removed.previous.value, 2);

    let remaining_completion: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM habit_completions WHERE habit_id = ?1 AND completed_date = '2026-04-24'",
            [&habit.id],
            |row| row.get(0),
        )
        .expect("count remaining completion");
    assert_eq!(remaining_completion, 0);

    let completion_entity_id = format!("{}:2026-04-24", habit.id);
    let edge_changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?1 AND entity_id = ?2",
            [EDGE_HABIT_COMPLETION, completion_entity_id.as_str()],
            |row| row.get(0),
        )
        .expect("count completion changelog");
    assert_eq!(edge_changelog_count, 3);

    let edge_outbox_delete_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'delete'",
            [EDGE_HABIT_COMPLETION, completion_entity_id.as_str()],
            |row| row.get(0),
        )
        .expect("count completion delete outbox");
    assert_eq!(edge_outbox_delete_count, 1);

    let seq = read_local_change_seq(&conn).expect("read local change seq");
    assert_eq!(seq, 4);
}
