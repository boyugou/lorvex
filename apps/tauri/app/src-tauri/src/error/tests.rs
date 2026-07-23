use super::boundary::append_app_error_boundary_log;
use super::envelope::CommandError;
use super::*;
use serde_json::Value;

fn parse_envelope(s: &str) -> Value {
    serde_json::from_str(s).unwrap_or_else(|e| panic!("not a typed envelope ({e}): {s:?}"))
}

#[test]
fn app_error_disk_full_emits_typed_envelope() {
    let err = AppError::DiskFull("SQLITE_FULL: out of space".to_string());
    let s: String = err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "disk_full");
    assert_eq!(env["detail"], "SQLITE_FULL: out of space");
    assert!(env["message"].as_str().unwrap().contains("storage is full"));
}

#[test]
fn app_error_from_store_disk_full_emits_typed_envelope() {
    let store_err = lorvex_store::StoreError::DiskFull {
        details: "database or disk is full".to_string(),
    };
    let app_err: AppError = store_err.into();
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "disk_full");
    assert!(env["detail"].as_str().unwrap().contains("disk is full"));
}

#[test]
fn app_error_from_rusqlite_diskfull_routes_via_store_variant() {
    // the `From<rusqlite::Error> for StoreError` impl
    // is the canonical site that *trips the process-wide DiskFull
    // breaker* (see `lorvex_store::error::from_rusqlite`). Pre-fix
    // this test exercised that conversion but never cleared the
    // breaker afterwards, so every subsequent write-path test in
    // the same binary observed `is_disk_full_tripped() == true`
    // and short-circuited with a `Local storage is full` error
    // — visible as cascading failures on the dependency,
    // remote-apply, and widget-snapshot suites whenever this test
    // happened to run first under the parallel scheduler.
    //
    // We can't acquire the lorvex-store-private `breaker_test_mutex`
    // from this crate, but the behavior we're asserting (the typed
    // envelope classification) is independent of the exact moment
    // the breaker is read, so a paired clear before+after guards
    // the global state without needing the mutex: any sibling test
    // that mutates the breaker is already serialized through it
    // upstream, and a sibling read-only test would see exactly the
    // same `false` value either before or after we run.
    use rusqlite::ffi::{Error as FfiError, ErrorCode as FfiErrorCode};
    lorvex_store::clear_disk_full_breaker_for_tests();
    let sqlite_err = rusqlite::Error::SqliteFailure(
        FfiError {
            code: FfiErrorCode::DiskFull,
            extended_code: 13,
        },
        Some("database or disk is full".to_string()),
    );
    let store_err: lorvex_store::StoreError = sqlite_err.into();
    let app_err: AppError = store_err.into();
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "disk_full");
    lorvex_store::clear_disk_full_breaker_for_tests();
}

#[test]
fn app_error_validation_emits_typed_envelope() {
    let app_err = AppError::Validation("title cannot be empty".to_string());
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "validation");
    assert_eq!(env["message"], "title cannot be empty");
}

#[test]
fn app_error_not_found_emits_typed_envelope() {
    let app_err = AppError::NotFound("Task not found: abc-123".to_string());
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "not_found");
    assert_eq!(env["message"], "Task not found: abc-123");
}

#[test]
fn app_error_cancelled_emits_typed_envelope() {
    // a user-initiated cancel of a long-running
    // sync command must surface as `kind: "cancelled"` so the
    // toast layer can render a benign "Cancelled" affordance
    // rather than the red error banner that
    // validation/internal-kind envelopes would trigger.
    let app_err =
        AppError::Cancelled("filesystem-bridge sync cancelled by user during pull".to_string());
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "cancelled");
    assert!(env["message"]
        .as_str()
        .unwrap()
        .contains("cancelled by user"));
}

#[test]
fn app_error_memory_locked_emits_typed_envelope() {
    // #4351: biometric-gated memory lock surfaces as `kind: memory_locked`
    // so the renderer can prompt for Touch ID / Windows Hello unlock
    // rather than rendering the opaque internal-error toast.
    let app_err: AppError = crate::memory_lock::MemoryLocked.into();
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "memory_locked");
    assert!(!env["message"].as_str().unwrap().is_empty());
}

#[test]
fn app_error_generic_sql_sanitizes_to_internal_envelope() {
    // Raw SQL errors must not leak schema details to the renderer.
    // Pre-#2949 this was a free-text "An internal error occurred"
    // string; the typed envelope keeps that human-facing message
    // but the `kind: internal` tag lets the toast layer route it
    // through the generic-error path without substring matching.
    let app_err: AppError = rusqlite::Error::QueryReturnedNoRows.into();
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "internal");
    assert!(env["message"]
        .as_str()
        .unwrap()
        .to_lowercase()
        .contains("internal"));
}

// -----------------------------------------------------------------
// / H2 / ERR-H3: typed routing for `From<String>`,
// `From<RuntimeError>`, and `From<ApplyError>`.
//
// Every test below pins one specific source-error variant to its
// post-fix `AppError` variant, and confirms the IPC envelope
// emits the expected `kind` tag. Pre-fix every variant
// collapsed into `AppError::Internal(to_string())` (RuntimeError)
// or `AppError::Validation(other.to_string())` (ApplyError catch-
// all), erasing the actionable signal from the renderer.
// -----------------------------------------------------------------

#[test]
fn app_error_from_runtime_invalid_lease_ttl_routes_to_validation() {
    let runtime_err = lorvex_runtime::RuntimeError::InvalidLeaseTtl(-50);
    let app_err: AppError = runtime_err.into();
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(
        env["kind"], "validation",
        "InvalidLeaseTtl is caller-actionable, must surface as `validation`",
    );
    // Typed message must round-trip — pre-fix the renderer saw
    // the opaque "An internal error occurred." string.
    assert!(env["message"].as_str().unwrap().contains("ttl_ms"));
}

#[test]
fn app_error_from_runtime_corrupt_local_change_seq_routes_to_validation() {
    let runtime_err = lorvex_runtime::RuntimeError::CorruptLocalChangeSeq {
        value: "abc".to_string(),
    };
    let app_err: AppError = runtime_err.into();
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "validation");
}

#[test]
fn app_error_from_runtime_sqlite_routes_through_sql_arm() {
    // SQLite-shaped variant must NOT surface as a typed validation
    // error — it's a real DB failure that the existing `Sql`
    // routing should sanitize through the disk-full classifier.
    let sqlite_err = rusqlite::Error::QueryReturnedNoRows;
    let runtime_err = lorvex_runtime::RuntimeError::Sqlite(sqlite_err);
    let app_err: AppError = runtime_err.into();
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "internal");
}

#[test]
fn app_error_from_apply_invalid_payload_routes_to_validation() {
    let apply_err =
        lorvex_sync::apply::ApplyError::InvalidPayload("task title must not be empty".to_string());
    let app_err: AppError = apply_err.into();
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "validation");
    assert!(env["message"]
        .as_str()
        .unwrap()
        .contains("must not be empty"));
}

#[test]
fn app_error_from_apply_invalid_version_routes_to_validation() {
    let apply_err = lorvex_sync::apply::ApplyError::InvalidVersion("not-an-hlc".to_string());
    let app_err: AppError = apply_err.into();
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "validation");
}

#[test]
fn app_error_from_apply_unknown_entity_type_routes_to_internal() {
    // `UnknownEntityType` is a forward-compat / peer-protocol
    // failure — the renderer cannot fix it, so it MUST NOT
    // surface as caller-actionable validation.
    let apply_err = lorvex_sync::apply::ApplyError::UnknownEntityType("bogus_entity".to_string());
    let app_err: AppError = apply_err.into();
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(
        env["kind"], "internal",
        "UnknownEntityType is not caller-actionable; \
         pre-fix it routed to `validation` and presented as a fixable error",
    );
}

#[test]
fn app_error_from_apply_tombstone_redirect_cycle_routes_to_internal() {
    let apply_err = lorvex_sync::apply::ApplyError::TombstoneRedirectCycle {
        entity_type: lorvex_domain::naming::EntityKind::Task.as_str().to_string(),
        entity_id: "abc".to_string(),
    };
    let app_err: AppError = apply_err.into();
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "internal");
}

#[test]
fn app_error_from_apply_invalid_operation_routes_to_internal() {
    let apply_err = lorvex_sync::apply::ApplyError::InvalidOperation {
        entity_type: lorvex_domain::naming::EntityKind::AiChangelog
            .as_str()
            .to_string(),
        operation: "delete".to_string(),
    };
    let app_err: AppError = apply_err.into();
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "internal");
}

#[test]
fn app_error_remote_update_failed_emits_internal_envelope_with_sanitized_message() {
    // #3033-H4: `tauri_plugin_updater::Error::to_string()` can
    // include reqwest URL paths, `HTTPS_PROXY` proxy authority
    // fragments (`user:pass@host`), and signing-key error
    // strings. The typed envelope must drop the raw cause from
    // the user-facing `message` and route the detail to the
    // diagnostic log via the `detail` field.
    let leaky_detail = "https://updates.example.com/latest.json proxy=http://user:secret@10.0.0.1 \
         signing key error: bad sigs"
        .to_string();
    let app_err = AppError::RemoteUpdateFailed(leaky_detail.clone());
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "internal");
    assert_eq!(
        env["message"], "Update check failed. Try again later.",
        "user-facing message must be a fixed sanitized string \
         with no proxy authority or URL fragments",
    );
    let message = env["message"].as_str().unwrap();
    assert!(!message.contains("secret"), "proxy auth must not leak");
    assert!(
        !message.contains("updates.example.com"),
        "update server hostname must not leak",
    );
    // Detail field round-trips for the diagnostic log.
    assert_eq!(env["detail"].as_str().unwrap(), leaky_detail);
}

#[test]
fn app_error_window_op_emits_internal_envelope_with_sanitized_message() {
    // #3033-H4: `tauri::Error::to_string()` for window ops can
    // name internal IPC channel state and platform-specific
    // objc/com error fragments that the renderer should not see.
    let app_err = AppError::WindowOp(
        "WindowNotFound: WebViewWindow id=focus, NSObject 0xdeadbeef returned nil".to_string(),
    );
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "internal");
    assert_eq!(env["message"], "A window operation failed. Try again.");
    let message = env["message"].as_str().unwrap();
    assert!(
        !message.contains("0xdeadbeef") && !message.contains("WebViewWindow"),
        "platform-internal pointer/handle fragments must not leak",
    );
    assert!(env["detail"].as_str().unwrap().contains("0xdeadbeef"));
}

#[test]
fn app_error_boundary_persists_internal_diagnostic_row() {
    let conn = crate::test_support::test_conn();
    let app_err = AppError::RemoteUpdateFailed(
        "GET /latest.json failed: Authorization: Bearer eyJhbGciOi.deadbeef.xyz".to_string(),
    );
    let command_error = CommandError::from_app_error(&app_err);

    append_app_error_boundary_log(&conn, &app_err, &command_error);

    let row: (String, String, String, String) = conn
        .query_row(
            "SELECT source, level, message, details
             FROM error_logs
             WHERE source = 'app.command_error.boundary'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read app error boundary diagnostic");

    assert_eq!(row.0, "app.command_error.boundary");
    assert_eq!(row.1, "error");
    assert_eq!(row.2, "Tauri command returned diagnostic error");
    assert!(row.3.contains("kind=internal"));
    assert!(row.3.contains("variant=RemoteUpdateFailed"));
    assert!(!row.3.contains("eyJhbGciOi.deadbeef.xyz"));
    assert!(row.3.contains("[REDACTED]"));
}

#[test]
fn app_error_boundary_skips_routine_user_errors() {
    let conn = crate::test_support::test_conn();
    let routine_errors = [
        AppError::Validation("title cannot be empty".to_string()),
        AppError::NotFound("Task not found: abc".to_string()),
        AppError::Cancelled("sync cancelled by user".to_string()),
    ];

    for app_err in routine_errors {
        let command_error = CommandError::from_app_error(&app_err);
        append_app_error_boundary_log(&conn, &app_err, &command_error);
    }

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'app.command_error.boundary'",
            [],
            |row| row.get(0),
        )
        .expect("count app error boundary diagnostics");

    assert_eq!(count, 0);
}

#[test]
fn app_error_from_string_lands_in_transaction_rollback_failed_variant() {
    // the catch-all `From<String>` impl pre-fix
    // routed every stringy `?` into `AppError::Internal`, which
    // the IPC envelope sanitized to the opaque "An internal
    // error occurred." toast. The post-fix impl is reserved for
    // `lorvex_store::with_immediate_transaction`'s rollback-
    // failure synthesis path; the typed `TransactionRollbackFailed`
    // variant carries the message into the diagnostic stream
    // while still presenting a sanitized renderer toast.
    let app_err: AppError = "rollback failed: SQLITE_BUSY".to_string().into();
    match &app_err {
        AppError::TransactionRollbackFailed(msg) => {
            assert!(msg.contains("rollback failed"));
        }
        other => panic!(
            "From<String> must land in TransactionRollbackFailed, \
             got {other:?}"
        ),
    }
    // The IPC envelope still routes this as `internal` so the
    // renderer doesn't surface raw SQLite plumbing details, but
    // the detail field carries the diagnostic message.
    let s: String = app_err.into();
    let env = parse_envelope(&s);
    assert_eq!(env["kind"], "internal");
    assert!(env["detail"].as_str().unwrap().contains("rollback failed"));
}
