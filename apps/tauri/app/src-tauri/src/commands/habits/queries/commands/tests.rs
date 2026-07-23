use super::cache::{
    best_streak_full_history_scan_count_for_test, clear_best_streak_cache_for_test,
    reset_best_streak_full_history_scan_count_for_test,
};
use super::stats::{
    gather_habits_with_stats, BEST_STREAK_COMPLETION_DATES_QUERY, RECENT_COMPLETIONS_QUERY,
    STREAK_WINDOW_DAYS,
};
use super::*;
use rusqlite::hooks::{AuthAction, AuthContext, Authorization};

use crate::test_support::test_conn;

fn insert_habit(conn: &rusqlite::Connection, id: &str) {
    conn.execute(
        "INSERT INTO habits (id, name, frequency_type, target_count, archived, version, created_at, updated_at)
         VALUES (?1, 'Habit', 'daily', 1, 0, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        params![id],
    )
    .expect("insert habit");
}

#[test]
fn compute_all_streaks_rejects_invalid_completed_date() {
    let conn = test_conn();
    insert_habit(&conn, "habit-1");
    conn.execute(
        "INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, updated_at)
         VALUES ('habit-1', 'not-a-date', 1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("insert invalid completion");

    let error = compute_all_streaks(&conn, "2026-03-29")
        .expect_err("invalid completion date should be rejected");
    match error {
        AppError::Validation(message) => assert!(message.contains("not-a-date")),
        other => panic!("expected validation error, got {other:?}"),
    }
}

#[test]
fn compute_current_streak_rejects_invalid_completed_date() {
    let conn = test_conn();
    insert_habit(&conn, "habit-1");
    conn.execute(
        "INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, updated_at)
         VALUES ('habit-1', '2026-99-99', 1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("insert invalid completion");

    let error = compute_current_streak(
        &conn,
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
        "daily",
        1,
        "2026-03-29",
    )
    .expect_err("invalid completion date should be rejected");
    match error {
        AppError::Validation(message) => assert!(message.contains("2026-99-99")),
        other => panic!("expected validation error, got {other:?}"),
    }
}

#[test]
fn current_streaks_ignore_future_completion_dates() {
    let conn = test_conn();
    insert_habit(&conn, "habit-1");
    for completed_date in ["2026-03-28", "2026-03-29", "2026-03-30"] {
        conn.execute(
            "INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, updated_at)
             VALUES ('habit-1', ?1, 1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
            params![completed_date],
        )
        .expect("insert completion");
    }

    let current = compute_current_streak(
        &conn,
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
        "daily",
        1,
        "2026-03-29",
    )
    .expect("compute current streak");
    assert_eq!(
        current, 2,
        "future completions must not inflate today's current streak"
    );

    let all = compute_all_streaks(&conn, "2026-03-29").expect("compute all streaks");
    assert_eq!(
        all.get("habit-1"),
        Some(&2),
        "batched streak computation must share the same future-date clamp"
    );
}

#[test]
fn load_existing_completion_value_surfaces_lookup_failures() {
    let conn = test_conn();
    insert_habit(&conn, "habit-1");
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "habit_completions",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let error = load_existing_completion_value(
        &conn,
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
        "2026-03-29",
    )
    .expect_err("existing completion lookup failure should surface");
    match error {
        AppError::Sql(_) => {}
        other => panic!("expected SQL error, got {other:?}"),
    }
}

/// Both #2291 tests share the process-wide `best_streak_cache`,
/// so they must not run concurrently — otherwise one test's
/// `clear_best_streak_cache_for_test()` at the top of the other
/// test's window silently invalidates the warm cache and flips
/// the cache-hit assertion. Cargo runs tests in parallel by
/// default; this static Mutex restores serial ordering between
/// just these two tests (leaving the rest of the suite fully
/// parallel).
fn best_streak_cache_test_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

fn query_plan_details<P>(conn: &rusqlite::Connection, sql: &str, bind_params: P) -> Vec<String>
where
    P: rusqlite::Params,
{
    let mut stmt = conn.prepare(sql).expect("prepare query plan");
    stmt.query_map(bind_params, |row| row.get::<_, String>(3))
        .expect("query plan rows")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect query plan rows")
}

fn assert_query_plan_uses_index_without_completion_scan<P>(
    conn: &rusqlite::Connection,
    sql: &str,
    bind_params: P,
    index_name: &str,
) where
    P: rusqlite::Params,
{
    let plan = query_plan_details(conn, sql, bind_params);
    assert!(
        plan.iter().any(|detail| detail.contains(index_name)),
        "expected query plan to use {index_name}; plan={plan:?}"
    );
    assert!(
        plan.iter().all(|detail| {
            let upper = detail.to_ascii_uppercase();
            !upper.contains("SCAN HC") && !upper.contains("SCAN HABIT_COMPLETIONS")
        }),
        "expected query plan to avoid a full habit_completions scan; plan={plan:?}"
    );
}

/// seed 20 habits × ~3 years of daily
/// completions (~21,900 rows, above the 20k floor called for in
/// the issue). Asserts the Habits-view read keeps the warm-cache
/// bounded-scan contract without relying on wall-clock timing,
/// which is too noisy under parallel `cargo test` scheduler load.
#[test]
fn get_habits_with_stats_bounded_scan_scales_to_large_history() {
    let _guard = best_streak_cache_test_lock()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let conn = test_conn();
    clear_best_streak_cache_for_test();
    reset_best_streak_full_history_scan_count_for_test();

    let total_days: i64 = 3 * 365;
    let today = chrono::Utc::now().date_naive();
    let start = today - chrono::Duration::days(total_days - 1);

    let tx = conn.unchecked_transaction().expect("begin tx");
    for idx in 0..10 {
        let habit_id = format!("bench-habit-{idx:02}");
        tx.execute(
            "INSERT INTO habits (id, name, frequency_type, target_count, archived, version, created_at, updated_at)
             VALUES (?1, ?2, 'daily', 1, 0, 'bench_ver', '2023-01-01T00:00:00Z', '2023-01-01T00:00:00Z')",
            params![habit_id, format!("Bench habit {idx}")],
        )
        .expect("insert habit");

        let mut stmt = tx
            .prepare(
                "INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, updated_at)
                 VALUES (?1, ?2, 1, 'bench_ver', '2023-01-01T00:00:00Z', '2023-01-01T00:00:00Z')",
            )
            .expect("prepare completion insert");
        for day in 0..total_days {
            let d = start + chrono::Duration::days(day);
            let date_str = d.format("%Y-%m-%d").to_string();
            stmt.execute(params![habit_id, date_str])
                .expect("seed completion");
        }
    }
    // Second fan-out of habits so the combined row count clears
    // 20k without violating the (habit_id, completed_date) PK.
    for idx in 0..10 {
        let habit_id = format!("bench-habit-b-{idx:02}");
        tx.execute(
            "INSERT INTO habits (id, name, frequency_type, target_count, archived, version, created_at, updated_at)
             VALUES (?1, ?2, 'daily', 1, 0, 'bench_ver', '2023-01-01T00:00:00Z', '2023-01-01T00:00:00Z')",
            params![habit_id, format!("Bench habit B{idx}")],
        )
        .expect("insert habit b");

        let mut stmt = tx
            .prepare(
                "INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, updated_at)
                 VALUES (?1, ?2, 1, 'bench_ver', '2023-01-01T00:00:00Z', '2023-01-01T00:00:00Z')",
            )
            .expect("prepare b completion insert");
        for day in 0..total_days {
            let d = start + chrono::Duration::days(day);
            let date_str = d.format("%Y-%m-%d").to_string();
            stmt.execute(params![habit_id, date_str])
                .expect("seed completion b");
        }
    }
    tx.commit().expect("commit bench seed");

    let total_rows: i64 = conn
        .query_row("SELECT COUNT(*) FROM habit_completions", [], |row| {
            row.get(0)
        })
        .expect("count rows");
    assert!(
        total_rows >= 20_000,
        "fixture must seed >= 20k rows to exercise the bounded-scan path, got {total_rows}",
    );

    // Cold call: best-streak cache is empty, so this pays the
    // per-habit full-history scan once and populates the cache.
    let rows_cold = gather_habits_with_stats(&conn).expect("cold gather");
    assert_eq!(rows_cold.len(), 20, "expected 20 active habits");
    assert_eq!(
        best_streak_full_history_scan_count_for_test(),
        20,
        "cold path should scan all-time history exactly once per active habit"
    );

    // Warm call: best-streak is cached, so this is the common
    // Habits-view-open path. The regression contract is structural:
    // rolling stats are bounded to the configured window and the
    // all-time best streak comes from the cache instead of replaying
    // every historical row per habit.
    let scans_before_warm = best_streak_full_history_scan_count_for_test();
    let rows_warm = gather_habits_with_stats(&conn).expect("warm gather");
    assert_eq!(rows_warm.len(), 20);
    assert_eq!(
        best_streak_full_history_scan_count_for_test(),
        scans_before_warm,
        "warm path must not run per-habit all-time best-streak scans"
    );
    assert_eq!(
        STREAK_WINDOW_DAYS, 365,
        "Habits-view bounded current-streak window is part of the #2291 contract"
    );

    for h in &rows_warm {
        assert_eq!(
            h.total_completions, total_days,
            "habit {} expected {total_days} total, got {}",
            h.id, h.total_completions
        );
        assert_eq!(
            h.best_streak, total_days,
            "habit {} expected exact all-time best_streak {total_days}, got {}",
            h.id, h.best_streak
        );
        assert_eq!(
            h.current_streak, STREAK_WINDOW_DAYS,
            "habit {} should report the full 365-day bounded current streak",
            h.id
        );
        assert_eq!(
            h.completions_last_30, 30,
            "habit {} expected only the trailing 30 days in completions_last_30",
            h.id
        );
        assert_eq!(
            h.recent_completion_dates.len(),
            90,
            "habit {} expected only the trailing 90 recent dates",
            h.id
        );
    }

    assert_query_plan_uses_index_without_completion_scan(
        &conn,
        &format!("EXPLAIN QUERY PLAN {RECENT_COMPLETIONS_QUERY}"),
        params!["2026-01-01", "2026-12-31"],
        "idx_habit_completions_date",
    );

    assert_query_plan_uses_index_without_completion_scan(
        &conn,
        &format!("EXPLAIN QUERY PLAN {BEST_STREAK_COMPLETION_DATES_QUERY}"),
        params!["bench-habit-00"],
        "idx_habit_completions_date",
    );
}

#[test]
fn best_streak_cache_hit_short_circuits_full_history_scan() {
    let _guard = best_streak_cache_test_lock()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let conn = test_conn();
    clear_best_streak_cache_for_test();

    let today = chrono::Utc::now().date_naive();
    insert_habit(&conn, "cache-habit-1");
    let mut stmt = conn
        .prepare(
            "INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, updated_at)
             VALUES (?1, ?2, 1, 'cache_ver', '2025-01-01T00:00:00Z', '2025-01-01T00:00:00Z')",
        )
        .expect("prepare");
    for day in 1..=10 {
        let d = today - chrono::Duration::days(day);
        stmt.execute(params!["cache-habit-1", d.format("%Y-%m-%d").to_string()])
            .expect("seed row");
    }

    let first = gather_habits_with_stats(&conn).expect("first gather");
    assert_eq!(first.len(), 1);
    let original_best = first[0].best_streak;
    assert!(
        original_best >= 10,
        "expected best >= 10, got {original_best}"
    );

    // Delete every completion — without invalidation, the cached
    // best_streak should still be returned.
    conn.execute(
        "DELETE FROM habit_completions WHERE habit_id = 'cache-habit-1'",
        [],
    )
    .expect("wipe completions");

    let cached = gather_habits_with_stats(&conn).expect("cached gather");
    assert_eq!(
        cached[0].best_streak, original_best,
        "cache should still report the pre-delete best_streak"
    );

    // After explicit invalidation, recomputation returns 0.
    invalidate_best_streak_cache(&lorvex_domain::HabitId::from_trusted(
        "cache-habit-1".to_string(),
    ));
    let recomputed = gather_habits_with_stats(&conn).expect("recomputed gather");
    assert_eq!(
        recomputed[0].best_streak, 0,
        "post-invalidation best_streak should recompute to 0"
    );
}
