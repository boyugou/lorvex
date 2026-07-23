//! Tests for `task_write`. Extracted from the parent file
//! to keep the production module focused.

use super::*;
use crate::connection::open_db_in_memory;
use crate::StoreError;
use lorvex_domain::{naming::TaskStatus, Patch};

fn setup() -> Connection {
    open_db_in_memory().expect("in-memory DB")
}

#[test]
fn create_minimal_task() {
    let conn = setup();
    let params = TaskCreateParams::builder("t1", "Buy milk", "open", "v1", "2026-03-27T00:00:00Z")
        .build()
        .unwrap();
    let row = create_task(&conn, &params).unwrap();

    // `create_task` returns the inserted row so
    // callers no longer need a follow-up `get_task` round-trip.
    assert_eq!(row.core.id, "t1");
    assert_eq!(row.core.title, "Buy milk");
    assert_eq!(row.core.created_at, row.core.updated_at);
    assert_eq!(row.core.version, "v1");

    let title: String = conn
        .query_row("SELECT title FROM tasks WHERE id = 't1'", [], |r| r.get(0))
        .unwrap();
    assert_eq!(title, "Buy milk");
}

#[test]
fn create_full_task() {
    let conn = setup();
    let params = TaskCreateParams::builder("t2", "Full task", "open", "v2", "2026-03-27T00:00:00Z")
        .body(Some("body text"))
        .raw_input(Some("raw"))
        .ai_notes(Some("notes"))
        .priority(Some(2))
        .due_date(Some("2026-04-01"))
        .due_time(Some("14:30"))
        .estimated_minutes(Some(30))
        .recurrence(Some("weekly"))
        .recurrence_group_id(Some("rg1"))
        .canonical_occurrence_date(Some("2026-04-01"))
        .planned_date(Some("2026-04-01"))
        .build()
        .unwrap();
    create_task(&conn, &params).unwrap();

    let (body, priority, est): (Option<String>, Option<i64>, Option<i64>) = conn
        .query_row(
            "SELECT body, priority, estimated_minutes FROM tasks WHERE id = 't2'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .unwrap();
    assert_eq!(body.as_deref(), Some("body text"));
    assert_eq!(priority, Some(2));
    assert_eq!(est, Some(30));
}

#[test]
fn schema_rejects_due_time_without_due_date() {
    let conn = setup();
    let error = conn
        .execute(
            "INSERT INTO tasks (id, title, status, due_time, version, created_at, updated_at)
             VALUES ('raw-time-only', 'Time only', 'open', '09:30', 'v1',
                     '2026-03-27T00:00:00Z', '2026-03-27T00:00:00Z')",
            [],
        )
        .expect_err("schema must reject due_time without due_date");

    assert!(
        error.to_string().contains("CHECK constraint failed"),
        "unexpected schema error: {error}"
    );
}

#[test]
fn create_rejects_due_time_without_due_date() {
    let error = TaskCreateParams::builder(
        "time-only",
        "Time only",
        "open",
        "v1",
        "2026-03-27T00:00:00Z",
    )
    .due_time(Some("09:30"))
    .build()
    .expect_err("create builder must reject due_time without due_date");

    assert!(
        error.to_string().contains("due_time without due_date"),
        "unexpected validation error: {error}"
    );
}

#[test]
fn update_title_only() {
    let conn = setup();
    let create = TaskCreateParams::builder("t3", "Original", "open", "v1", "2026-03-27T00:00:00Z")
        .build()
        .unwrap();
    create_task(&conn, &create).unwrap();

    let patch = TaskUpdatePatch {
        task_id: "t3",
        title: Some("Updated"),
        version: "v2",
        now: "2026-03-27T01:00:00Z",
        before_status: Some(TaskStatus::Open),
        ..Default::default()
    };
    apply_task_update(&conn, &patch).unwrap();

    let title: String = conn
        .query_row("SELECT title FROM tasks WHERE id = 't3'", [], |r| r.get(0))
        .unwrap();
    assert_eq!(title, "Updated");
}

#[test]
fn update_rejects_due_time_without_existing_due_date() {
    let conn = setup();
    let create = TaskCreateParams::builder(
        "time-only-update",
        "Time only update",
        "open",
        "v1",
        "2026-03-27T00:00:00Z",
    )
    .build()
    .unwrap();
    create_task(&conn, &create).unwrap();

    let error = apply_task_update(
        &conn,
        &TaskUpdatePatch {
            task_id: "time-only-update",
            due_time: Patch::Set("09:30"),
            version: "v2",
            now: "2026-03-27T01:00:00Z",
            before_status: Some(TaskStatus::Open),
            ..Default::default()
        },
    )
    .expect_err("update must reject due_time without due_date");

    assert!(
        error.to_string().contains("due_time without due_date"),
        "unexpected validation error: {error}"
    );
}

#[test]
fn update_status_sets_transition_metadata() {
    let conn = setup();
    let create =
        TaskCreateParams::builder("t4", "Complete me", "open", "v1", "2026-03-27T00:00:00Z")
            .build()
            .unwrap();
    create_task(&conn, &create).unwrap();

    let patch = TaskUpdatePatch {
        task_id: "t4",
        status: Some(TaskStatus::Completed),
        version: "v2",
        now: "2026-03-27T10:00:00Z",
        before_status: Some(TaskStatus::Open),
        ..Default::default()
    };
    apply_task_update(&conn, &patch).unwrap();

    let completed_at: Option<String> = conn
        .query_row("SELECT completed_at FROM tasks WHERE id = 't4'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(completed_at.as_deref(), Some("2026-03-27T10:00:00Z"));
}

#[test]
fn update_status_requires_typed_before_status() {
    let conn = setup();
    let create = TaskCreateParams::builder(
        "missing-before-status",
        "Complete me",
        "open",
        "v1",
        "2026-03-27T00:00:00Z",
    )
    .build()
    .unwrap();
    create_task(&conn, &create).unwrap();

    let patch = TaskUpdatePatch {
        task_id: "missing-before-status",
        status: Some(TaskStatus::Completed),
        version: "v2",
        now: "2026-03-27T10:00:00Z",
        ..Default::default()
    };

    let err = apply_task_update(&conn, &patch)
        .expect_err("status updates must carry typed before_status");
    match err {
        StoreError::Invariant(message) => {
            assert!(message.contains("missing typed before_status"));
            assert!(message.contains("missing-before-status"));
        }
        other => panic!("expected invariant error, got {other:?}"),
    }

    let (status, completed_at): (String, Option<String>) = conn
        .query_row(
            "SELECT status, completed_at FROM tasks WHERE id = 'missing-before-status'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(status, "open");
    assert!(completed_at.is_none());
}

#[test]
fn update_clear_nullable_field() {
    let conn = setup();
    let create = TaskCreateParams::builder("t5", "Has body", "open", "v1", "2026-03-27T00:00:00Z")
        .body(Some("body content"))
        .build()
        .unwrap();
    create_task(&conn, &create).unwrap();

    // Clear body with Patch::Clear
    let patch = TaskUpdatePatch {
        task_id: "t5",
        body: Patch::Clear,
        version: "v2",
        now: "2026-03-27T01:00:00Z",
        before_status: Some(TaskStatus::Open),
        ..Default::default()
    };
    apply_task_update(&conn, &patch).unwrap();

    let body: Option<String> = conn
        .query_row("SELECT body FROM tasks WHERE id = 't5'", [], |r| r.get(0))
        .unwrap();
    assert!(body.is_none());
}

#[test]
fn duplicate_copies_fields_and_resets() {
    let conn = setup();
    let create = TaskCreateParams::builder(
        "src",
        "Source task",
        "completed",
        "v1",
        "2026-03-27T00:00:00Z",
    )
    .body(Some("body"))
    .ai_notes(Some("ai notes"))
    .priority(Some(3))
    .due_date(Some("2026-04-01"))
    .due_time(Some("09:00"))
    .estimated_minutes(Some(60))
    .recurrence(Some("daily"))
    .recurrence_group_id(Some("rg1"))
    .canonical_occurrence_date(Some("2026-04-01"))
    .build()
    .unwrap();
    create_task(&conn, &create).unwrap();

    // Mark the source as completed (so we can verify dup resets it)
    conn.execute(
        "UPDATE tasks SET completed_at = '2026-03-27T05:00:00Z' WHERE id = 'src'",
        [],
    )
    .unwrap();

    // Read source as TaskRow
    let source = crate::repositories::task::read::get_task(
        &conn,
        &lorvex_domain::TaskId::from_trusted("src".to_string()),
    )
    .unwrap()
    .unwrap();

    duplicate_task(
        &conn,
        &source,
        "dup",
        "Source task (copy)",
        Some("rg1"),
        Some("2026-04-01"),
        "v2",
        "2026-03-27T06:00:00Z",
    )
    .unwrap();

    let (status, completed_at, raw_input, defer_count): (
        String,
        Option<String>,
        Option<String>,
        i64,
    ) = conn
        .query_row(
            "SELECT status, completed_at, raw_input, defer_count FROM tasks WHERE id = 'dup'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
        )
        .unwrap();
    assert_eq!(status, "open");
    assert!(completed_at.is_none());
    assert!(raw_input.is_none());
    assert_eq!(defer_count, 0);

    // Verify copied fields
    let (title, body, priority): (String, Option<String>, Option<i64>) = conn
        .query_row(
            "SELECT title, body, priority FROM tasks WHERE id = 'dup'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .unwrap();
    assert_eq!(title, "Source task (copy)");
    assert_eq!(body.as_deref(), Some("body"));
    assert_eq!(priority, Some(3));
}

#[test]
fn update_rejects_clearing_list_id() {
    let conn = setup();
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('l1', 'Inbox', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-27T00:00:00Z', '2026-03-27T00:00:00Z')",
        [],
    )
    .unwrap();
    create_task(
        &conn,
        &TaskCreateParams::builder(
            "t6",
            "Keep classified",
            "open",
            "v1",
            "2026-03-27T00:00:00Z",
        )
        .list_id(Some("l1"))
        .build()
        .unwrap(),
    )
    .unwrap();

    let error = apply_task_update(
        &conn,
        &TaskUpdatePatch {
            task_id: "t6",
            list_id: Patch::Clear,
            version: "v2",
            now: "2026-03-27T01:00:00Z",
            before_status: Some(TaskStatus::Open),
            ..Default::default()
        },
    )
    .expect_err("clearing list_id should fail");

    assert!(error
        .to_string()
        .contains("tasks must belong to a real list"));
}

#[test]
fn update_task_sets_ai_notes_on_ai_notes_change() {
    let conn = setup();
    create_task(
        &conn,
        &TaskCreateParams::builder(
            "t-attr",
            "Attribution",
            "open",
            "v1",
            "2026-04-18T00:00:00Z",
        )
        .build()
        .unwrap(),
    )
    .unwrap();

    let patch = TaskUpdatePatch {
        task_id: "t-attr",
        ai_notes: Patch::Set("AI-authored note"),
        version: "v2",
        now: "2026-04-18T01:00:00Z",
        before_status: Some(TaskStatus::Open),
        ..Default::default()
    };
    apply_task_update(&conn, &patch).unwrap();

    let notes: Option<String> = conn
        .query_row("SELECT ai_notes FROM tasks WHERE id = 't-attr'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(notes.as_deref(), Some("AI-authored note"));
}

/// routing the trash transition through the canonical
/// patch must (a) emit an `archived_at = ?` SET clause when the
/// caller passes `Some(Some(ts))`, (b) emit `archived_at = NULL`
/// when the caller passes `Some(None)` (restore), and (c) leave the
/// column untouched when the field is `None` (skip). Direct row
/// readback is the cheapest way to assert all three behaviors —
/// inspecting the generated SQL would couple the test to the
/// internal SET-clause format.
#[test]
fn update_archived_at_round_trips_through_patch() {
    let conn = setup();
    create_task(
        &conn,
        &TaskCreateParams::builder("t-trash", "Trash me", "open", "v1", "2026-04-26T00:00:00Z")
            .build()
            .unwrap(),
    )
    .unwrap();

    // (a) Set archived_at — moves the task into Trash.
    apply_task_update(
        &conn,
        &TaskUpdatePatch {
            task_id: "t-trash",
            archived_at: Patch::Set("2026-04-26T01:00:00Z"),
            version: "v2",
            now: "2026-04-26T01:00:00Z",
            before_status: Some(TaskStatus::Open),
            ..Default::default()
        },
    )
    .unwrap();
    let archived: Option<String> = conn
        .query_row(
            "SELECT archived_at FROM tasks WHERE id = 't-trash'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(archived.as_deref(), Some("2026-04-26T01:00:00Z"));

    // (c) An unrelated patch must leave `archived_at` alone.
    apply_task_update(
        &conn,
        &TaskUpdatePatch {
            task_id: "t-trash",
            title: Some("Renamed in Trash"),
            version: "v3",
            now: "2026-04-26T02:00:00Z",
            before_status: Some(TaskStatus::Open),
            ..Default::default()
        },
    )
    .unwrap();
    let still_archived: Option<String> = conn
        .query_row(
            "SELECT archived_at FROM tasks WHERE id = 't-trash'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        still_archived.as_deref(),
        Some("2026-04-26T01:00:00Z"),
        "archived_at must not change when the field is not in the patch",
    );

    // (b) Clear archived_at — restores the task from Trash.
    apply_task_update(
        &conn,
        &TaskUpdatePatch {
            task_id: "t-trash",
            archived_at: Patch::Clear,
            version: "v4",
            now: "2026-04-26T03:00:00Z",
            before_status: Some(TaskStatus::Open),
            ..Default::default()
        },
    )
    .unwrap();
    let restored: Option<String> = conn
        .query_row(
            "SELECT archived_at FROM tasks WHERE id = 't-trash'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert!(restored.is_none());
}

#[test]
fn update_task_clears_ai_notes() {
    let conn = setup();
    create_task(
        &conn,
        &TaskCreateParams::builder("t-clear", "Clear", "open", "v1", "2026-04-18T00:00:00Z")
            .ai_notes(Some("Old note"))
            .build()
            .unwrap(),
    )
    .unwrap();

    let patch = TaskUpdatePatch {
        task_id: "t-clear",
        ai_notes: Patch::Clear,
        version: "v2",
        now: "2026-04-18T01:00:00Z",
        before_status: Some(TaskStatus::Open),
        ..Default::default()
    };
    apply_task_update(&conn, &patch).unwrap();

    let notes: Option<String> = conn
        .query_row("SELECT ai_notes FROM tasks WHERE id = 't-clear'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert!(notes.is_none());
}
