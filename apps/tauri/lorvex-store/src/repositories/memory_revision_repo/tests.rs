use super::{append_revision, get_revision, get_revisions_for_key};
use crate::test_support::test_conn;
use lorvex_domain::{MemoryKey, MemoryRevisionId};

fn mrid(id: &str) -> MemoryRevisionId {
    MemoryRevisionId::from_trusted(id.to_string())
}
fn mkey(k: &str) -> MemoryKey {
    MemoryKey::from_trusted(k.to_string())
}

const ACTOR: &str = "ai";

fn ts(ms: u64) -> String {
    // Canonical millisecond-Z form, in lockstep with `SyncTimestamp`.
    let secs = ms / 1000;
    let frac = ms % 1000;
    format!("2026-05-03T00:00:{secs:02}.{frac:03}Z")
}

#[test]
fn append_then_get_revision_round_trips_every_field() {
    let conn = test_conn();
    append_revision(
        &conn,
        &mrid("rev-1"),
        &mkey("user_profile"),
        Some("hello world"),
        "upsert",
        Some(&mrid("rev-0")),
        ACTOR,
        "v1",
        &ts(1),
    )
    .expect("append");

    let row = get_revision(&conn, "rev-1").expect("get").expect("present");
    assert_eq!(row.id, "rev-1");
    assert_eq!(row.memory_key, "user_profile");
    assert_eq!(row.content.as_deref(), Some("hello world"));
    assert_eq!(row.operation, "upsert");
    assert_eq!(row.source_revision_id.as_deref(), Some("rev-0"));
    assert_eq!(row.actor, ACTOR);
    assert_eq!(row.version, "v1");
    // `SyncTimestamp` canonicalizes to ms-Z; the stored input was
    // already canonical so the round trip is byte-stable.
    assert_eq!(row.created_at.as_string(), ts(1));
}

#[test]
fn null_content_and_null_source_revision_are_preserved() {
    // Delete operations historically wrote `content = NULL`; the
    // serializer must distinguish "no content" from `Some("")`.
    let conn = test_conn();
    append_revision(
        &conn,
        &mrid("rev-del"),
        &mkey("ephemeral_key"),
        None,
        "delete",
        None,
        ACTOR,
        "v2",
        &ts(2),
    )
    .expect("append");

    let row = get_revision(&conn, "rev-del")
        .expect("get")
        .expect("present");
    assert!(row.content.is_none());
    assert!(row.source_revision_id.is_none());
    assert_eq!(row.operation, "delete");
}

#[test]
fn get_revision_returns_none_for_unknown_id() {
    let conn = test_conn();
    let result = get_revision(&conn, "rev-nope").expect("get");
    assert!(result.is_none());
}

#[test]
fn get_revisions_for_key_orders_most_recent_first() {
    let conn = test_conn();
    // Append in chronological order; `get_revisions_for_key` returns
    // newest-first via `ORDER BY created_at DESC`.
    append_revision(
        &conn,
        &mrid("rev-1"),
        &mkey("k"),
        Some("first"),
        "upsert",
        None,
        ACTOR,
        "v1",
        &ts(1),
    )
    .unwrap();
    append_revision(
        &conn,
        &mrid("rev-2"),
        &mkey("k"),
        Some("second"),
        "upsert",
        None,
        ACTOR,
        "v2",
        &ts(2),
    )
    .unwrap();
    append_revision(
        &conn,
        &mrid("rev-3"),
        &mkey("k"),
        Some("third"),
        "upsert",
        None,
        ACTOR,
        "v3",
        &ts(3),
    )
    .unwrap();

    let rows = get_revisions_for_key(&conn, &mkey("k"), 10).expect("list");
    let ids: Vec<&str> = rows.iter().map(|r| r.id.as_str()).collect();
    assert_eq!(ids, vec!["rev-3", "rev-2", "rev-1"]);
}

#[test]
fn get_revisions_for_key_uses_id_asc_tiebreaker_within_same_timestamp() {
    // A batch import that stamps multiple appends with the same `now`
    // would otherwise return rows in an arbitrary order, breaking
    // OFFSET pagination across pages. The repo's ORDER BY is
    // `created_at DESC, id ASC` — within the same timestamp the
    // smaller id wins (UUIDv7 is monotonic, so "first append wins").
    let conn = test_conn();
    let same_ts = ts(5);
    append_revision(
        &conn,
        &mrid("rev-aaa"),
        &mkey("k"),
        Some("alpha"),
        "upsert",
        None,
        ACTOR,
        "v1",
        &same_ts,
    )
    .unwrap();
    append_revision(
        &conn,
        &mrid("rev-bbb"),
        &mkey("k"),
        Some("beta"),
        "upsert",
        None,
        ACTOR,
        "v2",
        &same_ts,
    )
    .unwrap();
    append_revision(
        &conn,
        &mrid("rev-ccc"),
        &mkey("k"),
        Some("gamma"),
        "upsert",
        None,
        ACTOR,
        "v3",
        &same_ts,
    )
    .unwrap();

    let rows = get_revisions_for_key(&conn, &mkey("k"), 10).expect("list");
    let ids: Vec<&str> = rows.iter().map(|r| r.id.as_str()).collect();
    // All three have the same `created_at`, so they tie under the
    // DESC sort and the ASC id tiebreaker fires.
    assert_eq!(ids, vec!["rev-aaa", "rev-bbb", "rev-ccc"]);
}

#[test]
fn get_revisions_for_key_respects_limit() {
    let conn = test_conn();
    for i in 0..5 {
        append_revision(
            &conn,
            &mrid(&format!("rev-{i}")),
            &mkey("k"),
            Some("x"),
            "upsert",
            None,
            ACTOR,
            &format!("v{i}"),
            &ts(i),
        )
        .unwrap();
    }
    let rows = get_revisions_for_key(&conn, &mkey("k"), 2).expect("list");
    assert_eq!(rows.len(), 2);
}

#[test]
fn get_revisions_for_key_isolates_keys() {
    let conn = test_conn();
    append_revision(
        &conn,
        &mrid("a-1"),
        &mkey("key-A"),
        Some("for A"),
        "upsert",
        None,
        ACTOR,
        "v1",
        &ts(1),
    )
    .unwrap();
    append_revision(
        &conn,
        &mrid("b-1"),
        &mkey("key-B"),
        Some("for B"),
        "upsert",
        None,
        ACTOR,
        "v2",
        &ts(2),
    )
    .unwrap();

    let only_a = get_revisions_for_key(&conn, &mkey("key-A"), 10).expect("list");
    assert_eq!(only_a.len(), 1);
    assert_eq!(only_a[0].id, "a-1");
}

#[test]
fn get_revisions_for_key_returns_empty_for_unknown_key() {
    let conn = test_conn();
    let rows = get_revisions_for_key(&conn, &mkey("key-no-such"), 10).expect("list");
    assert!(rows.is_empty());
}
