//! Sync-effect accumulators for the task-create flow.
//!
//! [`CreateTaskSyncEffects`] is the canonical envelope every
//! consumer surface (mcp-server, CLI, Tauri commands) drives into
//! its outbox enqueue path. Lives separately so the orchestrator
//! stays focused on the control flow and so downstream surfaces can
//! reach for the type without pulling in the full create implementation.

#[derive(Debug, Default, Clone)]
pub struct TaskTagSyncEffects {
    pub tag_upsert_ids: Vec<String>,
    pub task_tag_edge_upsert_ids: Vec<String>,
}

#[derive(Debug, Default)]
pub struct CreateTaskSyncEffects {
    pub task_upsert_ids: Vec<String>,
    pub reminder_upsert_ids: Vec<String>,
    pub cancelled_reminder_ids: Vec<String>,
    pub dependency_edge_upsert_ids: Vec<String>,
    pub tag_upsert_ids: Vec<String>,
    pub task_tag_edge_upsert_ids: Vec<String>,
    pub spawned_successors: Vec<super::input::CreateTaskSpawnedSuccessor>,
    pub spawned_successor_tag_edges: Vec<crate::lifecycle::CopiedTagEdge>,
    pub spawned_successor_checklist_item_ids: Vec<String>,
    pub spawned_successor_reminder_ids: Vec<String>,
    pub focus_rewire_audits: Vec<super::input::CreateTaskFocusRewireAudit>,
    pub rewired_focus_schedule_dates: Vec<String>,
    pub rewired_current_focus_dates: Vec<String>,
}
