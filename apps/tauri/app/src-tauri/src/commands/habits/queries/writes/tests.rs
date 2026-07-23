use super::*;
use crate::test_support::test_conn;

#[test]
fn create_habit_with_conn_round_trip_writes_row_and_outbox() {
    let conn = test_conn();

    let habit = create_habit_with_conn(
        &conn,
        CreateHabitParams {
            name: "Read 30 minutes",
            icon: Some("read"),
            color: Some("#AABBCC"),
            cue: Some("After dinner"),
            frequency_type: Some("daily"),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: Some(1),
        },
    )
    .expect("create_habit_with_conn should succeed");

    assert_eq!(habit.name, "Read 30 minutes");
    assert_eq!(habit.icon.as_deref(), Some("read"));
    assert_eq!(habit.color.as_deref(), Some("#AABBCC"));
    assert_eq!(habit.cue.as_deref(), Some("After dinner"));
    assert_eq!(
        habit.frequency_type,
        lorvex_domain::HabitFrequencyType::Daily
    );
    assert_eq!(habit.target_count, 1);
    assert!(!habit.archived);

    let stored_name: String = conn
        .query_row(
            "SELECT name FROM habits WHERE id = ?1",
            params![habit.id],
            |row| row.get(0),
        )
        .expect("load stored habit");
    assert_eq!(stored_name, "Read 30 minutes");

    let (entity_type, operation): (String, String) = conn
        .query_row(
            "SELECT entity_type, operation FROM sync_outbox \
             WHERE entity_id = ?1 ORDER BY id DESC LIMIT 1",
            params![habit.id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load sync_outbox row");
    assert_eq!(entity_type, ENTITY_HABIT);
    assert_eq!(operation, OP_UPSERT);
}

#[test]
fn create_habit_with_conn_weekly_materializes_weekday_child() {
    let conn = test_conn();
    let habit = create_habit_with_conn(
        &conn,
        CreateHabitParams {
            name: "Gym",
            icon: None,
            color: None,
            cue: None,
            frequency_type: Some("weekly"),
            // Mon=0, Wed=2, Fri=4 (unsorted input is normalized).
            weekdays: Some(&[4, 0, 2]),
            per_period_target: None,
            day_of_month: None,
            target_count: Some(1),
        },
    )
    .expect("create weekly habit should succeed");
    assert_eq!(
        habit.frequency_type,
        lorvex_domain::HabitFrequencyType::Weekly
    );
    assert_eq!(habit.weekdays, vec![0, 2, 4]);

    // The materialized `habit_weekdays` child mirrors the sorted set.
    let stored: Vec<i64> = conn
        .prepare("SELECT weekday FROM habit_weekdays WHERE habit_id = ?1 ORDER BY weekday")
        .expect("prepare weekday query")
        .query_map(params![habit.id], |row| row.get(0))
        .expect("query weekdays")
        .collect::<Result<_, _>>()
        .expect("collect weekdays");
    assert_eq!(stored, vec![0, 2, 4]);
}

#[test]
fn create_habit_with_conn_times_per_week_carries_per_period_target() {
    let conn = test_conn();
    let habit = create_habit_with_conn(
        &conn,
        CreateHabitParams {
            name: "Run",
            icon: None,
            color: None,
            cue: None,
            frequency_type: Some("times_per_week"),
            weekdays: None,
            per_period_target: Some(3),
            day_of_month: None,
            target_count: Some(1),
        },
    )
    .expect("create times_per_week habit should succeed");
    assert_eq!(
        habit.frequency_type,
        lorvex_domain::HabitFrequencyType::TimesPerWeek
    );
    assert_eq!(habit.per_period_target, 3);
    assert!(habit.weekdays.is_empty());
}

#[test]
fn create_habit_with_conn_rejects_empty_name() {
    let conn = test_conn();
    let error = create_habit_with_conn(
        &conn,
        CreateHabitParams {
            name: "   ",
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
    .expect_err("empty name should be rejected");
    assert!(matches!(error, AppError::Validation(_)));
}

#[test]
fn create_habit_with_conn_rejects_invalid_color() {
    let conn = test_conn();
    let error = create_habit_with_conn(
        &conn,
        CreateHabitParams {
            name: "Hydrate",
            icon: None,
            color: Some("red"),
            cue: None,
            frequency_type: Some("daily"),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: None,
        },
    )
    .expect_err("invalid habit color should be rejected");

    assert!(matches!(error, AppError::Validation(_)));
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
fn create_habit_with_conn_rejects_duplicate_active_name() {
    let conn = test_conn();
    create_habit_with_conn(
        &conn,
        CreateHabitParams {
            name: "Meditate",
            icon: None,
            color: None,
            cue: None,
            frequency_type: Some("daily"),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: Some(1),
        },
    )
    .expect("first create should succeed");

    let error = create_habit_with_conn(
        &conn,
        CreateHabitParams {
            name: "meditate",
            icon: None,
            color: None,
            cue: None,
            frequency_type: Some("daily"),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: Some(1),
        },
    )
    .expect_err("case-insensitive duplicate should be rejected");
    let message = error.to_string();
    assert!(message.to_lowercase().contains("already exists"));
}

/// dedup is enforced at the schema layer via the
/// partial UNIQUE index `idx_habits_lookup_key_active`. Two
/// habits whose names differ only by Unicode normalization
/// (NFKC + Unicode case-fold + whitespace-collapse) MUST collide
/// before the in-memory loop ever runs — otherwise a concurrent
/// peer write that bypasses the validator could plant a
/// near-duplicate row with no schema-side gate.
///
/// We prove "the index is the contract" by writing the second
/// row with a raw INSERT that pre-computes the same `lookup_key`.
/// SQLite must reject it with `UNIQUE constraint failed`.
#[test]
fn habits_lookup_key_unique_index_rejects_unicode_duplicates_at_schema_layer() {
    use lorvex_domain::tag::normalize_lookup_key;

    let conn = test_conn();
    create_habit_with_conn(
        &conn,
        CreateHabitParams {
            name: "Café",
            icon: None,
            color: None,
            cue: None,
            frequency_type: Some("daily"),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: Some(1),
        },
    )
    .expect("first create should succeed");

    // Force-bypass the validator and try to plant a second active
    // row whose `name` differs from the first only by Unicode
    // normalization (decomposed `Café` vs the composed form
    // already inserted). Both names normalize to the same
    // `lookup_key` — the partial UNIQUE index must reject this
    // INSERT regardless of the application-layer check.
    let decomposed = "Cafe\u{0301}";
    let key = normalize_lookup_key(decomposed);
    let composed_key = normalize_lookup_key("Café");
    assert_eq!(
        key, composed_key,
        "test premise: both forms must normalize to the same lookup_key"
    );

    let raw_id = uuid::Uuid::now_v7().to_string();
    let raw_version = generate_version_result().expect("hlc version");
    let now = sync_timestamp_now();
    let result = conn.execute(
        "INSERT INTO habits (id, name, icon, color, cue, frequency_type, \
             per_period_target, day_of_month, target_count, archived, lookup_key, \
             created_at, updated_at, version) \
         VALUES (?1, ?2, NULL, NULL, NULL, 'daily', 1, NULL, 1, 0, ?3, ?4, ?4, ?5)",
        params![raw_id, decomposed, key, now, raw_version],
    );
    let error = result.expect_err("unique index must reject the duplicate lookup_key");
    let message = error.to_string();
    assert!(
        message.contains("UNIQUE") || message.contains("unique"),
        "expected UNIQUE constraint violation, got: {message}"
    );
}

#[test]
fn create_habit_with_conn_rejects_invalid_frequency_type() {
    let conn = test_conn();
    let error = create_habit_with_conn(
        &conn,
        CreateHabitParams {
            name: "Stretch",
            icon: None,
            color: None,
            cue: None,
            frequency_type: Some("hourly"),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: None,
        },
    )
    .expect_err("invalid frequency should be rejected");
    let message = error.to_string();
    assert!(message.contains("frequency_type"));
}

#[test]
fn delete_habit_with_conn_removes_row_and_emits_tombstone_envelopes() {
    let conn = test_conn();
    let habit = create_habit_with_conn(
        &conn,
        CreateHabitParams {
            name: "Journal",
            icon: None,
            color: None,
            cue: None,
            frequency_type: Some("daily"),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: Some(1),
        },
    )
    .expect("create habit");

    conn.execute(
        "INSERT INTO habit_completions \
         (habit_id, completed_date, value, note, version, created_at, updated_at) \
         VALUES (?1, '2026-04-15', 2, 'Evening session', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-15T08:00:00Z', '2026-04-15T09:00:00Z')",
        params![habit.id],
    )
    .expect("seed completion");
    conn.execute(
        "INSERT INTO habit_reminder_policies \
         (id, habit_id, reminder_time, enabled, version, created_at, updated_at) \
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000901', ?1, '07:45', 0, '0000000000000_0000_b0b0b0b0b0b0b0b0', '2026-04-14T08:00:00Z', '2026-04-14T09:00:00Z')",
        params![habit.id],
    )
    .expect("seed reminder policy");

    let pre_delete_habit_version: String = conn
        .query_row(
            "SELECT version FROM habits WHERE id = ?1",
            params![habit.id],
            |row| row.get(0),
        )
        .expect("read pre-delete habit version");

    let result = delete_habit_with_conn(
        &conn,
        &lorvex_domain::HabitId::from_trusted(habit.id.clone()),
    )
    .expect("delete_habit_with_conn should succeed");
    assert!(result.deleted);
    assert_eq!(result.id, habit.id);
    assert_eq!(result.completions_destroyed, 1);
    assert_eq!(result.reminder_policies_destroyed, 1);

    let remaining: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM habits WHERE id = ?1",
            params![habit.id],
            |row| row.get(0),
        )
        .expect("count habits");
    assert_eq!(remaining, 0);

    let habit_delete_envelopes: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'habit' AND entity_id = ?1 AND operation = 'delete'",
            params![habit.id],
            |row| row.get(0),
        )
        .expect("count habit delete envelopes");
    assert!(habit_delete_envelopes >= 1);

    let habit_delete_payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox \
             WHERE entity_type = 'habit' AND entity_id = ?1 AND operation = 'delete' \
             ORDER BY id DESC LIMIT 1",
            params![habit.id],
            |row| row.get(0),
        )
        .expect("read habit delete payload");
    let habit_delete_payload: serde_json::Value =
        serde_json::from_str(&habit_delete_payload).expect("parse habit delete payload");
    assert_eq!(habit_delete_payload["id"], habit.id);
    assert_eq!(habit_delete_payload["name"], "Journal");
    assert_eq!(habit_delete_payload["frequency_type"], "daily");
    assert_eq!(habit_delete_payload["target_count"], 1);
    assert_eq!(habit_delete_payload["created_at"], habit.created_at);
    assert_eq!(habit_delete_payload["updated_at"], habit.updated_at);
    assert_eq!(habit_delete_payload["version"], pre_delete_habit_version);

    let completion_entity = format!("{}:2026-04-15", habit.id);
    let completion_tombstones: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones \
             WHERE entity_type = 'habit_completion' AND entity_id = ?1",
            params![completion_entity],
            |row| row.get(0),
        )
        .expect("count completion tombstones");
    assert_eq!(completion_tombstones, 1);

    let completion_payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox \
             WHERE entity_type = 'habit_completion' \
               AND entity_id = ?1 \
               AND operation = 'delete'",
            params![completion_entity],
            |row| row.get(0),
        )
        .expect("read completion delete payload");
    let completion_payload: serde_json::Value =
        serde_json::from_str(&completion_payload).expect("parse completion payload");
    assert_eq!(completion_payload["habit_id"], habit.id);
    assert_eq!(completion_payload["completed_date"], "2026-04-15");
    assert_eq!(completion_payload["value"], 2);
    assert_eq!(completion_payload["note"], "Evening session");
    assert_eq!(completion_payload["created_at"], "2026-04-15T08:00:00Z");
    assert_eq!(completion_payload["updated_at"], "2026-04-15T09:00:00Z");
    assert!(completion_payload["version"].as_str().is_some());

    let policy_payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox \
             WHERE entity_type = 'habit_reminder_policy' \
               AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000901' \
               AND operation = 'delete'",
            [],
            |row| row.get(0),
        )
        .expect("read policy delete payload");
    let policy_payload: serde_json::Value =
        serde_json::from_str(&policy_payload).expect("parse policy payload");
    assert_eq!(policy_payload["id"], "01966a3f-7c8b-7d4e-8f3a-000000000901");
    assert_eq!(policy_payload["habit_id"], habit.id);
    assert_eq!(policy_payload["reminder_time"], "07:45");
    assert_eq!(policy_payload["enabled"], false);
    assert_eq!(policy_payload["created_at"], "2026-04-14T08:00:00Z");
    assert_eq!(policy_payload["updated_at"], "2026-04-14T09:00:00Z");
    assert!(policy_payload["version"].as_str().is_some());
}

#[test]
fn delete_habit_with_conn_rejects_missing_habit() {
    let conn = test_conn();
    let error = delete_habit_with_conn(
        &conn,
        &lorvex_domain::HabitId::from_trusted("nonexistent-habit".to_string()),
    )
    .expect_err("missing habit should be rejected");
    assert!(matches!(error, AppError::NotFound(_)));
}
