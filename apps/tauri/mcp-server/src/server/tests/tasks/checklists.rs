use super::*;
use serde_json::json;

fn seed_checklist_item(
    server: &LorvexMcpServer,
    item_id: &str,
    task_id: &str,
    position: i64,
    text: &str,
    completed_at: Option<&str>,
) {
    let now = "2026-03-01T00:00:00Z";
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO task_checklist_items (
                    id, task_id, position, text, completed_at, version, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, ?4, ?5, '0000000000000_0000_0000000000000000', ?6, ?6)",
                (item_id, task_id, position, text, completed_at, now),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed checklist item");
}

#[test]
#[serial_test::serial(hlc)]
fn get_task_response_includes_checklist_items_array() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000103",
        "Checklist Task",
        "open",
        None,
        None,
        None,
        0,
    );
    seed_checklist_item(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000901",
        "01966a3f-7c8b-7d4e-8f3a-000000000103",
        0,
        "First",
        None,
    );
    seed_checklist_item(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000902",
        "01966a3f-7c8b-7d4e-8f3a-000000000103",
        1,
        "Second",
        Some("2026-03-02T00:00:00Z"),
    );

    let response = server
        .get_task(Parameters(GetTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000103".to_string(),
        }))
        .expect("get task");
    let task: Value = serde_json::from_str(&response).expect("parse task");

    let items = task["checklist_items"]
        .as_array()
        .expect("task should include checklist_items");
    assert_eq!(items.len(), 2);
    // #2422: get_task wraps user-origin checklist item text with the
    // `⟦user⟧` untrusted fence (write-path returns stay raw).
    assert_eq!(
        items[0]["text"],
        json!("\u{27E6}user\u{27E7} First \u{27E6}/user\u{27E7}")
    );
    assert_eq!(items[1]["completed_at"], json!("2026-03-02T00:00:00Z"));
}

#[test]
#[serial_test::serial(hlc)]
fn add_task_checklist_item_returns_updated_task_with_inserted_order() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000102",
        "Checklist Add",
        "open",
        None,
        None,
        None,
        0,
    );
    seed_checklist_item(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000903",
        "01966a3f-7c8b-7d4e-8f3a-000000000102",
        0,
        "A",
        None,
    );
    seed_checklist_item(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000904",
        "01966a3f-7c8b-7d4e-8f3a-000000000102",
        1,
        "B",
        None,
    );

    let response = server
        .add_task_checklist_item(Parameters(AddTaskChecklistItemArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000102".to_string(),
            text: "Inserted".to_string(),
            position: Some(1),
            idempotency_key: None,
        }))
        .expect("add checklist item");
    let task: Value = serde_json::from_str(&response).expect("parse task");
    let texts: Vec<&str> = task["checklist_items"]
        .as_array()
        .expect("checklist_items array")
        .iter()
        .map(|item| item["text"].as_str().expect("text"))
        .collect();
    assert_eq!(texts, vec!["A", "Inserted", "B"]);
}

#[test]
#[serial_test::serial(hlc)]
fn toggle_and_reorder_checklist_items_return_enriched_task() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000104",
        "Checklist Toggle",
        "open",
        None,
        None,
        None,
        0,
    );
    seed_checklist_item(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000901",
        "01966a3f-7c8b-7d4e-8f3a-000000000104",
        0,
        "One",
        None,
    );
    seed_checklist_item(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000902",
        "01966a3f-7c8b-7d4e-8f3a-000000000104",
        1,
        "Two",
        None,
    );

    let toggled = server
        .toggle_task_checklist_item(Parameters(ToggleTaskChecklistItemArgs {
            item_id: "01966a3f-7c8b-7d4e-8f3a-000000000901".to_string(),
            completed: true,
            idempotency_key: None,
        }))
        .expect("toggle checklist item");
    let toggled_task: Value = serde_json::from_str(&toggled).expect("parse toggled task");
    assert!(
        toggled_task["checklist_items"][0]["completed_at"]
            .as_str()
            .is_some(),
        "completed toggle should set completed_at"
    );

    let reordered = server
        .reorder_task_checklist_items(Parameters(ReorderTaskChecklistItemsArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000104".to_string(),
            item_ids: vec![
                "01966a3f-7c8b-7d4e-8f3a-000000000902".to_string(),
                "01966a3f-7c8b-7d4e-8f3a-000000000901".to_string(),
            ],
            idempotency_key: None,
        }))
        .expect("reorder checklist items");
    let reordered_task: Value = serde_json::from_str(&reordered).expect("parse reordered task");
    let texts: Vec<&str> = reordered_task["checklist_items"]
        .as_array()
        .expect("checklist_items array")
        .iter()
        .map(|item| item["text"].as_str().expect("text"))
        .collect();
    assert_eq!(texts, vec!["Two", "One"]);
}

#[test]
#[serial_test::serial(hlc)]
fn toggle_task_checklist_item_retry_keeps_explicit_target_state() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000105",
        "Checklist Retry",
        "open",
        None,
        None,
        None,
        0,
    );
    seed_checklist_item(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000904",
        "01966a3f-7c8b-7d4e-8f3a-000000000105",
        0,
        "Retry-safe",
        None,
    );

    let mut task = json!(null);
    for _ in 0..2 {
        let response = server
            .toggle_task_checklist_item(Parameters(ToggleTaskChecklistItemArgs {
                item_id: "01966a3f-7c8b-7d4e-8f3a-000000000904".to_string(),
                completed: true,
                idempotency_key: None,
            }))
            .expect("set checklist item completed");
        task = serde_json::from_str(&response).expect("parse completed task");
    }
    assert!(
        task["checklist_items"][0]["completed_at"]
            .as_str()
            .is_some(),
        "duplicate completed=true calls should not flip the item back to incomplete",
    );

    for _ in 0..2 {
        let response = server
            .toggle_task_checklist_item(Parameters(ToggleTaskChecklistItemArgs {
                item_id: "01966a3f-7c8b-7d4e-8f3a-000000000904".to_string(),
                completed: false,
                idempotency_key: None,
            }))
            .expect("set checklist item incomplete");
        task = serde_json::from_str(&response).expect("parse incomplete task");
    }
    assert!(
        task["checklist_items"][0]["completed_at"].is_null(),
        "duplicate completed=false calls should keep the item incomplete",
    );
}

#[test]
#[serial_test::serial(hlc)]
fn toggle_task_checklist_item_rejects_missing_completed_target() {
    let err = serde_json::from_value::<ToggleTaskChecklistItemArgs>(json!({
        "item_id": "01966a3f-7c8b-7d4e-8f3a-000000000904",
    }))
    .expect_err("completed target should be required");
    assert!(
        err.to_string().contains("completed"),
        "serde error should name the missing completed field: {err}",
    );
}

/// `add_task_checklist_item` must:
///   1. emit a strictly-increasing, unique HLC per affected row
///      (the inserted item + every shifted sibling), and
///   2. advance the in-process HLC clock past the highest emitted
///      version so the NEXT local generate (in this transaction or
///      the next one sharing the writer connection) produces a
///      strictly greater HLC — no collisions with the suffix-
///      incremented values we just persisted.
///
/// Pre-fix the helper called `generate_hlc_version` per row inside
/// the loop, which is correct but wastes a process-wide mutex
/// acquisition + state rewrite per item. Post-fix we mint ONE base
/// HLC and locally suffix-increment its counter; the regression
/// surface is that the in-process clock no longer naturally
/// reflects every emitted version, so without the
/// `observe_local_event` advance the next generate would re-emit
/// `base.counter() + 1` and collide with the second persisted row.
/// This test pins both invariants.
#[test]
#[serial_test::serial(hlc)]
fn add_task_checklist_item_emits_unique_strictly_increasing_hlcs() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000101",
        "HLC batching",
        "open",
        None,
        None,
        None,
        0,
    );
    // Seed enough existing items that the position-bump loop runs
    // for every iteration (the new item lands at position 0, every
    // existing row shifts +1).
    for index in 0..6 {
        seed_checklist_item(
            &server,
            &format!("01966a3f-7c8b-7d4e-8f3a-00000000091{index}"),
            "01966a3f-7c8b-7d4e-8f3a-000000000101",
            index,
            &format!("Seed {index}"),
            None,
        );
    }

    server
        .add_task_checklist_item(Parameters(AddTaskChecklistItemArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000101".to_string(),
            text: "Inserted".to_string(),
            position: Some(0),
            idempotency_key: None,
        }))
        .expect("add checklist item");

    // Read every checklist row's persisted HLC and assert
    // (a) all unique and (b) strictly increasing in position order.
    let versions: Vec<String> = server
        .with_conn(|conn| {
            let mut stmt = conn
                .prepare(
                    "SELECT version FROM task_checklist_items \
                     WHERE task_id = ?1 ORDER BY position ASC",
                )
                .map_err(to_error_message)?;
            let rows = stmt
                .query_map(["01966a3f-7c8b-7d4e-8f3a-000000000101"], |row| {
                    row.get::<_, String>(0)
                })
                .map_err(to_error_message)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(to_error_message)?;
            Ok(rows)
        })
        .expect("read versions");
    assert_eq!(versions.len(), 7, "6 seeded + 1 newly-inserted");
    let unique: std::collections::HashSet<&String> = versions.iter().collect();
    assert_eq!(
        unique.len(),
        versions.len(),
        "every row must carry a unique HLC: {versions:?}",
    );
    for window in versions.windows(2) {
        assert!(
            window[0] < window[1],
            "HLCs must be strictly increasing in position order: {window:?}",
        );
    }
    let highest = versions.iter().max().expect("non-empty").clone();
    let highest_hlc =
        lorvex_domain::hlc::Hlc::parse(&highest).expect("emitted HLC must be parseable");

    // The next local write must produce an HLC strictly greater
    // than the highest emitted version. Use the public
    // `generate_hlc_version` helper to mint one and compare.
    let next_version = server
        .with_conn(|conn| {
            crate::runtime::change_tracking::generate_hlc_version(conn).map_err(to_error_message)
        })
        .expect("generate next HLC");
    let next_hlc =
        lorvex_domain::hlc::Hlc::parse(&next_version).expect("next HLC must be parseable");
    assert!(
        next_hlc > highest_hlc,
        "next generate ({next_hlc}) must exceed highest emitted ({highest_hlc}) — \
         the suffix-increment loop must advance the in-process clock past the top of the batch",
    );
}

#[test]
#[serial_test::serial(hlc)]
fn add_task_checklist_item_rolls_child_hlcs_at_counter_ceiling() {
    let server = make_server();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000010a";
    seed_task(&server, task_id, "HLC ceiling", "open", None, None, None, 0);
    seed_checklist_item(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-00000000090a",
        task_id,
        0,
        "Seed",
        None,
    );

    let mcp_suffix = server
        .with_conn(|conn| {
            let device_id = crate::runtime::change_tracking::get_or_create_sync_device_id(conn)
                .map_err(to_error_message)?;
            Ok(lorvex_runtime::device_id_to_hlc_suffix(
                &device_id,
                lorvex_domain::hlc::HlcSurface::Mcp,
            ))
        })
        .expect("derive MCP HLC suffix");
    let seed_version = format!("9000000000000_9996_{mcp_suffix}");
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE task_checklist_items SET version = ?1 WHERE id = ?2",
                (seed_version, "01966a3f-7c8b-7d4e-8f3a-00000000090a"),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed high checklist HLC");

    server
        .add_task_checklist_item(Parameters(AddTaskChecklistItemArgs {
            id: task_id.to_string(),
            text: "Inserted".to_string(),
            position: Some(0),
            idempotency_key: None,
        }))
        .expect("add checklist item at HLC counter ceiling");

    let versions: Vec<String> = server
        .with_conn(|conn| {
            let mut stmt = conn
                .prepare(
                    "SELECT version FROM task_checklist_items \
                     WHERE task_id = ?1 ORDER BY position ASC",
                )
                .map_err(to_error_message)?;
            let rows = stmt
                .query_map([task_id], |row| row.get::<_, String>(0))
                .map_err(to_error_message)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(to_error_message)?;
            Ok(rows)
        })
        .expect("read checklist HLCs");

    assert_eq!(versions.len(), 2, "inserted item plus shifted seed item");
    for version in &versions {
        let counter = version
            .split('_')
            .nth(1)
            .expect("counter segment should exist");
        assert_eq!(
            counter.len(),
            4,
            "counter segment must stay canonical width in {version}",
        );
        let parsed = lorvex_domain::hlc::Hlc::parse(version).expect("persisted HLC must parse");
        assert!(
            parsed.counter() <= lorvex_domain::hlc_state::MAX_COUNTER,
            "persisted HLC counter must stay <= MAX_COUNTER: {version}",
        );
    }
    for window in versions.windows(2) {
        assert!(
            window[0] < window[1],
            "rolled-over checklist row HLCs must remain strictly ordered: {versions:?}",
        );
    }
}

#[test]
#[serial_test::serial(hlc)]
fn remove_task_checklist_item_rejects_missing_item() {
    let server = make_server();
    let error = server
        .remove_task_checklist_item(Parameters(RemoveTaskChecklistItemArgs {
            item_id: "missing-item".to_string(),
            idempotency_key: None,
        }))
        .expect_err("missing checklist item should error");
    // #2182: not-found errors on the MCP boundary are structured JSON.
    let payload: serde_json::Value =
        serde_json::from_str(&error).expect("error must be a structured JSON payload");
    assert_eq!(payload["code"], "not_found");
    assert_eq!(payload["details"]["entity_id"], "missing-item");
    assert!(
        payload["message"]
            .as_str()
            .unwrap()
            .contains("checklist item 'missing-item' not found"),
        "message must preserve human-readable prose: {payload}"
    );
}
