use super::*;

fn open_memory_db() -> Connection {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
    conn
}

// ── Parser tests ────────────────────────────────────────────────

#[test]
fn parser_extracts_tables_indexes_triggers_views() {
    let sql = "
        CREATE TABLE IF NOT EXISTS alpha (id INTEGER PRIMARY KEY);
        CREATE UNIQUE INDEX IF NOT EXISTS idx_alpha_id ON alpha(id);
        CREATE INDEX idx_alpha_id2 ON alpha(id);
        CREATE TRIGGER IF NOT EXISTS trg_alpha AFTER INSERT ON alpha BEGIN SELECT 1; END;
        CREATE VIEW IF NOT EXISTS v_alpha AS SELECT id FROM alpha;
        CREATE VIRTUAL TABLE IF NOT EXISTS alpha_fts USING fts5(body);
    ";
    let objs = extract_objects(sql);
    let pairs: Vec<(DdlKind, &str)> = objs.iter().map(|o| (o.kind, o.name.as_str())).collect();
    assert_eq!(
        pairs,
        vec![
            (DdlKind::Table, "alpha"),
            (DdlKind::Index, "idx_alpha_id"),
            (DdlKind::Index, "idx_alpha_id2"),
            (DdlKind::Trigger, "trg_alpha"),
            (DdlKind::View, "v_alpha"),
            (DdlKind::Table, "alpha_fts"),
        ]
    );
}

#[test]
fn parser_ignores_create_statements_inside_comments() {
    let sql = "
        -- CREATE TABLE ghost (id INTEGER);
        /* CREATE INDEX idx_ghost ON ghost(id); */
        CREATE TABLE real_tbl (id INTEGER);
    ";
    let objs = extract_objects(sql);
    assert_eq!(objs.len(), 1);
    assert_eq!(objs[0].name, "real_tbl");
    assert_eq!(objs[0].kind, DdlKind::Table);
}

#[test]
fn parser_handles_quoted_identifiers() {
    let sql = r#"
        CREATE TABLE "quoted tbl" (id INTEGER);
        CREATE INDEX `idx_back` ON t(c);
        CREATE VIEW [bracketed_view] AS SELECT 1;
    "#;
    let objs = extract_objects(sql);
    assert_eq!(objs.len(), 3);
    assert_eq!(objs[0].name, "quoted tbl");
    assert_eq!(objs[1].name, "idx_back");
    assert_eq!(objs[2].name, "bracketed_view");
}

#[test]
fn parser_preserves_partial_index_where_clause_but_only_names_are_checked() {
    // A partial index's `WHERE` clause must not be picked up as an
    // object name; only `idx_partial` matters for existence checks.
    let sql = "
        CREATE INDEX idx_partial ON t(col) WHERE col IS NOT NULL;
    ";
    let objs = extract_objects(sql);
    assert_eq!(objs.len(), 1);
    assert_eq!(objs[0].name, "idx_partial");
    assert_eq!(objs[0].kind, DdlKind::Index);
}

#[test]
fn parser_is_case_insensitive_on_keywords() {
    let sql = "create table lower_case (id INTEGER); CREATE Table MixedCase (id INTEGER);";
    let objs = extract_objects(sql);
    assert_eq!(objs.len(), 2);
    assert_eq!(objs[0].name, "lower_case");
    assert_eq!(objs[1].name, "MixedCase");
}

#[test]
fn parser_handles_full_production_schema() {
    // Sanity: the canonical schema parses without panicking and
    // produces a non-trivial count. The exact number drifts as the
    // schema evolves, so just assert a floor that would catch a
    // wholesale regression.
    // Path is one `..` deeper than the original `schema_audit.rs` site
    // because tests now live under `schema_audit/tests.rs`.
    let sql = include_str!("../../schema/001_schema.sql");
    let objs = extract_objects(sql);
    assert!(
        objs.len() >= 100,
        "expected >=100 DDL objects in canonical schema, got {}",
        objs.len()
    );
}

// ── Runner integration tests ─────────────────────────────────────

#[test]
fn audit_passes_when_all_objects_present() {
    let conn = open_memory_db();
    let migration = Migration {
        version: 1,
        name: "create_full".into(),
        sql: "CREATE TABLE foo (id INTEGER PRIMARY KEY); \
              CREATE INDEX idx_foo ON foo(id);"
            .into(),
    };
    conn.execute_batch(&migration.sql).unwrap();
    audit_migration(&conn, &migration).expect("all objects present");
}

#[test]
fn audit_fails_when_table_missing() {
    let conn = open_memory_db();
    let migration = Migration {
        version: 2,
        name: "create_gone".into(),
        sql: "CREATE TABLE needed (id INTEGER PRIMARY KEY);".into(),
    };
    // Don't run the DDL — simulate a dropped-out-of-band table.
    let err = audit_migration(&conn, &migration).expect_err("table missing should fail");
    match err {
        MigrationError::CorruptedSchema {
            version,
            missing_kind,
            missing_object,
            ..
        } => {
            assert_eq!(version, 2);
            assert_eq!(missing_kind, "table");
            assert_eq!(missing_object, "needed");
        }
        other => panic!("expected CorruptedSchema, got {other:?}"),
    }
}

#[test]
fn audit_fails_when_index_missing() {
    let conn = open_memory_db();
    // Create the table, but not the index.
    conn.execute_batch("CREATE TABLE foo (id INTEGER PRIMARY KEY);")
        .unwrap();
    let migration = Migration {
        version: 3,
        name: "partial_apply".into(),
        sql: "CREATE TABLE foo (id INTEGER PRIMARY KEY); \
              CREATE INDEX idx_foo_id ON foo(id);"
            .into(),
    };
    let err = audit_migration(&conn, &migration).expect_err("index missing should fail");
    match err {
        MigrationError::CorruptedSchema {
            missing_kind,
            missing_object,
            ..
        } => {
            assert_eq!(missing_kind, "index");
            assert_eq!(missing_object, "idx_foo_id");
        }
        other => panic!("expected CorruptedSchema, got {other:?}"),
    }
}

#[test]
fn audit_fails_when_trigger_missing() {
    let conn = open_memory_db();
    conn.execute_batch("CREATE TABLE foo (id INTEGER PRIMARY KEY);")
        .unwrap();
    let migration = Migration {
        version: 4,
        name: "missing_trigger".into(),
        sql: "CREATE TABLE foo (id INTEGER PRIMARY KEY); \
              CREATE TRIGGER trg_foo AFTER INSERT ON foo BEGIN SELECT 1; END;"
            .into(),
    };
    let err = audit_migration(&conn, &migration).expect_err("trigger missing should fail");
    match err {
        MigrationError::CorruptedSchema {
            missing_kind,
            missing_object,
            ..
        } => {
            assert_eq!(missing_kind, "trigger");
            assert_eq!(missing_object, "trg_foo");
        }
        other => panic!("expected CorruptedSchema, got {other:?}"),
    }
}

#[test]
fn audit_partial_index_where_clause_is_not_re_checked() {
    // The WHERE predicate is preserved in the DDL signature (it's
    // inside the CREATE statement) but the audit only checks object
    // *existence*, not predicate equivalence. So an index present in
    // sqlite_schema under the expected name passes, regardless of
    // whether its WHERE matches what the migration file says.
    let conn = open_memory_db();
    conn.execute_batch(
        "CREATE TABLE t (id INTEGER PRIMARY KEY, deleted INTEGER); \
         CREATE INDEX idx_partial ON t(id) WHERE id > 0;",
    )
    .unwrap();
    let migration = Migration {
        version: 5,
        name: "partial_where".into(),
        // File says WHERE deleted = 0 — different predicate, but we
        // don't compare predicates. Existence alone is enough.
        sql: "CREATE TABLE t (id INTEGER PRIMARY KEY, deleted INTEGER); \
              CREATE INDEX idx_partial ON t(id) WHERE deleted = 0;"
            .into(),
    };
    audit_migration(&conn, &migration).expect("existence-only audit passes");
}

#[test]
fn audit_reports_first_missing_object_deterministically() {
    // When multiple objects are missing, the audit returns the first
    // one encountered in DDL order. Callers get a single actionable
    // name rather than a dumped list.
    let conn = open_memory_db();
    let migration = Migration {
        version: 6,
        name: "all_missing".into(),
        sql: "CREATE TABLE alpha (id INTEGER PRIMARY KEY); \
              CREATE TABLE beta (id INTEGER PRIMARY KEY);"
            .into(),
    };
    let err = audit_migration(&conn, &migration).unwrap_err();
    match err {
        MigrationError::CorruptedSchema { missing_object, .. } => {
            assert_eq!(missing_object, "alpha");
        }
        other => panic!("expected CorruptedSchema, got {other:?}"),
    }
}

#[test]
fn audit_treats_virtual_table_as_table_in_sqlite_schema() {
    // FTS5 virtual tables are recorded with type='table' in
    // sqlite_schema — the audit must use that type, not
    // 'virtual table', or it would spuriously fail.
    let conn = open_memory_db();
    conn.execute_batch("CREATE VIRTUAL TABLE t_fts USING fts5(body);")
        .unwrap();
    let migration = Migration {
        version: 7,
        name: "virt".into(),
        sql: "CREATE VIRTUAL TABLE IF NOT EXISTS t_fts USING fts5(body);".into(),
    };
    audit_migration(&conn, &migration).expect("virtual table audit passes");
}
