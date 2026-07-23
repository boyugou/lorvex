use super::*;

#[test]
fn scoped_import_reports_missing_entity_dependency_without_mutation() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("scoped-import.zip");
    write_import_zip_with_manifest(
        &zip_path,
        serde_json::json!({
            "format_version": EXPORT_FORMAT_VERSION,
            "schema_version": 1,
            "payload_schema_version": 1,
            "created_at": "2026-03-29T00:00:00Z",
            "device_id": "test-device",
            "scope_kind": "scoped",
            "scope_categories": ["tasks"],
            "dependency_mode": "closure",
        }),
        &[serde_json::json!({
            "entity_type": ENTITY_TASK,
            "entity_id": "task-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "task-1",
                "title": "Scoped task",
                "status": "open",
                "list_id": "missing-list",
                "defer_count": 0,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let summary =
        import_from_zip_with_options(&conn, &zip_path, ImportOptions { dry_run: true }).unwrap();
    assert!(summary.dry_run);
    assert_eq!(summary.entities_created, 0);
    assert_eq!(summary.entities_updated, 0);
    assert_eq!(summary.entities_skipped, 0);
    assert_eq!(
        serde_json::to_value(summary.scope_kind).unwrap(),
        serde_json::json!("scoped")
    );
    assert_eq!(summary.scope_categories, vec![ExportCategory::Tasks]);
    assert!(
        summary.validation_findings.iter().any(|finding| {
            finding.code == "missing_list_reference" && finding.message.contains("missing-list")
        }),
        "expected missing_list_reference finding, got {:?}",
        summary.validation_findings,
    );
    let task_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get(0))
        .unwrap();
    assert_eq!(task_count, 0);
}

#[test]
fn scoped_import_commit_rejects_validation_errors_without_mutation() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("scoped-import.zip");
    write_import_zip_with_manifest(
        &zip_path,
        serde_json::json!({
            "format_version": EXPORT_FORMAT_VERSION,
            "schema_version": 1,
            "payload_schema_version": 1,
            "created_at": "2026-03-29T00:00:00Z",
            "device_id": "test-device",
            "scope_kind": "scoped",
            "scope_categories": ["tasks"],
            "dependency_mode": "closure",
        }),
        &[serde_json::json!({
            "entity_type": ENTITY_TASK,
            "entity_id": "task-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "task-1",
                "title": "Scoped task",
                "status": "open",
                "list_id": "missing-list",
                "defer_count": 0,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip_with_options(&conn, &zip_path, ImportOptions { dry_run: false })
        .unwrap_err();
    match err {
        ImportError::InvalidPayload(message) => {
            assert!(
                message.contains("scoped import validation failed"),
                "expected scoped validation failure message, got: {message}"
            );
            assert!(
                message.contains("missing_list_reference"),
                "expected finding code in failure message, got: {message}"
            );
        }
        other => panic!("expected InvalidPayload for scoped validation error, got {other:?}"),
    }
    let task_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get(0))
        .unwrap();
    assert_eq!(task_count, 0);
}

#[test]
fn scoped_import_preflight_rejects_entity_id_payload_identity_mismatch() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("scoped-identity-mismatch.zip");
    write_import_zip_with_manifest(
        &zip_path,
        serde_json::json!({
            "format_version": EXPORT_FORMAT_VERSION,
            "schema_version": 1,
            "payload_schema_version": 1,
            "created_at": "2026-03-29T00:00:00Z",
            "device_id": "test-device",
            "scope_kind": "scoped",
            "scope_categories": ["tasks"],
            "dependency_mode": "closure",
        }),
        &[serde_json::json!({
            "entity_type": ENTITY_TASK,
            "entity_id": "task-top-level",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "task-payload",
                "title": "Scoped task",
                "status": "open",
                "list_id": "list-1",
                "defer_count": 0,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip_with_options(&conn, &zip_path, ImportOptions { dry_run: true })
        .unwrap_err();

    match err {
        ImportError::InvalidPayload(message) => {
            assert!(message.contains("invalid entities.jsonl"));
            assert!(message.contains("entity_id `task-top-level`"));
            assert!(message.contains("payload identity is `task-payload`"));
        }
        other => panic!("expected InvalidPayload, got {other:?}"),
    }
}

#[test]
fn scoped_import_rejects_archive_records_outside_declared_scope() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("scoped-impure.zip");
    write_import_zip_with_manifest(
        &zip_path,
        serde_json::json!({
            "format_version": EXPORT_FORMAT_VERSION,
            "schema_version": 1,
            "payload_schema_version": 1,
            "created_at": "2026-03-29T00:00:00Z",
            "device_id": "test-device",
            "scope_kind": "scoped",
            "scope_categories": ["tasks"],
            "dependency_mode": "closure",
        }),
        &[
            serde_json::json!({
                "entity_type": ENTITY_LIST,
                "entity_id": "list-1",
                "version": "1711234567890_0000_deadbeefdeadbeef",
                "payload": {
                    "id": "list-1",
                    "name": "Scoped list",
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_TASK,
                "entity_id": "task-1",
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": {
                    "id": "task-1",
                    "title": "Scoped task",
                    "status": "open",
                    "list_id": "list-1",
                    "defer_count": 0,
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_PREFERENCE,
                "entity_id": "theme",
                "version": "1711234567890_0002_deadbeefdeadbeef",
                "payload": {
                    "key": "theme",
                    "value": "\"dark\"",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
        ],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let summary =
        import_from_zip_with_options(&conn, &zip_path, ImportOptions { dry_run: true }).unwrap();
    assert!(summary.dry_run);
    assert_eq!(summary.entities_created, 0);
    assert!(
        summary.validation_findings.iter().any(|finding| {
            finding.code == "scope_purity_violation" && finding.message.contains("preference")
        }),
        "expected scope_purity_violation finding, got {:?}",
        summary.validation_findings,
    );
}

#[test]
fn scoped_import_rejects_payload_shadow_outside_declared_scope() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("scoped-shadow-impure.zip");
    write_import_zip_with_sections(
        &zip_path,
        serde_json::json!({
            "format_version": EXPORT_FORMAT_VERSION,
            "schema_version": 1,
            "payload_schema_version": 1,
            "created_at": "2026-03-29T00:00:00Z",
            "device_id": "test-device",
            "scope_kind": "scoped",
            "scope_categories": ["tasks"],
            "dependency_mode": "closure",
        }),
        &[
            serde_json::json!({
                "entity_type": ENTITY_LIST,
                "entity_id": "list-1",
                "version": "1711234567890_0000_deadbeefdeadbeef",
                "payload": {
                    "id": "list-1",
                    "name": "Scoped list",
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_TASK,
                "entity_id": "task-1",
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": {
                    "id": "task-1",
                    "title": "Scoped task",
                    "status": "open",
                    "list_id": "list-1",
                    "defer_count": 0,
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
        ],
        &[],
        &[],
        &[],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_PREFERENCE,
            "entity_id": "theme",
            "base_version": "1711234567890_0002_deadbeefdeadbeef",
            "payload_schema_version": 1,
            "raw_payload_json": "{\"key\":\"theme\",\"value\":\"\\\"dark\\\"\"}",
            "updated_at": "2026-03-29T00:00:00Z"
        })],
    );

    let conn = open_db_in_memory().unwrap();
    let summary =
        import_from_zip_with_options(&conn, &zip_path, ImportOptions { dry_run: true }).unwrap();
    assert!(summary.dry_run);
    assert_eq!(summary.entities_created, 0);
    assert!(
        summary.validation_findings.iter().any(|finding| {
            finding.code == "scope_purity_violation"
                && finding.message.contains("payload shadow")
                && finding.message.contains(ENTITY_PREFERENCE)
        }),
        "expected payload-shadow scope_purity_violation finding, got {:?}",
        summary.validation_findings,
    );
}

#[test]
fn scoped_import_rejects_provider_link_outside_declared_scope() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("scoped-provider-link-impure.zip");
    write_import_zip_with_sections_inner(
        &zip_path,
        serde_json::json!({
            "format_version": EXPORT_FORMAT_VERSION,
            "schema_version": 1,
            "payload_schema_version": 1,
            "created_at": "2026-03-29T00:00:00Z",
            "device_id": "test-device",
            "scope_kind": "scoped",
            "scope_categories": ["tasks"],
            "dependency_mode": "closure",
        }),
        ImportZipSectionRows {
            entities: &[
                serde_json::json!({
                    "entity_type": ENTITY_LIST,
                    "entity_id": "list-1",
                    "version": "1711234567890_0000_deadbeefdeadbeef",
                    "payload": {
                        "id": "list-1",
                        "name": "Scoped list",
                        "created_at": "2026-03-29T00:00:00Z",
                        "updated_at": "2026-03-29T00:00:00Z"
                    }
                }),
                serde_json::json!({
                    "entity_type": ENTITY_TASK,
                    "entity_id": "task-1",
                    "version": "1711234567890_0001_deadbeefdeadbeef",
                    "payload": {
                        "id": "task-1",
                        "title": "Scoped task",
                        "status": "open",
                        "list_id": "list-1",
                        "defer_count": 0,
                        "created_at": "2026-03-29T00:00:00Z",
                        "updated_at": "2026-03-29T00:00:00Z"
                    }
                }),
            ],
            provider_links: &[serde_json::json!({
                "entity_type": EDGE_TASK_PROVIDER_EVENT_LINK,
                "payload": {
                    "task_id": "task-outside",
                    "provider_kind": "eventkit",
                    "provider_scope": "local",
                    "provider_event_key": "event-outside",
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            })],
            ..ImportZipSectionRows::empty()
        },
    );

    let conn = open_db_in_memory().unwrap();
    let summary =
        import_from_zip_with_options(&conn, &zip_path, ImportOptions { dry_run: true }).unwrap();
    assert!(summary.dry_run);
    assert!(
        summary.validation_findings.iter().any(|finding| {
            finding.code == "scope_purity_violation"
                && finding.message.contains("provider link")
                && finding.message.contains(EDGE_TASK_PROVIDER_EVENT_LINK)
        }),
        "expected provider-link scope_purity_violation, got {:?}",
        summary.validation_findings,
    );

    let link_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_provider_event_links",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(link_count, 0);
}
