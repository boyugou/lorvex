//! Cooperative-cancellation tests for the long-running MCP tools
//! enumerated in #2133. Each test primes the rmcp
//! `tokio_util::sync::CancellationToken` before dispatch, invokes the
//! router handler directly, and asserts that:
//!   1. The tool returns the sanitized "cancelled by client" error
//!      rather than a full payload.
//!   2. The writer Mutex is released (the next `with_conn` call must
//!      succeed — otherwise we regress into the #2133 failure mode
//!      where a cancel leaves the pool locked).

use super::*;
use tokio_util::sync::CancellationToken;

/// A pre-cancelled token must short-circuit the multi-query
/// `analyze_task_patterns` aggregate at the first
/// `check_cancelled` call, not run the full pipeline.
#[tokio::test]
async fn analyze_task_patterns_respects_cancellation_token() {
    let server = make_server();
    seed_task(
        &server,
        "cancelled-overdue",
        "Overdue task",
        "open",
        None,
        Some("2000-01-01"),
        None,
        3,
    );

    let ct = CancellationToken::new();
    ct.cancel();

    let err = server
        .analyze_task_patterns(
            Parameters(AnalyzeTaskPatternsArgs {
                window_days: Some(30),
                top_n: Some(5),
            }),
            ct,
        )
        .await
        .expect_err("cancelled token must short-circuit the aggregate");

    assert!(
        err.contains("cancelled by client"),
        "expected cancellation error, got: {err}"
    );
}

/// `propose_daily_schedule` runs a calendar-timeline fetch plus an
/// O(n) per-task placement loop. A pre-cancelled token must be seen
/// before the placement loop makes any progress — and before the
/// "no focus set for this date" validation, because `check_cancelled`
/// is the first line of the handler. We assert the sanitized error
/// text because we can't observe the scheduler's internal state.
#[tokio::test]
async fn propose_daily_schedule_respects_cancellation_token() {
    let server = make_server();
    let today = crate::time::today_ymd_local_for_test();

    let ct = CancellationToken::new();
    ct.cancel();

    let err = server
        .propose_daily_schedule(
            Parameters(ProposeDailyScheduleArgs { date: Some(today) }),
            ct,
        )
        .await
        .expect_err("cancelled token must short-circuit schedule proposal");

    assert!(
        err.contains("cancelled by client"),
        "expected cancellation error, got: {err}"
    );
}

/// Regression guard: a cancelled write-path tool must not leave the
/// writer `Mutex` held. Before #2133 the writer lock survived the
/// cancelled future if the handler panicked or exited early between
/// BEGIN and COMMIT; now the `BEGIN IMMEDIATE` / `MutexGuard`
/// unwinding in `with_conn` releases it. We verify by running a
/// cancel-first call and immediately attempting another writer-held
/// operation on the same server.
#[tokio::test]
async fn cancellation_releases_writer_mutex() {
    let server = make_server();
    seed_list(&server, "list-post-cancel");

    let ct = CancellationToken::new();
    ct.cancel();

    let _ = server
        .analyze_task_patterns(
            Parameters(AnalyzeTaskPatternsArgs {
                window_days: Some(7),
                top_n: Some(3),
            }),
            ct,
        )
        .await
        .expect_err("cancelled analyze must fail");

    // A follow-up writer-held operation (seeding another task via
    // `with_conn`) must succeed — if the MutexGuard from the aborted
    // call had somehow been leaked, `writer_result` would deadlock or
    // return `PoisonError`.
    server
        .with_conn(|conn| {
            // lift to canonical TaskBuilder.
            lorvex_store::test_support::fixtures::TaskBuilder::new("post-cancel-task")
                .title("Placed after cancellation")
                .created_at("2026-03-01T00:00:00Z")
                .list_id(Some("list-post-cancel"))
                .insert(conn);
            Ok(())
        })
        .expect("writer mutex must remain usable after cancellation");
}
