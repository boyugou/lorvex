use super::*;

const SCALE_SMOKE_QUERY_MAX_MS: u128 = 3_000;

#[derive(Debug)]
pub(super) struct ScaleSmokeMetric {
    pub(super) name: &'static str,
    pub(super) elapsed_ms: u128,
    pub(super) rows: usize,
}

pub(super) fn collect_scale_smoke_metrics(conn: &Connection) -> Vec<ScaleSmokeMetric> {
    let today = today_ymd_local_for_test();
    let mut metrics = Vec::new();

    let started = Instant::now();
    let overview = lorvex_workflow::overview::load_overview_snapshot(
        conn,
        lorvex_workflow::overview::OverviewLimits::app(),
    )
    .expect("query overview snapshot");
    metrics.push(ScaleSmokeMetric {
        name: "today_overview",
        elapsed_ms: started.elapsed().as_millis(),
        rows: overview.top_by_priority.len() + overview.recently_completed.len(),
    });

    let started = Instant::now();
    let all_tasks_sql = build_get_all_tasks_sql(false, false);
    let all_tasks = tasks_from_query(conn, &all_tasks_sql, []).expect("query all tasks view");
    metrics.push(ScaleSmokeMetric {
        name: "all_tasks_view",
        elapsed_ms: started.elapsed().as_millis(),
        rows: all_tasks.len(),
    });

    let started = Instant::now();
    let upcoming_horizon = date_plus_days_ymd_local_for_test(14);
    let upcoming = tasks_from_query(
        conn,
        &format!(
            "SELECT {TASK_COLS} FROM tasks
             WHERE status = 'open'
               AND due_date IS NOT NULL
               AND due_date >= ?1
               AND due_date <= ?2
             ORDER BY due_date ASC, priority_effective ASC, created_at DESC"
        ),
        params![today, upcoming_horizon],
    )
    .expect("query upcoming tasks view");
    metrics.push(ScaleSmokeMetric {
        name: "upcoming_view",
        elapsed_ms: started.elapsed().as_millis(),
        rows: upcoming.len(),
    });

    let started = Instant::now();
    let mut lists_stmt = conn
        .prepare(
            "SELECT l.id, l.name, l.color, l.icon, l.description,
                    l.ai_notes, l.created_at, l.updated_at,
                    COUNT(CASE WHEN t.status = 'open' THEN 1 END) as open_count
             FROM lists l
             LEFT JOIN tasks t ON t.list_id = l.id AND t.status != 'cancelled'
             GROUP BY l.id
             ORDER BY l.created_at ASC",
        )
        .expect("prepare list query for settings");
    let list_rows = lists_stmt
        .query_map([], |row| {
            Ok(ListWithCount {
                list: list_from_row(row)?,
                open_count: row.get(8)?,
            })
        })
        .expect("query settings lists")
        .collect::<rusqlite::Result<Vec<_>>>()
        .expect("collect settings lists");
    let preference_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM preferences", [], |row| row.get(0))
        .expect("query preference count");
    metrics.push(ScaleSmokeMetric {
        name: "settings_view_data",
        elapsed_ms: started.elapsed().as_millis(),
        rows: list_rows.len() + preference_count as usize,
    });

    let started = Instant::now();
    // anchor to UTC's calendar day (matching the
    // dataset seeder and `today_ymd_local_for_test()` used above) so the
    // window's `from` and `to` are TZ-deterministic regardless of the
    // runner's timezone.
    let today_anchor = chrono::Utc::now().date_naive();
    let from = (today_anchor - chrono::Duration::days(7))
        .format("%Y-%m-%d")
        .to_string();
    let to = (today_anchor + chrono::Duration::days(30))
        .format("%Y-%m-%d")
        .to_string();
    let events = lorvex_store::calendar_timeline::queries::list_calendar_events(
        conn,
        &from,
        &to,
        u32::MAX,
        0,
    )
    .expect("query calendar rows");
    metrics.push(ScaleSmokeMetric {
        name: "calendar_view_data",
        elapsed_ms: started.elapsed().as_millis(),
        rows: events.len(),
    });

    metrics
}

pub(super) fn assert_scale_smoke_metrics(dataset_label: &str, metrics: &[ScaleSmokeMetric]) {
    for metric in metrics {
        println!(
            "[scale-smoke] {dataset_label} {}: {}ms rows={}",
            metric.name, metric.elapsed_ms, metric.rows
        );
        assert!(
            metric.elapsed_ms <= SCALE_SMOKE_QUERY_MAX_MS,
            "{dataset_label} {} exceeded {}ms budget: {}ms",
            metric.name,
            SCALE_SMOKE_QUERY_MAX_MS,
            metric.elapsed_ms
        );
        assert!(
            metric.rows > 0,
            "{dataset_label} {} returned no rows",
            metric.name
        );
    }
}
