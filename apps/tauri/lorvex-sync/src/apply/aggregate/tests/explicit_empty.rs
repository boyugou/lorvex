use super::super::apply_task_upsert;
use super::super::helpers::optional_str_preserving_empty;
use super::support::*;
use rusqlite::OptionalExtension;
use serde_json::json;

fn task_payload_with_body(body: serde_json::Value, list_id: &str) -> String {
    json!({
        "title": "Research notes",
        "body": body,
        "status": "open",
        "list_id": list_id,
        "defer_count": 0,
        "created_at": "2026-03-23T12:00:00.000Z",
        "updated_at": "2026-03-23T12:00:00.000Z",
    })
    .to_string()
}

fn task_payload_without_body(list_id: &str) -> String {
    json!({
        "title": "Research notes",
        "status": "open",
        "list_id": list_id,
        "defer_count": 0,
        "created_at": "2026-03-23T12:00:00.000Z",
        "updated_at": "2026-03-23T12:00:00.000Z",
    })
    .to_string()
}

#[test]
fn explicit_empty_body_is_applied_as_sql_null_clear() {
    // A peer sends body="old text" first, then another envelope with
    // body="" (user cleared the field). The second envelope must
    // land as SQL NULL — previously `optional_str` collapsed "" to
    // "absent" which, combined with the UPSERT SET clause, still
    // wrote NULL but hid the *intent*. This test pins the clear
    // semantic so any future partial-update strategy keeps it.
    let conn = test_db();
    let list_id = lorvex_store::INBOX_LIST_ID;
    seed_list(&conn, list_id);

    // First: body has real content.
    apply_task_upsert(
        &conn,
        "task-2308-body",
        &task_payload_with_body(json!("old text"), list_id),
        &next_version(),
        false.into(),
        "",
    )
    .unwrap();
    let initial: Option<String> = conn
        .query_row(
            "SELECT body FROM tasks WHERE id = 'task-2308-body'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(initial.as_deref(), Some("old text"));

    // Second: explicit empty body as a user-driven clear.
    apply_task_upsert(
        &conn,
        "task-2308-body",
        &task_payload_with_body(json!(""), list_id),
        &next_version(),
        false.into(),
        "",
    )
    .unwrap();
    let cleared: Option<String> = conn
        .query_row(
            "SELECT body FROM tasks WHERE id = 'task-2308-body'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert!(
        cleared.is_none(),
        "explicit empty body must round-trip as SQL NULL, got {cleared:?}"
    );
}

#[test]
fn explicit_empty_tag_color_is_applied_as_sql_null_clear() {
    // A tag originally has color="#abcdef"; a second envelope
    // carries color="" meaning "reset to default palette". The
    // stored row must land as SQL NULL so peers render the default
    // color rather than hanging onto the stale hex.
    let conn = test_db();

    let payload_with_color = json!({
        "display_name": "focus",
        "color": "#abcdef",
        "created_at": "2026-03-23T12:00:00.000Z",
        "updated_at": "2026-03-23T12:00:00.000Z",
    })
    .to_string();
    crate::apply::tag::apply_tag_upsert(
        &conn,
        "tag-2308",
        &payload_with_color,
        &next_version(),
        false.into(),
        "",
    )
    .unwrap();
    let initial: Option<String> = conn
        .query_row("SELECT color FROM tags WHERE id = 'tag-2308'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(initial.as_deref(), Some("#abcdef"));

    let payload_cleared = json!({
        "display_name": "focus",
        "color": "",
        "created_at": "2026-03-23T12:00:00.000Z",
        "updated_at": "2026-03-23T12:00:00.000Z",
    })
    .to_string();
    crate::apply::tag::apply_tag_upsert(
        &conn,
        "tag-2308",
        &payload_cleared,
        &next_version(),
        false.into(),
        "",
    )
    .unwrap();
    let cleared: Option<String> = conn
        .query_row("SELECT color FROM tags WHERE id = 'tag-2308'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert!(
        cleared.is_none(),
        "explicit empty tag.color must round-trip as SQL NULL, got {cleared:?}"
    );
}

#[test]
fn absent_body_key_is_treated_as_null_no_op_merge() {
    // An envelope that simply omits the `body` key carries no
    // intent for the column. The current schema-driven UPSERT still
    // writes NULL (nothing to cite as "preserve" yet), but the test
    // documents that the tri-state helper returns `Ok(None)` for
    // absent and the caller collapses that to NULL — *not* to an
    // empty string, and not into a special sentinel that would
    // confuse downstream readers.
    let conn = test_db();
    let list_id = lorvex_store::INBOX_LIST_ID;
    seed_list(&conn, list_id);

    apply_task_upsert(
        &conn,
        "task-2308-absent",
        &task_payload_without_body(list_id),
        &next_version(),
        false.into(),
        "",
    )
    .unwrap();
    let stored: Option<String> = conn
        .query_row(
            "SELECT body FROM tasks WHERE id = 'task-2308-absent'",
            [],
            |r| r.get(0),
        )
        .optional()
        .unwrap()
        .flatten();
    assert!(
        stored.is_none(),
        "absent body key must store SQL NULL, got {stored:?}"
    );

    // And the direct helper call confirms the tri-state value.
    let val: serde_json::Value = serde_json::from_str(&task_payload_without_body(list_id)).unwrap();
    let tri = optional_str_preserving_empty(&val, "body", "task").unwrap();
    assert_eq!(
        tri,
        lorvex_domain::Patch::Unset,
        "absent key must yield Patch::Unset from the helper"
    );
}
