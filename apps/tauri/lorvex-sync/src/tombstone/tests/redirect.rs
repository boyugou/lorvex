//! Redirect-tombstone semantics: validate the `redirect_entity_*`
//! shape, reject the structurally nonsensical same-type self-redirect,
//! and accept a cross-type same-id redirect (legitimate cross-type
//! merge).

use super::support::*;

#[test]
fn create_tombstone_with_redirect() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "tag-loser",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2026-03-23T12:00:00.000Z",
        Some("tag-winner"),
        Some(naming::ENTITY_TAG),
    )
    .unwrap();

    let ts = get_tombstone(&conn, naming::ENTITY_TAG, "tag-loser")
        .unwrap()
        .expect("tombstone should exist");

    assert_eq!(ts.redirect_entity_id.as_deref(), Some("tag-winner"));
    assert_eq!(ts.redirect_entity_type.as_deref(), Some(naming::ENTITY_TAG));
}

/// a same-type, same-id self-redirect is a structurally
/// nonsensical merge ("X redirects to itself") and is rejected at the
/// primitive entry point so the apply pipeline never observes a row
/// it would have to treat as a one-hop redirect cycle. Cross-type
/// "self" redirects (different entity_type with the same id) remain
/// permitted because the tuple identity differs.
#[test]
fn create_tombstone_rejects_self_redirect() {
    let conn = test_db();

    let result = create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "tag-self",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2026-03-23T12:00:00.000Z",
        Some("tag-self"),
        Some(naming::ENTITY_TAG),
    );

    let err = result.expect_err("self-redirect must be rejected");
    match err {
        lorvex_store::StoreError::Validation(msg) => {
            assert!(
                msg.contains("self-redirect"),
                "expected self-redirect rejection, got: {msg}"
            );
        }
        other => panic!("expected Validation error, got {other:?}"),
    }

    // The bad shape must NOT have landed in the table.
    let stored = get_tombstone(&conn, naming::ENTITY_TAG, "tag-self").unwrap();
    assert!(stored.is_none(), "self-redirect must not be persisted");
}

/// same-id but cross-type redirects are valid because
/// the tombstone composite key includes `entity_type`; the redirect
/// chase in `apply/mod.rs::follow_redirect_chain` honours type as
/// part of the lookup key, so this is a real one-hop cross-type
/// merge rather than a cycle.
#[test]
fn create_tombstone_allows_cross_type_same_id_redirect() {
    let conn = test_db();

    // Calling with `entity_type` differing from `redirect_entity_type`
    // is the expected shape for a cross-type merge. The same `id`
    // string on both sides is a coincidence we must not reject.
    let result = create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "shared-id",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2026-03-23T12:00:00.000Z",
        Some("shared-id"),
        Some(naming::ENTITY_HABIT),
    );
    assert!(
        result.is_ok(),
        "cross-type same-id redirect must be allowed"
    );

    let stored = get_tombstone(&conn, naming::ENTITY_TASK, "shared-id")
        .unwrap()
        .expect("tombstone should exist");
    assert_eq!(stored.redirect_entity_id.as_deref(), Some("shared-id"));
    assert_eq!(
        stored.redirect_entity_type.as_deref(),
        Some(naming::ENTITY_HABIT)
    );
}
