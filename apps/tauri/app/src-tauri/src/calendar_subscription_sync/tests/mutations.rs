use super::*;

fn subscription_outbox_row(
    conn: &rusqlite::Connection,
    id: &str,
) -> (String, String, serde_json::Value) {
    let (operation, version, payload_raw): (String, String, String) = conn
        .query_row(
            "SELECT operation, version, payload FROM sync_outbox
             WHERE entity_type = 'calendar_subscription' AND entity_id = ?1",
            params![id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("load subscription outbox row");
    (
        operation,
        version,
        serde_json::from_str(&payload_raw).expect("payload json"),
    )
}

fn subscription_version(conn: &rusqlite::Connection, id: &str) -> String {
    conn.query_row(
        "SELECT version FROM calendar_subscriptions WHERE id = ?1",
        params![id],
        |row| row.get(0),
    )
    .expect("load subscription version")
}

// IPC test coverage for `add_calendar_subscription`
// and `toggle_calendar_subscription`. These mutate the
// `calendar_subscriptions` table directly; the `_with_conn` shims
// run the production SQL against an in-memory DB.
// ──────────────────────────────────────────────────────────────────

#[test]
fn add_calendar_subscription_with_conn_inserts_row_with_enabled_default() {
    let conn = setup();

    let value = add_calendar_subscription_with_conn(
        &conn,
        "Work Cal",
        "https://example.com/cal.ics",
        Some("#ff0088"),
    )
    .expect("add should succeed");

    // The typed return must carry the full row back (rich return,
    // per core design rule #5).
    assert_eq!(value.name, "Work Cal");
    assert_eq!(value.url, "https://example.com/cal.ics");
    assert_eq!(value.color.as_deref(), Some("#ff0088"));
    assert!(value.enabled);
    assert!(value.last_fetched_at.is_none());
    assert!(value.error_message.is_none());
    assert!(value.next_retry_at.is_none());
    assert_eq!(value.consecutive_failures, 0);
    assert!(value.last_retry_after_hint.is_none());
    assert_eq!(value.sync_health, CalendarSubscriptionSyncHealth::Pending);

    // The row must land in the DB with enabled=1.
    let stored_enabled: i64 = conn
        .query_row(
            "SELECT enabled FROM calendar_subscriptions WHERE url = 'https://example.com/cal.ics'",
            [],
            |row| row.get(0),
        )
        .expect("load enabled");
    assert_eq!(stored_enabled, 1);

    let id = value.id.as_str();
    let row_version = subscription_version(&conn, id);
    let (operation, outbox_version, payload) = subscription_outbox_row(&conn, id);
    assert_eq!(operation, "upsert");
    assert_eq!(outbox_version, row_version);
    assert_eq!(payload["id"], id);
    assert_eq!(payload["name"], "Work Cal");
    assert_eq!(payload["url"], "https://example.com/cal.ics");
    assert_eq!(payload["color"], "#ff0088");
    assert_eq!(payload["enabled"], true);
    assert!(payload.get("next_retry_at").is_none());
    assert!(payload.get("consecutive_failures").is_none());
    assert!(payload.get("last_retry_after_hint").is_none());
}

#[test]
fn add_calendar_subscription_with_conn_accepts_null_color() {
    let conn = setup();

    add_calendar_subscription_with_conn(
        &conn,
        "Uncolored Cal",
        "https://example.com/uncolored.ics",
        None,
    )
    .expect("add without color should succeed");

    let stored_color: Option<String> = conn
        .query_row(
            "SELECT color FROM calendar_subscriptions WHERE url = 'https://example.com/uncolored.ics'",
            [],
            |row| row.get(0),
        )
        .expect("load color");
    assert!(stored_color.is_none(), "missing color must persist as NULL");
}

#[test]
fn toggle_calendar_subscription_with_conn_flips_enabled_flag() {
    let conn = setup();

    let added = add_calendar_subscription_with_conn(
        &conn,
        "Toggle Cal",
        "https://example.com/toggle.ics",
        None,
    )
    .expect("seed subscription");
    let id = added.id;

    toggle_calendar_subscription_with_conn(&conn, &id, false).expect("disable should succeed");
    let enabled_after_disable: i64 = conn
        .query_row(
            "SELECT enabled FROM calendar_subscriptions WHERE id = ?1",
            params![id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(enabled_after_disable, 0);
    let disabled_version = subscription_version(&conn, &id);
    let (operation, outbox_version, payload) = subscription_outbox_row(&conn, &id);
    assert_eq!(operation, "upsert");
    assert_eq!(outbox_version, disabled_version);
    assert_eq!(payload["enabled"], false);

    toggle_calendar_subscription_with_conn(&conn, &id, true).expect("re-enable should succeed");
    let enabled_after_reenable: i64 = conn
        .query_row(
            "SELECT enabled FROM calendar_subscriptions WHERE id = ?1",
            params![id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(enabled_after_reenable, 1);
    let enabled_version = subscription_version(&conn, &id);
    let (operation, outbox_version, payload) = subscription_outbox_row(&conn, &id);
    assert_eq!(operation, "upsert");
    assert_eq!(outbox_version, enabled_version);
    assert_eq!(payload["enabled"], true);
}

#[test]
fn update_calendar_subscription_color_with_conn_enqueues_definition_upsert() {
    let conn = setup();
    let added = add_calendar_subscription_with_conn(
        &conn,
        "Color Cal",
        "https://example.com/color.ics",
        None,
    )
    .expect("seed subscription");
    let id = added.id;

    update_calendar_subscription_color_with_conn(&conn, &id, Some("#112233"))
        .expect("color update should succeed");

    let row_version = subscription_version(&conn, &id);
    let (operation, outbox_version, payload) = subscription_outbox_row(&conn, &id);
    assert_eq!(operation, "upsert");
    assert_eq!(outbox_version, row_version);
    assert_eq!(payload["color"], "#112233");
    assert!(payload.get("next_retry_at").is_none());
}

#[test]
fn remove_calendar_subscription_with_conn_enqueues_delete_for_existing_row_only() {
    let conn = setup();
    let added = add_calendar_subscription_with_conn(
        &conn,
        "Delete Cal",
        "https://example.com/delete.ics",
        Some("#445566"),
    )
    .expect("seed subscription");
    let id = added.id;

    remove_calendar_subscription_with_conn(&conn, &id).expect("delete should succeed");

    let (operation, _version, payload) = subscription_outbox_row(&conn, &id);
    assert_eq!(operation, "delete");
    assert_eq!(payload["id"], id);
    assert_eq!(payload["name"], "Delete Cal");
    assert_eq!(payload["url"], "https://example.com/delete.ics");
    assert!(payload.get("next_retry_at").is_none());

    remove_calendar_subscription_with_conn(&conn, "does-not-exist")
        .expect("missing delete should remain a no-op");
    let missing_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'calendar_subscription' AND entity_id = 'does-not-exist'",
            [],
            |row| row.get(0),
        )
        .expect("count missing outbox");
    assert_eq!(missing_rows, 0);
}

#[test]
fn toggle_calendar_subscription_with_conn_is_noop_on_unknown_id() {
    let conn = setup();

    // Toggling a subscription that doesn't exist should succeed as a
    // row-affected=0 UPDATE (consistent with the inner's current
    // behavior: no NotFound surface). This guards against a future
    // regression where an accidental error branch would break the
    // UI's optimistic toggle flow.
    let result = toggle_calendar_subscription_with_conn(&conn, "does-not-exist", false);
    assert!(
        result.is_ok(),
        "toggle on missing id must not surface an error: {result:?}"
    );
    let outbox_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'calendar_subscription' AND entity_id = 'does-not-exist'",
            [],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert_eq!(outbox_rows, 0);
}
