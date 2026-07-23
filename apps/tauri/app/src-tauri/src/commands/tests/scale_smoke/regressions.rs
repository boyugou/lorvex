use super::dataset::{apply_scale_perf_migrations, seed_scale_smoke_dataset};
use super::metrics::{assert_scale_smoke_metrics, collect_scale_smoke_metrics};
use super::*;

#[test]
fn app_scale_smoke_queries_remain_responsive_at_1k_dataset() {
    let mut conn = setup_sync_test_conn();
    apply_scale_perf_migrations(&conn);
    seed_scale_smoke_dataset(&mut conn, 1_000, 120);

    let metrics = collect_scale_smoke_metrics(&conn);
    let all_tasks_rows = metrics
        .iter()
        .find(|metric| metric.name == "all_tasks_view")
        .map(|metric| metric.rows)
        .unwrap_or_default();
    assert!(
        all_tasks_rows >= 700,
        "1k all_tasks view should return substantial rows (got {all_tasks_rows})"
    );
    assert_scale_smoke_metrics("dataset=1k", &metrics);
}

#[test]
fn app_scale_smoke_queries_remain_responsive_at_10k_dataset() {
    let mut conn = setup_sync_test_conn();
    apply_scale_perf_migrations(&conn);
    seed_scale_smoke_dataset(&mut conn, 10_000, 1_200);

    let metrics = collect_scale_smoke_metrics(&conn);
    let all_tasks_rows = metrics
        .iter()
        .find(|metric| metric.name == "all_tasks_view")
        .map(|metric| metric.rows)
        .unwrap_or_default();
    // The all_tasks query has LIMIT 2000 for performance; with 10k tasks
    // (mix of open/completed/cancelled), we expect up to 2000 rows returned.
    assert!(
        all_tasks_rows >= 1_500,
        "10k all_tasks view should return substantial rows within LIMIT (got {all_tasks_rows})"
    );
    assert_scale_smoke_metrics("dataset=10k", &metrics);
}
