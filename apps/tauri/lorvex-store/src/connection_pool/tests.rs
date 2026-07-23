//! Tests for `connection_pool`. Extracted from the parent file
//! to keep the production module focused.

use super::*;
#[cfg(unix)]
use std::ffi::OsString;
#[cfg(unix)]
use std::os::unix::ffi::OsStringExt;
use std::sync::Barrier;
use std::time::{Duration, Instant};

/// Create a connection pool backed by a real file in a temp directory.
fn pool_in_tempdir(dir: &tempfile::TempDir, read_pool_size: usize) -> ConnectionPool {
    let db_path = dir.path().join("test.db");
    ConnectionPool::new(&db_path, read_pool_size).expect("failed to create pool")
}

// -- Test 1: Writer serialization -----------------------------------------

#[test]
fn writer_serializes_concurrent_operations() {
    let dir = tempfile::tempdir().expect("create tempdir for ConnectionPool test");
    let pool = Arc::new(pool_in_tempdir(&dir, 2));

    // Create a test table.
    {
        let conn = pool.writer();
        conn.execute_batch("CREATE TABLE test_serial (v INTEGER NOT NULL);")
            .unwrap();
    }

    // Spawn two threads that each insert a value through the writer.
    let barrier = Arc::new(Barrier::new(2));
    let mut handles = Vec::new();

    for i in 0..2 {
        let pool = Arc::clone(&pool);
        let barrier = Arc::clone(&barrier);
        handles.push(std::thread::spawn(move || {
            barrier.wait();
            let conn = pool.writer();
            conn.execute("INSERT INTO test_serial (v) VALUES (?1)", [i])
                .unwrap();
        }));
    }

    for h in handles {
        h.join().expect("test thread panicked");
    }

    // Both rows must exist.
    let read_conn = pool.read();
    let conn = read_conn.lock().expect("read pool mutex poisoned");
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM test_serial", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 2);

    // Verify both values are present.
    let mut stmt = conn
        .prepare("SELECT v FROM test_serial ORDER BY v")
        .unwrap();
    let vals: Vec<i64> = stmt
        .query_map([], |r| r.get(0))
        .unwrap()
        .filter_map(std::result::Result::ok)
        .collect();
    assert_eq!(vals, vec![0, 1]);
}

// -- Test 2: Read pool parallel execution ---------------------------------

#[test]
fn read_pool_serves_parallel_queries() {
    let dir = tempfile::tempdir().expect("create tempdir for ConnectionPool test");
    let pool = Arc::new(pool_in_tempdir(&dir, 4));

    // Seed some data.
    {
        let conn = pool.writer();
        conn.execute_batch(
            "CREATE TABLE test_read (v INTEGER);
             INSERT INTO test_read VALUES (1);
             INSERT INTO test_read VALUES (2);
             INSERT INTO test_read VALUES (3);",
        )
        .unwrap();
    }

    // Fire 4 reads in parallel. Each simulates work by computing a sum.
    let barrier = Arc::new(Barrier::new(4));
    let start = Instant::now();
    let mut handles = Vec::new();

    for _ in 0..4 {
        let pool = Arc::clone(&pool);
        let barrier = Arc::clone(&barrier);
        handles.push(std::thread::spawn(move || {
            barrier.wait();
            let read_conn = pool.read();
            let conn = read_conn.lock().expect("read pool mutex poisoned");
            let sum: i64 = conn
                .query_row("SELECT SUM(v) FROM test_read", [], |r| r.get(0))
                .unwrap();
            assert_eq!(sum, 6);
        }));
    }

    for h in handles {
        h.join().expect("test thread panicked");
    }

    // All 4 reads completed. With parallel execution and a barrier-synced
    // start, this should finish quickly. We assert a generous upper bound
    // just to confirm nothing serialized pathologically.
    let elapsed = start.elapsed();
    assert!(
        elapsed < Duration::from_secs(5),
        "parallel reads took too long: {elapsed:?}"
    );
}

// -- Test 3: Writer + reader concurrency ----------------------------------

#[test]
fn writes_and_reads_are_concurrent() {
    use std::sync::atomic::AtomicBool;

    let dir = tempfile::tempdir().expect("create tempdir for ConnectionPool test");
    let pool = Arc::new(pool_in_tempdir(&dir, 2));

    // Create table and seed initial data.
    {
        let conn = pool.writer();
        conn.execute_batch(
            "CREATE TABLE test_concurrent (id INTEGER PRIMARY KEY, v TEXT);
             INSERT INTO test_concurrent (id, v) VALUES (1, 'initial');",
        )
        .unwrap();
    }

    // Reader: read during the write.
    // We start a slow write and simultaneously issue a read.
    let write_started = Arc::new(AtomicBool::new(false));
    let write_started_clone = Arc::clone(&write_started);

    let pool_w = Arc::clone(&pool);
    let writer_handle = std::thread::spawn(move || {
        let conn = pool_w.writer();
        write_started_clone.store(true, Ordering::Release);
        // Insert many rows to simulate a longer write.
        for i in 2..=100 {
            conn.execute(
                "INSERT INTO test_concurrent (id, v) VALUES (?1, ?2)",
                rusqlite::params![i, format!("row-{i}")],
            )
            .unwrap();
        }
    });

    // Spin until the write has started.
    while !write_started.load(Ordering::Acquire) {
        std::thread::yield_now();
    }

    // Read should succeed even while the write is in progress (WAL mode).
    let read_conn = pool.read();
    let conn = read_conn.lock().expect("read pool mutex poisoned");
    let val: String = conn
        .query_row("SELECT v FROM test_concurrent WHERE id = 1", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(val, "initial");
    drop(conn);

    writer_handle.join().expect("test thread panicked");

    // After the write, the reader should see the new data.
    let read_conn = pool.read();
    let conn = read_conn.lock().expect("read pool mutex poisoned");
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM test_concurrent", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 100);
}

// -- Test 4: Repository functions work through pool read connections ------

#[test]
fn repository_read_through_pool() {
    let dir = tempfile::tempdir().expect("create tempdir for ConnectionPool test");
    let pool = pool_in_tempdir(&dir, 2);

    // The pool's writer connection has already run all migrations,
    // so the `tasks` table exists. Insert a task via the writer.
    {
        let conn = pool.writer();
        conn.execute(
            "INSERT INTO tasks (id, title, status, version, created_at, updated_at, defer_count)
             VALUES ('task-001', 'Buy groceries', 'open', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 0)",
            [],
        )
        .unwrap();
    }

    // Read it back through a pool read connection, using the same pattern
    // that repository functions use (accept &Connection, run a query).
    let read_conn = pool.read();
    let conn = read_conn.lock().expect("read pool mutex poisoned");

    // Simulate a repository-style function.
    fn get_task_title(conn: &Connection, task_id: &str) -> Result<String, rusqlite::Error> {
        conn.query_row("SELECT title FROM tasks WHERE id = ?1", [task_id], |r| {
            r.get(0)
        })
    }

    let title = get_task_title(&conn, "task-001").unwrap();
    assert_eq!(title, "Buy groceries");
}

// -- Test 5: Round-robin distribution -------------------------------------

#[test]
fn read_pool_round_robins() {
    let dir = tempfile::tempdir().expect("create tempdir for ConnectionPool test");
    let pool = pool_in_tempdir(&dir, 3);

    // Get 6 read connections — should cycle through indices 0, 1, 2, 0, 1, 2.
    let ptrs: Vec<usize> = (0..6)
        .map(|_| {
            let conn = pool.read();
            Arc::as_ptr(&conn) as usize
        })
        .collect();

    // First and fourth should be the same connection.
    assert_eq!(ptrs[0], ptrs[3]);
    // Second and fifth.
    assert_eq!(ptrs[1], ptrs[4]);
    // Third and sixth.
    assert_eq!(ptrs[2], ptrs[5]);
    // All three in the first cycle should be distinct.
    assert_ne!(ptrs[0], ptrs[1]);
    assert_ne!(ptrs[1], ptrs[2]);
    assert_ne!(ptrs[0], ptrs[2]);
}

// -- Test 6: Write returns values -----------------------------------------

#[test]
fn write_returns_result_from_writer() {
    let dir = tempfile::tempdir().expect("create tempdir for ConnectionPool test");
    let pool = pool_in_tempdir(&dir, 1);

    {
        let conn = pool.writer();
        conn.execute_batch("CREATE TABLE test_ret (v INTEGER);")
            .unwrap();
    }

    let inserted_id = {
        let conn = pool.writer();
        conn.execute("INSERT INTO test_ret (v) VALUES (7)", [])
            .unwrap();
        conn.last_insert_rowid()
    };

    assert!(inserted_id > 0);
}

// -- Test 7: Drop is clean ------------------------------------------------

#[test]
fn drop_is_clean() {
    let dir = tempfile::tempdir().expect("create tempdir for ConnectionPool test");
    let db_path = dir.path().join("drop_test.db");

    {
        let pool = ConnectionPool::new(&db_path, 2).unwrap();
        let conn = pool.writer();
        conn.execute_batch("CREATE TABLE test_drop (v INTEGER);")
            .unwrap();
        drop(conn);
        // pool is dropped here
    }

    // Re-open the database to verify the table persists (clean drop
    // means the writer connection was properly closed, flushing WAL).
    let conn = Connection::open(&db_path).unwrap();
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='test_drop'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 1);
}

#[test]
fn new_rejects_zero_read_pool_size_without_panicking() {
    let dir = tempfile::tempdir().expect("create tempdir for ConnectionPool test");
    let db_path = dir.path().join("test.db");

    let result = std::panic::catch_unwind(|| ConnectionPool::new(&db_path, 0));

    assert!(result.is_ok(), "ConnectionPool::new should not panic");
    let error = result
        .unwrap()
        .expect_err("zero read_pool_size should be rejected");
    assert!(
        error.to_string().contains("read_pool_size"),
        "unexpected error: {error}"
    );
}

#[cfg(unix)]
#[test]
fn new_accepts_non_utf8_db_path_without_panicking() {
    let dir = tempfile::tempdir().expect("create tempdir for ConnectionPool test");
    let file_name = OsString::from_vec(vec![0xFF, b'.', b'd', b'b']);
    let db_path = dir.path().join(file_name);

    let result = std::panic::catch_unwind(|| ConnectionPool::new(&db_path, 1));

    assert!(result.is_ok(), "ConnectionPool::new should not panic");
    let error = result
        .unwrap()
        .expect_err("non-UTF-8 database path should be rejected explicitly");
    assert!(
        error.to_string().contains("UTF-8"),
        "unexpected error: {error}"
    );
}

#[test]
fn writer_result_rejects_poisoned_writer_lock() {
    let dir = tempfile::tempdir().expect("create tempdir for ConnectionPool test");
    let pool = Arc::new(pool_in_tempdir(&dir, 1));
    let poisoned = Arc::clone(&pool);

    // bind the JoinHandle to a named variable
    // and assert the join surfaces the expected panic. The pre-fix
    // shape `let _ = thread::spawn(...).join()` discarded the
    // `Result<(), Box<dyn Any + Send>>` so a regression that
    // changed the panic payload — or accidentally returned `Ok`
    // from the closure — went unnoticed. We still expect the
    // panic (that's what poisons the mutex), but we now record
    // it explicitly.
    let handle = std::thread::spawn(move || {
        let _guard = poisoned.writer.lock().expect("read pool mutex poisoned");
        panic!("poison writer lock");
    });
    let join_outcome = handle.join();
    assert!(
        join_outcome.is_err(),
        "spawned thread must panic to poison the writer mutex"
    );

    let error = pool
        .writer_result()
        .expect_err("poisoned writer lock should return an error");
    assert!(
        matches!(
            error,
            PoolError::PoisonedLock {
                lock: "writer connection"
            }
        ),
        "unexpected error: {error}"
    );
}

#[test]
fn try_writer_result_returns_none_when_writer_is_busy() {
    let dir = tempfile::tempdir().expect("create tempdir for ConnectionPool test");
    let pool = pool_in_tempdir(&dir, 1);
    let _guard = pool.writer_result().expect("lock writer connection");

    let maybe_writer = pool
        .try_writer_result()
        .expect("try writer lock should not fail for a busy writer");

    assert!(
        maybe_writer.is_none(),
        "busy writer lock should be reported without blocking"
    );
}

#[test]
fn read_lock_result_rejects_poisoned_read_lock() {
    let dir = tempfile::tempdir().expect("create tempdir for ConnectionPool test");
    let pool = Arc::new(pool_in_tempdir(&dir, 1));
    let poisoned = Arc::clone(&pool);

    // bind the JoinHandle and assert the panic
    // surfaces in the join Result — see the writer-poison test for
    // the rationale.
    let handle = std::thread::spawn(move || {
        let _guard = poisoned.read_pool[0]
            .lock()
            .expect("read pool mutex poisoned");
        panic!("poison read lock");
    });
    let join_outcome = handle.join();
    assert!(
        join_outcome.is_err(),
        "spawned thread must panic to poison the read mutex"
    );

    let error = pool
        .read_lock_result()
        .expect_err("poisoned read lock should return an error");
    assert!(
        matches!(
            error,
            PoolError::PoisonedLock {
                lock: "read connection"
            }
        ),
        "unexpected error: {error}"
    );
}

mod incompatible_classification {
    use crate::connection_pool::PoolError;
    use crate::migration::MigrationError;

    #[test]
    fn schema_incompatibilities_are_recoverable() {
        let checksum = PoolError::Migration(MigrationError::ChecksumMismatch {
            version: 1,
            name: "schema".into(),
            expected: "aaaa".into(),
            actual: "bbbb".into(),
        });
        assert!(checksum.is_incompatible_database());

        let downgrade = PoolError::Migration(MigrationError::DowngradeDetected {
            binary_max_version: 1,
            db_max_version: 2,
        });
        assert!(downgrade.is_incompatible_database());

        let corrupt = PoolError::Migration(MigrationError::CorruptedSchema {
            version: 1,
            name: "schema".into(),
            missing_kind: "table",
            missing_object: "tasks".into(),
        });
        assert!(corrupt.is_incompatible_database());
    }

    #[test]
    fn not_a_database_and_corrupt_image_are_recoverable() {
        // Pass the raw SQLite primary result codes — rusqlite's `ErrorCode`
        // enum discriminants do not equal SQLite's numeric codes, so `Error::new`
        // takes the integer and derives the `ErrorCode` from it.
        for raw in [rusqlite::ffi::SQLITE_NOTADB, rusqlite::ffi::SQLITE_CORRUPT] {
            let err =
                rusqlite::Error::SqliteFailure(rusqlite::ffi::Error::new(raw), Some("boom".into()));
            assert!(
                PoolError::Sqlite(err).is_incompatible_database(),
                "raw code {raw} should be recoverable"
            );
        }
    }

    #[test]
    fn transient_and_build_side_errors_are_not_recoverable() {
        // Lock-checksum drift is a developer build error, never a user DB problem.
        let lock = PoolError::Migration(MigrationError::LockChecksumMismatch {
            version: 1,
            name: "schema".into(),
            expected: "aaaa".into(),
            actual: "bbbb".into(),
        });
        assert!(!lock.is_incompatible_database());

        // Transient/environmental SQLite codes must never discard the file.
        for raw in [
            rusqlite::ffi::SQLITE_BUSY,
            rusqlite::ffi::SQLITE_LOCKED,
            rusqlite::ffi::SQLITE_CANTOPEN,
            rusqlite::ffi::SQLITE_PERM,
            rusqlite::ffi::SQLITE_READONLY,
        ] {
            let err = rusqlite::Error::SqliteFailure(rusqlite::ffi::Error::new(raw), None);
            assert!(
                !PoolError::Sqlite(err).is_incompatible_database(),
                "raw code {raw} must be treated as transient"
            );
        }
    }
}
