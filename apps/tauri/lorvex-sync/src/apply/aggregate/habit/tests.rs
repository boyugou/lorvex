use crate::apply::LwwTieBreak;
use crate::test_db;
use rusqlite::params;

fn habit_payload(position: Option<i64>) -> String {
    let position_field = position
        .map(|value| format!(r#","position":{value}"#))
        .unwrap_or_default();
    format!(
        r#"{{
            "name":"Read",
            "frequency_type":"daily",
            "target_count":1,
            "created_at":"2026-04-01T00:00:00.000Z",
            "updated_at":"2026-04-01T00:01:00.000Z"
            {position_field}
        }}"#
    )
}

#[test]
fn apply_habit_upsert_persists_position() {
    let conn = test_db();
    let habit_id = "00000000-0000-7000-8000-000000003101";

    super::apply_habit_upsert(
        &conn,
        habit_id,
        &habit_payload(Some(12)),
        "1711234569999_0000_aaaaaaaaaaaaaaaa",
        LwwTieBreak::RejectEqual,
        "2026-04-01T00:01:00.000Z",
    )
    .unwrap();

    let position: i64 = conn
        .query_row(
            "SELECT position FROM habits WHERE id = ?1",
            params![habit_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(position, 12);
}

#[test]
fn apply_habit_upsert_absent_position_preserves_existing_value() {
    let conn = test_db();
    let habit_id = "00000000-0000-7000-8000-000000003102";
    conn.execute(
        "INSERT INTO habits (id, name, frequency_type, per_period_target, day_of_month,
                             target_count, archived, position, lookup_key, version,
                             created_at, updated_at)
         VALUES (?1, 'Read', 'daily', 1, NULL, 1, 0, 8, 'read', ?2,
                 '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
        params![habit_id, "1711234560000_0000_aaaaaaaaaaaaaaaa"],
    )
    .unwrap();

    super::apply_habit_upsert(
        &conn,
        habit_id,
        &habit_payload(None),
        "1711234569999_0000_bbbbbbbbbbbbbbbb",
        LwwTieBreak::RejectEqual,
        "2026-04-01T00:01:00.000Z",
    )
    .unwrap();

    let position: i64 = conn
        .query_row(
            "SELECT position FROM habits WHERE id = ?1",
            params![habit_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(position, 8);
}

/// same shape as the task-side
/// `cascade_does_not_run_when_byte_compare_fallback_rejects_legacy_local_version`
/// test — a habit row whose `version` column is a legacy
/// `'v1'` literal (which lex-dominates a canonical HLC) must
/// have its delete refused, AND the cascade pass over
/// `habit_completions` / `habit_reminder_policies` must NOT
/// run. Pre-#3002 the cascade fired before the byte-compare
/// fallback rejected the parent delete, leaving orphan
/// completion + reminder-policy tombstones.
#[test]
fn cascade_does_not_run_when_byte_compare_fallback_rejects_legacy_local_version() {
    let conn = test_db();
    let habit_id = "00000000-0000-7000-8000-000000003001";
    let canonical_envelope_version = "1711234599000_0000_dec0000200000002";
    let legacy_local_version = "v1";

    conn.execute(
        "INSERT INTO habits (id, name, frequency_type, per_period_target, day_of_month,
                             target_count, archived, lookup_key, version,
                             created_at, updated_at)
         VALUES (?1, 'Read', 'daily', 1, NULL, 1, 0, 'read', ?2,
                 '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
        params![habit_id, legacy_local_version],
    )
    .unwrap();

    // Seed one completion + one reminder policy so we can
    // assert the cascade pass would have written tombstones if
    // it had run.
    let completion_date = "2026-04-01";
    conn.execute(
        "INSERT INTO habit_completions (habit_id, completed_date, value, version,
                                        created_at, updated_at)
         VALUES (?1, ?2, 1, ?3,
                 '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
        params![habit_id, completion_date, canonical_envelope_version],
    )
    .unwrap();
    let policy_id = "00000000-0000-7000-8000-000000003002";
    conn.execute(
        "INSERT INTO habit_reminder_policies (
            id, habit_id, reminder_time, enabled,
            version, created_at, updated_at
         ) VALUES (?1, ?2, '09:00', 1,
                   ?3, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
        params![policy_id, habit_id, canonical_envelope_version],
    )
    .unwrap();

    let outcome = super::apply_habit_delete(
        &conn,
        habit_id,
        canonical_envelope_version,
        "2026-04-01T00:00:00.000Z",
    )
    .unwrap();
    assert!(
        matches!(outcome, super::super::LwwGatedDeleteOutcome::LwwRejected(_)),
        "byte-compare fallback must surface as LwwRejected, got {outcome:?}"
    );

    let parent_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM habits WHERE id = ?1",
            params![habit_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        parent_count, 1,
        "parent habit must survive the rejected delete"
    );

    let completion_edge_id = format!("{habit_id}:{completion_date}");
    let completion_ts_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones \
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![
                lorvex_domain::naming::EDGE_HABIT_COMPLETION,
                &completion_edge_id
            ],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        completion_ts_count, 0,
        "habit_completion cascade tombstone must NOT be written on rejected parent delete"
    );

    let policy_ts_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones \
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![
                lorvex_domain::naming::ENTITY_HABIT_REMINDER_POLICY,
                policy_id
            ],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        policy_ts_count, 0,
        "habit_reminder_policy cascade tombstone must NOT be written on rejected parent delete"
    );
}
