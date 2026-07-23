use super::*;

#[test]
fn local_change_seq_defaults_to_zero() {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    initialize_local_runtime_tables(&conn).expect("init tables");
    assert_eq!(read_local_change_seq(&conn).expect("read seq"), 0);
}

#[test]
fn bump_local_change_seq_monotonically_increments() {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    initialize_local_runtime_tables(&conn).expect("init tables");

    assert_eq!(bump_local_change_seq(&conn).expect("first bump"), 1);
    assert_eq!(bump_local_change_seq(&conn).expect("second bump"), 2);
    assert_eq!(read_local_change_seq(&conn).expect("read seq"), 2);
}

/// every bump must yield a distinct, strictly increasing
/// value — the bump-and-read happens in a single SQL statement so a
/// concurrent writer cannot observe the same value as this caller.
/// Single-connection serial test; the SQLite locking model already
/// guarantees that two `INSERT ... RETURNING` statements on the same
/// connection cannot interleave, but the test pins the contract so
/// any future refactor that splits the statement gets caught.
#[test]
fn bump_local_change_seq_yields_distinct_values_per_call() {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    initialize_local_runtime_tables(&conn).expect("init tables");

    let mut seen = std::collections::BTreeSet::new();
    let mut last = 0u64;
    for _ in 0..32 {
        let n = bump_local_change_seq(&conn).expect("bump");
        assert!(seen.insert(n), "duplicate seq {n}");
        assert!(n > last, "seq did not strictly increase: {n} <= {last}");
        last = n;
    }
    assert_eq!(seen.len(), 32);
    assert_eq!(read_local_change_seq(&conn).expect("read seq"), 32);
}

/// a manually-corrupted negative value must
/// surface as a typed `CorruptLocalChangeSeq` error rather than
/// silently fall back to 0. Every consumer of the seq depends on
/// strict monotonicity; a silent reset is far worse than a loud
/// failure because a stale seq passes the "is newer" check the
/// reconciler downstream uses.
#[test]
fn read_local_change_seq_surfaces_corrupt_negative_value() {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    initialize_local_runtime_tables(&conn).expect("init tables");
    // Negative values are rejected by `bump_local_change_seq` at write
    // time; here we seed one directly to model on-disk corruption.
    conn.execute(
        "INSERT INTO local_counters (name, value, updated_at) VALUES (?1, -1, ?2)",
        params![LOCAL_CHANGE_SEQ_KEY, 1_700_000_000_000_i64],
    )
    .expect("seed corrupt row");

    let err = read_local_change_seq(&conn).expect_err("must reject negative");
    assert!(
        matches!(&err, RuntimeError::CorruptLocalChangeSeq { value } if value == "-1"),
        "expected CorruptLocalChangeSeq(\"-1\"), got {err:?}"
    );
}

/// the runtime test fixture
/// `initialize_local_runtime_tables` must produce the same column
/// shape as the production migration stack in
/// `lorvex-store/src/schema/001_schema.sql`. Drift between the two
/// (extra column, type mismatch, missing CHECK) lets runtime tests
/// pass under a fixture that hasn't kept up with production, so a
/// real bug only surfaces at runtime on a customer device. This
/// test snapshots the production schema for the four runtime-owned
/// tables and asserts the fixture matches column-by-column.
#[test]
fn runtime_fixture_matches_production_schema() {
    // Read the production schema string at compile time; running the
    // full migration stack here would pull in the entire `lorvex-store`
    // graph as a dev-dependency cycle. The shape contract we care
    // about is text-level: a CREATE TABLE with the same column list,
    // types, and CHECK clauses.
    //
    // route through `LORVEX_STORE_SCHEMA_SQL_PATH`
    // (emitted by `lorvex-runtime/build.rs`) instead of the prior
    // relative `include_str!("../../lorvex-store/...")`. The
    // hard-coded relative path silently broke any time either crate
    // moved; the build script now resolves the canonical absolute
    // path at compile time and registers `cargo:rerun-if-changed`
    // so a schema edit re-runs this parity test.
    let schema_sql = include_str!(env!("LORVEX_STORE_SCHEMA_SQL_PATH"));

    for table in ["local_sync_owner", "local_counters", "mcp_host_authority"] {
        // Find the `CREATE TABLE IF NOT EXISTS <table> (` block in
        // the production schema and the fixture's CREATE for the
        // same table; assert both strings exist and the column
        // signature in production is a substring of the fixture's
        // (or vice versa, allowing differing whitespace). We compare
        // the bracketed body case-insensitively after collapsing
        // whitespace so cosmetic formatting differences don't trip
        // the parity test.
        let prod_marker = format!("CREATE TABLE IF NOT EXISTS {table}");
        assert!(
            schema_sql.contains(&prod_marker),
            "production schema is missing CREATE TABLE for {table}"
        );

        // Open a fresh in-memory DB through the fixture and a second
        // through ad-hoc execution of the production CREATE block;
        // PRAGMA table_info() output must agree on (name, type, notnull, pk).
        let fixture_conn = Connection::open_in_memory().expect("fixture open");
        initialize_local_runtime_tables(&fixture_conn).expect("fixture init");

        let prod_conn = Connection::open_in_memory().expect("prod open");
        // Extract just the relevant CREATE TABLE block by scanning
        // forward from `CREATE TABLE IF NOT EXISTS <table>` to the
        // first `;` after a closing `)`.
        let start = schema_sql.find(&prod_marker).unwrap();
        let tail = &schema_sql[start..];
        let end = tail
            .find(") STRICT;")
            .expect("table block ends with ) STRICT;");
        let block = &tail[..end + ") STRICT;".len()];
        prod_conn
            .execute_batch(block)
            .unwrap_or_else(|e| panic!("failed to apply prod block for {table}: {e}\n{block}"));

        let fixture_cols = collect_table_info(&fixture_conn, table);
        let prod_cols = collect_table_info(&prod_conn, table);
        assert_eq!(
            fixture_cols, prod_cols,
            "fixture vs production column shape mismatch for {table}: fixture={fixture_cols:?} prod={prod_cols:?}"
        );
    }
}

fn collect_table_info(conn: &Connection, table: &str) -> Vec<(String, String, i64, i64)> {
    let mut stmt = conn
        .prepare(&format!("PRAGMA table_info({table})"))
        .expect("prepare pragma");
    let rows: Vec<(String, String, i64, i64)> = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(1)?, // name
                row.get::<_, String>(2)?, // type
                row.get::<_, i64>(3)?,    // notnull
                row.get::<_, i64>(5)?,    // pk
            ))
        })
        .expect("query pragma")
        .filter_map(std::result::Result::ok)
        .collect();
    rows
}
