//! `Mutation<T>` — typed mutation orchestrator for cross-surface writes.
//!
//! Every Lorvex write — MCP tool, Tauri IPC command, CLI handler —
//! shares the same six-step pipeline:
//!
//! ```text
//! 1. capture pre-mutation snapshot
//! 2. mint an HLC version (via the surface's HlcSession)
//! 3. apply the row mutation
//! 4. enqueue the entity payload upsert to the sync outbox
//! 5. write the `ai_changelog` audit row
//! 6. bump `local_change_seq`
//! ```
//!
//! The whole pipeline must run, in order, every time. Skipping step 5
//! violates Core Design Rule 2 ("every MCP write must log to
//! `ai_changelog`"); skipping step 4 silently desyncs peers; skipping
//! step 6 wedges the Tauri app's poll-driven invalidation.
//!
//! The [`Mutation`] trait makes this contract type-level. A descriptor
//! type describes **what** changes — the entity kind, the operation
//! tag, the pre-snapshot reader, and the per-row `apply` that returns
//! the post-snapshot and a human-readable summary. The workflow crate
//! owns the orchestration entry point [`execute_with_context`], which
//! enforces pre-snapshot → apply → finalizer ordering. Surface adapters
//! plug in a per-surface finalizer that handles the audit + sync
//! enqueue + change-seq bump (each surface owns concerns the workflow
//! crate has no business knowing about: MCP rate limits, widget
//! refresh, preview discriminators, tombstone payloads; CLI
//! transaction-policy coupling and HLC guard re-borrow).
//!
//! ## Side-channel extras
//!
//! [`Mutation::apply`] returns a single [`MutationOutput`], but a few
//! descriptors need to surface follow-up values the surrounding handler
//! consumes after the orchestrator returns (a child revision id minted
//! alongside the parent upsert, the freshly-minted HLC version, the
//! post-mutation typed row, child relation sync payloads, …). Those
//! values flow through `MutationOutput.extra`, a JSON map keyed by
//! typed [`MutationExtraKey`](crate::mutation_extras::MutationExtraKey)
//! constants. The map storage is private; access goes through
//! [`MutationOutput::set_extra`] / [`MutationOutput::get_extra`] /
//! [`MutationOutput::take_extra`], so descriptors cannot stamp
//! bare-string keys that would silently collide across entity kinds.
//! See [`mutation_extras`](crate::mutation_extras) for the canonical
//! key catalog and the namespacing rule.
//!
//! ## Authoring a descriptor
//!
//! 1. **Identify the entity + operation.** Pick the matching
//!    `lorvex_domain::naming::ENTITY_*` constant for `entity_kind`
//!    and `OP_*` (or a domain-specific verb) for `operation`.
//! 2. **Lift the body into a `Mutation` impl.** The struct's fields
//!    are the validated, sanitized arguments the site already
//!    destructures (`TaskId`, normalized text, …). Implement
//!    [`pre_snapshot`](Mutation::pre_snapshot) by calling the
//!    surface's existing `fetch_*_json` / `load_*_row` helper, or by
//!    returning a borrowed pre-row the caller already loaded. Move
//!    the SQL UPDATE + summary construction into
//!    [`apply`](Mutation::apply); mint every HLC stamp through the
//!    `HlcSession` argument so the parent row, the outbox envelope,
//!    and the audit row share one strict-monotonic counter run.
//! 3. **Choose the surface adapter.** MCP handlers call
//!    `execute_mcp_mutation` / `execute_mcp_mutation_with_finalizer`;
//!    CLI handlers call `execute_cli_entity_mutation_map_store_error`
//!    / `execute_cli_mutation_with_finalizer`. Those adapters set up
//!    the HLC session and own the audit/outbox/local-change
//!    finalizer.
//! 4. **Surface stale-version rejections.** `apply` returns
//!    `Err(StoreError::StaleVersion { … })` on LWW rejects; the
//!    surface executor maps it to its typed error
//!    (`McpError::Validation` / `CliError::Conflict`) via the
//!    `map_store_error` argument to `execute_with_context`.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::{Map, Value};

use crate::mutation_extras::MutationExtraKey;

/// One unit of mutation work. A type implements this trait to describe
/// **what** changes; the per-surface executor (see the trait-level
/// docs for the migration playbook) owns the orchestration around it.
///
/// Implementations are typically zero-cost descriptor structs that
/// hold the validated, sanitized arguments. The trait methods run
/// inside the orchestrator's transaction, so they share the same
/// connection and the same HLC session.
pub trait Mutation {
    /// The entity table this mutation writes to. Used by the executor
    /// to drive `ai_changelog.entity_type`, the per-entity outbox
    /// envelope routing, and the snapshot reader registry. Must be one
    /// of the `lorvex_domain::naming::ENTITY_*` constants.
    fn entity_kind(&self) -> &'static str;

    /// Changelog operation tag — one of `lorvex_domain::naming::OP_*`
    /// (`OP_UPSERT`, `OP_DELETE`, …) or a domain-specific verb
    /// already in use on the audit feed (`"update"`, `"complete"`).
    /// The executor stamps this verbatim onto `ai_changelog.operation`.
    fn operation(&self) -> &'static str;

    /// Pre-mutation snapshot. The executor reads this BEFORE
    /// [`apply`](Mutation::apply) runs so the audit row's `before_json`
    /// reflects the row's pre-stamp shape. Returning `None` means
    /// "no meaningful before-state" (create paths) — the executor
    /// will not stamp `before_json` in that case.
    fn pre_snapshot(&self, conn: &Connection) -> Result<Option<Value>, StoreError>;

    /// Apply the row mutation against `conn` using `hlc` for any
    /// version stamps. Returns the post-mutation snapshot (the value
    /// the audit row's `after_json` will carry) plus the
    /// human-readable summary the changelog UI surfaces.
    ///
    /// Implementations MUST mint every HLC stamp they need through
    /// `hlc` so the parent row, the outbox envelope, and the audit
    /// row share one strict-monotonic counter run. They MUST NOT call
    /// surface-specific helpers like `next_hlc_version` /
    /// `generate_hlc_version` directly — those re-lock the storage
    /// mutex and produce versions that lex-order inconsistently with
    /// the envelopes the surrounding mutation emits.
    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError>;
}

/// Result of a single [`Mutation::apply`] run.
///
/// Carries the post-mutation row snapshot (for `ai_changelog.after_json`
/// and the IPC return value) plus the human-readable summary the audit
/// feed and Changelog view render.
#[derive(Debug, Clone, Default)]
pub struct MutationOutput {
    /// Post-mutation entity snapshot. The executor stamps this onto
    /// `ai_changelog.after_json` and returns it to the caller as the
    /// canonical "rich return value" required by Core Design Rule 5.
    pub after: Value,
    /// One-line audit summary (e.g.
    /// `"Added AI notes to 'design review': Plan first…"`). Will be
    /// run through `lorvex_store::changelog::sanitize_changelog_summary`
    /// at the audit boundary, so call sites can build it freely from
    /// user-supplied prose.
    pub summary: String,
    /// Side-channel extras the descriptor surfaces back to the
    /// surrounding surface adapter — e.g. the `revision_id` of a child
    /// `memory_revision` row that the parent `memories` upsert
    /// cascades into, or the post-stamp HLC version the descriptor
    /// minted inside `apply` and the response patches onto the JSON
    /// body. Values must be JSON-typed so the audit funnel does not
    /// need to know the per-site shape.
    ///
    /// Keys are namespaced [`MutationExtraKey`]s minted by
    /// [`crate::mutation_extras`] — the underlying map storage is
    /// private so descriptors and consumers cannot bypass the
    /// namespace rule with a bare-string `extra.insert("version", v)`.
    /// Use [`Self::set_extra`] / [`Self::get_extra`] /
    /// [`Self::take_extra`].
    extra: Map<String, Value>,
}

impl MutationOutput {
    /// Build a [`MutationOutput`] without extras. Convenience for
    /// descriptors that don't need the side-channel.
    #[must_use]
    pub fn new(after: Value, summary: impl Into<String>) -> Self {
        Self {
            after,
            summary: summary.into(),
            extra: Map::new(),
        }
    }

    /// Stamp a side-channel value under a typed [`MutationExtraKey`].
    /// Replaces any prior value at the same key (the side-channel is a
    /// single-slot per key by contract).
    pub fn set_extra(&mut self, key: &MutationExtraKey, value: Value) {
        self.extra.insert(key.as_str().to_string(), value);
    }

    #[must_use]
    pub fn get_extra(&self, key: &MutationExtraKey) -> Option<&Value> {
        self.extra.get(key.as_str())
    }

    /// Move the value out of the side-channel by key. Used by surface
    /// adapters that consume the value once and don't need the map
    /// to retain it.
    #[must_use]
    pub fn take_extra(&mut self, key: &MutationExtraKey) -> Option<Value> {
        self.extra.remove(key.as_str())
    }
}

/// Per-mutation HLC context threaded through the orchestrator.
///
/// The context wraps a borrowed [`HlcSession`] so every stamp inside
/// one mutation run goes through the same strict-monotonic counter.
/// The originating device id is intentionally not threaded here —
/// surface adapters obtain it from
/// `lorvex_runtime::get_or_create_device_id` at the audit-funnel
/// boundary, not from the mutation orchestrator.
pub struct MutationContext<'a> {
    hlc: &'a HlcSession<'a>,
}

impl<'a> MutationContext<'a> {
    /// Build a context from a surface's HLC session. Surfaces normally
    /// do not call this directly — they invoke the surface-specific
    /// `execute` adapter (see the trait docs) which constructs the
    /// context for them.
    #[must_use]
    pub const fn new(hlc: &'a HlcSession<'a>) -> Self {
        Self { hlc }
    }

    /// Borrow the HLC session for the duration of one `apply` run.
    #[must_use]
    pub const fn hlc(&self) -> &HlcSession<'_> {
        self.hlc
    }
}

/// Complete output of a [`Mutation`] before the surface-specific audit
/// and sync finalizer runs.
///
/// Surface adapters receive this value from [`execute_with_context`]
/// and must persist the side effects that make a row mutation visible:
/// audit row, sync outbox envelope, and local-change notification. The
/// payload intentionally carries the operation/entity metadata from
/// the descriptor so adapters do not have to re-thread those fields in
/// parallel with the mutation itself.
#[derive(Debug, Clone)]
pub struct MutationExecution {
    pub operation: &'static str,
    pub entity_kind: &'static str,
    pub before: Option<Value>,
    pub output: MutationOutput,
}

/// Run a [`Mutation`] and require the caller to finalize the produced
/// pre/post payload before the mutation output can escape.
///
/// This bridges the pure workflow descriptor and each surface's
/// side-effect policy. The workflow crate stays unaware of MCP rate
/// limits, widget refreshes, CLI transaction policy, or undo bundles —
/// those live in surface adapters. What this function centralizes is
/// the ordering contract: pre-snapshot, apply, finalizer. A call site
/// cannot run `apply` and forget the audit/outbox/local-change phase.
pub fn execute_with_context<M, E, F, MapStoreError>(
    mutation: &M,
    conn: &Connection,
    cx: &MutationContext<'_>,
    map_store_error: MapStoreError,
    finalize: F,
) -> Result<MutationOutput, E>
where
    M: Mutation,
    F: FnOnce(MutationExecution) -> Result<(), E>,
    MapStoreError: Fn(StoreError) -> E,
{
    let before = mutation.pre_snapshot(conn).map_err(&map_store_error)?;
    let output = mutation.apply(conn, cx.hlc()).map_err(&map_store_error)?;
    let execution = MutationExecution {
        operation: mutation.operation(),
        entity_kind: mutation.entity_kind(),
        before,
        output: output.clone(),
    };
    finalize(execution)?;
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    use lorvex_domain::hlc::Hlc;
    use lorvex_domain::hlc_session::HlcStateHandle;
    use serde_json::json;
    use std::cell::Cell;

    struct FakeHlc {
        counter: Cell<u64>,
    }
    impl HlcStateHandle for FakeHlc {
        fn generate(&self) -> Hlc {
            let n = self.counter.get();
            self.counter.set(n + 1);
            // 16-hex suffix.
            Hlc::new(n, 0, "abcdef0123456789").expect("valid hlc")
        }
    }

    struct DummyMutation;
    impl Mutation for DummyMutation {
        fn entity_kind(&self) -> &'static str {
            "task"
        }
        fn operation(&self) -> &'static str {
            "update"
        }
        fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
            Ok(Some(json!({"id": "task-1", "title": "old"})))
        }
        fn apply(
            &self,
            _conn: &Connection,
            hlc: &HlcSession<'_>,
        ) -> Result<MutationOutput, StoreError> {
            // Mint a stamp through the session to prove the API binds.
            let _v = hlc.next_version();
            Ok(MutationOutput::new(
                json!({"id": "task-1", "title": "new"}),
                "renamed task",
            ))
        }
    }

    #[test]
    fn execute_with_context_requires_finalizer_before_returning_output() {
        let conn = Connection::open_in_memory().unwrap();
        let handle = FakeHlc {
            counter: Cell::new(0),
        };
        let session = HlcSession::new(&handle);
        let cx = MutationContext::new(&session);
        let m = DummyMutation;
        let mut finalized = false;

        let output = execute_with_context(
            &m,
            &conn,
            &cx,
            |err| err,
            |execution| {
                finalized = true;
                assert_eq!(execution.operation, "update");
                assert_eq!(execution.entity_kind, "task");
                assert_eq!(execution.before.unwrap()["title"], "old");
                assert_eq!(execution.output.after["title"], "new");
                assert_eq!(execution.output.summary, "renamed task");
                Ok::<(), StoreError>(())
            },
        )
        .unwrap();

        assert!(finalized);
        assert_eq!(output.after["title"], "new");
    }
}
