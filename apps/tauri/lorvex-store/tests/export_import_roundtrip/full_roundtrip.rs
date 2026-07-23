use super::support::*;

#[test]
fn test_full_roundtrip() {
    let dirs = setup_dirs();

    // Set up source DB.
    let source = open_db_in_memory().unwrap();

    // -- Lists --
    source
        .execute(
            "INSERT INTO lists (id, name, color, icon, description, ai_notes, created_at, updated_at, version)
             VALUES ('list-1', 'Work', '#FF0000', 'briefcase', 'Work tasks', 'AI: high priority list',
                     '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0000_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();

    // -- Tasks --
    source
        .execute(
            "INSERT INTO tasks (id, title, body, status, list_id, priority, due_date, estimated_minutes,
                     created_at, updated_at, version)
             VALUES ('task-1', 'Do stuff', 'Task body text', 'open', 'list-1', 2, '2026-03-25', 60,
                     '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0001_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO tasks (id, title, status, list_id, priority, created_at, updated_at, version)
             VALUES ('task-2', 'Another task', 'completed', 'list-1', 3,
                     '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z', '1711234567890_0002_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();

    // -- Tags --
    source
        .execute(
            "INSERT INTO tags (id, display_name, lookup_key, color, created_at, updated_at, version)
             VALUES ('tag-1', 'Urgent', 'urgent', '#FF0000',
                     '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0003_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO tags (id, display_name, lookup_key, created_at, updated_at, version)
             VALUES ('tag-2', 'Low Priority', 'low priority',
                     '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0004_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();

    // -- Task-tag edges --
    source
        .execute(
            "INSERT INTO task_tags (task_id, tag_id, created_at, version)
             VALUES ('task-1', 'tag-1', '2026-01-01T00:00:00Z', '1711234567890_0005_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO task_tags (task_id, tag_id, created_at, version)
             VALUES ('task-2', 'tag-2', '2026-01-01T00:00:00Z', '1711234567890_0006_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();

    // -- Habits -- weekly cadence with a materialized weekday set
    // (Mon=0, Wed=2, Fri=4) to exercise the `habit_weekdays` child
    // export → import round-trip.
    source
        .execute(
            "INSERT INTO habits (id, name, frequency_type, per_period_target, day_of_month,
                     target_count, milestone_target, archived, color, icon, created_at, updated_at, version)
             VALUES ('habit-1', 'Exercise', 'weekly', 1, NULL, 1, 30, 0, '#00FF00', 'dumbbell',
                     '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0010_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO habit_weekdays (habit_id, weekday) VALUES ('habit-1', 0), ('habit-1', 2), ('habit-1', 4)",
            [],
        )
        .unwrap();

    // -- Current focus with items --
    source
        .execute(
            "INSERT INTO current_focus (date, briefing, timezone, created_at, updated_at, version)
             VALUES ('2026-03-24', 'Focus on task-1 today', 'America/New_York',
                     '2026-03-24T08:00:00Z', '2026-03-24T08:00:00Z', '1711234567890_0020_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO current_focus_items (date, position, task_id)
             VALUES ('2026-03-24', 0, 'task-1')",
            [],
        )
        .unwrap();

    // -- Daily review with task links --
    source
        .execute(
            "INSERT INTO daily_reviews (date, summary, mood, energy_level, timezone, created_at, updated_at, version)
             VALUES ('2026-03-23', 'Good productive day', 4, 3, 'America/New_York',
                     '2026-03-23T22:00:00Z', '2026-03-23T22:00:00Z', '1711234567890_0030_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO daily_review_task_links (review_date, task_id, created_at)
             VALUES ('2026-03-23', 'task-1', '2026-03-23T22:00:00Z')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO daily_review_list_links (review_date, list_id, created_at)
             VALUES ('2026-03-23', 'list-1', '2026-03-23T22:00:00Z')",
            [],
        )
        .unwrap();

    // -- Task dependencies --
    source
        .execute(
            "INSERT INTO task_dependencies (task_id, depends_on_task_id, created_at, version)
             VALUES ('task-2', 'task-1', '2026-01-01T00:00:00Z', '1711234567890_0040_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();

    // -- Export --
    let manifest = export_to_zip(&source, &dirs.zip_path, "device-test").unwrap();

    // Verify manifest counts.
    assert!(
        manifest.entity_counts.get("task").copied().unwrap_or(0) >= 2,
        "expected at least 2 tasks in manifest"
    );
    assert!(
        manifest.entity_counts.get("list").copied().unwrap_or(0) >= 1,
        "expected at least 1 list in manifest"
    );
    assert!(
        manifest.entity_counts.get("tag").copied().unwrap_or(0) >= 2,
        "expected at least 2 tags in manifest"
    );
    assert!(
        manifest.entity_counts.get("habit").copied().unwrap_or(0) >= 1,
        "expected at least 1 habit in manifest"
    );
    assert!(
        manifest
            .entity_counts
            .get("current_focus")
            .copied()
            .unwrap_or(0)
            >= 1,
        "expected at least 1 current_focus in manifest"
    );
    assert!(
        manifest
            .entity_counts
            .get("daily_review")
            .copied()
            .unwrap_or(0)
            >= 1,
        "expected at least 1 daily_review in manifest"
    );
    assert!(
        manifest.edge_counts.get("task_tag").copied().unwrap_or(0) >= 2,
        "expected at least 2 task_tag edges in manifest"
    );
    assert!(
        manifest
            .edge_counts
            .get("task_dependency")
            .copied()
            .unwrap_or(0)
            >= 1,
        "expected at least 1 task_dependency edge in manifest"
    );

    // -- Import into fresh DB --
    let target = open_db_in_memory().unwrap();
    let summary = import_from_zip(&target, &dirs.zip_path).unwrap();
    assert!(
        summary.entities_created > 0,
        "expected some entities created"
    );

    // -- Verify data matches --

    // Tasks
    let task_title: String = target
        .query_row("SELECT title FROM tasks WHERE id = 'task-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(task_title, "Do stuff");

    let task_body: Option<String> = target
        .query_row("SELECT body FROM tasks WHERE id = 'task-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(task_body, Some("Task body text".to_string()));

    let task_priority: Option<i64> = target
        .query_row("SELECT priority FROM tasks WHERE id = 'task-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(task_priority, Some(2));

    let task_count: i64 = target
        .query_row("SELECT COUNT(*) FROM tasks", [], |r| r.get(0))
        .unwrap();
    assert_eq!(task_count, 2);

    // Lists
    let list_name: String = target
        .query_row("SELECT name FROM lists WHERE id = 'list-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(list_name, "Work");

    let list_desc: Option<String> = target
        .query_row(
            "SELECT description FROM lists WHERE id = 'list-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(list_desc, Some("Work tasks".to_string()));

    // Tags
    let tag_display_name: String = target
        .query_row(
            "SELECT display_name FROM tags WHERE id = 'tag-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(tag_display_name, "Urgent");

    let tag_count: i64 = target
        .query_row("SELECT COUNT(*) FROM tags", [], |r| r.get(0))
        .unwrap();
    assert_eq!(tag_count, 2);

    // Task-tag edges
    let edge_count: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE task_id = 'task-1' AND tag_id = 'tag-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(edge_count, 1);

    let total_edges: i64 = target
        .query_row("SELECT COUNT(*) FROM task_tags", [], |r| r.get(0))
        .unwrap();
    assert_eq!(total_edges, 2);

    // Task dependencies
    let dep_count: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM task_dependencies WHERE task_id = 'task-2' AND depends_on_task_id = 'task-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(dep_count, 1);

    // Habits
    let habit_name: String = target
        .query_row("SELECT name FROM habits WHERE id = 'habit-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(habit_name, "Exercise");

    let habit_freq: String = target
        .query_row(
            "SELECT frequency_type FROM habits WHERE id = 'habit-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(habit_freq, "weekly");

    // The nullable `milestone_target` scalar must survive the
    // export → import round-trip (carried in the habit payload, bound
    // by the import upsert).
    let habit_milestone: Option<i64> = target
        .query_row(
            "SELECT milestone_target FROM habits WHERE id = 'habit-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(habit_milestone, Some(30));

    // The `habit_weekdays` child is rebuilt from the imported habit
    // payload's `weekdays` array — the round-trip must preserve the set.
    let weekdays: Vec<i64> = target
        .prepare("SELECT weekday FROM habit_weekdays WHERE habit_id = 'habit-1' ORDER BY weekday")
        .unwrap()
        .query_map([], |r| r.get(0))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    assert_eq!(weekdays, vec![0, 2, 4]);

    // Current focus (day-scoped aggregate)
    let briefing: Option<String> = target
        .query_row(
            "SELECT briefing FROM current_focus WHERE date = '2026-03-24'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(briefing, Some("Focus on task-1 today".to_string()));

    // Embedded child: current_focus_items round-tripped via embedded task_ids.
    let focus_item_count: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = '2026-03-24'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(focus_item_count, 1, "current_focus_items should round-trip");

    let focus_task_id: String = target
        .query_row(
            "SELECT task_id FROM current_focus_items WHERE date = '2026-03-24' AND position = 0",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(focus_task_id, "task-1");

    // Daily review (day-scoped aggregate)
    let review_summary: String = target
        .query_row(
            "SELECT summary FROM daily_reviews WHERE date = '2026-03-23'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(review_summary, "Good productive day");

    let review_mood: Option<i64> = target
        .query_row(
            "SELECT mood FROM daily_reviews WHERE date = '2026-03-23'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(review_mood, Some(4));

    // Embedded children: daily_review_task_links and daily_review_list_links round-tripped.
    let review_task_link_count: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM daily_review_task_links WHERE review_date = '2026-03-23'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        review_task_link_count, 1,
        "daily_review_task_links should round-trip"
    );

    let review_list_link_count: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM daily_review_list_links WHERE review_date = '2026-03-23'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        review_list_link_count, 1,
        "daily_review_list_links should round-trip"
    );
}
