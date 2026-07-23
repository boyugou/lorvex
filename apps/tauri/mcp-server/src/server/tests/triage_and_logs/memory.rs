use super::*;

#[test]
#[serial_test::serial(hlc)]
fn write_memory_rolls_back_when_changelog_insert_fails() {
    let server = make_server();

    server
        .with_conn(|conn| {
            conn.execute_batch(
                "
                CREATE TRIGGER fail_ai_changelog_insert
                BEFORE INSERT ON ai_changelog
                BEGIN
                    SELECT RAISE(ABORT, 'forced changelog failure');
                END;
                ",
            )
            .map_err(to_error_message)
        })
        .expect("install changelog failure trigger");

    let err = server
        .write_memory(Parameters(WriteMemoryArgs {
            key: "atomicity-test".to_string(),
            content: "should rollback".to_string(),
            idempotency_key: None,
        }))
        .expect_err("write_memory should fail when changelog insert fails");
    assert!(
        err.contains("ai_changelog") || err.contains("changelog") || err.contains("internal error"),
        "unexpected error: {err}"
    );

    let memory_row = server
        .with_conn(|conn| {
            query_one_as_json(
                conn,
                "SELECT * FROM memories WHERE key = ?",
                ["atomicity-test".to_string()],
            )
            .map_err(to_error_message)
        })
        .expect("query memories");
    assert!(
        memory_row.is_none(),
        "memory write must rollback on failure"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn write_memory_rolls_back_when_changelog_outbox_enqueue_fails() {
    let server = make_server();

    server
        .with_conn(|conn| {
            conn.execute_batch(
                "
                CREATE TRIGGER fail_ai_changelog_outbox_insert
                BEFORE INSERT ON sync_outbox
                WHEN NEW.entity_type = 'ai_changelog'
                BEGIN
                    SELECT RAISE(ABORT, 'forced ai_changelog outbox failure');
                END;
                ",
            )
            .map_err(to_error_message)
        })
        .expect("install changelog outbox failure trigger");

    let err = server
        .write_memory(Parameters(WriteMemoryArgs {
            key: "atomicity-test-outbox".to_string(),
            content: "should rollback".to_string(),
            idempotency_key: None,
        }))
        .expect_err("write_memory should fail when ai_changelog outbox enqueue fails");
    assert!(
        err.contains("ai_changelog") || err.contains("outbox") || err.contains("internal error"),
        "unexpected error: {err}"
    );

    let memory_row = server
        .with_conn(|conn| {
            query_one_as_json(
                conn,
                "SELECT * FROM memories WHERE key = ?",
                ["atomicity-test-outbox".to_string()],
            )
            .map_err(to_error_message)
        })
        .expect("query memories");
    assert!(
        memory_row.is_none(),
        "memory write must rollback on ai_changelog outbox failure"
    );
}
