use super::super::*;

#[test]
#[serial_test::serial(hlc)]
fn get_list_health_snapshot_returns_bounded_counts_and_compact_names() {
    let server = make_server();
    let today = today_ymd_local_for_test();
    let yesterday = crate::time::date_plus_days_ymd_local_for_test(-1);
    let long_name = "Alpha".repeat(30);

    seed_list_named(&server, "list-a", &long_name);
    seed_list_named(&server, "list-b", "Bravo");
    seed_list_named(&server, "list-c", "Charlie");

    seed_task(
        &server,
        "list-a-open-overdue",
        "A overdue open",
        "open",
        Some("list-a"),
        Some(&yesterday),
        None,
        0,
    );
    seed_task(
        &server,
        "list-a-open-today",
        "A today open",
        "open",
        Some("list-a"),
        Some(&today),
        None,
        0,
    );
    seed_task(
        &server,
        "list-a-open-undated",
        "A undated open",
        "open",
        Some("list-a"),
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "list-a-deferred",
        "A deferred",
        "open",
        Some("list-a"),
        None,
        None,
        3,
    );
    seed_task(
        &server,
        "list-a-completed",
        "A completed",
        "completed",
        Some("list-a"),
        Some(&today),
        None,
        0,
    );
    seed_task(
        &server,
        "list-b-open-today",
        "B today open",
        "open",
        Some("list-b"),
        Some(&today),
        None,
        0,
    );

    let payload = server
        .get_list_health_snapshot(Parameters(GetListHealthSnapshotArgs {
            limit: 2,
            offset: 0,
        }))
        .expect("get list health snapshot");
    let value: Value = serde_json::from_str(&payload).expect("valid json");

    assert_eq!(value["date"], today);
    // 3 explicitly seeded lists + 1 schema-seeded 'inbox' = 4 total
    assert_eq!(value["summary"]["total_lists"], 4);
    assert_eq!(value["summary"]["returned_lists"], 2);
    assert_eq!(value["summary"]["limit"], 2);
    assert_eq!(value["summary"]["truncated"], true);
    assert_eq!(value["limits"]["lists"], 2);
    assert_eq!(value["limits"]["name_max_chars"], 80);

    let rows = value["lists"].as_array().expect("lists array");
    assert_eq!(rows.len(), 2);

    let first = &rows[0];
    assert_eq!(first["id"], "list-a");
    assert_eq!(first["open_count"], 4); // 3 regular open + 1 open with defer history
    assert_eq!(first["overdue_open_count"], 1);
    assert_eq!(first["due_today_open_count"], 1);
    assert!(first.get("total_lists").is_none());
    // #2422: list name is clamped first, then wrapped with the
    // `⟦user⟧` untrusted fence (16-char overhead).
    let name = first["name"].as_str().expect("list name");
    assert!(name.starts_with("\u{27E6}user\u{27E7} "));
    assert!(name.ends_with(" \u{27E6}/user\u{27E7}"));
    assert!(name.chars().count() <= 83 + 16);
    assert!(name.contains("..."));

    let second = &rows[1];
    assert_eq!(second["id"], "list-b");
    assert_eq!(second["open_count"], 1);
    assert_eq!(second["overdue_open_count"], 0);
    assert_eq!(second["due_today_open_count"], 1);
}

#[test]
#[serial_test::serial(hlc)]
fn get_list_health_snapshot_applies_default_and_cap_limits() {
    let server = make_server();
    seed_list_named(&server, "list-1", "List 1");
    seed_list_named(&server, "list-2", "List 2");
    seed_list_named(&server, "list-3", "List 3");

    let default_payload = server
        .get_list_health_snapshot(Parameters(GetListHealthSnapshotArgs {
            limit: 0,
            offset: 0,
        }))
        .expect("default list health snapshot");
    let default_value: Value = serde_json::from_str(&default_payload).expect("valid json");
    // 3 explicitly seeded + 1 schema-seeded 'inbox' = 4
    assert_eq!(default_value["summary"]["total_lists"], 4);
    assert_eq!(default_value["summary"]["returned_lists"], 4);
    assert_eq!(default_value["summary"]["limit"], 50);
    assert_eq!(default_value["summary"]["truncated"], false);

    let capped_payload = server
        .get_list_health_snapshot(Parameters(GetListHealthSnapshotArgs {
            limit: 999,
            offset: 0,
        }))
        .expect("capped list health snapshot");
    let capped_value: Value = serde_json::from_str(&capped_payload).expect("valid json");
    assert_eq!(capped_value["summary"]["total_lists"], 4);
    assert_eq!(capped_value["summary"]["returned_lists"], 4);
    assert_eq!(capped_value["summary"]["limit"], 200);
    assert_eq!(capped_value["summary"]["truncated"], false);
}
