//! Typed error enum for the Lorvex CLI.
//!
//! `std::error::Error`, and 13 `From` impls. Every other crate in
//! the workspace uses `thiserror`, and the manual error-chain
//! plumbing was a long-standing drift hazard — every new variant
//! needed three updates to keep the chain coherent. The `thiserror`
//! rewrite collapses ~100 lines of boilerplate into derive macros
//! while preserving the typed exit-code classification (the
//! `exit_code()` accessor and the downcast-walking
//! `exit_code_for_error()` are unchanged on the wire).

use thiserror::Error;

#[derive(Debug, Error)]
pub(crate) enum CliError {
    // External failure variants — every inner type is boxed to keep
    // `CliError` under the 128-byte `clippy::result_large_err` threshold
    // (the SQL / store / enqueue inner errors carry `rusqlite::Error`
    // and other large payloads that would otherwise inflate every
    // `Result<T, CliError>` in the CLI). `#[error(transparent)]`
    // forwards Display + `source()` through the `Box`'s `Deref` so the
    // existing exit-code downcast walker in `exit_code_for_error`
    // keeps working unchanged. `#[from]` builds the conversion through
    // a manual `From<Inner> for Box<Inner>` step in the variant impl
    // below, so `?` propagation stays as-is at call sites.
    #[error(transparent)]
    Runtime(Box<lorvex_runtime::RuntimeError>),
    #[error(transparent)]
    Store(Box<lorvex_store::StoreError>),
    #[error(transparent)]
    Enqueue(Box<lorvex_sync::outbox_enqueue::EnqueueError>),
    #[error(transparent)]
    Import(Box<lorvex_store::ImportError>),
    #[error(transparent)]
    Export(Box<lorvex_store::ExportError>),
    #[error(transparent)]
    Open(Box<lorvex_store::OpenError>),
    #[error(transparent)]
    Sql(Box<rusqlite::Error>),
    #[error(transparent)]
    Io(Box<std::io::Error>),
    // #3033-H3: classify `serde_json::Error` by the structured
    // `Category` returned by `serde_json::Error::classify()` instead of
    // collapsing every JSON failure to exit 65. Inbound parse failures
    // (`Data | Syntax | Eof`) are real input-shape problems the caller
    // can fix → exit 65 (EX_DATAERR). Outbound serialization failures
    // (`Io`) are internal-invariant violations on a buffer we control
    // → exit 70 (EX_SOFTWARE).
    // as 65, so a serializer panicking on an unrepresentable struct
    // looked indistinguishable from a malformed user input.
    #[error(transparent)]
    Json(Box<serde_json::Error>),

    // Typed CLI-originated kinds. Exit codes are derived from the
    // kind tag, NOT from message text. Localizing or rephrasing the
    // message MUST NOT reclassify the exit code.
    /// Input failed validation (bad shape, length, range, format).
    /// Exit code 65 (EX_DATAERR).
    #[error("{0}")]
    Validation(String),
    /// Referenced entity does not exist. Exit code 66 (EX_NOINPUT).
    #[error("{0}")]
    NotFound(String),
    /// Operation conflicts with existing state (duplicate name,
    /// concurrent edit, FK violation surfaced as user-facing).
    /// Exit code 73 (EX_CANTCREAT).
    #[error("{0}")]
    Conflict(String),
    /// Structured MCP tool error forwarded through the CLI workflow
    /// wrappers. The MCP server already classifies these payloads with
    /// a stable `kind`, retry hint, optional docs pointer, and optional
    /// entity id; keep those fields typed instead of collapsing back to
    /// substring-classified prose.
    #[error(
        "{message}{context}",
        context = mcp_tool_error_context(*retryable, docs_hint.as_deref(), entity_id.as_deref())
    )]
    McpTool {
        kind: String,
        message: String,
        retryable: bool,
        docs_hint: Option<String>,
        entity_id: Option<String>,
    },
    /// Internal invariant violation, mutex poison, third-party
    /// library failure surfaced as a string. Exit code 70
    /// (EX_SOFTWARE) — distinct from the IO/SQL family which
    /// already maps to 74.
    #[error("{0}")]
    Internal(String),
}

impl CliError {
    pub(crate) fn exit_code(&self) -> i32 {
        match self {
            CliError::Store(error) => store_exit_code(error),
            CliError::Enqueue(error) => enqueue_exit_code(error),
            CliError::Sql(_) | CliError::Io(_) | CliError::Open(_) | CliError::Runtime(_) => 74,
            CliError::Json(error) => json_exit_code(error),
            // typed kinds carry their classification
            // independent of message text. Localizing the message must
            // NOT reclassify the exit code.
            CliError::Import(_) | CliError::Export(_) | CliError::Validation(_) => 65,
            CliError::NotFound(_) => 66,
            CliError::Conflict(_) => 73,
            CliError::McpTool {
                kind, retryable, ..
            } => mcp_tool_exit_code(kind, *retryable),
            CliError::Internal(_) => 70,
        }
    }

    /// Stable, machine-readable tag for this error class. Mirrors the
    /// contract in [`Self::exit_code`] but with snake_case string
    /// labels suitable for JSON-envelope round-trips. The CLI's
    /// JSON-error renderer in `main.rs` writes `{kind, message,
    /// exit_code}` to stderr in JSON mode so consumers do not have
    /// to substring-match the message to distinguish `StaleVersion`
    /// (75 — retryable) from `Validation` (65 — hard fail).
    ///
    /// New variants must be added here AND in the matching code path
    /// the consumer switches on (typically a TS discriminated union or
    /// a shell exit-code dispatcher).
    /// Surface-specific follow-up suggestion shown beneath the error
    /// chain in human (TTY) output. Per-kind hints are short and
    /// action-oriented ("→ Try: `lorvex tasks ls` to inspect available
    /// IDs.") so a user landing on a typed failure sees a concrete
    /// next step instead of bouncing between man pages.
    ///
    /// Returns `None` for transparent wrappers around external errors
    /// (Sql / Io / Open / Runtime / Json) — those carry their own
    /// upstream "caused by" message and a generic hint there would
    /// be more noise than signal.
    ///
    /// Never used by the JSON error reporter: machine consumers key
    /// off the typed `kind` field, so adding a localized hint to the
    /// JSON envelope would just bloat the wire payload without
    /// improving the contract. The styling (ANSI dim, `→ Try:` prefix)
    /// is applied by `render::style_next_action` in the human path so
    /// piped output and `NO_COLOR` environments still receive the
    /// plain ASCII fallback.
    pub(crate) const fn next_action_hint(&self) -> Option<&'static str> {
        match self {
            CliError::Validation(_) => Some(
                "review the failing field, then re-run with corrected args. Use `lorvex <subcommand> --help` for the accepted shape.",
            ),
            CliError::NotFound(_) => Some(
                "list the available IDs first — e.g. `lorvex task ls`, `lorvex list ls`, or `lorvex habit ls` — and re-issue with a valid id.",
            ),
            CliError::Conflict(_) => Some(
                "another writer raced ahead. Re-read the entity (`lorvex <entity> show <id>`) and try again with the latest version.",
            ),
            CliError::McpTool { retryable: true, .. } => Some(
                "transient failure — wait a moment and retry the same command.",
            ),
            CliError::McpTool { retryable: false, .. } => Some(
                "MCP tool refused the call. Check the entity exists and the args match the contract.",
            ),
            CliError::Internal(_) => Some(
                "this is an internal invariant violation — please file `gh issue create --label bug` with the command you ran and the surrounding context.",
            ),
            CliError::Import(_) | CliError::Export(_) => Some(
                "verify the import/export file path and JSON shape, then re-run.",
            ),
            CliError::Enqueue(_) => Some(
                "sync enqueue refused the write — run `lorvex sync status` to inspect, then retry the mutation.",
            ),
            CliError::Store(_) => Some(
                "storage layer surfaced an error — run `lorvex sync status` to inspect outbox health and disk state.",
            ),
            CliError::Runtime(_)
            | CliError::Sql(_)
            | CliError::Io(_)
            | CliError::Open(_)
            | CliError::Json(_) => None,
        }
    }

    pub(crate) fn kind(&self) -> &str {
        match self {
            CliError::Validation(_) => "validation",
            CliError::NotFound(_) => "not_found",
            CliError::Conflict(_) => "conflict",
            CliError::McpTool { kind, .. } => kind.as_str(),
            CliError::Internal(_) => "internal",
            _ => kind_for_exit_code(self.exit_code()),
        }
    }
}

/// Classify a `serde_json::Error` into a CLI exit code. See
/// [`CliError::Json`] for the rationale; this is broken out so the
/// classifier sits next to its store/enqueue siblings rather than
/// inline in the `match` arm.
fn json_exit_code(error: &serde_json::Error) -> i32 {
    match error.classify() {
        // Inbound parse failure — the caller-supplied JSON is
        // malformed. EX_DATAERR (65), the same class as
        // `CliError::Validation`.
        serde_json::error::Category::Data
        | serde_json::error::Category::Syntax
        | serde_json::error::Category::Eof => 65,
        // Outbound serialization (or read-IO during serde) hit an
        // I/O failure on a buffer this process owns. The caller did
        // nothing wrong; this is an internal invariant violation.
        // EX_SOFTWARE (70), the same class as `CliError::Internal`.
        serde_json::error::Category::Io => 70,
    }
}

// `70 => "internal"` and `_ => "internal"` share a body, but the
// explicit arm documents the canonical mapping next to the other
// known exit codes. Collapsing it into the wildcard would suggest 70
// is "unknown / fallback" rather than the documented EX_SOFTWARE
// classification.
#[allow(clippy::match_same_arms)]
const fn kind_for_exit_code(exit_code: i32) -> &'static str {
    match exit_code {
        65 => "validation",
        66 => "not_found",
        70 => "internal",
        73 => "conflict",
        74 => "io",
        75 => "stale_version",
        _ => "internal",
    }
}

// The explicit `"internal" => 70` arm and the wildcard fallback share a body,
// but the explicit arm documents the canonical kind→exit-code mapping next to
// the other known kinds. Collapsing it into the wildcard would erase that
// table-of-contents intent.
#[allow(clippy::match_same_arms)]
fn mcp_tool_exit_code(kind: &str, retryable: bool) -> i32 {
    if retryable {
        return 75;
    }
    match kind {
        "validation" | "serialization" => 65,
        "not_found" => 66,
        "sync_conflict" => 73,
        "db_busy" | "rate_limited" => 75,
        "internal" => 70,
        _ => 70,
    }
}

fn mcp_tool_error_context(
    retryable: bool,
    docs_hint: Option<&str>,
    entity_id: Option<&str>,
) -> String {
    let mut parts = Vec::new();
    parts.push(format!("retryable={retryable}"));
    if let Some(value) = docs_hint {
        parts.push(format!("docs_hint={value}"));
    }
    if let Some(value) = entity_id {
        parts.push(format!("entity_id={value}"));
    }
    format!(" [mcp: {}]", parts.join("; "))
}

const fn store_exit_code(error: &lorvex_store::StoreError) -> i32 {
    match error {
        lorvex_store::StoreError::NotFound { .. } => 66,
        lorvex_store::StoreError::Validation(_) => 65,
        lorvex_store::StoreError::Sql(_)
        | lorvex_store::StoreError::Io(_)
        | lorvex_store::StoreError::DiskFull { .. } => 74,
        lorvex_store::StoreError::Invariant(_) | lorvex_store::StoreError::Serialization(_) => 70,
        // a LWW-gated UPDATE matched zero rows because
        // the caller's stamp lost to an in-flight peer write. Mirror
        // the EnqueueError::VersionSuperseded mapping (EX_TEMPFAIL =
        // 75) so caller wrappers retry against the latest state.
        lorvex_store::StoreError::StaleVersion { .. } => 75,
    }
}

const fn sync_exit_code(error: &lorvex_sync::error::SyncError) -> i32 {
    match error {
        lorvex_sync::error::SyncError::Store(store_error) => store_exit_code(store_error),
        lorvex_sync::error::SyncError::Sql(_) => 74,
        lorvex_sync::error::SyncError::SerializationCategorized { .. } => 65,
        lorvex_sync::error::SyncError::NetworkDropped { .. } => 75,
        lorvex_sync::error::SyncError::Envelope(_) => 73,
    }
}

const fn enqueue_exit_code(error: &lorvex_sync::outbox_enqueue::EnqueueError) -> i32 {
    match error {
        lorvex_sync::outbox_enqueue::EnqueueError::EntityNotFound { .. } => 66,
        lorvex_sync::outbox_enqueue::EnqueueError::UnknownEntityType(_)
        | lorvex_sync::outbox_enqueue::EnqueueError::Canonicalization(_)
        // `UnsupportedOperation` is a programmer-error
        // invariant (local writers must construct explicit Upsert /
        // Delete). Treat as EX_USAGE alongside other "the input
        // shape is fundamentally wrong" errors so test harnesses
        // and shell wrappers don't retry — there's no recovery
        // path for a caller that constructed `SyncOperation::Unknown`.
        | lorvex_sync::outbox_enqueue::EnqueueError::UnsupportedOperation { .. } => 65,
        lorvex_sync::outbox_enqueue::EnqueueError::Store(error) => store_exit_code(error),
        lorvex_sync::outbox_enqueue::EnqueueError::Sqlite(_)
        | lorvex_sync::outbox_enqueue::EnqueueError::VersionStamp(_) => 74,
        // VersionSuperseded: a concurrent writer raced this enqueue
        // and stamped a strictly newer version. TaintedVersion: outbox
        // refused the envelope because the incoming `version` failed
        // `Hlc::parse`. Both surface as exit code 75 (EX_TEMPFAIL) so
        // caller wrappers retry the mutation against the latest state —
        // the playbook (re-read + re-stamp + re-enqueue) is identical.
        lorvex_sync::outbox_enqueue::EnqueueError::VersionSuperseded { .. }
        | lorvex_sync::outbox_enqueue::EnqueueError::TaintedVersion { .. }
        // ContentionExhausted: the outbox coalesce retry budget was
        // burned through against the UNIQUE-partial-index race
        // between concurrent writers. EX_TEMPFAIL alongside the
        // other "racer won, retry against the latest state" errors —
        // the playbook is identical (#4583 B20).
        | lorvex_sync::outbox_enqueue::EnqueueError::ContentionExhausted { .. } => 75,
        lorvex_sync::outbox_enqueue::EnqueueError::PendingDrainTargetLookup { source, .. }
        | lorvex_sync::outbox_enqueue::EnqueueError::PendingDrain { source, .. } => {
            sync_exit_code(source)
        }
    }
}

/// `From<Inner>` impls that `Box::new`-wrap each external failure type
/// into its boxed `CliError` variant. These replace the `#[from]`
/// attribute on the corresponding variants — `thiserror`'s `#[from]`
/// cannot synthesize a conversion through a `Box<Inner>` field, so the
/// `Box::new` step has to live in a hand-written `From` impl. With
/// these in place `?` propagation at every CLI call site keeps working
/// unchanged.
impl From<lorvex_runtime::RuntimeError> for CliError {
    fn from(e: lorvex_runtime::RuntimeError) -> Self {
        CliError::Runtime(Box::new(e))
    }
}

impl From<lorvex_store::StoreError> for CliError {
    fn from(e: lorvex_store::StoreError) -> Self {
        CliError::Store(Box::new(e))
    }
}

impl From<lorvex_sync::outbox_enqueue::EnqueueError> for CliError {
    fn from(e: lorvex_sync::outbox_enqueue::EnqueueError) -> Self {
        CliError::Enqueue(Box::new(e))
    }
}

impl From<lorvex_store::ImportError> for CliError {
    fn from(e: lorvex_store::ImportError) -> Self {
        CliError::Import(Box::new(e))
    }
}

impl From<lorvex_store::ExportError> for CliError {
    fn from(e: lorvex_store::ExportError) -> Self {
        CliError::Export(Box::new(e))
    }
}

impl From<lorvex_store::OpenError> for CliError {
    fn from(e: lorvex_store::OpenError) -> Self {
        CliError::Open(Box::new(e))
    }
}

impl From<rusqlite::Error> for CliError {
    fn from(e: rusqlite::Error) -> Self {
        CliError::Sql(Box::new(e))
    }
}

impl From<std::io::Error> for CliError {
    fn from(e: std::io::Error) -> Self {
        CliError::Io(Box::new(e))
    }
}

impl From<serde_json::Error> for CliError {
    fn from(e: serde_json::Error) -> Self {
        CliError::Json(Box::new(e))
    }
}

/// Domain validators return `ValidationError`; their `Display` impl
/// already names the field, so callers can propagate via `?` without
/// adding redundant prefixes. Hand-rolled (rather than `#[from]` on
/// a transparent variant) because we collapse the structured
/// validation error into our stringly-typed `Validation` variant
/// rather than carrying the source through.
impl From<lorvex_domain::validation::ValidationError> for CliError {
    fn from(e: lorvex_domain::validation::ValidationError) -> Self {
        CliError::Validation(e.to_string())
    }
}

/// chrono parse failures are user-input failures (bad date/time
/// strings on the command line, bad dates in imported payloads).
impl From<chrono::ParseError> for CliError {
    fn from(e: chrono::ParseError) -> Self {
        CliError::Validation(format!("date/time parse failed: {e}"))
    }
}

/// `lorvex_store::transaction::with_immediate_transaction` and
/// `with_savepoint` synthesize `E: From<String>` for combined
/// commit/rollback failure messages (#3019-H3 batch atomicity needs
/// these helpers wired through `CliError`). Map to `Internal` so the
/// classifier returns EX_SOFTWARE for these compound errors — they
/// indicate transaction-cleanup failure layered on top of a primary
/// fault, not user-facing input errors.
impl From<String> for CliError {
    fn from(message: String) -> Self {
        CliError::Internal(message)
    }
}

#[cfg(test)]
mod tests;
