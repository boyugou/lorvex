//! every
//! arm of `validate_provider_link_args` must reject the offending
//! input with a typed `McpError::Validation` so a malicious or
//! buggy caller cannot ride a multi-MB `provider_kind` into the
//! SQLite FK pipeline and cannot escape the canonical
//! `lorvex_domain::PROVIDER_KIND_ALLOWLIST` that every other
//! surface (Tauri IPC, platform writers, sync apply, store
//! schema) shares.

use super::*;

const VALID_TASK_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000000300";

fn assert_rejects(task: &str, kind: &str, scope: &str, key: &str, expected_substring: &str) {
    let err = validate_provider_link_args(task, kind, scope, key)
        .expect_err("expected Validation error for invalid input");
    let McpError::Validation(message) = err else {
        panic!("expected McpError::Validation, got: {err:?}");
    };
    assert!(
        message.contains(expected_substring),
        "diagnostic should contain {expected_substring:?}, got: {message}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn rejects_empty_task_id() {
    assert_rejects(
        "",
        "eventkit",
        "default",
        "evt-1",
        "task_id must not be empty",
    );
}

#[test]
#[serial_test::serial(hlc)]
fn rejects_malformed_task_id() {
    assert_rejects(
        "task-1",
        "eventkit",
        "default",
        "evt-1",
        "task_id is not a valid UUID",
    );
}

#[test]
#[serial_test::serial(hlc)]
fn rejects_provider_kind_over_max_length() {
    let too_long = "a".repeat(lorvex_domain::provider_link::MAX_PROVIDER_LINK_FIELD_LEN + 1);
    assert_rejects(
        VALID_TASK_ID,
        &too_long,
        "default",
        "evt-1",
        "provider_kind exceeds maximum length",
    );
}

#[test]
#[serial_test::serial(hlc)]
fn rejects_provider_kind_outside_allowlist() {
    for bad in ["google", "evernote", "eventkit_v2", "EventKit"] {
        assert_rejects(
            VALID_TASK_ID,
            bad,
            "default",
            "evt-1",
            "is not in the allowlist",
        );
    }
}

#[test]
#[serial_test::serial(hlc)]
fn rejects_empty_provider_kind() {
    assert_rejects(
        VALID_TASK_ID,
        "",
        "default",
        "evt-1",
        "provider_kind must not be empty",
    );
}

#[test]
#[serial_test::serial(hlc)]
fn rejects_kinds_outside_canonical_domain_allowlist() {
    // Closing #2954: the canonical allowlist now lives in
    // `lorvex_domain::PROVIDER_KIND_ALLOWLIST` and covers every
    // real producer (eventkit / google_calendar / ical_subscription
    // / ics / linux_ics / outlook / windows_appointments). Pre-fix
    // the per-module allowlist drifted from the platform writers'
    // set so an MCP write that touched a platform-written row
    // failed the local gate. Pin that values outside the canonical
    // domain set still fail here so the MCP path remains the same
    // gate the Tauri IPC enforces.
    for unsupported in ["evernote", "exchange_legacy", "fastmail_caldav"] {
        assert_rejects(
            VALID_TASK_ID,
            unsupported,
            "default",
            "evt-1",
            "is not in the allowlist",
        );
    }
}

#[test]
#[serial_test::serial(hlc)]
fn accepts_kinds_that_only_platform_writers_used_pre_fix() {
    // Closing #2954: the platform-direct writers (linux,
    // windows, ical subscription) used to bypass the IPC gate, so
    // their kinds were stored on disk but rejected by the IPC
    // validator — meaning a follow-on MCP write touching the same
    // row failed. The canonical allowlist now includes every
    // producer, so the MCP path accepts them.
    for kind in ["linux_ics", "windows_appointments", "ical_subscription"] {
        validate_provider_link_args(VALID_TASK_ID, kind, "default", "evt-1")
            .unwrap_or_else(|e| panic!("kind {kind:?} should be accepted post-#2954, got: {e:?}"));
    }
}

#[test]
#[serial_test::serial(hlc)]
fn rejects_provider_scope_over_max_length() {
    let too_long = "a".repeat(lorvex_domain::provider_link::MAX_PROVIDER_LINK_FIELD_LEN + 1);
    assert_rejects(
        VALID_TASK_ID,
        "eventkit",
        &too_long,
        "evt-1",
        "provider_scope exceeds maximum length",
    );
}

#[test]
#[serial_test::serial(hlc)]
fn accepts_empty_provider_scope_for_single_scope_provider_events() {
    let (_, _, scope, _) = validate_provider_link_args(VALID_TASK_ID, "eventkit", "", "evt-1")
        .expect("empty scope is the canonical scope for built-in provider mirrors");
    assert_eq!(scope, "");
}

#[test]
#[serial_test::serial(hlc)]
fn rejects_empty_provider_event_key() {
    assert_rejects(
        VALID_TASK_ID,
        "eventkit",
        "default",
        "",
        "provider_event_key must not be empty",
    );
}

#[test]
#[serial_test::serial(hlc)]
fn rejects_provider_event_key_over_max_length() {
    let too_long = "a".repeat(lorvex_domain::provider_link::MAX_PROVIDER_LINK_FIELD_LEN + 1);
    assert_rejects(
        VALID_TASK_ID,
        "eventkit",
        "default",
        &too_long,
        "provider_event_key exceeds maximum length",
    );
}

#[test]
#[serial_test::serial(hlc)]
fn accepts_every_allowlisted_provider_kind() {
    for kind in lorvex_domain::PROVIDER_KIND_ALLOWLIST {
        validate_provider_link_args(VALID_TASK_ID, kind, "default", "evt-1")
            .unwrap_or_else(|e| panic!("kind {kind:?} should be accepted, got: {e:?}"));
    }
}

#[test]
#[serial_test::serial(hlc)]
fn mcp_known_provider_kind_contract_matches_domain_allowlist() {
    let mcp_kinds = crate::contract::KnownProviderKind::ALL
        .iter()
        .copied()
        .map(crate::contract::KnownProviderKind::as_canonical_str)
        .collect::<Vec<_>>();
    assert_eq!(mcp_kinds, lorvex_domain::PROVIDER_KIND_ALLOWLIST);
}

#[test]
#[serial_test::serial(hlc)]
fn link_args_reject_unknown_provider_kind_at_deserialize_boundary() {
    let err = serde_json::from_value::<LinkTaskToProviderEventArgs>(serde_json::json!({
        "task_id": VALID_TASK_ID,
        "provider_kind": "evernote",
        "provider_scope": "default",
        "provider_event_key": "evt-1"
    }))
    .expect_err("unknown provider kinds must fail before handler validation");
    let msg = err.to_string();
    assert!(
        msg.contains("provider_kind") || msg.contains("unknown variant"),
        "expected provider_kind deserialize error, got: {msg}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn accepts_inputs_at_max_length_boundary() {
    let at_limit = "a".repeat(lorvex_domain::provider_link::MAX_PROVIDER_LINK_FIELD_LEN);
    validate_provider_link_args(VALID_TASK_ID, "eventkit", &at_limit, &at_limit)
        .expect("inputs at the max-length boundary must be accepted");
}

#[test]
#[serial_test::serial(hlc)]
fn sanitizes_bidi_overrides_in_scope_and_event_key() {
    // #2891-M7: legitimate scope / key are programmatic IDs but
    // the sanitize_user_text pass strips bidi / zero-width / NUL
    // codepoints in case a peer ships a maliciously formatted
    // value. The output must equal the trimmed normal-form so
    // downstream SQL parameters are predictable.
    let raw_scope = "\u{202E}calendar\u{202C}";
    let (_, _, scope, _) =
        validate_provider_link_args(VALID_TASK_ID, "eventkit", raw_scope, "evt-1")
            .expect("sanitized scope should be accepted");
    assert_eq!(scope, "calendar");
}

#[test]
#[serial_test::serial(hlc)]
fn returns_normalized_strings() {
    // The validator must return the canonicalized values so
    // callers don't accidentally pass the raw input into
    // downstream SQL parameters.
    let (task, kind, scope, key) =
        validate_provider_link_args(VALID_TASK_ID, "eventkit", "  default  ", "  evt-1  ")
            .expect("valid input");
    assert_eq!(task, VALID_TASK_ID);
    assert_eq!(kind, "eventkit");
    assert_eq!(scope, "default");
    assert_eq!(key, "evt-1");
}

fn seed_task(conn: &Connection, id: &str) {
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title("Provider task")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-29T08:00:00Z")
        .insert(conn);
}

fn count_provider_changelog(conn: &Connection) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?1",
        [naming::EDGE_TASK_PROVIDER_EVENT_LINK],
        |row| row.get(0),
    )
    .expect("count provider changelog rows")
}

#[test]
#[serial_test::serial(hlc)]
fn link_provider_event_rejects_malformed_task_id_before_lookup() {
    let conn = rusqlite::Connection::open_in_memory().expect("open db");
    lorvex_store::migration::apply_migrations(&conn, &lorvex_store::schema::all_migrations())
        .expect("apply migrations");

    let err = link_task_to_provider_event(
        &conn,
        LinkTaskToProviderEventArgs {
            task_id: "task-1".to_string(),
            provider_kind: crate::contract::KnownProviderKind::Eventkit,
            provider_scope: "".to_string(),
            provider_event_key: "evt-1".to_string(),
            idempotency_key: Some("malformed-provider-task".to_string()),
        },
    )
    .expect_err("malformed provider-link task id should reject");

    let msg = err.to_string();
    assert!(
        msg.contains("task_id") && msg.contains("UUID"),
        "expected task_id UUID validation error, got: {msg}"
    );
    assert_eq!(count_provider_changelog(&conn), 0);
}

#[test]
#[serial_test::serial(hlc)]
fn unlink_missing_provider_link_rejects_without_changelog_or_idempotency_cache() {
    let conn = rusqlite::Connection::open_in_memory().expect("open db");
    lorvex_store::migration::apply_migrations(&conn, &lorvex_store::schema::all_migrations())
        .expect("apply migrations");
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000301");

    let err = unlink_task_from_provider_event(
        &conn,
        UnlinkTaskFromProviderEventArgs {
            task_id: "01966a3f-7c8b-7d4e-8f3a-000000000301".to_string(),
            provider_kind: crate::contract::KnownProviderKind::Eventkit,
            provider_scope: "default".to_string(),
            provider_event_key: "missing-event".to_string(),
            idempotency_key: Some("missing-provider-link".to_string()),
        },
    )
    .expect_err("missing provider link should reject");

    let msg = err.to_string();
    assert!(
        msg.contains("not found") && msg.contains("missing-event"),
        "expected missing-link error, got: {msg}"
    );
    assert_eq!(count_provider_changelog(&conn), 0);
    let cached_rows: i64 = conn
        .query_row("SELECT COUNT(*) FROM mcp_idempotency", [], |row| row.get(0))
        .expect("count idempotency rows");
    assert_eq!(cached_rows, 0);
}

#[test]
#[serial_test::serial(hlc)]
fn provider_links_read_rejects_malformed_task_id() {
    let conn = rusqlite::Connection::open_in_memory().expect("open db");
    lorvex_store::migration::apply_migrations(&conn, &lorvex_store::schema::all_migrations())
        .expect("apply migrations");

    let err = get_provider_event_links_for_task(
        &conn,
        GetProviderEventLinksForTaskArgs {
            task_id: "task-1".to_string(),
        },
    )
    .expect_err("malformed task id should reject");

    let msg = err.to_string();
    assert!(
        msg.contains("task_id") && msg.contains("UUID"),
        "expected task_id UUID validation error, got: {msg}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn provider_links_read_rejects_missing_task() {
    let conn = rusqlite::Connection::open_in_memory().expect("open db");
    lorvex_store::migration::apply_migrations(&conn, &lorvex_store::schema::all_migrations())
        .expect("apply migrations");

    let err = get_provider_event_links_for_task(
        &conn,
        GetProviderEventLinksForTaskArgs {
            task_id: "01966a3f-7c8b-7d4e-8f3a-000000000302".to_string(),
        },
    )
    .expect_err("missing task should reject");

    let msg = err.to_string();
    assert!(
        msg.contains("task not found"),
        "expected missing-task error, got: {msg}"
    );
}
