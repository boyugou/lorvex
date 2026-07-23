use super::*;

const VALID_VERSION: &str = "1711234567890_0001_deadbeefdeadbeef";

fn zip_with_single_versioned_row(
    stream_name: &str,
    row: serde_json::Value,
) -> (tempfile::TempDir, std::path::PathBuf) {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");

    match stream_name {
        "entities.jsonl" => write_import_zip(&zip_path, &[row], &[], &[], &[], &[]),
        "edges.jsonl" => write_import_zip(&zip_path, &[], &[row], &[], &[], &[]),
        "children.jsonl" => write_import_zip(&zip_path, &[], &[], &[row], &[], &[]),
        other => panic!("unsupported stream in test helper: {other}"),
    }

    (dir, zip_path)
}

fn versioned_row(entity_type: &str) -> serde_json::Value {
    serde_json::json!({
        "entity_type": entity_type,
        "entity_id": "row-1",
        "version": VALID_VERSION,
        "payload": {
            "id": "row-1",
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        }
    })
}

fn assert_invalid_payload_contains(err: ImportError, expected_parts: &[&str]) {
    match err {
        ImportError::InvalidPayload(message) => {
            for expected in expected_parts {
                assert!(
                    message.contains(expected),
                    "expected invalid payload message to contain {expected:?}, got: {message}"
                );
            }
        }
        other => panic!("expected InvalidPayload, got {other:?}"),
    }
}

fn tombstones_import_error(tombstones: &[serde_json::Value], dry_run: bool) -> ImportError {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(&zip_path, &[], &[], &[], &[], tombstones);
    let conn = open_db_in_memory().unwrap();

    import_from_zip_with_options(&conn, &zip_path, ImportOptions { dry_run }).unwrap_err()
}

fn provider_links_import_error(provider_links: &[serde_json::Value], dry_run: bool) -> ImportError {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip_with_provider_links(&zip_path, provider_links);
    let conn = open_db_in_memory().unwrap();

    import_from_zip_with_options(&conn, &zip_path, ImportOptions { dry_run }).unwrap_err()
}

#[test]
fn import_rejects_unknown_entity_type_in_entities_stream() {
    let (_dir, zip_path) =
        zip_with_single_versioned_row("entities.jsonl", versioned_row("future_entity"));
    let conn = open_db_in_memory().unwrap();

    let err = import_from_zip(&conn, &zip_path).unwrap_err();

    assert_invalid_payload_contains(
        err,
        &["entities.jsonl", "unknown entity_type", "future_entity"],
    );
}

#[test]
fn import_rejects_unknown_entity_type_in_edges_stream() {
    let (_dir, zip_path) =
        zip_with_single_versioned_row("edges.jsonl", versioned_row("future_edge"));
    let conn = open_db_in_memory().unwrap();

    let err = import_from_zip(&conn, &zip_path).unwrap_err();

    assert_invalid_payload_contains(err, &["edges.jsonl", "unknown entity_type", "future_edge"]);
}

#[test]
fn import_rejects_unknown_entity_type_in_children_stream() {
    let (_dir, zip_path) =
        zip_with_single_versioned_row("children.jsonl", versioned_row("future_child"));
    let conn = open_db_in_memory().unwrap();

    let err = import_from_zip(&conn, &zip_path).unwrap_err();

    assert_invalid_payload_contains(
        err,
        &["children.jsonl", "unknown entity_type", "future_child"],
    );
}

#[test]
fn import_rejects_edge_rows_in_entities_stream() {
    let (_dir, zip_path) =
        zip_with_single_versioned_row("entities.jsonl", versioned_row(EDGE_TASK_TAG));
    let conn = open_db_in_memory().unwrap();

    let err = import_from_zip(&conn, &zip_path).unwrap_err();

    assert_invalid_payload_contains(
        err,
        &["entities.jsonl", EDGE_TASK_TAG, "different import stream"],
    );
}

#[test]
fn import_rejects_aggregate_rows_in_edges_stream() {
    let (_dir, zip_path) = zip_with_single_versioned_row("edges.jsonl", versioned_row(ENTITY_TASK));
    let conn = open_db_in_memory().unwrap();

    let err = import_from_zip(&conn, &zip_path).unwrap_err();

    assert_invalid_payload_contains(
        err,
        &["edges.jsonl", ENTITY_TASK, "different import stream"],
    );
}

#[test]
fn import_rejects_aggregate_rows_in_children_stream() {
    let (_dir, zip_path) =
        zip_with_single_versioned_row("children.jsonl", versioned_row(ENTITY_TASK));
    let conn = open_db_in_memory().unwrap();

    let err = import_from_zip(&conn, &zip_path).unwrap_err();

    assert_invalid_payload_contains(
        err,
        &["children.jsonl", ENTITY_TASK, "different import stream"],
    );
}

#[test]
fn import_rejects_entity_id_that_disagrees_with_payload_identity() {
    let mut row = versioned_row(ENTITY_LIST);
    row["payload"]["id"] = serde_json::json!("payload-list");
    let (_dir, zip_path) = zip_with_single_versioned_row("entities.jsonl", row);
    let conn = open_db_in_memory().unwrap();

    let err = import_from_zip(&conn, &zip_path).unwrap_err();

    assert_invalid_payload_contains(
        err,
        &[
            "entities.jsonl",
            ENTITY_LIST,
            "entity_id `row-1`",
            "payload identity is `payload-list`",
        ],
    );
}

#[test]
fn import_rejects_entity_row_missing_top_level_entity_id() {
    let mut row = versioned_row(ENTITY_LIST);
    row.as_object_mut().unwrap().remove("entity_id");
    let (_dir, zip_path) = zip_with_single_versioned_row("entities.jsonl", row);
    let conn = open_db_in_memory().unwrap();

    let err = import_from_zip(&conn, &zip_path).unwrap_err();

    assert_invalid_payload_contains(err, &["entities.jsonl", ENTITY_LIST, "top-level entity_id"]);
}

#[test]
fn import_rejects_child_entity_id_that_disagrees_with_payload_identity() {
    let mut row = versioned_row(ENTITY_TASK_REMINDER);
    row["payload"]["id"] = serde_json::json!("payload-reminder");
    let (_dir, zip_path) = zip_with_single_versioned_row("children.jsonl", row);
    let conn = open_db_in_memory().unwrap();

    let err = import_from_zip(&conn, &zip_path).unwrap_err();

    assert_invalid_payload_contains(
        err,
        &[
            "children.jsonl",
            ENTITY_TASK_REMINDER,
            "entity_id `row-1`",
            "payload identity is `payload-reminder`",
        ],
    );
}

#[test]
fn dry_run_rejects_unknown_entity_type_before_preview_success() {
    let (_dir, zip_path) =
        zip_with_single_versioned_row("entities.jsonl", versioned_row("future_entity"));
    let conn = open_db_in_memory().unwrap();

    let err = import_from_zip_with_options(&conn, &zip_path, ImportOptions { dry_run: true })
        .unwrap_err();

    assert_invalid_payload_contains(
        err,
        &["entities.jsonl", "unknown entity_type", "future_entity"],
    );
}

#[test]
fn dry_run_rejects_wrong_stream_entity_type_before_preview_success() {
    let (_dir, zip_path) =
        zip_with_single_versioned_row("children.jsonl", versioned_row(ENTITY_TASK));
    let conn = open_db_in_memory().unwrap();

    let err = import_from_zip_with_options(&conn, &zip_path, ImportOptions { dry_run: true })
        .unwrap_err();

    assert_invalid_payload_contains(
        err,
        &["children.jsonl", ENTITY_TASK, "different import stream"],
    );
}

#[test]
fn import_rejects_unknown_entity_type_in_tombstones_stream() {
    let err = tombstones_import_error(
        &[serde_json::json!({
            "entity_type": "future_tombstone",
            "entity_id": "future-1",
            "version": VALID_VERSION,
            "deleted_at": "2026-03-29T00:00:00Z"
        })],
        false,
    );

    assert_invalid_payload_contains(
        err,
        &[
            "tombstones.jsonl",
            "unknown entity_type",
            "future_tombstone",
        ],
    );
}

#[test]
fn dry_run_rejects_unknown_entity_type_in_tombstones_stream() {
    let err = tombstones_import_error(
        &[serde_json::json!({
            "entity_type": "future_tombstone",
            "entity_id": "future-1",
            "version": VALID_VERSION,
            "deleted_at": "2026-03-29T00:00:00Z"
        })],
        true,
    );

    assert_invalid_payload_contains(
        err,
        &[
            "tombstones.jsonl",
            "unknown entity_type",
            "future_tombstone",
        ],
    );
}

#[test]
fn import_rejects_unknown_redirect_entity_type_in_tombstones_stream() {
    let err = tombstones_import_error(
        &[serde_json::json!({
            "entity_type": ENTITY_TAG,
            "entity_id": "tag-merged-1",
            "version": VALID_VERSION,
            "deleted_at": "2026-03-29T00:00:00Z",
            "redirect_entity_id": "future-target-1",
            "redirect_entity_type": "future_redirect_target"
        })],
        false,
    );

    assert_invalid_payload_contains(
        err,
        &[
            "tombstones.jsonl",
            "unknown redirect_entity_type",
            "future_redirect_target",
        ],
    );
}

#[test]
fn dry_run_rejects_unknown_redirect_entity_type_in_tombstones_stream() {
    let err = tombstones_import_error(
        &[serde_json::json!({
            "entity_type": ENTITY_TAG,
            "entity_id": "tag-merged-1",
            "version": VALID_VERSION,
            "deleted_at": "2026-03-29T00:00:00Z",
            "redirect_entity_id": "future-target-1",
            "redirect_entity_type": "future_redirect_target"
        })],
        true,
    );

    assert_invalid_payload_contains(
        err,
        &[
            "tombstones.jsonl",
            "unknown redirect_entity_type",
            "future_redirect_target",
        ],
    );
}

#[test]
fn import_rejects_wrong_entity_type_in_provider_links_stream() {
    let err = provider_links_import_error(
        &[serde_json::json!({
            "entity_type": ENTITY_TASK,
            "entity_id": "task-1",
            "payload": {
                "task_id": "task-1",
                "provider_kind": "eventkit",
                "provider_scope": "primary",
                "provider_event_key": "event-1",
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        false,
    );

    assert_invalid_payload_contains(
        err,
        &[
            "provider_links.jsonl",
            ENTITY_TASK,
            EDGE_TASK_PROVIDER_EVENT_LINK,
        ],
    );
}

#[test]
fn dry_run_rejects_unknown_entity_type_in_provider_links_stream() {
    let err = provider_links_import_error(
        &[serde_json::json!({
            "entity_type": "future_provider_link",
            "entity_id": "future-link-1",
            "payload": {
                "task_id": "task-1",
                "provider_kind": "eventkit",
                "provider_scope": "primary",
                "provider_event_key": "event-1",
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        true,
    );

    assert_invalid_payload_contains(
        err,
        &[
            "provider_links.jsonl",
            "future_provider_link",
            EDGE_TASK_PROVIDER_EVENT_LINK,
        ],
    );
}
