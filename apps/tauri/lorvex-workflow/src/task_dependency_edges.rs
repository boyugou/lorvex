//! Canonical [`Mutation`] descriptors for task→task dependency-edge
//! writes. Both add (upsert) and remove (delete) flow through the
//! workflow `Mutation` trait so the Tauri IPC handler shares one HLC
//! stamping, one outbox-envelope shape, and one `local_change_seq`
//! discipline with any other surface that adopts these descriptors.
//!
//! Surface coverage today: the Tauri app's `atomic.rs` IPC handler is
//! the sole consumer. The CLI writes dependency edges through its
//! own `canonical_flush.rs` path — a deliberately sibling shape that
//! shares the underlying [`lorvex_store::repositories::task::dependencies`]
//! row writers but composes its outbox envelope inside the CLI's
//! transaction wrapper rather than through these descriptors. The two
//! shapes are intentional, not migrational drift: CLI dep-edge writes
//! always travel with a parent `task update` mutation, so the CLI
//! batches both into a single canonical-flush span. The descriptors
//! here service the per-edge IPC entry points (add / remove a single
//! edge with no surrounding task update) and the future MCP dep-edge
//! tool if one ships.
//!
//! Each descriptor owns the **complete** dependency-edge write contract
//! for IPC: pre-apply idempotency / pre-delete state probe, the row
//! mutation itself, and the outbox envelope payload assembly. Surface
//! handlers stay thin — they validate inputs, call
//! [`AddTaskDependencyMutation::pre_apply_check`] /
//! [`RemoveTaskDependencyMutation::pre_apply_check`] to short-circuit
//! no-ops, run [`crate::mutation::execute_with_context`] on the
//! descriptor, and feed its captured probe context plus the executor's
//! `MutationOutput` back through [`AddTaskDependencyMutation::payload_for_envelope`]
//! / [`RemoveTaskDependencyMutation::payload_for_envelope`] to build
//! the outbox payload. Cycle validation (which needs a database read
//! the surface already does for task existence) and parent-task
//! re-stamping (which needs a typed `Task` row the surface owns)
//! remain in the surface — those touch knowledge the workflow crate
//! intentionally does not own.

use crate::mutation::{Mutation, MutationOutput};
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{EDGE_TASK_DEPENDENCY, OP_DELETE, OP_UPSERT};
use lorvex_domain::{TaskDependencyEdgeId, TaskId};
use lorvex_store::repositories::task::dependencies;
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::Value;

/// Outcome of [`AddTaskDependencyMutation::pre_apply_check`] /
/// [`RemoveTaskDependencyMutation::pre_apply_check`]. The surface
/// handler matches on this before calling
/// [`crate::mutation::execute_with_context`] so an already-satisfied
/// write (duplicate add, no-op delete) skips HLC mint, outbox traffic,
/// the audit row, and the `local_change_seq` bump entirely — preserving
/// the contract that two webviews racing the same click produce one
/// envelope, not two.
#[derive(Debug)]
pub enum DependencyEdgePrecheck {
    /// Mutation should run. `pre_delete` is `Some((version, created_at))`
    /// for [`RemoveTaskDependencyMutation`] and carries the pre-delete
    /// row state the envelope payload needs; it is always `None` for
    /// [`AddTaskDependencyMutation`].
    Proceed { pre_delete: Option<PreDeleteState> },
    /// Mutation is already satisfied (duplicate add, or delete of a
    /// row that does not exist). Surface should short-circuit.
    NoOp,
}

/// Pre-delete `(version, created_at)` tuple loaded inside the row
/// probe and forwarded to the delete-envelope payload assembly so
/// peer LWW has a coherent compare basis on the tombstone.
#[derive(Debug, Clone)]
pub struct PreDeleteState {
    pub version: String,
    pub created_at: String,
}

/// Descriptor for adding one dependency edge. The cycle / existence
/// validation runs in the surrounding command body; this descriptor's
/// `apply` owns only the edge INSERT + HLC stamp so the executor
/// pipeline (outbox enqueue, `local_change_seq` bump, event-bus
/// broadcast) wraps a coherent single-row write.
pub struct AddTaskDependencyMutation<'a> {
    pub task_id: &'a TaskId,
    pub depends_on_task_id: &'a TaskId,
    pub now: &'a str,
}

impl<'a> AddTaskDependencyMutation<'a> {
    /// Probe whether the edge already exists, so the surface can
    /// short-circuit the executor pipeline on idempotent clicks. Runs
    /// inside the surface's transaction (caller-provided `conn`) so
    /// the probe and the subsequent `apply` see the same snapshot.
    pub fn pre_apply_check(&self, conn: &Connection) -> Result<DependencyEdgePrecheck, StoreError> {
        let exists = dependency_edge_exists(conn, self.task_id, self.depends_on_task_id)?;
        Ok(if exists {
            DependencyEdgePrecheck::NoOp
        } else {
            DependencyEdgePrecheck::Proceed { pre_delete: None }
        })
    }

    /// Build the `EDGE_TASK_DEPENDENCY` outbox payload from the
    /// executor's `MutationOutput`. The surface enqueues this payload
    /// under `OP_UPSERT` and the descriptor's [`Self::entity_id`].
    #[must_use]
    pub fn payload_for_envelope(&self, output: &MutationOutput) -> Value {
        let version = output
            .after
            .get("version")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        let created_at = output
            .after
            .get("created_at")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        serde_json::json!({
            "task_id": self.task_id,
            "depends_on_task_id": self.depends_on_task_id,
            "version": version,
            "created_at": created_at,
        })
    }

    /// Composite `(task_id, depends_on_task_id)` entity id used on the
    /// outbox envelope and the tombstone redirect table.
    #[must_use]
    pub fn entity_id(&self) -> TaskDependencyEdgeId {
        TaskDependencyEdgeId::new(self.task_id, self.depends_on_task_id)
    }
}

impl<'a> Mutation for AddTaskDependencyMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        EDGE_TASK_DEPENDENCY
    }
    fn operation(&self) -> &'static str {
        OP_UPSERT
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let inserted = dependencies::insert_dependency_edges_batch(
            conn,
            self.task_id,
            std::slice::from_ref(self.depends_on_task_id),
            &version,
            self.now,
        )?;
        let entity_id = TaskDependencyEdgeId::new(self.task_id, self.depends_on_task_id);
        let after = serde_json::json!({
            "task_id": self.task_id,
            "depends_on_task_id": self.depends_on_task_id,
            "version": version,
            "created_at": self.now,
            "inserted": inserted,
        });
        Ok(MutationOutput::new(
            after,
            format!("Added dependency edge {entity_id}"),
        ))
    }
}

/// Descriptor for removing one dependency edge. `apply` does the
/// DELETE itself and stamps a fresh HLC on the parent task version via
/// the executor's session — the edge delete envelope carries the
/// pre-delete `(version, created_at)` tuple loaded by the caller so
/// peer LWW has a coherent compare basis.
pub struct RemoveTaskDependencyMutation<'a> {
    pub task_id: &'a TaskId,
    pub depends_on_task_id: &'a TaskId,
}

impl<'a> RemoveTaskDependencyMutation<'a> {
    /// Load the pre-delete `(version, created_at)` tuple so the
    /// tombstone envelope can carry it for peer LWW. Returns
    /// [`DependencyEdgePrecheck::NoOp`] when the row is already absent
    /// — the surface short-circuits without running the executor.
    pub fn pre_apply_check(&self, conn: &Connection) -> Result<DependencyEdgePrecheck, StoreError> {
        match load_pre_delete_state(conn, self.task_id, self.depends_on_task_id)? {
            Some(state) => Ok(DependencyEdgePrecheck::Proceed {
                pre_delete: Some(state),
            }),
            None => Ok(DependencyEdgePrecheck::NoOp),
        }
    }

    /// Build the `EDGE_TASK_DEPENDENCY` delete-envelope payload from
    /// the pre-delete `(version, created_at)` tuple loaded by
    /// [`Self::pre_apply_check`]. The version is captured before the
    /// DELETE — peers' LWW resolver needs the original row's
    /// `(version, created_at)` to compare against any concurrent
    /// re-add that may have raced the tombstone.
    #[must_use]
    pub fn payload_for_envelope(&self, pre_delete: &PreDeleteState) -> Value {
        serde_json::json!({
            "task_id": self.task_id,
            "depends_on_task_id": self.depends_on_task_id,
            "version": pre_delete.version,
            "created_at": pre_delete.created_at,
        })
    }

    /// Composite `(task_id, depends_on_task_id)` entity id used on the
    /// outbox tombstone envelope.
    #[must_use]
    pub fn entity_id(&self) -> TaskDependencyEdgeId {
        TaskDependencyEdgeId::new(self.task_id, self.depends_on_task_id)
    }
}

impl<'a> Mutation for RemoveTaskDependencyMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        EDGE_TASK_DEPENDENCY
    }
    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        // Stamp a session-bound version so the executor's HLC session
        // accounts for this mutation even though the SQL itself is a
        // DELETE (the version is consumed by the finalizer when it
        // re-stamps the parent task upsert).
        let _ = hlc.next_version_string();
        let deleted = dependencies::delete_dependency_edges_batch(
            conn,
            self.task_id,
            std::slice::from_ref(self.depends_on_task_id),
        )?;
        let entity_id = TaskDependencyEdgeId::new(self.task_id, self.depends_on_task_id);
        Ok(MutationOutput::new(
            serde_json::json!({
                "task_id": self.task_id,
                "depends_on_task_id": self.depends_on_task_id,
                "deleted": deleted,
            }),
            format!("Removed dependency edge {entity_id}"),
        ))
    }
}

fn dependency_edge_exists(
    conn: &Connection,
    task_id: &TaskId,
    depends_on_task_id: &TaskId,
) -> Result<bool, StoreError> {
    conn.query_row(
        "SELECT 1 FROM task_dependencies \
         WHERE task_id = ?1 AND depends_on_task_id = ?2",
        rusqlite::params![task_id.as_str(), depends_on_task_id.as_str()],
        |_| Ok(()),
    )
    .map(|_: ()| true)
    .or_else(|err| match err {
        rusqlite::Error::QueryReturnedNoRows => Ok(false),
        other => Err(StoreError::from(other)),
    })
}

fn load_pre_delete_state(
    conn: &Connection,
    task_id: &TaskId,
    depends_on_task_id: &TaskId,
) -> Result<Option<PreDeleteState>, StoreError> {
    match conn.query_row(
        "SELECT version, created_at FROM task_dependencies \
         WHERE task_id = ?1 AND depends_on_task_id = ?2",
        rusqlite::params![task_id.as_str(), depends_on_task_id.as_str()],
        |row| {
            Ok(PreDeleteState {
                version: row.get(0)?,
                created_at: row.get(1)?,
            })
        },
    ) {
        Ok(state) => Ok(Some(state)),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
        Err(err) => Err(StoreError::from(err)),
    }
}
