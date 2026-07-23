use super::*;
use rusqlite::params;

// ── lww_upsert_spec ──────────────────────────────────────────────

/// The rendered SQL must include every per-entity piece (table,
/// conflict cols, non-conflict columns assigned from `excluded`)
/// and the LWW predicate keyed off the `allow_equal` flag.
/// Byte-equality with the canonical hand-rolled apply-pipeline
/// template is checked separately by the integration tests.
#[test]
fn build_sql_emits_strict_lww_clause() {
    let spec = LwwUpsertSpec {
        table: "preferences",
        columns: &["key", "value", "updated_at", "version"],
        conflict: &["key"],
        tie_break: LwwTieBreak::RejectEqual,
    };
    let sql = spec.build_sql();
    assert!(sql.contains("INSERT INTO preferences (key, value, updated_at, version)"));
    assert!(sql.contains("VALUES (:key, :value, :updated_at, :version)"));
    assert!(sql.contains("ON CONFLICT(key) DO UPDATE SET"));
    // Conflict column must NOT appear in SET.
    assert!(!sql.contains("key=excluded.key"));
    assert!(sql.contains("value=excluded.value"));
    assert!(sql.contains("version=excluded.version"));
    assert!(sql.contains("WHERE excluded.version > preferences.version"));
}

#[test]
fn build_sql_allow_equal_flips_predicate() {
    let spec = LwwUpsertSpec {
        table: "preferences",
        columns: &["key", "value", "updated_at", "version"],
        conflict: &["key"],
        tie_break: LwwTieBreak::AllowEqual,
    };
    let sql = spec.build_sql();
    assert!(sql.contains("WHERE excluded.version >= preferences.version"));
}

#[test]
fn build_sql_supports_composite_conflict_keys() {
    let spec = LwwUpsertSpec {
        table: "task_tags",
        columns: &["task_id", "tag_id", "created_at", "version"],
        conflict: &["task_id", "tag_id"],
        tie_break: LwwTieBreak::RejectEqual,
    };
    let sql = spec.build_sql();
    assert!(sql.contains("ON CONFLICT(task_id, tag_id) DO UPDATE SET"));
    // Both conflict columns must be excluded from SET.
    assert!(!sql.contains("task_id=excluded.task_id"));
    assert!(!sql.contains("tag_id=excluded.tag_id"));
    assert!(sql.contains("created_at=excluded.created_at"));
    assert!(sql.contains("version=excluded.version"));
}

// ── lww_gated_delete ──────────────────────────────────────────────

fn fresh_conn() -> Connection {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    conn.execute(
        "CREATE TABLE widgets (id TEXT PRIMARY KEY, version TEXT NOT NULL)",
        [],
    )
    .expect("create widgets");
    conn.execute(
        "CREATE TABLE composites (
            a TEXT NOT NULL,
            b TEXT NOT NULL,
            version TEXT NOT NULL,
            PRIMARY KEY (a, b)
        )",
        [],
    )
    .expect("create composites");
    conn
}

fn count_widgets(conn: &Connection, id: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM widgets WHERE id = ?1",
        params![id],
        |row| row.get(0),
    )
    .expect("count widgets")
}

#[test]
fn deletes_when_incoming_version_strictly_greater() {
    let conn = fresh_conn();
    conn.execute(
        "INSERT INTO widgets (id, version) VALUES (?1, ?2)",
        params!["w1", "0000000001000_0000_aaaaaaaaaaaaaaaa"],
    )
    .expect("seed widget");
    let deleted = lww_gated_delete(
        &conn,
        "widgets",
        &["id"],
        &["w1"],
        "0000000002000_0000_aaaaaaaaaaaaaaaa",
    )
    .expect("delete");
    assert_eq!(deleted, 1);
    assert_eq!(count_widgets(&conn, "w1"), 0);
}

#[test]
fn deletes_when_incoming_version_equal() {
    let conn = fresh_conn();
    let v = "0000000001000_0000_aaaaaaaaaaaaaaaa";
    conn.execute(
        "INSERT INTO widgets (id, version) VALUES (?1, ?2)",
        params!["w1", v],
    )
    .expect("seed widget");
    // The legacy SQL `:version >= version` admitted equal versions.
    // The helper preserves that — `compare_versions_with_fallback`
    // returns Equal, which is NOT Less, so the DELETE proceeds.
    let deleted = lww_gated_delete(&conn, "widgets", &["id"], &["w1"], v).expect("delete");
    assert_eq!(deleted, 1);
}

#[test]
fn refuses_when_local_version_strictly_greater() {
    let conn = fresh_conn();
    conn.execute(
        "INSERT INTO widgets (id, version) VALUES (?1, ?2)",
        params!["w1", "0000000002000_0000_aaaaaaaaaaaaaaaa"],
    )
    .expect("seed widget");
    let deleted = lww_gated_delete(
        &conn,
        "widgets",
        &["id"],
        &["w1"],
        "0000000001000_0000_aaaaaaaaaaaaaaaa",
    )
    .expect("delete");
    assert_eq!(
        deleted, 0,
        "stale incoming must not clobber a newer local row"
    );
    assert_eq!(count_widgets(&conn, "w1"), 1);
}

#[test]
fn refuses_when_local_carries_tainted_letter_prefix() {
    // Regression: the legacy SQL `:version >= version` byte-compared,
    // so a tainted local 'v1' lex-sorts above any canonical HLC and
    // refused the incoming delete (conservative outcome — better to
    // leave the row than clobber it). The helper must preserve this
    // byte-compare fallback for unparseable local versions.
    let conn = fresh_conn();
    conn.execute(
        "INSERT INTO widgets (id, version) VALUES (?1, ?2)",
        params!["w1", "v1"],
    )
    .expect("seed widget");
    let deleted = lww_gated_delete(
        &conn,
        "widgets",
        &["id"],
        &["w1"],
        "0000000099999_0000_aaaaaaaaaaaaaaaa",
    )
    .expect("delete");
    assert_eq!(deleted, 0);
    assert_eq!(count_widgets(&conn, "w1"), 1);
}

#[test]
fn missing_row_is_a_noop() {
    let conn = fresh_conn();
    let deleted = lww_gated_delete(
        &conn,
        "widgets",
        &["id"],
        &["does-not-exist"],
        "0000000001000_0000_aaaaaaaaaaaaaaaa",
    )
    .expect("delete");
    assert_eq!(deleted, 0);
}

#[test]
fn supports_composite_pk() {
    let conn = fresh_conn();
    conn.execute(
        "INSERT INTO composites (a, b, version) VALUES (?1, ?2, ?3)",
        params!["task-1", "tag-1", "0000000001000_0000_aaaaaaaaaaaaaaaa"],
    )
    .expect("seed composite");

    // Stale incoming for the seeded row → refused.
    let stale = lww_gated_delete(
        &conn,
        "composites",
        &["a", "b"],
        &["task-1", "tag-1"],
        "0000000000500_0000_aaaaaaaaaaaaaaaa",
    )
    .expect("stale delete");
    assert_eq!(stale, 0);

    // Newer incoming for the seeded row → applied.
    let fresh = lww_gated_delete(
        &conn,
        "composites",
        &["a", "b"],
        &["task-1", "tag-1"],
        "0000000002000_0000_aaaaaaaaaaaaaaaa",
    )
    .expect("fresh delete");
    assert_eq!(fresh, 1);

    // Different PK pair than the seed → no row found, noop.
    let other = lww_gated_delete(
        &conn,
        "composites",
        &["a", "b"],
        &["task-1", "tag-other"],
        "0000000099999_0000_aaaaaaaaaaaaaaaa",
    )
    .expect("other delete");
    assert_eq!(other, 0);
}
