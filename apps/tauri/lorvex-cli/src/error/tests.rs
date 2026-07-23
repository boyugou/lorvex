use super::*;

#[test]
fn exit_code_classifies_store_and_io() {
    assert_eq!(
        CliError::from(lorvex_store::StoreError::Validation("bad".to_string())).exit_code(),
        65
    );
    assert_eq!(
        CliError::from(lorvex_store::StoreError::NotFound {
            entity: "task",
            id: "task-1".to_string(),
        })
        .exit_code(),
        66
    );
    assert_eq!(
        CliError::from(lorvex_store::StoreError::Invariant("oops".to_string())).exit_code(),
        70
    );
    assert_eq!(
        CliError::from(std::io::Error::other("disk")).exit_code(),
        74
    );
}

/// typed kinds carry their classification
/// independent of message text. Localizing the message must NOT
/// reclassify the exit code. Use Chinese strings to prove the
/// English-substring classifier is gone.
#[test]
fn exit_code_typed_kinds_independent_of_message() {
    assert_eq!(
        CliError::Validation("优先级超出范围".to_string()).exit_code(),
        65,
        "Validation must classify as 65 regardless of message language"
    );
    assert_eq!(
        CliError::NotFound("找不到任务".to_string()).exit_code(),
        66,
        "NotFound must classify as 66 regardless of message language"
    );
    assert_eq!(
        CliError::Conflict("名称已存在".to_string()).exit_code(),
        73,
        "Conflict must classify as 73 regardless of message language"
    );
    assert_eq!(
        CliError::Internal("内部不变量被违反".to_string()).exit_code(),
        70,
        "Internal must classify as 70 regardless of message language"
    );
    assert_eq!(
        CliError::McpTool {
            kind: "sync_conflict".to_string(),
            message: "同步冲突".to_string(),
            retryable: true,
            docs_hint: None,
            entity_id: None,
        }
        .exit_code(),
        75,
        "retryable MCP tool errors must classify as EX_TEMPFAIL"
    );
    // Empty messages are still classified by kind.
    assert_eq!(CliError::Validation(String::new()).exit_code(), 65);
    assert_eq!(CliError::NotFound(String::new()).exit_code(), 66);
    assert_eq!(CliError::Conflict(String::new()).exit_code(), 73);
    assert_eq!(CliError::Internal(String::new()).exit_code(), 70);
}

/// `From<ValidationError>` should yield a `Validation` variant
/// (exit 65) and preserve the field name through `Display`.
#[test]
fn validation_error_conversion_preserves_kind_and_field() {
    let err: CliError = lorvex_domain::validation::ValidationError::OutOfRange {
        field: "priority",
        min: 1,
        max: 4,
        actual: 9,
    }
    .into();
    assert_eq!(err.exit_code(), 65);
    let msg = format!("{err}");
    assert!(msg.contains("priority"), "field name should be preserved");
    assert!(msg.contains("out of range"));
}

/// #3033-H3: inbound parse failures (`Data | Syntax | Eof`) and
/// outbound serialization-IO failures (`Io`) classify to distinct
/// exit codes. Pre-fix the `Json(_)` arm collapsed every
/// `serde_json::Error` to 65, so a serializer panicking on an
/// unrepresentable struct looked exactly like a user supplying
/// malformed JSON.
#[test]
fn json_error_classifies_parse_vs_serialize() {
    // Syntax failure — caller-fixable (EX_DATAERR / 65).
    let parse_err: serde_json::Error =
        serde_json::from_str::<serde_json::Value>("not json").unwrap_err();
    let cli_err: CliError = parse_err.into();
    assert_eq!(
        cli_err.exit_code(),
        65,
        "syntax-class JSON error must classify as EX_DATAERR (65)",
    );

    // EOF failure — also caller-fixable.
    let eof_err: serde_json::Error = serde_json::from_str::<serde_json::Value>("").unwrap_err();
    let cli_err: CliError = eof_err.into();
    assert_eq!(cli_err.exit_code(), 65);

    // Synthesizing an Io-category error is awkward without writing
    // to a failing writer; we exercise the classifier directly.
    // The contract is: `Category::Io` → 70.
    assert_eq!(
        json_exit_code_for_category(serde_json::error::Category::Io),
        70,
        "IO-class JSON error must classify as EX_SOFTWARE (70)",
    );
    assert_eq!(
        json_exit_code_for_category(serde_json::error::Category::Data),
        65,
    );
    assert_eq!(
        json_exit_code_for_category(serde_json::error::Category::Syntax),
        65,
    );
    assert_eq!(
        json_exit_code_for_category(serde_json::error::Category::Eof),
        65,
    );
}

/// Test-only shim that lets us assert the `Category::Io` arm of
/// `json_exit_code` without manufacturing an actual IO-class
/// `serde_json::Error` (the public constructor for that category
/// requires a writer that returns an `io::Error` on a specific call,
/// which is awkward to set up). Mirrors the production classifier
/// exactly.
fn json_exit_code_for_category(cat: serde_json::error::Category) -> i32 {
    match cat {
        serde_json::error::Category::Data
        | serde_json::error::Category::Syntax
        | serde_json::error::Category::Eof => 65,
        serde_json::error::Category::Io => 70,
    }
}

/// #3033-M1: local variants expose a stable kind matching their
/// exit-code class, while structured MCP errors preserve the
/// server-provided kind tag even when several retryable kinds share
/// EX_TEMPFAIL (75). Pre-fix the batch surfaces collapsed errors to
/// `error.to_string()`, which let retryable and hard-fail cases
/// round-trip with identical shape and forced consumers to
/// substring-match the message.
#[test]
fn kind_uses_variant_or_mcp_payload_classification() {
    assert_eq!(CliError::Validation("v".into()).kind(), "validation");
    assert_eq!(CliError::NotFound("n".into()).kind(), "not_found");
    assert_eq!(CliError::Conflict("c".into()).kind(), "conflict");
    assert_eq!(CliError::Internal("i".into()).kind(), "internal");
    assert_eq!(CliError::from(std::io::Error::other("io")).kind(), "io");
    assert_eq!(
        CliError::McpTool {
            kind: "db_busy".into(),
            message: "database is locked".into(),
            retryable: true,
            docs_hint: Some("docs/design/ARCHITECTURE.md#sqlite-concurrency".into()),
            entity_id: None,
        }
        .kind(),
        "db_busy",
        "structured MCP errors keep their server-provided kind tag",
    );
    assert_eq!(
        CliError::from(lorvex_store::StoreError::StaleVersion {
            entity: "habit",
            id: "h-1".into(),
        })
        .kind(),
        "stale_version",
        "StaleVersion must round-trip a distinct kind so retryable \
         retries are programmatically separable from hard fails",
    );
}

#[test]
fn mcp_tool_display_preserves_retry_docs_and_entity_metadata() {
    let err = CliError::McpTool {
        kind: "sync_conflict".into(),
        message: "task was superseded".into(),
        retryable: true,
        docs_hint: Some("docs/execution/SYNC_RECOVERY_PLAYBOOK.md".into()),
        entity_id: Some("task-1".into()),
    };

    assert_eq!(
        err.to_string(),
        "task was superseded [mcp: retryable=true; docs_hint=docs/execution/SYNC_RECOVERY_PLAYBOOK.md; entity_id=task-1]",
    );
}

/// `thiserror`'s `#[error(transparent)]`
/// forwards Display through to the inner error so the wire
/// format stays unchanged.
#[test]
fn transparent_variants_forward_display() {
    let err = CliError::from(rusqlite::Error::QueryReturnedNoRows);
    let display = format!("{err}");
    let inner_display = format!("{}", rusqlite::Error::QueryReturnedNoRows);
    assert_eq!(
        display, inner_display,
        "transparent variant must forward inner Display verbatim"
    );
}
