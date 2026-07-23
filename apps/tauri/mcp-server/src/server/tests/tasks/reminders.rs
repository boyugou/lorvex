use super::*;

const OFFSET_REMINDER_AT: &str = "2026-12-01T09:00:00-05:00";
const CANONICAL_REMINDER_AT: &str = "2026-12-01T14:00:00.000Z";
const AFTER_CANONICAL_REMINDER_AT: &str = "2026-12-02T00:00:00.000Z";

fn create_task_args(title: &str, reminders: Option<Vec<String>>) -> CreateTaskArgs {
    CreateTaskArgs {
        title: title.to_string(),
        list_id: Some("list-inbox".to_string()),
        priority: None,
        due_date: Some("2026-12-01".to_string()),
        due_time: None,
        estimated_minutes: None,
        tags: None,
        body: None,
        raw_input: None,
        ai_notes: None,
        planned_date: None,
        depends_on: None,
        completed: None,
        reminders,
        recurrence: None,
        include_advice: None,
        idempotency_key: None,
    }
}

fn task_id_from_create_payload(payload: &str) -> String {
    let value: Value = serde_json::from_str(payload).expect("parse task payload");
    value["task"]["id"]
        .as_str()
        .expect("task has id")
        .to_string()
}

fn assert_canonical_sync_timestamp(value: &str) {
    assert_eq!(value.len(), 24, "unexpected timestamp width: {value}");
    assert!(value.ends_with('Z'), "timestamp must end in Z: {value}");
    let fraction = value
        .split('.')
        .nth(1)
        .and_then(|tail| tail.strip_suffix('Z'))
        .expect("timestamp must include a fractional second: {value}");
    assert_eq!(
        fraction.len(),
        3,
        "timestamp must use milliseconds: {value}"
    );
}

fn assert_single_canonical_reminder_is_queryable(server: &TestServer, task_id: &str) {
    server
        .with_conn(|conn| {
            let (reminder_at, created_at): (String, String) = conn
                .query_row(
                    "SELECT reminder_at, created_at FROM task_reminders WHERE task_id = ?1",
                    [task_id],
                    |row| Ok((row.get(0)?, row.get(1)?)),
                )
                .map_err(to_error_message)?;
            assert_eq!(reminder_at, CANONICAL_REMINDER_AT);
            assert_canonical_sync_timestamp(&created_at);

            let result = lorvex_store::repositories::task::reminders::get_due_task_reminders(
                conn,
                AFTER_CANONICAL_REMINDER_AT,
                10,
            )
            .map_err(to_error_message)?;
            assert!(
                result.rows.iter().any(|row| row.task_id == task_id),
                "canonicalized reminder should be readable by due-reminder query"
            );
            Ok(())
        })
        .expect("canonical reminder should be queryable");
}

#[test]
#[serial_test::serial(hlc)]
fn get_task_response_includes_reminders_array() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let result = server
        .create_task(Parameters(CreateTaskArgs {
            title: "Enrichment Test".to_string(),
            list_id: Some("list-inbox".to_string()),
            priority: None,
            due_date: Some("2026-04-01".to_string()),
            due_time: None,
            estimated_minutes: None,
            tags: None,
            body: None,
            raw_input: None,
            ai_notes: None,

            planned_date: None,

            depends_on: None,

            completed: None,

            reminders: Some(vec![
                "2026-03-31T09:00:00Z".to_string(),
                "2026-03-31T18:00:00Z".to_string(),
            ]),
            recurrence: None,
            include_advice: None,
            idempotency_key: None,
        }))
        .expect("create task with reminders");

    let created: Value = serde_json::from_str(&result).expect("parse created task");
    let task_id = created["task"]["id"].as_str().expect("task has id");

    // The create response itself should include reminders
    let reminders = created["task"]["reminders"]
        .as_array()
        .expect("created task should have reminders array");
    assert_eq!(
        reminders.len(),
        2,
        "created response should have 2 reminders"
    );

    // get_task should also include reminders
    let get_result = server
        .get_task(Parameters(GetTaskArgs {
            id: task_id.to_string(),
        }))
        .expect("get task");
    let fetched: Value = serde_json::from_str(&get_result).expect("parse fetched task");
    let fetched_reminders = fetched["reminders"]
        .as_array()
        .expect("fetched task should have reminders array");
    assert_eq!(
        fetched_reminders.len(),
        2,
        "get_task should return 2 reminders"
    );
    assert!(fetched_reminders[0]["reminder_at"].as_str().is_some());
}

#[test]
#[serial_test::serial(hlc)]
fn get_task_without_reminders_has_empty_reminders_array() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let result = server
        .create_task(Parameters(CreateTaskArgs {
            title: "No Reminder Enrichment".to_string(),
            list_id: Some("list-inbox".to_string()),
            priority: None,
            due_date: None,
            due_time: None,
            estimated_minutes: None,
            tags: None,
            body: None,
            raw_input: None,
            ai_notes: None,

            planned_date: None,

            depends_on: None,

            completed: None,

            reminders: None,
            recurrence: None,
            include_advice: None,
            idempotency_key: None,
        }))
        .expect("create task without reminders");

    let created: Value = serde_json::from_str(&result).expect("parse task");
    let task_id = created["task"]["id"].as_str().expect("task has id");

    let get_result = server
        .get_task(Parameters(GetTaskArgs {
            id: task_id.to_string(),
        }))
        .expect("get task");
    let fetched: Value = serde_json::from_str(&get_result).expect("parse fetched task");
    let reminders = fetched["reminders"]
        .as_array()
        .expect("task should have reminders array even when empty");
    assert_eq!(reminders.len(), 0, "no reminder rows expected");
}

#[test]
#[serial_test::serial(hlc)]
fn create_task_with_reminders_inserts_task_reminders_rows() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let result = server
        .create_task(Parameters(CreateTaskArgs {
            title: "Reminder Task".to_string(),
            list_id: Some("list-inbox".to_string()),
            priority: None,
            due_date: Some("2026-04-01".to_string()),
            due_time: None,
            estimated_minutes: None,
            tags: None,
            body: None,
            raw_input: None,
            ai_notes: None,

            planned_date: None,

            depends_on: None,

            completed: None,

            reminders: Some(vec![
                "2026-03-31T09:00:00Z".to_string(),
                "2026-03-31T18:00:00Z".to_string(),
            ]),
            recurrence: None,
            include_advice: None,
            idempotency_key: None,
        }))
        .expect("create task with reminders");

    let response: Value = serde_json::from_str(&result).expect("parse task");
    let task_id = response["task"]["id"].as_str().expect("task has id");

    let count: i64 = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM task_reminders WHERE task_id = ?",
                [task_id],
                |row| row.get(0),
            )
            .map_err(to_error_message)
        })
        .expect("count reminders");

    assert_eq!(count, 2, "should have 2 reminder rows");
}

#[test]
#[serial_test::serial(hlc)]
fn create_task_with_offset_reminder_persists_canonical_utc_timestamp() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let result = server
        .create_task(Parameters(create_task_args(
            "Offset reminder create",
            Some(vec![OFFSET_REMINDER_AT.to_string()]),
        )))
        .expect("create task with offset reminder");
    let created: Value = serde_json::from_str(&result).expect("parse created task");
    let task_id = created["task"]["id"].as_str().expect("task has id");
    assert_eq!(
        created["task"]["reminders"][0]["reminder_at"].as_str(),
        Some(CANONICAL_REMINDER_AT)
    );
    server
        .with_conn(|conn| {
            let (created_at, updated_at): (String, String) = conn
                .query_row(
                    "SELECT created_at, updated_at FROM tasks WHERE id = ?1",
                    [task_id],
                    |row| Ok((row.get(0)?, row.get(1)?)),
                )
                .map_err(to_error_message)?;
            assert_canonical_sync_timestamp(&created_at);
            assert_canonical_sync_timestamp(&updated_at);
            Ok(())
        })
        .expect("created task timestamps should be canonical sync timestamps");
    assert_single_canonical_reminder_is_queryable(&server, task_id);
}

#[test]
#[serial_test::serial(hlc)]
fn create_task_without_reminders_has_no_reminder_rows() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let result = server
        .create_task(Parameters(CreateTaskArgs {
            title: "No Reminder".to_string(),
            list_id: Some("list-inbox".to_string()),
            priority: None,
            due_date: None,
            due_time: None,
            estimated_minutes: None,
            tags: None,
            body: None,
            raw_input: None,
            ai_notes: None,

            planned_date: None,

            depends_on: None,

            completed: None,

            reminders: None,
            recurrence: None,
            include_advice: None,
            idempotency_key: None,
        }))
        .expect("create task without reminders");

    let response: Value = serde_json::from_str(&result).expect("parse task");
    let task_id = response["task"]["id"].as_str().expect("task has id");

    let count: i64 = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM task_reminders WHERE task_id = ?",
                [task_id],
                |row| row.get(0),
            )
            .map_err(to_error_message)
        })
        .expect("count reminders");

    assert_eq!(count, 0, "no reminder rows expected");
}

#[test]
#[serial_test::serial(hlc)]
fn add_task_reminder_with_offset_persists_canonical_utc_timestamp() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let result = server
        .create_task(Parameters(create_task_args("Offset reminder add", None)))
        .expect("create task");
    let task_id = task_id_from_create_payload(&result);

    let response = server
        .add_task_reminder(Parameters(AddTaskReminderArgs {
            id: task_id.clone(),
            reminder_at: OFFSET_REMINDER_AT.to_string(),
            idempotency_key: None,
        }))
        .expect("add offset reminder");
    let value: Value = serde_json::from_str(&response).expect("parse add response");
    assert_eq!(
        value["reminders"][0]["reminder_at"].as_str(),
        Some(CANONICAL_REMINDER_AT)
    );
    assert_single_canonical_reminder_is_queryable(&server, &task_id);
}

#[test]
#[serial_test::serial(hlc)]
fn add_task_reminder_logs_parent_audit_and_relation_sync() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let result = server
        .create_task(Parameters(create_task_args("Reminder audit", None)))
        .expect("create task");
    let task_id = task_id_from_create_payload(&result);

    let response = server
        .add_task_reminder(Parameters(AddTaskReminderArgs {
            id: task_id.clone(),
            reminder_at: OFFSET_REMINDER_AT.to_string(),
            idempotency_key: None,
        }))
        .expect("add reminder");
    let value: Value = serde_json::from_str(&response).expect("parse add response");
    let reminder_id = value["reminders"][0]["id"]
        .as_str()
        .expect("added reminder has id")
        .to_string();

    server
        .with_conn(|conn| {
            let audit_count: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM ai_changelog
                     WHERE mcp_tool = 'add_task_reminder'
                       AND entity_type = ?1
                       AND entity_id = ?2
                       AND before_json IS NOT NULL
                       AND after_json IS NOT NULL",
                    rusqlite::params![lorvex_domain::naming::ENTITY_TASK, task_id],
                    |row| row.get(0),
                )
                .map_err(to_error_message)?;
            assert_eq!(audit_count, 1, "parent task audit row should be logged");

            let relation_outbox_count: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM sync_outbox
                     WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
                    rusqlite::params![
                        lorvex_domain::naming::ENTITY_TASK_REMINDER,
                        reminder_id,
                        lorvex_domain::naming::OP_UPSERT,
                    ],
                    |row| row.get(0),
                )
                .map_err(to_error_message)?;
            assert_eq!(
                relation_outbox_count, 1,
                "added reminder relation should enqueue one upsert"
            );
            Ok(())
        })
        .expect("audit and relation sync should be present");
}

#[test]
#[serial_test::serial(hlc)]
fn set_task_reminders_with_offset_persists_canonical_utc_timestamp() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let result = server
        .create_task(Parameters(create_task_args("Offset reminder set", None)))
        .expect("create task");
    let task_id = task_id_from_create_payload(&result);

    let response = server
        .set_task_reminders(Parameters(SetTaskRemindersArgs {
            id: task_id.clone(),
            reminders: vec![OFFSET_REMINDER_AT.to_string()],
            idempotency_key: None,
        }))
        .expect("set offset reminder");
    let value: Value = serde_json::from_str(&response).expect("parse set response");
    assert_eq!(
        value["reminders"][0]["reminder_at"].as_str(),
        Some(CANONICAL_REMINDER_AT)
    );
    assert_single_canonical_reminder_is_queryable(&server, &task_id);
}

#[test]
#[serial_test::serial(hlc)]
fn set_task_reminders_logs_parent_audit_and_relation_sync() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let result = server
        .create_task(Parameters(create_task_args(
            "Reminder replacement audit",
            None,
        )))
        .expect("create task");
    let task_id = task_id_from_create_payload(&result);

    let first_response = server
        .set_task_reminders(Parameters(SetTaskRemindersArgs {
            id: task_id.clone(),
            reminders: vec![OFFSET_REMINDER_AT.to_string()],
            idempotency_key: None,
        }))
        .expect("set initial reminder");
    let first_value: Value = serde_json::from_str(&first_response).expect("parse first response");
    let old_reminder_id = first_value["reminders"][0]["id"]
        .as_str()
        .expect("initial reminder has id")
        .to_string();

    let second_response = server
        .set_task_reminders(Parameters(SetTaskRemindersArgs {
            id: task_id.clone(),
            reminders: vec!["2026-12-02T09:00:00-05:00".to_string()],
            idempotency_key: None,
        }))
        .expect("replace reminder");
    let second_value: Value =
        serde_json::from_str(&second_response).expect("parse second response");
    let new_reminder_id = second_value["reminders"][0]["id"]
        .as_str()
        .expect("replacement reminder has id")
        .to_string();

    server
        .with_conn(|conn| {
            let audit_count: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM ai_changelog
                     WHERE mcp_tool = 'set_task_reminders'
                       AND entity_type = ?1
                       AND entity_id = ?2
                       AND before_json IS NOT NULL
                       AND after_json IS NOT NULL",
                    rusqlite::params![lorvex_domain::naming::ENTITY_TASK, task_id],
                    |row| row.get(0),
                )
                .map_err(to_error_message)?;
            assert_eq!(
                audit_count, 2,
                "each reminder replacement should log a parent task audit row"
            );

            let delete_count: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM sync_outbox
                     WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
                    rusqlite::params![
                        lorvex_domain::naming::ENTITY_TASK_REMINDER,
                        old_reminder_id,
                        lorvex_domain::naming::OP_DELETE,
                    ],
                    |row| row.get(0),
                )
                .map_err(to_error_message)?;
            assert_eq!(
                delete_count, 1,
                "replaced reminder should enqueue one delete"
            );

            let upsert_count: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM sync_outbox
                     WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
                    rusqlite::params![
                        lorvex_domain::naming::ENTITY_TASK_REMINDER,
                        new_reminder_id,
                        lorvex_domain::naming::OP_UPSERT,
                    ],
                    |row| row.get(0),
                )
                .map_err(to_error_message)?;
            assert_eq!(
                upsert_count, 1,
                "replacement reminder should enqueue one upsert"
            );
            Ok(())
        })
        .expect("audit and relation sync should be present");
}

#[test]
#[serial_test::serial(hlc)]
fn add_task_reminder_ignores_cancelled_and_dismissed_history_for_cap() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let result = server
        .create_task(Parameters(CreateTaskArgs {
            title: "Reminder history".to_string(),
            list_id: Some("list-inbox".to_string()),
            priority: None,
            due_date: None,
            due_time: None,
            estimated_minutes: None,
            tags: None,
            body: None,
            raw_input: None,
            ai_notes: None,
            planned_date: None,
            depends_on: None,
            completed: None,
            reminders: None,
            recurrence: None,
            include_advice: None,
            idempotency_key: None,
        }))
        .expect("create task");
    let created: Value = serde_json::from_str(&result).expect("parse created task");
    let task_id = created["task"]["id"]
        .as_str()
        .expect("task has id")
        .to_string();

    server
        .with_conn(|conn| {
            for index in 0..crate::system::vec_limits::MAX_REMINDERS_PER_TASK {
                let dismissed_at: Option<&str> = (index % 2 == 0).then_some("2026-03-30T00:00:00Z");
                let cancelled_at: Option<&str> = (index % 2 == 1).then_some("2026-03-30T00:00:00Z");
                conn.execute(
                    "INSERT INTO task_reminders
                       (id, task_id, reminder_at, dismissed_at, cancelled_at, version, created_at)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, '2026-03-29T00:00:00Z')",
                    rusqlite::params![
                        format!("history-{index}"),
                        task_id,
                        format!("2026-03-29T{:02}:00:00Z", index % 24),
                        dismissed_at,
                        cancelled_at,
                        format!("00000000000{index:02}_0000_0000000000000000"),
                    ],
                )
                .map_err(to_error_message)?;
            }
            Ok(())
        })
        .expect("seed historical reminders");

    server
        .add_task_reminder(Parameters(AddTaskReminderArgs {
            id: task_id.clone(),
            reminder_at: "2026-03-31T10:00:00Z".to_string(),
            idempotency_key: None,
        }))
        .expect("historical reminders should not consume active cap");

    let active_count: i64 = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM task_reminders
                 WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL",
                [&task_id],
                |row| row.get(0),
            )
            .map_err(to_error_message)
        })
        .expect("count active reminders");
    assert_eq!(active_count, 1);
}
