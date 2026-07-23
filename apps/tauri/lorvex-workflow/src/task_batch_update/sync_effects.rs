//! Aggregated sync side-effects from a batch run.
//!
//! Type aliases for the per-row [`TaskUpdateSyncEffects`] accumulator
//! and the per-row audit records the surface adapter flushes after the
//! batch completes. Keeping these names co-located with the batch
//! driver lets every surface (MCP, Tauri, CLI) destructure the batch
//! output under the historical batch names while the canonical type
//! definitions stay in [`crate::task_update`].

pub use crate::task_update::{
    TaskTagEdgeDelete, TaskUpdateSyncEffects as BatchUpdateSyncEffects,
    UpdateTaskCancelledSuccessor as BatchUpdateCancelledSuccessor,
    UpdateTaskFocusRewireAudit as BatchUpdateFocusRewireAudit,
    UpdateTaskSpawnedSuccessor as BatchUpdateSpawnedSuccessor,
};
