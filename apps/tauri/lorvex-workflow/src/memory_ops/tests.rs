use super::*;
use lorvex_store::open_db_in_memory;
use serde_json::json;

fn setup() -> rusqlite::Connection {
    open_db_in_memory().unwrap()
}

#[test]
fn upsert_creates_memory_and_revision() {
    let conn = setup();
    let result = upsert_memory_entry(
        &conn,
        "user_profile",
        "likes coffee",
        "ai",
        "v1",
        "2026-03-27T10:00:00Z",
    )
    .unwrap()
    .expect("fresh insert must report Some");
    assert_eq!(result.memory_key, "user_profile");

    // Verify memories row
    let (content, version, updated_at): (String, String, String) = conn
        .query_row(
            "SELECT content, version, updated_at FROM memories WHERE key = 'user_profile'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(content, "likes coffee");
    assert_eq!(version, "v1");
    assert_eq!(updated_at, "2026-03-27T10:00:00Z");

    // Verify memory_revisions row
    let (rev_key, rev_content, rev_op, rev_actor): (String, Option<String>, String, String) = conn
        .query_row(
            "SELECT memory_key, content, operation, actor FROM memory_revisions WHERE id = ?1",
            [&result.revision_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .unwrap();
    assert_eq!(rev_key, "user_profile");
    assert_eq!(rev_content.as_deref(), Some("likes coffee"));
    assert_eq!(rev_op, "upsert");
    assert_eq!(rev_actor, "ai");
}

#[test]
fn upsert_updates_existing() {
    let conn = setup();
    upsert_memory_entry(
        &conn,
        "user_profile",
        "likes coffee",
        "ai",
        "v1",
        "2026-03-27T10:00:00Z",
    )
    .unwrap();
    upsert_memory_entry(
        &conn,
        "user_profile",
        "likes tea now",
        "ai",
        "v2",
        "2026-03-27T11:00:00Z",
    )
    .unwrap();

    // Memories row has updated content
    let content: String = conn
        .query_row(
            "SELECT content FROM memories WHERE key = 'user_profile'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(content, "likes tea now");

    // Two revisions exist
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memory_revisions WHERE memory_key = 'user_profile'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 2);
}

#[test]
fn delete_removes_and_appends_revision() {
    let conn = setup();
    upsert_memory_entry(
        &conn,
        "user_profile",
        "some content",
        "ai",
        "v1",
        "2026-03-27T10:00:00Z",
    )
    .unwrap();
    let del = delete_memory_entry(&conn, "user_profile", "ai", "v2", "2026-03-27T11:00:00Z")
        .unwrap()
        .expect("delete revision should be returned for existing key");
    assert_eq!(del.memory_key, "user_profile");
    assert_eq!(
        del.pre_delete_payload,
        Some(json!({
            "key": "user_profile",
            "content": "some content",
            "version": "v1",
            "updated_at": "2026-03-27T10:00:00Z",
        }))
    );

    // Memories row gone
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memories WHERE key = 'user_profile'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 0);

    // Delete revision exists with operation="delete" and content=NULL
    let (op, content): (String, Option<String>) = conn
        .query_row(
            "SELECT operation, content FROM memory_revisions WHERE id = ?1",
            [&del.revision_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(op, "delete");
    assert!(content.is_none());
}

/// deleting a non-existent key MUST return None
/// rather than fabricating a revision_id for a row that was
/// never inserted.
#[test]
fn delete_returns_none_when_key_missing() {
    let conn = setup();
    let result =
        delete_memory_entry(&conn, "never_existed", "ai", "v1", "2026-03-27T10:00:00Z").unwrap();
    assert!(
        result.is_none(),
        "delete of missing key must return None (no fabricated revision_id)"
    );
    // No revision row was appended.
    let revs: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memory_revisions WHERE memory_key = 'never_existed'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(revs, 0);
}

#[test]
fn restore_from_past_revision() {
    let conn = setup();
    let created = upsert_memory_entry(
        &conn,
        "user_profile",
        "original",
        "ai",
        "v1",
        "2026-03-27T10:00:00Z",
    )
    .unwrap()
    .expect("fresh insert must report Some");
    delete_memory_entry(&conn, "user_profile", "ai", "v2", "2026-03-27T11:00:00Z").unwrap();

    // Restore from the upsert revision
    let restored = restore_memory_revision(
        &conn,
        &created.revision_id,
        "human",
        "v3",
        "2026-03-27T12:00:00Z",
    )
    .unwrap()
    .expect("post-delete restore must report Some");
    assert_eq!(restored.memory_key, "user_profile");

    // Memories row is back
    let content: String = conn
        .query_row(
            "SELECT content FROM memories WHERE key = 'user_profile'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(content, "original");

    // Restore revision exists with operation="restore"
    let (op, source_rev): (String, Option<String>) = conn
        .query_row(
            "SELECT operation, source_revision_id FROM memory_revisions WHERE id = ?1",
            [&restored.revision_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(op, "restore");
    assert_eq!(source_rev.as_deref(), Some(created.revision_id.as_str()));
}

#[test]
fn restore_from_delete_revision_fails() {
    let conn = setup();
    upsert_memory_entry(
        &conn,
        "user_profile",
        "content",
        "ai",
        "v1",
        "2026-03-27T10:00:00Z",
    )
    .unwrap();
    let del = delete_memory_entry(&conn, "user_profile", "ai", "v2", "2026-03-27T11:00:00Z")
        .unwrap()
        .expect("delete revision should be returned for existing key");

    let err = restore_memory_revision(
        &conn,
        &del.revision_id,
        "human",
        "v3",
        "2026-03-27T12:00:00Z",
    );
    assert!(err.is_err());
    let msg = format!("{}", err.unwrap_err());
    assert!(
        msg.contains("cannot restore from a delete revision"),
        "unexpected error: {msg}"
    );
}

/// a stale-version upsert MUST NOT clobber a
/// newer-version row, AND MUST NOT append a phantom revision row
/// claiming the stale content was written.
#[test]
fn upsert_rejects_stale_version_and_skips_revision() {
    let conn = setup();
    // Seed at v2.
    upsert_memory_entry(
        &conn,
        "user_profile",
        "newer remote write",
        "ai",
        "v2",
        "2026-03-27T11:00:00Z",
    )
    .unwrap()
    .expect("fresh insert must report Some");
    let revisions_before: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memory_revisions WHERE memory_key = 'user_profile'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(revisions_before, 1);

    // Stale write at v1 must be a no-op.
    let result = upsert_memory_entry(
        &conn,
        "user_profile",
        "stale local clobber",
        "ai",
        "v1",
        "2026-03-26T00:00:00Z",
    )
    .unwrap();
    assert!(
        result.is_none(),
        "stale-version upsert must report None (no row written)"
    );

    // Memories row untouched.
    let (content, version): (String, String) = conn
        .query_row(
            "SELECT content, version FROM memories WHERE key = 'user_profile'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(content, "newer remote write");
    assert_eq!(version, "v2");

    // No phantom revision was appended.
    let revisions_after: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memory_revisions WHERE memory_key = 'user_profile'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        revisions_after, revisions_before,
        "stale upsert must not append a revision"
    );
}

/// a stale-version delete MUST NOT clobber a
/// newer-version row, AND MUST NOT append a phantom delete revision.
/// Mirrors `upsert_rejects_stale_version_and_skips_revision` —
/// delete and upsert share the same LWW envelope contract.
#[test]
fn delete_rejects_stale_version_and_skips_revision() {
    let conn = setup();
    // Peer wrote at v5.
    upsert_memory_entry(
        &conn,
        "user_profile",
        "peer wrote v5",
        "ai",
        "v5",
        "2026-03-27T15:00:00Z",
    )
    .unwrap()
    .expect("v5 insert must report Some");
    let revisions_before: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memory_revisions WHERE memory_key = 'user_profile'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(revisions_before, 1);

    // Stale local replays delete at v3 — must be rejected.
    let result =
        delete_memory_entry(&conn, "user_profile", "ai", "v3", "2026-03-26T00:00:00Z").unwrap();
    assert!(
        result.is_none(),
        "stale-version delete must report None (no row removed)"
    );

    // Memories row untouched.
    let (content, version): (String, String) = conn
        .query_row(
            "SELECT content, version FROM memories WHERE key = 'user_profile'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(content, "peer wrote v5");
    assert_eq!(version, "v5");

    // No phantom delete revision was appended.
    let revisions_after: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memory_revisions WHERE memory_key = 'user_profile'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        revisions_after, revisions_before,
        "stale delete must not append a revision"
    );
}

/// same gate applies to the `restore_memory_revision`
/// UPDATE arm. A stale stamp must not clobber a newer row, and the
/// "restore" revision must not be appended.
#[test]
fn restore_rejects_stale_version_and_skips_revision() {
    let conn = setup();
    // Capture a v1 revision we can later try to restore from.
    let v1 = upsert_memory_entry(
        &conn,
        "user_profile",
        "v1 content",
        "ai",
        "v1",
        "2026-03-27T10:00:00Z",
    )
    .unwrap()
    .expect("v1 insert must report Some");
    // A newer remote write lands at v3.
    upsert_memory_entry(
        &conn,
        "user_profile",
        "newer remote write",
        "ai",
        "v3",
        "2026-03-27T12:00:00Z",
    )
    .unwrap()
    .expect("v3 update must report Some");
    let revisions_before: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memory_revisions WHERE memory_key = 'user_profile'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(revisions_before, 2);

    // Attempt to restore at stale v2 — must be rejected.
    let result = restore_memory_revision(
        &conn,
        &v1.revision_id,
        "human",
        "v2",
        "2026-03-27T11:30:00Z",
    )
    .unwrap();
    assert!(
        result.is_none(),
        "stale-version restore must report None (no row written)"
    );

    let (content, version): (String, String) = conn
        .query_row(
            "SELECT content, version FROM memories WHERE key = 'user_profile'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(content, "newer remote write");
    assert_eq!(version, "v3");

    let revisions_after: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memory_revisions WHERE memory_key = 'user_profile'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        revisions_after, revisions_before,
        "stale restore must not append a revision"
    );
}
