use super::support::*;

#[test]
fn test_audit_entries_survive_roundtrip() {
    let dirs = setup_dirs();

    let source = open_db_in_memory().unwrap();
    source
        .execute(
            "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, entity_id, summary, initiated_by, mcp_tool)
             VALUES ('cl-1', '2026-03-24T10:00:00Z', 'create', 'task', 'task-1', 'Created task Do stuff', 'ai', 'create_tasks')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, entity_id, summary, initiated_by)
             VALUES ('cl-2', '2026-03-24T11:00:00Z', 'update', 'task', 'task-1', 'Updated priority', 'ai')",
            [],
        )
        .unwrap();

    export_to_zip(&source, &dirs.zip_path, "dev-1").unwrap();

    let target = open_db_in_memory().unwrap();
    import_from_zip(&target, &dirs.zip_path).unwrap();

    let audit_count: i64 = target
        .query_row("SELECT COUNT(*) FROM ai_changelog", [], |r| r.get(0))
        .unwrap();
    assert_eq!(audit_count, 2);

    let summary: String = target
        .query_row(
            "SELECT summary FROM ai_changelog WHERE id = 'cl-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(summary, "Created task Do stuff");
}

#[test]
fn test_audit_export_filters_non_canonical_entries() {
    let dirs = setup_dirs();
    let source = open_db_in_memory().unwrap();

    // Insert one canonical (ai) and one non-canonical (human) entry.
    source.execute(
        "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, entity_id, summary, initiated_by)
         VALUES ('cl-ai', '2026-03-24T10:00:00Z', 'create', 'task', 't1', 'AI created', 'ai')",
        [],
    ).unwrap();
    source.execute(
        "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, entity_id, summary, initiated_by)
         VALUES ('cl-human', '2026-03-24T11:00:00Z', 'update', 'task', 't1', 'Human edited', 'human')",
        [],
    ).unwrap();

    export_to_zip(&source, &dirs.zip_path, "dev-1").unwrap();

    let target = open_db_in_memory().unwrap();
    import_from_zip(&target, &dirs.zip_path).unwrap();

    // Only the canonical (ai) entry should survive.
    let count: i64 = target
        .query_row("SELECT COUNT(*) FROM ai_changelog", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 1, "Only canonical entries should be exported");

    let id: String = target
        .query_row("SELECT id FROM ai_changelog", [], |r| r.get(0))
        .unwrap();
    assert_eq!(id, "cl-ai");
}

// ---------------------------------------------------------------------------
// Preferences and AI memory survive round-trip
// ---------------------------------------------------------------------------

#[test]
fn test_preferences_and_memory_roundtrip() {
    let dirs = setup_dirs();

    let source = open_db_in_memory().unwrap();
    source
        .execute(
            "INSERT INTO preferences (key, value, updated_at, version)
             VALUES ('theme', '\"dark\"', '2026-01-01T00:00:00Z', '1711234567890_0050_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO memories (id, key, content, updated_at, version)
             VALUES ('01920000-0000-7000-8000-000000000051', 'user_timezone', 'America/New_York', '2026-01-01T00:00:00Z', '1711234567890_0051_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();

    export_to_zip(&source, &dirs.zip_path, "dev-1").unwrap();

    let target = open_db_in_memory().unwrap();
    import_from_zip(&target, &dirs.zip_path).unwrap();

    let theme: String = target
        .query_row(
            "SELECT value FROM preferences WHERE key = 'theme'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(theme, "\"dark\"");

    let tz: String = target
        .query_row(
            "SELECT content FROM memories WHERE key = 'user_timezone'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(tz, "America/New_York");
}
