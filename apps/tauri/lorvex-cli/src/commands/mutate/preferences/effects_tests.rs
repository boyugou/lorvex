use super::effects::*;
use lorvex_domain::naming::{ENTITY_PREFERENCE, OP_DELETE, OP_UPSERT};
use rusqlite::OptionalExtension;

#[test]
fn preference_mutations_write_sync_outbox_and_changelog() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    let created =
        set_preference_with_conn(&mut conn, "weekly_review_day", "1").expect("set preference");
    assert_eq!(created.key, "weekly_review_day");
    assert_eq!(created.value, serde_json::json!(1));
    assert_eq!(created.operation, "create");

    let stored: String = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = 'weekly_review_day'",
            [],
            |row| row.get(0),
        )
        .expect("load preference");
    assert_eq!(stored, "1");

    let outbox_payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = 'weekly_review_day' AND operation = ?2
             ORDER BY id DESC LIMIT 1",
            [ENTITY_PREFERENCE, OP_UPSERT],
            |row| row.get(0),
        )
        .expect("load preference outbox payload");
    let outbox_payload: serde_json::Value =
        serde_json::from_str(&outbox_payload).expect("parse outbox payload");
    assert_eq!(outbox_payload["value"], serde_json::json!(1));
    assert_eq!(
        outbox_payload["version"],
        serde_json::json!(created.version)
    );

    let updated = set_preference_with_conn(&mut conn, "weekly_review_day", r#"{"enabled":true}"#)
        .expect("update preference");
    assert_eq!(updated.operation, "update");
    assert_eq!(updated.value, serde_json::json!({"enabled": true}));

    let deleted =
        delete_preference_with_conn(&mut conn, "weekly_review_day").expect("delete preference");
    assert!(deleted.deleted);
    let missing: Option<String> = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = 'weekly_review_day'",
            [],
            |row| row.get(0),
        )
        .optional()
        .expect("load deleted preference");
    assert!(missing.is_none());

    let delete_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = 'weekly_review_day' AND operation = ?2",
            [ENTITY_PREFERENCE, OP_DELETE],
            |row| row.get(0),
        )
        .expect("count preference delete outbox");
    assert_eq!(delete_outbox_count, 1);

    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog
             WHERE entity_type = ?1 AND entity_id = 'weekly_review_day'",
            [ENTITY_PREFERENCE],
            |row| row.get(0),
        )
        .expect("count preference changelog");
    assert_eq!(changelog_count, 3);
}

#[test]
fn preference_mutations_reject_forbidden_and_malformed_values() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    let forbidden = set_preference_with_conn(
        &mut conn,
        lorvex_domain::preference_keys::PREF_TIMEZONE,
        r#""UTC""#,
    )
    .expect_err("timezone must be user-scoped");
    assert!(forbidden.to_string().contains("user-scope only"));

    let malformed = set_preference_with_conn(&mut conn, "weekly_review_day", "not-json")
        .expect_err("malformed JSON should fail");
    assert!(malformed.to_string().contains("valid JSON"));
}
