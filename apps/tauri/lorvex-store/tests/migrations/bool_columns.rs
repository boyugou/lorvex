use super::support::{
    assert_sql_fails, normalized_table_sql, semantic_sqlite_bool_columns, BoolColumnCheckCase,
};
use lorvex_store::open_db_in_memory;

#[test]
fn semantic_bool_columns_have_schema_checks() {
    let conn = open_db_in_memory().unwrap();

    for (table, column) in semantic_sqlite_bool_columns() {
        let table_sql = normalized_table_sql(&conn, table);
        assert!(
            table_sql.contains(&format!("CHECK ({column} IN (0, 1))")),
            "{table}.{column} is semantically boolean but lacks a SQLite 0/1 CHECK: {table_sql}",
        );
    }
}

#[test]
fn external_payload_bool_columns_stay_registered() {
    for (table, column) in lorvex_domain::storage_schema::SQLITE_BOOL_COLUMNS {
        assert!(
            lorvex_domain::storage_schema::is_sqlite_bool_column(table, column),
            "{table}.{column} must stay registered as an external JSON bool",
        );
    }
}

#[test]
fn semantic_bool_columns_reject_non_boolean_integers() {
    let conn = open_db_in_memory().unwrap();

    for case in [
        BoolColumnCheckCase {
            invalid_insert: "INSERT INTO habits (
                 id, name, archived, version, created_at, updated_at
             ) VALUES (
                 'habit-invalid', 'Invalid archived habit', 2, 'v-habit', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z'
             )",
            valid_insert: "INSERT INTO habits (id, name, version, created_at, updated_at)
             VALUES ('habit-ok', 'Valid habit', 'v-habit', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
            invalid_update: "UPDATE habits SET archived = 2 WHERE id = 'habit-ok'",
        },
        BoolColumnCheckCase {
            invalid_insert: "INSERT INTO calendar_events (
                 id, title, start_date, all_day, version, created_at, updated_at
             ) VALUES (
                 'event-invalid', 'Invalid all-day event', '2026-04-01', 2, 'v-event', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z'
             )",
            valid_insert: "INSERT INTO calendar_events (id, title, start_date, version, created_at, updated_at)
             VALUES ('event-ok', 'Valid event', '2026-04-01', 'v-event', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
            invalid_update: "UPDATE calendar_events SET all_day = 2 WHERE id = 'event-ok'",
        },
        BoolColumnCheckCase {
            invalid_insert: "INSERT INTO calendar_subscriptions (
                 id, name, url, enabled, version, created_at, updated_at
             ) VALUES (
                 'sub-invalid', 'Invalid subscription', 'https://example.com/calendar.ics', 2, 'v-sub', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z'
             )",
            valid_insert: "INSERT INTO calendar_subscriptions (id, name, url, version, created_at, updated_at)
             VALUES ('sub-ok', 'Valid subscription', 'https://example.com/calendar.ics', 'v-sub', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
            invalid_update: "UPDATE calendar_subscriptions SET enabled = 2 WHERE id = 'sub-ok'",
        },
        BoolColumnCheckCase {
            invalid_insert: "INSERT INTO habit_reminder_policies (
                 id, habit_id, reminder_time, enabled, version, created_at, updated_at
             ) VALUES (
                 'policy-invalid', 'habit-ok', '09:00', 2, 'v-policy', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z'
             )",
            valid_insert: "INSERT INTO habit_reminder_policies (id, habit_id, reminder_time, version, created_at, updated_at)
             VALUES ('policy-ok', 'habit-ok', '09:00', 'v-policy', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
            invalid_update: "UPDATE habit_reminder_policies SET enabled = 2 WHERE id = 'policy-ok'",
        },
        BoolColumnCheckCase {
            invalid_insert: "INSERT INTO provider_calendar_events (
                 provider_kind, provider_scope, provider_event_key, title,
                 start_date, all_day, last_seen_at, last_refreshed_at
             ) VALUES (
                 'eventkit', '', 'provider-event-invalid', 'Invalid provider event',
                 '2026-04-01', 2, '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z'
             )",
            valid_insert: "INSERT INTO provider_calendar_events (
                 provider_kind, provider_scope, provider_event_key, title,
                 start_date, last_seen_at, last_refreshed_at
             ) VALUES (
                 'eventkit', '', 'provider-event-ok', 'Valid provider event',
                 '2026-04-01', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z'
             )",
            invalid_update: "UPDATE provider_calendar_events
             SET all_day = 2
             WHERE provider_kind = 'eventkit'
               AND provider_scope = ''
               AND provider_event_key = 'provider-event-ok'",
        },
        BoolColumnCheckCase {
            invalid_insert: "INSERT INTO provider_scope_runtime_state (
                 provider_kind, provider_scope, enabled
             ) VALUES (
                 'eventkit', 'scope-invalid', 2
             )",
            valid_insert: "INSERT INTO provider_scope_runtime_state (provider_kind, provider_scope)
             VALUES ('eventkit', 'scope-ok')",
            invalid_update: "UPDATE provider_scope_runtime_state
             SET enabled = 2
             WHERE provider_kind = 'eventkit'
               AND provider_scope = 'scope-ok'",
        },
    ] {
        assert_sql_fails(&conn, case.invalid_insert);
        conn.execute(case.valid_insert, []).unwrap();
        assert_sql_fails(&conn, case.invalid_update);
    }
}
