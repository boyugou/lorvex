//! Tests for `transaction`. Extracted from the parent file
//! to keep the production module focused.

use super::savepoint::{assert_safe_savepoint_prefix, MAX_SAVEPOINT_PREFIX_LEN};
use super::*;
use rusqlite::Connection;
use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
struct TestError(String);

impl fmt::Display for TestError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<rusqlite::Error> for TestError {
    fn from(error: rusqlite::Error) -> Self {
        Self(error.to_string())
    }
}

impl From<String> for TestError {
    fn from(value: String) -> Self {
        Self(value)
    }
}

#[test]
fn commit_on_success() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER);").unwrap();

    with_immediate_transaction::<_, TestError>(&conn, |c| {
        c.execute("INSERT INTO t (v) VALUES (42)", [])?;
        Ok(())
    })
    .unwrap();

    let val: i64 = conn.query_row("SELECT v FROM t", [], |r| r.get(0)).unwrap();
    assert_eq!(val, 42);
}

#[test]
fn rollback_on_error() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER);").unwrap();

    let result: Result<(), TestError> = with_immediate_transaction(&conn, |c| {
        c.execute("INSERT INTO t (v) VALUES (99)", [])?;
        // Force an error.
        Err(TestError("boom".to_string()))
    });

    assert!(result.is_err());

    // The row should not exist because the transaction was rolled back.
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM t", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 0);
}

#[test]
fn panic_inside_transaction_rolls_back_and_connection_remains_usable() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER);").unwrap();

    // Run the closure inside catch_unwind so the test harness can
    // verify the panic was propagated faithfully (we rely on
    // resume_unwind preserving the original payload).
    let panic_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let _: Result<(), TestError> = with_immediate_transaction(&conn, |c| {
            c.execute("INSERT INTO t (v) VALUES (123)", [])
                .expect("insert ok");
            panic!("forced panic inside tx");
        });
    }));

    let payload = panic_result.expect_err("expected panic to propagate");
    let message = payload
        .downcast_ref::<&'static str>()
        .map(|s| (*s).to_string())
        .or_else(|| payload.downcast_ref::<String>().cloned())
        .unwrap_or_default();
    assert!(
        message.contains("forced panic inside tx"),
        "panic payload should round-trip, got: {message}"
    );

    // The row must have been rolled back.
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM t", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 0, "panicking closure must roll back inserts");

    // The connection must still be usable — no dangling transaction.
    with_immediate_transaction::<_, TestError>(&conn, |c| {
        c.execute("INSERT INTO t (v) VALUES (7)", [])?;
        Ok(())
    })
    .expect("subsequent transaction should succeed");
    let value: i64 = conn.query_row("SELECT v FROM t", [], |r| r.get(0)).unwrap();
    assert_eq!(value, 7);
}

#[test]
fn with_immediate_transaction_surfaces_rollback_failures() {
    let conn = Connection::open_in_memory().unwrap();

    let error = with_immediate_transaction::<_, TestError>(&conn, |c| {
        c.execute_batch("ROLLBACK;")
            .expect("rollback active transaction");
        Err::<(), TestError>(TestError("boom".to_string()))
    })
    .expect_err("rollback cleanup failure should surface");

    assert!(
        error.to_string().contains("boom"),
        "unexpected error: {error}"
    );
    assert!(
        error.to_string().contains("rollback failed"),
        "unexpected error: {error}"
    );
}

#[test]
fn panic_inside_with_savepoint_rolls_back_and_connection_remains_usable() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER);").unwrap();
    conn.execute_batch("BEGIN IMMEDIATE;").unwrap();

    let panic_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let _: Result<(), TestError> = with_savepoint(&conn, "panic_test", |c| {
            c.execute("INSERT INTO t (v) VALUES (123)", [])
                .expect("insert ok");
            panic!("forced panic inside savepoint");
        });
    }));

    let payload = panic_result.expect_err("expected panic to propagate");
    let message = payload
        .downcast_ref::<&'static str>()
        .map(|s| (*s).to_string())
        .or_else(|| payload.downcast_ref::<String>().cloned())
        .unwrap_or_default();
    assert!(
        message.contains("forced panic inside savepoint"),
        "panic payload should round-trip, got: {message}"
    );

    // The row must have been rolled back via the savepoint rollback.
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM t", [], |r| r.get(0))
        .unwrap();
    assert_eq!(
        count, 0,
        "panicking savepoint closure must roll back inserts"
    );

    // The connection must still be usable — another savepoint can open
    // and commit cleanly.
    with_savepoint::<_, TestError>(&conn, "after_panic", |c| {
        c.execute("INSERT INTO t (v) VALUES (7)", [])?;
        Ok(())
    })
    .expect("subsequent savepoint should succeed");
    conn.execute_batch("COMMIT;").unwrap();
    let value: i64 = conn.query_row("SELECT v FROM t", [], |r| r.get(0)).unwrap();
    assert_eq!(value, 7);
}

/// `assert_safe_savepoint_prefix` rejects empty /
/// all-non-alphanumeric prefixes so the generated savepoint name
/// never collapses to the same string for two distinct logical
/// contexts. Pre-fix all such prefixes silently produced
/// `lvx_sp__{counter}` and SQLite tolerated the double-underscore
/// — but every all-non-alphanumeric caller shared the same
/// namespace.
#[test]
fn assert_safe_savepoint_prefix_rejects_empty_and_all_non_alphanumeric() {
    for raw in ["", "   ", "@@@", "...", "----"] {
        let err = assert_safe_savepoint_prefix(raw)
            .expect_err("empty / non-alphanumeric prefix should error");
        assert!(
            err.contains("no valid identifier characters"),
            "input {raw:?}: unexpected error message: {err}"
        );
    }
}

#[test]
fn assert_safe_savepoint_prefix_rejects_over_long_inputs() {
    let too_long: String = "a".repeat(MAX_SAVEPOINT_PREFIX_LEN + 1);
    let err = assert_safe_savepoint_prefix(&too_long).expect_err("over-long prefix should error");
    assert!(
        err.contains(&format!("{MAX_SAVEPOINT_PREFIX_LEN}-char limit")),
        "unexpected error message: {err}"
    );
}

#[test]
fn assert_safe_savepoint_prefix_keeps_ascii_alphanumeric_and_underscore() {
    assert_eq!(
        assert_safe_savepoint_prefix("foo_bar123").unwrap(),
        "foo_bar123"
    );
    // Non-ASCII / Unicode chars are stripped so the prefix is
    // safely embedded in a SQL identifier without quoting.
    assert_eq!(assert_safe_savepoint_prefix("foo--bar").unwrap(), "foobar");
    assert_eq!(assert_safe_savepoint_prefix("a/b\\c").unwrap(), "abc");
}

#[test]
fn assert_safe_savepoint_prefix_accepts_exactly_max_length() {
    let at_limit: String = "a".repeat(MAX_SAVEPOINT_PREFIX_LEN);
    assert_eq!(
        assert_safe_savepoint_prefix(&at_limit).unwrap().len(),
        MAX_SAVEPOINT_PREFIX_LEN
    );
}

#[test]
fn with_savepoint_surfaces_cleanup_failures() {
    let conn = Connection::open_in_memory().unwrap();

    let error = with_savepoint::<_, TestError>(&conn, "cleanup", |c| {
        c.execute_batch("ROLLBACK;")
            .expect("rollback active savepoint transaction");
        Err::<(), TestError>(TestError("boom".to_string()))
    })
    .expect_err("savepoint cleanup failure should surface");

    assert!(
        error.to_string().contains("boom"),
        "unexpected error: {error}"
    );
    assert!(
        error.to_string().contains("rollback failed")
            || error.to_string().contains("release failed"),
        "unexpected error: {error}"
    );
}

#[test]
fn with_savepoint_mapped_surfaces_cleanup_failures() {
    let conn = Connection::open_in_memory().unwrap();

    let error = with_savepoint_mapped(
        &conn,
        "cleanup",
        |message| message,
        |c| {
            c.execute_batch("ROLLBACK;")
                .expect("rollback active savepoint transaction");
            Err::<(), String>("boom".to_string())
        },
    )
    .expect_err("mapped savepoint cleanup failure should surface");

    assert!(error.contains("boom"), "unexpected error: {error}");
    assert!(
        error.contains("rollback failed") || error.contains("release failed"),
        "unexpected error: {error}"
    );
}

// ── with_deferred_read_transaction ──────────────────────────────

/// Open a fresh file-backed connection in WAL mode. In-memory connections
/// cannot share snapshots between distinct `Connection` handles, so the
/// snapshot-isolation test needs a real file.
fn open_wal_conn(path: &std::path::Path) -> Connection {
    let conn = Connection::open(path).expect("open connection");
    conn.execute_batch(
        "PRAGMA journal_mode=WAL;\
         PRAGMA synchronous=NORMAL;\
         PRAGMA busy_timeout=5000;",
    )
    .expect("set pragmas");
    conn
}

#[test]
fn deferred_read_transaction_commits_cleanly() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER); INSERT INTO t (v) VALUES (1),(2),(3);")
        .unwrap();

    let value = with_deferred_read_transaction::<_, rusqlite::Error, _>(&conn, |c| {
        let sum: i64 = c.query_row("SELECT SUM(v) FROM t", [], |r| r.get(0))?;
        Ok(sum)
    })
    .expect("deferred read should succeed");

    assert_eq!(value, 6);

    // Connection is back in autocommit — next statement can open its own
    // transaction freely.
    assert!(conn.is_autocommit());
    conn.execute("INSERT INTO t (v) VALUES (4)", [])
        .expect("post-read write should succeed");
}

#[test]
fn deferred_read_transaction_rolls_back_on_error() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER);").unwrap();

    let result: rusqlite::Result<()> =
        with_deferred_read_transaction(&conn, |_c| Err(rusqlite::Error::InvalidQuery));

    assert!(matches!(result, Err(rusqlite::Error::InvalidQuery)));
    // Rollback must leave the connection in autocommit mode.
    assert!(conn.is_autocommit());
}

#[test]
fn deferred_read_transaction_sees_snapshot_isolation() {
    // Open two file-backed WAL connections sharing the same database.
    let dir = tempfile::tempdir().expect("create tempdir");
    let db_path = dir.path().join("snapshot.sqlite");

    let reader = open_wal_conn(&db_path);
    let writer = open_wal_conn(&db_path);

    // Seed: one row visible to both connections.
    writer
        .execute_batch("CREATE TABLE t (v INTEGER); INSERT INTO t (v) VALUES (1);")
        .unwrap();

    let observed_inside_tx =
        with_deferred_read_transaction::<_, rusqlite::Error, _>(&reader, |c| {
            // Prime the reader's snapshot with an initial SELECT; BEGIN
            // DEFERRED itself doesn't take the shared lock until the first
            // read statement runs.
            let initial: i64 = c.query_row("SELECT COUNT(*) FROM t", [], |r| r.get(0))?;
            assert_eq!(initial, 1);

            // Concurrent writer commits while the reader's transaction is
            // still open. On a bare (non-transactional) reader this would
            // bump the observed count to 2 on the next SELECT.
            writer
                .execute("INSERT INTO t (v) VALUES (2)", [])
                .expect("writer insert");

            let after_writer: i64 = c.query_row("SELECT COUNT(*) FROM t", [], |r| r.get(0))?;
            Ok(after_writer)
        })
        .expect("deferred read should succeed");

    // Snapshot pinning: the reader still sees the pre-writer count.
    assert_eq!(
        observed_inside_tx, 1,
        "BEGIN DEFERRED must pin the WAL snapshot across statements"
    );

    // Outside the transaction, the writer's row is visible.
    let after_commit: i64 = reader
        .query_row("SELECT COUNT(*) FROM t", [], |r| r.get(0))
        .unwrap();
    assert_eq!(after_commit, 2);
}

#[test]
fn deferred_read_transaction_nests_without_reopening() {
    // Composite handlers (e.g. get_session_context → get_overview_compact)
    // wrap at both layers; the inner call must reuse the outer snapshot
    // instead of attempting a nested BEGIN (which SQLite rejects).
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER); INSERT INTO t (v) VALUES (1);")
        .unwrap();

    with_deferred_read_transaction(&conn, |outer| {
        assert!(!outer.is_autocommit(), "outer transaction should be active");

        // Inner call — no error, runs directly on the existing snapshot.
        let inner_value =
            with_deferred_read_transaction::<_, rusqlite::Error, _>(outer, |inner| {
                let v: i64 = inner.query_row("SELECT v FROM t", [], |r| r.get(0))?;
                Ok(v)
            })?;
        assert_eq!(inner_value, 1);

        // After the inner call returns, the outer transaction is still
        // active — the inner helper must not have issued COMMIT/ROLLBACK.
        assert!(
            !outer.is_autocommit(),
            "inner helper must not commit the outer transaction"
        );

        Ok::<_, rusqlite::Error>(())
    })
    .expect("nested deferred read should succeed");

    assert!(conn.is_autocommit());
}

#[test]
fn deferred_read_transaction_rolls_back_on_panic() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER);").unwrap();

    let panic_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let _: rusqlite::Result<()> =
            with_deferred_read_transaction(&conn, |_c| panic!("forced panic in read"));
    }));

    let payload = panic_result.expect_err("expected panic to propagate");
    let message = payload
        .downcast_ref::<&'static str>()
        .map(|s| (*s).to_string())
        .or_else(|| payload.downcast_ref::<String>().cloned())
        .unwrap_or_default();
    assert!(
        message.contains("forced panic in read"),
        "panic payload should round-trip, got: {message}"
    );

    // Connection must be usable afterwards — no dangling BEGIN.
    assert!(conn.is_autocommit());
    with_deferred_read_transaction::<_, rusqlite::Error, _>(&conn, |c| {
        c.execute("INSERT INTO t (v) VALUES (42)", [])?;
        Ok(())
    })
    .expect("connection should still be usable");
    let v: i64 = conn.query_row("SELECT v FROM t", [], |r| r.get(0)).unwrap();
    assert_eq!(v, 42);
}

// Nested-savepoint discipline tests. Production paths nest
// `with_savepoint` calls inside an outer `with_immediate_transaction`
// and inside outer savepoints (e.g. recurrence merge wraps further
// inner work). The existing `panic_inside_with_savepoint_*` test
// only exercises one level — these lock down the contract for the
// nested case so a future change to the SAVEPOINT counter or the
// rollback discipline can't silently regress.

#[test]
fn nested_savepoint_inner_panic_outer_remains_usable() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER);").unwrap();
    conn.execute_batch("BEGIN IMMEDIATE;").unwrap();

    let outer_result: Result<(), TestError> = with_savepoint(&conn, "outer", |c| {
        c.execute("INSERT INTO t (v) VALUES (1)", [])
            .expect("outer insert ok");
        let inner_panic = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _: Result<(), TestError> = with_savepoint(c, "inner", |inner| {
                inner
                    .execute("INSERT INTO t (v) VALUES (2)", [])
                    .expect("inner insert ok");
                panic!("inner panic");
            });
        }));
        assert!(inner_panic.is_err(), "inner savepoint should have panicked");
        // The inner panic rolled back the inner savepoint; the row
        // it inserted must be gone, but the outer's row is still
        // pending and the outer savepoint frame is still healthy.
        let count: i64 = c
            .query_row("SELECT COUNT(*) FROM t WHERE v = 2", [], |r| r.get(0))
            .expect("count v=2");
        assert_eq!(count, 0, "inner panic must roll back the inner insert");
        // Continue using the outer savepoint normally.
        c.execute("INSERT INTO t (v) VALUES (3)", [])
            .expect("post-inner insert ok");
        Ok(())
    });
    outer_result.expect("outer savepoint should commit cleanly");
    conn.execute_batch("COMMIT;").unwrap();

    let mut stmt = conn
        .prepare("SELECT v FROM t ORDER BY v ASC")
        .expect("prepare");
    let values: Vec<i64> = stmt
        .query_map([], |r| r.get::<_, i64>(0))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    assert_eq!(values, vec![1, 3], "v=2 (inner panic) must not survive");
}

#[test]
fn nested_savepoint_inner_err_outer_commits() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER);").unwrap();
    conn.execute_batch("BEGIN IMMEDIATE;").unwrap();

    let outer_result: Result<(), TestError> = with_savepoint(&conn, "outer", |c| {
        c.execute("INSERT INTO t (v) VALUES (10)", [])
            .expect("outer insert ok");
        // Inner returns an Err — savepoint rolls back its insert,
        // outer still has a healthy frame.
        let inner_result: Result<(), TestError> = with_savepoint(c, "inner", |inner| {
            inner
                .execute("INSERT INTO t (v) VALUES (20)", [])
                .expect("inner insert ok");
            Err(TestError("inner explicit fail".to_string()))
        });
        assert!(inner_result.is_err());
        let count: i64 = c
            .query_row("SELECT COUNT(*) FROM t WHERE v = 20", [], |r| r.get(0))
            .expect("count v=20");
        assert_eq!(count, 0, "inner Err must roll back the inner insert");
        c.execute("INSERT INTO t (v) VALUES (30)", [])
            .expect("post-inner insert ok");
        Ok(())
    });
    outer_result.expect("outer savepoint should commit cleanly");
    conn.execute_batch("COMMIT;").unwrap();

    let mut stmt = conn
        .prepare("SELECT v FROM t ORDER BY v ASC")
        .expect("prepare");
    let values: Vec<i64> = stmt
        .query_map([], |r| r.get::<_, i64>(0))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    assert_eq!(values, vec![10, 30], "v=20 (inner Err) must not survive");
}

#[test]
fn sibling_savepoints_inside_one_outer_get_unique_names() {
    // Pin the SAVEPOINT_COUNTER discipline: two siblings inside one
    // outer must get distinct names. Otherwise the second SAVEPOINT
    // statement would collide and either fail or worse, the RELEASE
    // of the first would tear down both frames.
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER);").unwrap();
    conn.execute_batch("BEGIN IMMEDIATE;").unwrap();

    let outer_result: Result<(), TestError> = with_savepoint(&conn, "outer", |c| {
        let a: Result<(), TestError> = with_savepoint(c, "sib", |inner| {
            inner.execute("INSERT INTO t (v) VALUES (100)", [])?;
            Ok(())
        });
        a.expect("sibling A should commit cleanly");
        let b: Result<(), TestError> = with_savepoint(c, "sib", |inner| {
            inner.execute("INSERT INTO t (v) VALUES (200)", [])?;
            Ok(())
        });
        b.expect("sibling B should commit cleanly");
        Ok(())
    });
    outer_result.expect("outer savepoint should commit cleanly");
    conn.execute_batch("COMMIT;").unwrap();

    let mut stmt = conn
        .prepare("SELECT v FROM t ORDER BY v ASC")
        .expect("prepare");
    let values: Vec<i64> = stmt
        .query_map([], |r| r.get::<_, i64>(0))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    assert_eq!(values, vec![100, 200]);
}

// ── with_savepoint_then_rollback ───────────────────────────────────
//
// The dry-run helper has different semantics from `with_savepoint`:
// it ALWAYS rolls back the savepoint, regardless of whether the
// closure returned `Ok` or `Err`. The closure's `Ok` value flows
// back to the caller after the rollback completes. These tests pin
// the contract.

#[test]
fn with_savepoint_then_rollback_propagates_ok_value_after_rolling_back_writes() {
    // Closure inserts a row and returns Ok(value). The helper must
    // (a) roll back the insert (no row in the table after) and
    // (b) propagate the closure's value to the caller.
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER);").unwrap();
    conn.execute_batch("BEGIN IMMEDIATE;").unwrap();

    let result: Result<i64, TestError> = with_savepoint_then_rollback(&conn, "dry_run", |c| {
        c.execute("INSERT INTO t (v) VALUES (?)", rusqlite::params![42])?;
        Ok(42)
    });
    assert_eq!(result.expect("Ok value should propagate"), 42);

    // The savepoint rolled back, so the BEGIN IMMEDIATE outer
    // transaction should still see zero rows.
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM t", [], |row| row.get(0))
        .unwrap();
    assert_eq!(
        count, 0,
        "with_savepoint_then_rollback must roll back closure writes",
    );
    conn.execute_batch("COMMIT;").unwrap();
}

#[test]
fn with_savepoint_then_rollback_returns_closure_err_unchanged() {
    // Closure returns Err. The original error wins; the rollback
    // still runs (no dangling savepoint frame). The connection
    // stays usable for further writes after the helper returns.
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER);").unwrap();
    conn.execute_batch("BEGIN IMMEDIATE;").unwrap();

    let result: Result<(), TestError> = with_savepoint_then_rollback(&conn, "dry_run", |c| {
        c.execute("INSERT INTO t (v) VALUES (?)", rusqlite::params![7])?;
        Err(TestError("closure decided to fail".to_string()))
    });
    let err = result.expect_err("Err should propagate");
    assert_eq!(err.0, "closure decided to fail");

    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM t", [], |row| row.get(0))
        .unwrap();
    assert_eq!(count, 0, "Err path must also roll back");

    // Connection is usable for further writes — no dangling savepoint.
    conn.execute("INSERT INTO t (v) VALUES (?)", rusqlite::params![99])
        .expect("post-rollback writer must work");
    conn.execute_batch("COMMIT;").unwrap();
}

#[test]
#[should_panic(expected = "intentional dry-run panic")]
fn with_savepoint_then_rollback_rolls_back_on_panic_then_resumes_unwind() {
    // A panic inside the closure must roll back the savepoint
    // BEFORE the unwind resumes. Without this, the connection would
    // retain a dangling savepoint frame and the next writer would
    // fail with "no such savepoint" — exactly the bug class the
    // sibling `with_savepoint`'s panic-safety test pins for the
    // success-path helper.
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("CREATE TABLE t (v INTEGER);").unwrap();
    conn.execute_batch("BEGIN IMMEDIATE;").unwrap();

    let _: Result<(), TestError> = with_savepoint_then_rollback(&conn, "dry_run", |_c| {
        panic!("intentional dry-run panic");
    });
}
