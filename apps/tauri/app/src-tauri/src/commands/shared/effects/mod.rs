//! Tauri-surface adapter for [`lorvex_workflow::mutation::Mutation`].
//!
//! Mirrors `mcp-server::runtime::change_tracking::mutation_executor` and
//! `lorvex-cli::commands::shared::effects` so every Tauri IPC write
//! that mutates a syncable entity routes through the same six-step
//! pipeline as the MCP and CLI surfaces.
//!
//! ## The Tauri-side contract
//!
//! Out of the six steps in
//! [`lorvex_workflow::mutation`](lorvex_workflow::mutation) the Tauri
//! finalizer enforces five — the `ai_changelog` audit row is
//! intentionally **skipped** because Tauri's `log_change` is a no-op by
//! design (Core Design Rule 2: only the MCP server writes audit rows;
//! the CLI writes them tagged `mcp_tool = "cli"`; the desktop app
//! never authors `ai_changelog`).
//!
//! Steps enforced by the Tauri finalizer:
//!
//! ```text
//! 1. pre-snapshot         (orchestrator, before apply)
//! 2. HLC mint             (Mutation::apply mints through HlcSession)
//! 3. row write            (Mutation::apply)
//! 4. outbox enqueue       (caller's finalizer — entity-specific)
//! 5. local_change_seq++   (this module)
//! 6. event_bus broadcast  (this module)
//! ```
//!
//! Steps 4 stays in the caller's finalizer because each entity has its
//! own enqueue helper (`enqueue_list_upsert`, `enqueue_task_upsert`, …)
//! that reads the freshly-written row through the Tauri IPC model and
//! ships its canonicalized payload — the workflow crate has no notion
//! of those Tauri-specific row shapes.

use lorvex_domain::hlc::Hlc;
use lorvex_domain::hlc_session::{HlcSession, HlcStateHandle};
use lorvex_workflow::mutation::{
    execute_with_context, Mutation, MutationContext, MutationExecution, MutationOutput,
};
use rusqlite::Connection;

use crate::error::{AppError, AppResult};
use crate::event_bus;

/// Storage handle that backs the [`HlcSession`] threaded through every
/// IPC mutation. Mirrors the private `AppHlcStateHandle` in
/// `crate::hlc` — duplicated here only because the original is
/// module-private. The two delegate to the same `SurfaceHlcRuntime`
/// singleton so the stamps lex-order with every other Tauri write.
struct IpcHlcStateHandle;

impl HlcStateHandle for IpcHlcStateHandle {
    fn generate(&self) -> Hlc {
        crate::hlc::with_hlc_session(|session| Ok(session.next_version()))
            .expect("HLC runtime must be initialized before IpcMutationExecutor runs")
    }
}

/// Run a [`Mutation`] through the Tauri-surface executor and require
/// the caller to enqueue + emit before the output can escape.
///
/// This is the lowest-level executor entry point. Most call sites
/// should prefer one of the higher-level helpers below
/// ([`execute_ipc_entity_mutation`], …) which fill in standard
/// finalizer shapes.
///
/// Steps:
///
/// 1. Open an [`HlcSession`] over the process-wide `SurfaceHlcRuntime`
///    (one session per top-level mutation — every stamp inside
///    `apply` shares it).
/// 2. Capture the pre-snapshot, run `apply`, stash the resulting
///    [`MutationExecution`].
/// 3. Hand the execution to the caller-supplied `finalize` closure,
///    which is responsible for the **entity-specific** outbox enqueue.
/// 4. Bump `local_change_seq` (cheap, single-row UPDATE).
/// 5. Emit `event_bus::emit_data_changed(entity)` so React Query
///    invalidates the relevant caches. The variant is derived from
///    the descriptor's `entity_kind()` via
///    [`event_bus::Entity::from_entity_kind`] — descriptors no longer
///    pass a parallel `event_bus::Entity` that could disagree with
///    the wire tag stamped on the outbox envelope (#4487).
pub(crate) fn execute_ipc_mutation_with_finalizer<M, Finalize>(
    conn: &Connection,
    mutation: &M,
    finalize: Finalize,
) -> AppResult<MutationOutput>
where
    M: Mutation,
    Finalize: FnOnce(&Connection, &MutationExecution) -> AppResult<()>,
{
    let entity_kind = mutation.entity_kind();
    let entity = event_bus::Entity::from_entity_kind(entity_kind).unwrap_or_else(|| {
        panic!(
            "Mutation::entity_kind() returned '{entity_kind}' which has no event_bus::Entity \
             mapping — either add it to entity_type_to_bus or call event_bus::emit_data_changed \
             directly from the finalizer"
        )
    });
    let mut staged_execution: Option<MutationExecution> = None;
    let handle = IpcHlcStateHandle;
    let session = HlcSession::new(&handle);
    let cx = MutationContext::new(&session);
    let output = execute_with_context(mutation, conn, &cx, AppError::from, |execution| {
        staged_execution = Some(execution);
        Ok::<(), AppError>(())
    })?;
    let execution =
        staged_execution.expect("Mutation contract: execute_with_context staged finalizer payload");
    finalize(conn, &execution)?;
    lorvex_runtime::bump_local_change_seq(conn).map_err(AppError::from)?;
    // event_bus emit deferred to the caller's transaction-commit boundary
    // is unnecessary: `emit_data_changed` is a fire-and-forget Tauri
    // event whose only downstream effect is a React Query refetch, and
    // the underlying transaction will commit before any consumer can
    // observe stale data. Emitting here keeps the side-effect colocated
    // with the executor that owns it.
    event_bus::emit_data_changed(entity);
    Ok(output)
}

/// Higher-level helper for the common "single entity, fixed
/// entity_id" shape: caller supplies the entity id and an enqueue
/// closure; the executor handles the rest.
///
/// Use this for descriptors whose pre-snapshot and `apply` both work
/// against the same primary row (lists CRUD, task field updates).
/// Descriptors that fan out to multiple sibling entities (calendar
/// event delete cascading to attendees, focus parent re-resolution)
/// should call [`execute_ipc_mutation_with_finalizer`] directly.
pub(crate) fn execute_ipc_entity_mutation<M, Enqueue>(
    conn: &Connection,
    mutation: &M,
    enqueue: Enqueue,
) -> AppResult<MutationOutput>
where
    M: Mutation,
    Enqueue: FnOnce(&Connection, &MutationExecution) -> AppResult<()>,
{
    execute_ipc_mutation_with_finalizer(conn, mutation, |conn, execution| enqueue(conn, execution))
}

#[cfg(test)]
mod tests {
    use super::*;
    use lorvex_store::StoreError;
    use lorvex_workflow::mutation::MutationOutput;
    use serde_json::{json, Value};

    struct FixtureMutation;

    impl Mutation for FixtureMutation {
        fn entity_kind(&self) -> &'static str {
            lorvex_domain::naming::ENTITY_LIST
        }
        fn operation(&self) -> &'static str {
            lorvex_domain::naming::OP_UPSERT
        }
        fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
            Ok(None)
        }
        fn apply(
            &self,
            _conn: &Connection,
            hlc: &HlcSession<'_>,
        ) -> Result<MutationOutput, StoreError> {
            let _stamp = hlc.next_version();
            Ok(MutationOutput::new(json!({"id": "fixture"}), "fixture"))
        }
    }

    #[test]
    fn executor_runs_finalizer_and_emits_event() {
        crate::hlc::ensure_hlc_for_test();
        let conn = crate::test_support::test_conn();
        event_bus::clear_test_emitted_data_changed();

        let mut finalized = false;
        let mutation = FixtureMutation;
        let output = execute_ipc_mutation_with_finalizer(&conn, &mutation, |_conn, execution| {
            assert_eq!(execution.entity_kind, lorvex_domain::naming::ENTITY_LIST);
            assert_eq!(execution.operation, lorvex_domain::naming::OP_UPSERT);
            finalized = true;
            Ok(())
        })
        .expect("executor runs");

        assert!(finalized, "finalizer must be invoked");
        assert_eq!(output.after["id"], "fixture");
        let emitted = event_bus::take_test_emitted_data_changed();
        assert!(emitted.iter().any(|e| matches!(e, event_bus::Entity::List)));
    }

    /// Contract: every `ENTITY_*` constant a Mutation descriptor may
    /// stamp on `entity_kind()` must map to *some* `event_bus::Entity`
    /// variant, so the executor's derive-from-descriptor path never
    /// panics at runtime. Walk every syncable kind from the canonical
    /// `EntityKind` enum + the local-only kinds Mutation descriptors
    /// stamp (preferences, …) and assert the mapping resolves.
    #[test]
    fn every_mutation_entity_kind_maps_to_a_bus_variant() {
        use lorvex_domain::naming::{EntityKind, ALL_ENTITY_TYPES};
        // Mutation descriptors only ever stamp syncable entity kinds
        // (audit-only `ai_changelog` is written by the changelog
        // funnel, not a Mutation descriptor; local-only `device_state`
        // /`feedback`/`saved_query`/`import_session` are local writes
        // that emit through a dedicated path). The contract here is
        // that anything Mutation descriptors *can* stamp resolves.
        for raw in ALL_ENTITY_TYPES {
            if *raw == lorvex_domain::naming::ENTITY_AI_CHANGELOG {
                continue;
            }
            EntityKind::try_parse(raw)
                .unwrap_or_else(|err| panic!("ENTITY_* '{raw}' must parse: {err}"));
            assert!(
                event_bus::Entity::from_entity_kind(raw).is_some(),
                "Entity::from_entity_kind('{raw}') must agree with the typed mapping"
            );
        }
    }
}
