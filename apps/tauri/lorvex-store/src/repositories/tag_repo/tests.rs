use super::*;
use crate::test_support::test_conn;
use lorvex_domain::TagId;

fn tagid(id: &str) -> TagId {
    TagId::from_trusted(id.to_string())
}

// -- resolve_or_create_tag --

#[test]
fn create_tag_generates_uuidv7_and_computes_lookup_key() {
    let conn = test_conn();
    let (id, created) =
        resolve_or_create_tag(&conn, "Work", "v1", "2026-01-01T00:00:00.000Z").unwrap();
    assert!(created, "should report newly created");
    // ID should be a valid UUID (36 chars, 4 dashes).
    assert_eq!(id.len(), 36);
    assert_eq!(id.chars().filter(|&c| c == '-').count(), 4);

    // Verify the stored lookup_key is normalized.
    let tag = get_tag_by_name(&conn, "work").unwrap().unwrap();
    assert_eq!(tag.display_name, "Work");
    assert_eq!(tag.lookup_key, "work");
    assert_eq!(tag.version, "v1");
}

#[test]
fn resolve_or_create_finds_existing() {
    let conn = test_conn();
    let (id1, created1) =
        resolve_or_create_tag(&conn, "Home", "v1", "2026-01-01T00:00:00.000Z").unwrap();
    assert!(created1);
    let (id2, created2) =
        resolve_or_create_tag(&conn, "home", "v2", "2026-01-01T00:00:00.000Z").unwrap();
    assert!(!created2, "should find existing tag");
    assert_eq!(id1, id2, "should return the same tag ID");
}

#[test]
fn resolve_or_create_different_names_create_different_tags() {
    let conn = test_conn();
    let (id1, _) = resolve_or_create_tag(&conn, "Work", "v1", "2026-01-01T00:00:00.000Z").unwrap();
    let (id2, _) = resolve_or_create_tag(&conn, "Home", "v1", "2026-01-01T00:00:00.000Z").unwrap();
    assert_ne!(id1, id2);
}

// -- get_tag_by_name --

#[test]
fn get_tag_by_name_is_case_insensitive() {
    let conn = test_conn();
    resolve_or_create_tag(&conn, "Urgent", "v1", "2026-01-01T00:00:00.000Z").unwrap();

    // All case variants should find the same tag.
    assert!(get_tag_by_name(&conn, "urgent").unwrap().is_some());
    assert!(get_tag_by_name(&conn, "URGENT").unwrap().is_some());
    assert!(get_tag_by_name(&conn, "Urgent").unwrap().is_some());
    assert!(get_tag_by_name(&conn, "uRgEnT").unwrap().is_some());
}

#[test]
fn get_tag_by_name_returns_none_when_absent() {
    let conn = test_conn();
    assert!(get_tag_by_name(&conn, "nonexistent").unwrap().is_none());
}

// -- rename_tag --

#[test]
fn rename_updates_display_name_and_lookup_key() {
    let conn = test_conn();
    let (id, _) =
        resolve_or_create_tag(&conn, "Groceries", "v1", "2026-01-01T00:00:00.000Z").unwrap();

    rename_tag(
        &conn,
        &tagid(&id),
        "Shopping",
        "v2",
        "2026-01-01T00:00:00.000Z",
    )
    .unwrap();

    // Old name should no longer resolve via current lookup.
    assert!(get_tag_by_name(&conn, "Groceries").unwrap().is_none());
    // New name should resolve.
    let tag = get_tag_by_name(&conn, "Shopping").unwrap().unwrap();
    assert_eq!(tag.display_name, "Shopping");
    assert_eq!(tag.lookup_key, "shopping");
    assert_eq!(tag.version, "v2");
}

#[test]
fn rename_same_normalized_key_updates_display_only() {
    let conn = test_conn();
    let (id, _) = resolve_or_create_tag(&conn, "work", "v1", "2026-01-01T00:00:00.000Z").unwrap();
    rename_tag(&conn, &tagid(&id), "Work", "v2", "2026-01-01T00:00:00.000Z").unwrap();
    let tag = get_tag_by_name(&conn, "work").unwrap().unwrap();
    assert_eq!(tag.display_name, "Work");
}

#[test]
fn rename_nonexistent_tag_returns_error() {
    let conn = test_conn();
    let result = rename_tag(
        &conn,
        &tagid("nonexistent-id"),
        "NewName",
        "v1",
        "2026-01-01T00:00:00.000Z",
    );
    assert!(matches!(result, Err(StoreError::NotFound { .. })));
}

#[test]
fn rename_with_stale_version_returns_stale_version_error() {
    // a no-op caused by `?version > version` losing
    // the LWW gate must surface as `StoreError::StaleVersion` so the
    // response payload reflects the cluster's truth, not a silent
    // success that lies about the post-state.
    let conn = test_conn();
    let (id, _) =
        resolve_or_create_tag(&conn, "Original", "v9", "2026-01-01T00:00:00.000Z").unwrap();

    let result = rename_tag(
        &conn,
        &tagid(&id),
        "Stale",
        "v1",
        "2026-01-01T00:00:00.000Z",
    );
    match result {
        Err(StoreError::StaleVersion { entity, id: tag_id }) => {
            assert_eq!(entity, ENTITY_TAG);
            assert_eq!(tag_id, id);
        }
        other => panic!("expected StoreError::StaleVersion, got {other:?}"),
    }

    // The row's display_name must still reflect the canonical state.
    let tag = get_tag_by_name(&conn, "Original").unwrap().unwrap();
    assert_eq!(tag.version, "v9");
}

// -- CJK and emoji --

#[test]
fn create_cjk_tag() {
    let conn = test_conn();
    let (id, created) =
        resolve_or_create_tag(&conn, "工作", "v1", "2026-01-01T00:00:00.000Z").unwrap();
    assert!(created);

    let tag = get_tag_by_name(&conn, "工作").unwrap().unwrap();
    assert_eq!(tag.id, id);
    assert_eq!(tag.display_name, "工作");
    assert_eq!(tag.lookup_key, "工作");
}

#[test]
fn create_emoji_tag() {
    let conn = test_conn();
    let (id, created) =
        resolve_or_create_tag(&conn, "🏠 Home", "v1", "2026-01-01T00:00:00.000Z").unwrap();
    assert!(created);

    let tag = get_tag_by_name(&conn, "🏠 home").unwrap().unwrap();
    assert_eq!(tag.id, id);
    assert_eq!(tag.display_name, "🏠 Home");
}

// -- Sequential rename chain --

#[test]
fn rename_chain_preserves_history() {
    let conn = test_conn();
    let (id, _) = resolve_or_create_tag(&conn, "Alpha", "v1", "2026-01-01T00:00:00.000Z").unwrap();

    rename_tag(&conn, &tagid(&id), "Beta", "v2", "2026-01-01T00:00:00.000Z").unwrap();
    rename_tag(
        &conn,
        &tagid(&id),
        "Gamma",
        "v3",
        "2026-01-01T00:00:00.000Z",
    )
    .unwrap();

    // Current name resolves normally through get_tag_by_name.
    let tag = get_tag_by_name(&conn, "Gamma").unwrap().unwrap();
    assert_eq!(tag.id, id);
}

#[test]
fn tag_from_row_rejects_null_display_name() {
    let conn = test_conn();
    let result = conn.query_row(
        "SELECT 'tag-1', NULL, 'work', NULL, '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z', NULL",
        [],
        tag_from_row,
    );
    assert!(
        result.is_err(),
        "null display_name should not coerce to empty string"
    );
}

#[test]
fn tag_from_row_rejects_null_lookup_key() {
    let conn = test_conn();
    let result = conn.query_row(
        "SELECT 'tag-1', 'Work', NULL, NULL, '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z', NULL",
        [],
        tag_from_row,
    );
    assert!(
        result.is_err(),
        "null lookup_key should not coerce to empty string"
    );
}
