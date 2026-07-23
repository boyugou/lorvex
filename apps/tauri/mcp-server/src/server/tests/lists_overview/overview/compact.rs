use super::super::*;

#[test]
#[serial_test::serial(hlc)]
fn get_overview_compact_returns_bounded_payload() {
    let server = make_server();
    let today = today_ymd_local_for_test();
    let long_title = "L".repeat(500);
    let long_briefing = "B".repeat(700);
    seed_list(&server, "list-overview");

    for index in 0..7 {
        seed_task(
            &server,
            &format!("open-{index}"),
            &format!("{long_title} open {index}"),
            "open",
            Some("list-overview"),
            None,
            None,
            0,
        );
    }

    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO current_focus (date, briefing, version, created_at, updated_at) VALUES (?, ?, '0000000000000_0000_0000000000000000', ?, ?)",
                (
                    today.clone(),
                    long_briefing.clone(),
                    "2026-03-01T00:00:00Z".to_string(),
                    "2026-03-01T00:00:00Z".to_string(),
                ),
            )
            .map_err(to_error_message)?;
            // Materialize task_ids to the items sub-table
            conn.execute(
                "INSERT INTO current_focus_items (date, position, task_id) VALUES (?1, 0, 'open-0')",
                [today.clone()],
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO current_focus_items (date, position, task_id) VALUES (?1, 1, 'open-1')",
                [today.clone()],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed current focus");

    let payload = server
        .get_overview_compact()
        .expect("compact overview should succeed");
    let value: Value = serde_json::from_str(&payload).expect("valid json");

    assert_eq!(value["date"], today);
    assert_eq!(value["stats"]["open_count"], 7);
    assert_eq!(value["limits"]["top_tasks"], 5);
    assert_eq!(value["limits"]["title_max_chars"], 120);
    assert_eq!(value["limits"]["briefing_max_chars"], 320);
    assert_eq!(
        value["top_tasks"]
            .as_array()
            .expect("top_tasks array")
            .len(),
        5
    );
    assert_eq!(value["current_focus"]["exists"], true);
    assert_eq!(value["current_focus"]["task_count"], 2);
    // #2422: briefing and title are wrapped with the `⟦user⟧` untrusted
    // fence after truncation. The inner (trimmed) content still respects
    // the configured length cap; the fence adds a fixed overhead of
    // `⟦user⟧ ` + ` ⟦/user⟧` (16 chars) around it.
    let briefing = value["current_focus"]["briefing"]
        .as_str()
        .expect("briefing");
    assert!(briefing.starts_with("\u{27E6}user\u{27E7} "));
    assert!(briefing.ends_with(" \u{27E6}/user\u{27E7}"));
    assert!(briefing.chars().count() <= 323 + 16);
    assert!(briefing.contains("..."));

    let top_tasks = value["top_tasks"].as_array().expect("top_tasks array");
    assert!(top_tasks.iter().all(|row| {
        row["title"]
            .as_str()
            .is_some_and(|title| title.chars().count() <= 123 + 16)
    }));
    let top_title = top_tasks[0]["title"].as_str().expect("top tasks title");
    assert!(top_title.starts_with("\u{27E6}user\u{27E7} "));
    assert!(top_title.ends_with(" \u{27E6}/user\u{27E7}"));
    assert!(top_title.contains("..."));

    assert!(payload.len() <= 5_000);
}
