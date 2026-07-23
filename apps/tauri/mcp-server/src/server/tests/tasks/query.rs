use super::*;

fn payload_task_ids(payload: &str) -> Vec<String> {
    let value: Value = serde_json::from_str(payload).expect("valid list_tasks payload");
    value["tasks"]
        .as_array()
        .expect("tasks array")
        .iter()
        .filter_map(|task| task.get("id").and_then(Value::as_str))
        .map(str::to_string)
        .collect()
}

fn payload_task_lateness(payload: &str) -> Vec<(String, Option<String>)> {
    let value: Value = serde_json::from_str(payload).expect("valid list_tasks payload");
    value["tasks"]
        .as_array()
        .expect("tasks array")
        .iter()
        .map(|task| {
            (
                task["id"].as_str().expect("task id").to_string(),
                task.get("lateness_state")
                    .and_then(Value::as_str)
                    .map(str::to_string),
            )
        })
        .collect()
}

fn list_tasks_args(value: serde_json::Value) -> ListTasksArgs {
    serde_json::from_value(value).expect("valid ListTasksArgs")
}

#[test]
#[serial_test::serial(hlc)]
fn list_tasks_supports_planned_range_and_date_presence_filters() {
    let server = make_server();
    seed_list_named(&server, "list-work", "Work");
    server
        .with_conn(|conn| {
            // lift to canonical TaskBuilder.
            use lorvex_store::test_support::fixtures::TaskBuilder;
            TaskBuilder::new("task-planned-only")
                .title("Planned only")
                .created_at("2026-04-01T00:00:00Z")
                .list_id(Some("list-work"))
                .planned_date(Some("2026-04-02"))
                .insert(conn);
            TaskBuilder::new("task-due-only")
                .title("Due only")
                .created_at("2026-04-01T00:00:00Z")
                .list_id(Some("list-work"))
                .due_date(Some("2026-04-03"))
                .insert(conn);
            TaskBuilder::new("task-both")
                .title("Both dates")
                .created_at("2026-04-01T00:00:00Z")
                .list_id(Some("list-work"))
                .due_date(Some("2026-04-06"))
                .planned_date(Some("2026-04-05"))
                .insert(conn);
            Ok(())
        })
        .expect("seed tasks");

    let planned_only = server
        .list_tasks(Parameters(list_tasks_args(serde_json::json!({
            "list_id": "list-work",
            "status": "open",
            "planned_range": {
                "from": "2026-04-01",
                "to": "2026-04-03"
            },
            "has_due_date": false,
            "has_planned_date": true,
            "limit": 50
        }))))
        .expect("planned-range filter should succeed");
    assert_eq!(
        payload_task_ids(&planned_only),
        vec!["task-planned-only".to_string()]
    );

    let due_only = server
        .list_tasks(Parameters(list_tasks_args(serde_json::json!({
            "list_id": "list-work",
            "status": "open",
            "due_range": {
                "from": "2026-04-02",
                "to": "2026-04-04"
            },
            "has_due_date": true,
            "has_planned_date": false,
            "limit": 50
        }))))
        .expect("due-date presence filter should succeed");
    assert_eq!(
        payload_task_ids(&due_only),
        vec!["task-due-only".to_string()]
    );
}

#[test]
#[serial_test::serial(hlc)]
fn list_tasks_respects_explicit_planned_date_sorting() {
    let server = make_server();
    seed_list_named(&server, "list-work", "Work");
    server
        .with_conn(|conn| {
            // lift to canonical TaskBuilder.
            use lorvex_store::test_support::fixtures::TaskBuilder;
            for (id, title, planned) in [
                ("task-planned-early", "Early planned", "2026-04-01"),
                ("task-planned-late", "Late planned", "2026-04-07"),
                ("task-planned-middle", "Middle planned", "2026-04-03"),
            ] {
                TaskBuilder::new(id)
                    .title(title)
                    .created_at("2026-04-01T00:00:00Z")
                    .list_id(Some("list-work"))
                    .planned_date(Some(planned))
                    .insert(conn);
            }
            Ok(())
        })
        .expect("seed planned tasks");

    let payload = server
        .list_tasks(Parameters(list_tasks_args(serde_json::json!({
            "list_id": "list-work",
            "status": "open",
            "has_planned_date": true,
            "sort_by": "planned_date",
            "sort_direction": "desc",
            "limit": 50
        }))))
        .expect("planned-date sorting should succeed");

    assert_eq!(
        payload_task_ids(&payload),
        vec![
            "task-planned-late".to_string(),
            "task-planned-middle".to_string(),
            "task-planned-early".to_string(),
        ]
    );
}

#[test]
#[serial_test::serial(hlc)]
fn list_tasks_enriches_canonical_lateness_state() {
    let server = make_server();
    seed_list_named(&server, "list-work", "Work");
    let today = today_ymd_local_for_test();
    let today_date = chrono::NaiveDate::parse_from_str(&today, "%Y-%m-%d").expect("parse today");
    let yesterday = (today_date - chrono::Duration::days(1))
        .format("%Y-%m-%d")
        .to_string();
    let tomorrow = (today_date + chrono::Duration::days(1))
        .format("%Y-%m-%d")
        .to_string();

    server
        .with_conn(|conn| {
            // lift to canonical TaskBuilder.
            use lorvex_store::test_support::fixtures::TaskBuilder;
            TaskBuilder::new("task-past-planned")
                .title("Past planned")
                .created_at("2026-04-01T00:00:00Z")
                .list_id(Some("list-work"))
                .due_date(Some(&tomorrow))
                .planned_date(Some(&yesterday))
                .insert(conn);
            TaskBuilder::new("task-overdue-unhandled")
                .title("Overdue unhandled")
                .created_at("2026-04-01T00:00:00Z")
                .list_id(Some("list-work"))
                .due_date(Some(&yesterday))
                .insert(conn);
            TaskBuilder::new("task-overdue-acknowledged")
                .title("Overdue acknowledged")
                .created_at("2026-04-01T00:00:00Z")
                .list_id(Some("list-work"))
                .due_date(Some(&yesterday))
                .planned_date(Some(&today))
                .insert(conn);
            Ok(())
        })
        .expect("seed lateness tasks");

    let payload = server
        .list_tasks(Parameters(list_tasks_args(serde_json::json!({
            "list_id": "list-work",
            "status": "open",
            "limit": 50
        }))))
        .expect("list_tasks should succeed");

    let mut lateness = payload_task_lateness(&payload);
    lateness.sort_by(|left, right| left.0.cmp(&right.0));
    assert_eq!(
        lateness,
        vec![
            (
                "task-overdue-acknowledged".to_string(),
                Some("overdue_acknowledged".to_string()),
            ),
            (
                "task-overdue-unhandled".to_string(),
                Some("overdue_unhandled".to_string())
            ),
            (
                "task-past-planned".to_string(),
                Some("past_planned".to_string())
            ),
        ]
    );
}
