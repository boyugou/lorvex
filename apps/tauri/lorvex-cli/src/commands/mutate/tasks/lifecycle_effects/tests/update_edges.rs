use super::super::*;
use super::support::*;
use lorvex_domain::Patch;

const TASK_TAGS: &str = "01966a3f-7c8b-7d4e-8f3a-00000000b101";
const TASK_TAG_LIMIT: &str = "01966a3f-7c8b-7d4e-8f3a-00000000b102";

#[test]
fn update_task_with_conn_patches_tags_and_syncs_edges() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, TASK_TAGS, "Tagged", "open");
    let set_tags = vec!["Work".to_string(), "Deep Work".to_string()];
    update_task_with_conn(
        &mut conn,
        &tid(TASK_TAGS),
        &TaskUpdateFields {
            tags_set: Some(&set_tags),
            ..TaskUpdateFields::default()
        },
    )
    .expect("set tags");

    let add_tags = vec!["Home".to_string()];
    let remove_tags = vec!["Work".to_string()];
    update_task_with_conn(
        &mut conn,
        &tid(TASK_TAGS),
        &TaskUpdateFields {
            tags_add: Some(&add_tags),
            tags_remove: Some(&remove_tags),
            ..TaskUpdateFields::default()
        },
    )
    .expect("patch tags");

    let tags: Vec<String> = {
        let mut stmt = conn
            .prepare(
                "SELECT tg.display_name
                 FROM task_tags tt
                 JOIN tags tg ON tg.id = tt.tag_id
                 WHERE tt.task_id = ?1
                 ORDER BY tg.display_name ASC",
            )
            .expect("prepare tag query");
        stmt.query_map([TASK_TAGS], |row| row.get::<_, String>(0))
            .expect("query tags")
            .collect::<Result<Vec<_>, _>>()
            .expect("collect tags")
    };
    assert_eq!(tags, vec!["Deep Work".to_string(), "Home".to_string()]);

    let edge_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1",
            [EDGE_TASK_TAG],
            |row| row.get(0),
        )
        .expect("count task-tag edge outbox entries");
    assert_eq!(edge_outbox_count, 3);
}

#[test]
fn update_task_with_conn_rejects_tag_patch_above_task_limit() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, TASK_TAG_LIMIT, "Tagged", "open");
    let initial_tags: Vec<String> = (0..lorvex_domain::validation::MAX_TASK_TAGS)
        .map(|index| format!("tag-{index}"))
        .collect();
    update_task_with_conn(
        &mut conn,
        &tid(TASK_TAG_LIMIT),
        &TaskUpdateFields {
            tags_set: Some(&initial_tags),
            ..TaskUpdateFields::default()
        },
    )
    .expect("seed max tags");

    let add_tags = vec!["one-too-many".to_string()];
    let error = update_task_with_conn(
        &mut conn,
        &tid(TASK_TAG_LIMIT),
        &TaskUpdateFields {
            tags_add: Some(&add_tags),
            ..TaskUpdateFields::default()
        },
    )
    .expect_err("tag patch above per-task cap should fail");
    assert!(
        error.to_string().contains("tags supports at most"),
        "expected per-task tag cap message, got {error}"
    );

    let tag_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE task_id = ?1",
            [TASK_TAG_LIMIT],
            |row| row.get(0),
        )
        .expect("count task tags");
    assert_eq!(tag_count, lorvex_domain::validation::MAX_TASK_TAGS as i64);
}

#[test]
fn update_task_with_conn_patches_dependencies_and_syncs_edges() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000066";
    let blocker_a = "01949c00-0000-7000-8000-000000000067";
    let blocker_b = "01949c00-0000-7000-8000-000000000068";
    let blocker_c = "01949c00-0000-7000-8000-000000000069";
    seed_task(&conn, task_id, "Blocked", "open");
    seed_task(&conn, blocker_a, "Blocker A", "open");
    seed_task(&conn, blocker_b, "Blocker B", "open");
    seed_task(&conn, blocker_c, "Blocker C", "open");
    let set_deps = vec![blocker_a.to_string(), blocker_b.to_string()];
    update_task_with_conn(
        &mut conn,
        &tid(task_id),
        &TaskUpdateFields {
            depends_on_set: Some(&set_deps),
            ..TaskUpdateFields::default()
        },
    )
    .expect("set dependencies");

    let add_deps = vec![blocker_c.to_string()];
    let remove_deps = vec![blocker_a.to_string()];
    update_task_with_conn(
        &mut conn,
        &tid(task_id),
        &TaskUpdateFields {
            depends_on_add: Some(&add_deps),
            depends_on_remove: Some(&remove_deps),
            ..TaskUpdateFields::default()
        },
    )
    .expect("patch dependencies");

    let deps: Vec<String> = {
        let mut stmt = conn
            .prepare(
                "SELECT depends_on_task_id
                 FROM task_dependencies
                 WHERE task_id = ?1
                 ORDER BY depends_on_task_id ASC",
            )
            .expect("prepare dependency query");
        stmt.query_map([task_id], |row| row.get::<_, String>(0))
            .expect("query dependencies")
            .collect::<Result<Vec<_>, _>>()
            .expect("collect dependencies")
    };
    assert_eq!(deps, vec![blocker_b.to_string(), blocker_c.to_string()]);

    let edge_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1",
            [EDGE_TASK_DEPENDENCY],
            |row| row.get(0),
        )
        .expect("count task-dependency edge outbox entries");
    assert_eq!(edge_outbox_count, 3);
}

#[test]
fn update_task_with_conn_status_cancelled_does_not_readd_dependency_patch() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000051";
    let old_blocker_id = "01949c00-0000-7000-8000-000000000052";
    let new_blocker_id = "01949c00-0000-7000-8000-000000000053";
    seed_task(&conn, task_id, "Cancel with deps", "open");
    seed_task(&conn, old_blocker_id, "Old blocker", "open");
    seed_task(&conn, new_blocker_id, "New blocker", "open");
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES (?1, ?2,
                 '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
        [task_id, old_blocker_id],
    )
    .expect("seed dependency");

    let replacement_deps = vec![new_blocker_id.to_string()];
    let updated = update_task_with_conn(
        &mut conn,
        &tid(task_id),
        &TaskUpdateFields {
            status: Some("cancelled"),
            depends_on_set: Some(&replacement_deps),
            ..TaskUpdateFields::default()
        },
    )
    .expect("cancel with dependency patch");

    assert_eq!(updated.core().status(), "cancelled");
    let dep_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_dependencies WHERE task_id = ?1",
            [task_id],
            |row| row.get(0),
        )
        .expect("count remaining dependencies");
    assert_eq!(
        dep_count, 0,
        "cancelled tasks must not keep or recreate dependency edges"
    );
}

#[test]
fn update_task_with_conn_due_date_patch_preserves_recurring_cadence_anchor() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000070";
    let recurrence_group_id = "01949c00-0000-7000-8000-000000000071";
    seed_task(&conn, task_id, "Complete rescheduled", "open");
    let cadence_anchor = date_plus_days_ymd_for_conn(&conn, 10).expect("future recurrence anchor");
    let expected_successor_due_date =
        date_plus_days_ymd_for_conn(&conn, 11).expect("future recurrence successor");
    let manual_due_date =
        date_plus_days_ymd_for_conn(&conn, 12).expect("future manual due-date move");
    conn.execute(
        "UPDATE tasks
         SET due_date = ?1,
             canonical_occurrence_date = ?1,
             recurrence_group_id = ?2,
             recurrence = '{\"FREQ\":\"DAILY\",\"INTERVAL\":1}'
         WHERE id = ?3",
        [&cadence_anchor, recurrence_group_id, task_id],
    )
    .expect("seed recurrence");

    let updated = update_task_with_conn(
        &mut conn,
        &tid(task_id),
        &TaskUpdateFields {
            due_date: Patch::Set(&manual_due_date),
            status: Some("completed"),
            ..TaskUpdateFields::default()
        },
    )
    .expect("complete rescheduled recurrence");

    assert_eq!(updated.core().status(), "completed");
    assert_eq!(
        updated.scheduling().due_date(),
        Some(lorvex_domain::Date::parse(&manual_due_date).unwrap())
    );
    let successor_due_date: String = conn
        .query_row(
            "SELECT due_date FROM tasks WHERE spawned_from = ?1",
            [task_id],
            |row| row.get(0),
        )
        .expect("load spawned successor");
    assert_eq!(
        successor_due_date, expected_successor_due_date,
        "manual due-date moves must not shift the stable recurrence cadence anchor"
    );
}

#[test]
fn update_task_with_conn_rejects_dependency_cycles() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_a = "01949c00-0000-7000-8000-000000000072";
    let task_b = "01949c00-0000-7000-8000-000000000073";
    seed_task(&conn, task_a, "Task A", "open");
    seed_task(&conn, task_b, "Task B", "open");
    let deps = vec![task_b.to_string()];
    update_task_with_conn(
        &mut conn,
        &tid(task_a),
        &TaskUpdateFields {
            depends_on_set: Some(&deps),
            ..TaskUpdateFields::default()
        },
    )
    .expect("seed dependency");

    let cycle_deps = vec![task_a.to_string()];
    let error = update_task_with_conn(
        &mut conn,
        &tid(task_b),
        &TaskUpdateFields {
            depends_on_add: Some(&cycle_deps),
            ..TaskUpdateFields::default()
        },
    )
    .expect_err("cycle should fail");
    assert!(error.to_string().contains("Circular dependency detected"));

    let reverse_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_dependencies
             WHERE task_id = ?1 AND depends_on_task_id = ?2",
            [task_b, task_a],
            |row| row.get(0),
        )
        .expect("count reverse dependency");
    assert_eq!(reverse_count, 0);
}
