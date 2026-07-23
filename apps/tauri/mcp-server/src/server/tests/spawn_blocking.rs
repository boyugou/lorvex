//! Integration tests for #2177: async DB wrappers must route
//! rusqlite I/O through the tokio blocking pool so a long handler
//! can't starve the runtime.
//!
//! The harness uses `#[tokio::test(flavor = "multi_thread",
//! worker_threads = 1)]` — a *single* worker thread is the worst
//! case. Before the fix, a synchronous `with_read_conn` on the sole
//! worker monopolized it end-to-end; a concurrent future couldn't
//! make any progress until the blocking call returned. With
//! `with_read_conn_async`, rusqlite lives on the blocking pool and
//! the lone worker keeps servicing other futures.
//!
//! The test enqueues one "slow" handler that sleeps ~500 ms
//! synchronously inside the closure (simulating a long FTS5 query),
//! then races it against a "fast" handler that touches the database
//! immediately. The fast handler MUST finish well before the slow
//! one — proving the reactor wasn't blocked.

use super::make_server;
use std::time::{Duration, Instant};

/// fast-handler budget for the spawn_blocking race
/// test. The previous 100 ms ceiling vs. a 200 ms slow sleep left
/// only 100 ms of cushion, which under sanitizer / coverage / a busy
/// CI agent regularly tipped over and produced spurious failures
/// even though the reactor wasn't actually blocked. Widening the
/// fast budget to 300 ms vs. a 600 ms slow sleep preserves the 2×
/// headroom that proves spawn_blocking is doing its job, while
/// absorbing instrumentation-induced jitter we genuinely don't care
/// about. The regression we're guarding against is order-of-magnitude
/// (a fully-blocked reactor would wait the full 600 ms), so this
/// margin remains diagnostic.
const FAST_BUDGET: Duration = Duration::from_millis(300);

/// Sleep inside the rusqlite closure to model an uninterruptible
/// long-running read. Bumped in lockstep with `FAST_BUDGET` so the
/// 2× headroom invariant holds.
const SLOW_SLEEP: Duration = Duration::from_millis(600);

#[tokio::test(flavor = "multi_thread", worker_threads = 1)]
async fn with_read_conn_async_does_not_block_parallel_requests() {
    let server = make_server();
    let s1 = server.server.clone();
    let s2 = server.server.clone();

    // Kick off the slow handler first. It grabs a read connection
    // and sleeps inside the rusqlite closure — which is exactly the
    // shape of the runtime-stall hotspots (analyze_task_patterns,
    // weekly review).
    let slow = tokio::spawn(async move {
        s1.with_read_conn_async(|_conn| {
            std::thread::sleep(SLOW_SLEEP);
            Ok::<_, String>(())
        })
        .await
    });

    // Small nudge so the slow task reaches the blocking call before
    // the fast one starts — otherwise scheduling jitter could mask
    // the regression by letting the fast task finish first anyway.
    tokio::time::sleep(Duration::from_millis(20)).await;

    let started = Instant::now();
    let fast = s2
        .with_read_conn_async(|_conn| Ok::<_, String>(42_i64))
        .await
        .expect("fast handler succeeds");
    let elapsed = started.elapsed();

    assert_eq!(fast, 42);
    assert!(
        elapsed < FAST_BUDGET,
        "fast handler finished in {elapsed:?}, expected under {FAST_BUDGET:?} — \
         spawn_blocking is not covering the blocking closure"
    );

    slow.await
        .expect("slow task join")
        .expect("slow handler succeeds");
}

/// Writer pool has a single slot, so a blocking closure inside
/// `with_conn` serializes subsequent writes — that's expected
/// behavior. But a concurrent *read* must still proceed without
/// waiting for the writer closure to return. This is the scenario
/// that previously stalled the watchdog + stdio future.
#[tokio::test(flavor = "multi_thread", worker_threads = 1)]
async fn with_conn_async_writer_does_not_block_concurrent_reads() {
    let server = make_server();
    let s1 = server.server.clone();
    let s2 = server.server.clone();

    let writer = tokio::spawn(async move {
        s1.with_conn_async(|_conn| {
            std::thread::sleep(SLOW_SLEEP);
            Ok::<_, String>(())
        })
        .await
    });

    tokio::time::sleep(Duration::from_millis(20)).await;

    let started = Instant::now();
    let reader = s2
        .with_read_conn_async(|_conn| Ok::<_, String>("ok".to_string()))
        .await
        .expect("reader handler succeeds");
    let elapsed = started.elapsed();

    assert_eq!(reader, "ok");
    assert!(
        elapsed < FAST_BUDGET,
        "concurrent read finished in {elapsed:?}, expected under {FAST_BUDGET:?} — \
         writer starved the tokio worker"
    );

    writer
        .await
        .expect("writer task join")
        .expect("writer handler succeeds");
}

/// Shutdown drain must account for blocking-pool work even after
/// the async caller that spawned it is dropped. This mirrors the
/// rmcp cancellation path: the service task can stop waiting for a
/// response while an already-started `spawn_blocking` SQLite closure
/// is still running.
#[tokio::test(flavor = "multi_thread", worker_threads = 1)]
async fn in_flight_tracker_covers_blocking_work_after_async_waiter_is_dropped() {
    let server = make_server();
    let tracker = server.in_flight_tracker();
    let s1 = server.server.clone();

    let (started_tx, started_rx) = std::sync::mpsc::sync_channel(1);
    let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);

    let waiter = tokio::spawn(async move {
        s1.with_read_conn_async(move |_conn| {
            started_tx.send(()).expect("signal blocking work start");
            release_rx.recv().expect("wait for release signal");
            Ok::<_, String>(())
        })
        .await
    });

    started_rx
        .recv_timeout(Duration::from_secs(1))
        .expect("blocking closure should start");
    waiter.abort();

    let idle = tokio::spawn(tracker.clone().wait_for_idle());
    tokio::task::yield_now().await;
    assert!(
        !idle.is_finished(),
        "in-flight tracker must remain active while detached blocking work runs"
    );

    release_tx.send(()).expect("release blocking closure");
    idle.await
        .expect("in-flight tracker should become idle after blocking work exits");

    let join = waiter
        .await
        .expect_err("aborted waiter should not complete");
    assert!(join.is_cancelled());
}

#[test]
#[serial_test::serial(hlc)]
fn in_flight_tracker_covers_queued_blocking_work_before_closure_starts() {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(1)
        .max_blocking_threads(1)
        .enable_time()
        .build()
        .expect("build constrained runtime");

    runtime.block_on(async {
        let server = make_server();
        let tracker = server.in_flight_tracker();
        let s1 = server.server.clone();

        let (blocker_started_tx, blocker_started_rx) = std::sync::mpsc::sync_channel(1);
        let (blocker_release_tx, blocker_release_rx) = std::sync::mpsc::sync_channel(1);
        let blocker = tokio::task::spawn_blocking(move || {
            blocker_started_tx.send(()).expect("signal blocker start");
            blocker_release_rx.recv().expect("wait for blocker release");
        });
        blocker_started_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("blocking pool should be saturated");

        let (queued_started_tx, queued_started_rx) = std::sync::mpsc::sync_channel(1);
        let waiter = tokio::spawn(async move {
            s1.with_read_conn_async(move |_conn| {
                queued_started_tx
                    .send(())
                    .expect("signal queued closure start");
                Ok::<_, String>(())
            })
            .await
        });

        tokio::time::timeout(Duration::from_secs(1), async {
            while tracker.active_count() == 0 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .expect("queued blocking call should acquire in-flight guard before it can start");

        let idle = tokio::spawn(tracker.clone().wait_for_idle());
        tokio::task::yield_now().await;
        assert!(
            !idle.is_finished(),
            "queued blocking work must keep the in-flight tracker active before the closure starts"
        );

        waiter.abort();
        blocker_release_tx.send(()).expect("release blocker");
        queued_started_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("queued closure should still run after async waiter abort");

        idle.await
            .expect("in-flight tracker should become idle after queued work exits");
        blocker.await.expect("blocker task should finish");

        let join = waiter
            .await
            .expect_err("aborted waiter should not complete");
        assert!(join.is_cancelled());
    });
}

/// Regression for #3302: a watchdog timeout firing while a
/// `with_conn_async` write is still on the blocking thread MUST cause
/// that write's transaction to ROLLBACK rather than COMMIT, so a
/// client retry under the same idempotency key cannot observe the
/// orphaned writes from the cancelled invocation.
///
/// Pre-fix the blocking thread held the writer mutex through `BEGIN
/// IMMEDIATE` → user closure → `COMMIT;` with no cancellation
/// checkpoint. After `tokio::time::timeout` dropped the awaited
/// future, the blocking thread plowed on and committed; a retry
/// arriving before that commit landed re-executed the user closure
/// and produced duplicate rows.
///
/// Post-fix `run_with_timeout` publishes a `CancellationToken` in the
/// `WATCHDOG_TOKEN` task-local; `with_conn_async` snapshots it before
/// `spawn_blocking`; `with_conn_cancellable` re-checks it after the
/// user closure succeeds and routes a cancelled run to `ROLLBACK;`.
/// The retry then has nothing committed to collide with.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn watchdog_cancellation_rolls_back_in_flight_commit() {
    use crate::runtime::tool_timeout::run_with_timeout;
    use rmcp::model::{CallToolResult, Content};

    let server = make_server();

    // Seed a scratch table that is trivial to insert into and easy
    // to count — bypassing the full domain stack keeps the test
    // focused on the transaction-frame behaviour rather than any
    // particular tool's contract.
    server
        .with_writer_no_savepoint(|conn| {
            conn.execute_batch(
                "CREATE TABLE watchdog_probe (id INTEGER PRIMARY KEY AUTOINCREMENT);",
            )
            .map_err(|e| e.to_string())
        })
        .expect("seed scratch table");

    let count_rows = || {
        server
            .with_read_conn(|conn| {
                conn.query_row("SELECT COUNT(*) FROM watchdog_probe;", [], |r| {
                    r.get::<_, i64>(0)
                })
                .map_err(|e| e.to_string())
            })
            .expect("count probe rows")
    };

    // The handler future kicks off a long blocking write — long
    // enough that the 100 ms watchdog will fire well before the
    // user closure returns. The closure inserts a row, then sleeps,
    // then returns Ok — pre-fix that path commits the row even
    // though the watchdog already replied to the client.
    let s1 = server.server.clone();
    let handler = async move {
        let _ = s1
            .with_conn_async(|conn| {
                conn.execute("INSERT INTO watchdog_probe DEFAULT VALUES;", [])
                    .map_err(|e| e.to_string())?;
                std::thread::sleep(Duration::from_millis(400));
                Ok::<_, String>(())
            })
            .await;
        Ok::<_, rmcp::ErrorData>(CallToolResult::success(vec![Content::text("done")]))
    };

    let watchdog_err = run_with_timeout("watchdog_probe_tool", Duration::from_millis(100), handler)
        .await
        .expect_err("watchdog must trip on the slow write");
    assert!(
        watchdog_err.message.contains("watchdog timeout"),
        "expected watchdog timeout error, got: {}",
        watchdog_err.message
    );

    // Wait for the still-running blocking thread to finish.
    // `with_conn_async` doesn't expose a JoinHandle to the caller,
    // so poll the in-flight tracker until it drains. With the fix
    // the closure returns Ok, the cancellable wrapper observes the
    // cancelled token, and the transaction is rolled back; the
    // probe table stays empty.
    let tracker = server.in_flight_tracker();
    tokio::time::timeout(Duration::from_secs(2), tracker.wait_for_idle())
        .await
        .expect("in-flight blocking work should drain after watchdog cancellation");

    assert_eq!(
        count_rows(),
        0,
        "watchdog cancellation must roll back the in-flight transaction; \
         seeing a committed row means a client retry under the same \
         idempotency key would land a duplicate write"
    );
}
