use super::*;

// every test-fixture seed below references the canonical
// [`TEST_VERSION`] (re-exported from `lorvex_store::test_support`)
// rather than open-coding a literal. The previous shape included the
// outright invalid `"test_ver"` letter-prefixed seed below — a string
// that lex-sorts strictly *above* every realistic post-update HLC and
// would silently no-op any LWW-gated mutation against the seeded tags.

pub(super) fn apply_scale_perf_migrations(_conn: &Connection) {
    // No-op: all indexes are now in the consolidated 001_initial_schema.sql
}

pub(super) fn seed_scale_smoke_dataset(
    conn: &mut Connection,
    task_count: usize,
    event_count: usize,
) {
    let now = "2026-03-04T08:00:00Z";
    // anchor to UTC's calendar day so every derived
    // date (tomorrow, overdue, per-task plan_day, per-event day) is
    // TZ-deterministic and agrees with the metrics collector, which
    // resolves "today" via `today_ymd_local_for_test()` -> `Utc::now()`.
    // Previously this read `chrono::Local::now().date_naive()`, which
    // made the seeded dates shift with the runner's timezone and
    // could straddle local midnight, so downstream queries filtering
    // "today" vs a task whose planned_date was one day earlier
    // returned the wrong shape.
    let today_anchor = chrono::Utc::now().date_naive();
    let today = today_anchor.format("%Y-%m-%d").to_string();
    let tomorrow = (today_anchor + chrono::Duration::days(1))
        .format("%Y-%m-%d")
        .to_string();
    let in_three_days = (today_anchor + chrono::Duration::days(3))
        .format("%Y-%m-%d")
        .to_string();
    let overdue = (today_anchor - chrono::Duration::days(2))
        .format("%Y-%m-%d")
        .to_string();

    conn.execute(
        "INSERT INTO lists (id, name, color, icon, description, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?7, ?6, ?6)",
        params![
            "list-scale-smoke",
            "Scale Smoke List",
            "#4F8EF7",
            "scale",
            "Seeded for scale smoke tests",
            now,
            TEST_VERSION,
        ],
    )
    .expect("insert scale smoke list");

    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?4, ?3)",
        params!["theme", "\"system\"", now, TEST_VERSION],
    )
    .expect("insert theme preference");
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?4, ?3)",
        params!["language", "\"en-US\"", now, TEST_VERSION],
    )
    .expect("insert language preference");

    let tx = conn
        .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
        .expect("start scale smoke transaction");

    {
        // Stays raw: TaskBuilder doesn't expose `raw_input`, `ai_notes`
        // (deliberately AI-only), `estimated_minutes`, or
        // `last_deferred_at`. Scale-smoke needs all of them to seed a
        // realistic 18-column row; using the builder would silently
        // drop those signals and skew the perf measurements.
        let mut task_stmt = tx
            .prepare(
                "INSERT INTO tasks (
                  id, title, body, raw_input, ai_notes, status, list_id, priority,
                  due_date, due_time, estimated_minutes,
                  defer_count, version, created_at, updated_at, completed_at, last_deferred_at, planned_date
                 ) VALUES (
                  ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8,
                  ?9, ?10, ?11,
                  ?12, ?18, ?13, ?14, ?15, ?16, ?17
                 )",
            )
            .expect("prepare scale smoke task insert");
        let mut tag_stmt = tx
            .prepare("INSERT OR IGNORE INTO task_tags (task_id, tag_id, version, created_at) VALUES (?1, ?2, ?3, '2026-03-01T00:00:00Z')")
            .expect("prepare scale smoke tag insert");
        // Pre-resolve tag ids for the fixed set of tags used in this dataset.
        // Uses shared tag_repo for display_name/lookup_key normalization.
        // pass `TEST_VERSION` instead of the previous
        // `"test_ver"` letter-prefixed literal so any LWW-gated tag
        // rename or merge applied after seeding actually wins. The
        // old literal sorted strictly above every realistic HLC and
        // would have silently no-op'd the rename.
        let tag_names = ["scale", "ui", "smoke", "query", "perf"];
        let mut tag_id_map: std::collections::HashMap<String, String> =
            std::collections::HashMap::new();
        for tag_name in &tag_names {
            use lorvex_store::repositories::tag_repo;
            let (resolved_id, _) =
                tag_repo::resolve_or_create_tag(&tx, tag_name, TEST_VERSION, now)
                    .expect("resolve_or_create tag in scale smoke");
            tag_id_map.insert(tag_name.to_string(), resolved_id);
        }

        for n in 1..=task_count {
            let status = if n % 17 == 0 { "completed" } else { "open" };
            let has_defer_history = n % 11 == 0;

            let due_date = match n % 6 {
                0 => Some(tomorrow.as_str()),
                1 => Some(overdue.as_str()),
                2 => Some(today.as_str()),
                3 => Some(in_three_days.as_str()),
                _ => None,
            };
            let due_time = if due_date.is_some() && n % 8 == 0 {
                Some(format!("{:02}:{:02}", (n % 9) + 9, (n * 7) % 60))
            } else {
                None
            };

            let id = format!("scale-ui-{n:05}");
            let title = format!("Scale UI task {n:05}");
            let body = format!("Synthetic app smoke task #{n}");
            let raw_input = format!("scale smoke seed #{n}");
            let ai_notes = if n % 23 == 0 {
                Some("AI note: deferral risk")
            } else {
                None
            };
            let tag_list: Vec<&str> = if n % 2 == 0 {
                vec!["scale", "ui", "smoke"]
            } else {
                vec!["scale", "query", "perf"]
            };
            let completed_at = if status == "completed" {
                Some(now)
            } else {
                None
            };
            let last_deferred_at = if has_defer_history { Some(now) } else { None };
            let planned_date: Option<String> = if has_defer_history {
                let plan_day = today_anchor + chrono::Duration::days(((n % 14) + 1) as i64);
                Some(plan_day.format("%Y-%m-%d").to_string())
            } else {
                None
            };
            let due_time = due_time.as_deref();

            task_stmt
                .execute(params![
                    id,
                    title,
                    body,
                    raw_input,
                    ai_notes,
                    status,
                    "list-scale-smoke",
                    ((n % 3) + 1) as i64,
                    due_date,
                    due_time,
                    (((n % 6) + 1) * 15) as i64,
                    if has_defer_history {
                        ((n % 6) + 1) as i64
                    } else {
                        0
                    },
                    now,
                    now,
                    completed_at,
                    last_deferred_at,
                    planned_date,
                    TEST_VERSION,
                ])
                .expect("insert scale smoke task");

            // Materialize tags to join table using pre-resolved tag ids
            for tag in &tag_list {
                let tag_id = tag_id_map.get(*tag).expect("tag id must exist");
                tag_stmt
                    .execute(params![id, tag_id, TEST_VERSION])
                    .expect("insert task tag");
            }
        }
    }

    {
        let mut event_stmt = tx
            .prepare(
                "INSERT INTO calendar_events (
                  id, title, description, recurrence, timezone, start_date, start_time,
                  end_date, end_time, all_day, location, color,
                  version, created_at, updated_at
                ) VALUES (
                  ?1, ?2, ?3, ?4, ?5, ?6, ?7,
                  ?8, ?9, ?10, ?11, ?12,
                  ?15, ?13, ?14
                )",
            )
            .expect("prepare scale smoke event insert");

        for n in 1..=event_count {
            let day = today_anchor + chrono::Duration::days((n % 45) as i64);
            let start_date = day.format("%Y-%m-%d").to_string();
            let end_date = start_date.clone();
            let start_time = format!("{:02}:{:02}", 8 + (n % 9), (n * 5) % 60);
            let end_time = format!("{:02}:{:02}", 9 + (n % 9), (n * 5 + 30) % 60);

            event_stmt
                .execute(params![
                    format!("scale-event-{n:05}"),
                    format!("Scale Event {n:05}"),
                    "Synthetic scale event",
                    if n % 20 == 0 {
                        Some("{\"FREQ\":\"WEEKLY\",\"INTERVAL\":1}")
                    } else {
                        None
                    },
                    Some("America/Los_Angeles"),
                    start_date,
                    start_time,
                    end_date,
                    end_time,
                    0,
                    Some("Virtual"),
                    Some("#4F8EF7"),
                    now,
                    now,
                    TEST_VERSION,
                ])
                .expect("insert scale smoke event");
        }
    }

    let focus_task_ids: Vec<String> = (1..=10)
        .map(|index| format!("scale-ui-{index:05}"))
        .collect();
    tx.execute(
        "INSERT INTO current_focus (date, briefing, version, created_at, updated_at)
         VALUES (?1, ?2, ?4, ?3, ?3)",
        params![today, "Scale smoke focus briefing", now, TEST_VERSION],
    )
    .expect("insert scale smoke current focus");
    for (pos, task_id) in focus_task_ids.iter().enumerate() {
        tx.execute(
            "INSERT INTO current_focus_items (date, position, task_id) VALUES (?1, ?2, ?3)",
            params![today, pos as i64, task_id],
        )
        .expect("insert scale smoke focus item");
    }

    tx.commit().expect("commit scale smoke dataset");
}
