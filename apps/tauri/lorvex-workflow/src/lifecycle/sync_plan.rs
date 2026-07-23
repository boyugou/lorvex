//! Shared sync fan-out inventory for lifecycle transitions.
//!
//! The workflow layer owns the semantic side-effect result. Runtime
//! surfaces still own their outbox writer, undo hold, changelog, and
//! response contracts, but they should not rediscover which related
//! entities a lifecycle transition touched. This plan is the narrow
//! bridge: it borrows the transition result and exposes the exact
//! related-entity buckets every surface must enqueue.
//!
//! Deliberately out of scope: direct checklist-item / reminder CRUD
//! and permanent-delete cascades. Those paths own their primary entity
//! mutation at an entity-specific boundary, not as a lifecycle status
//! transition result. Keeping them out of this status-transition plan
//! preserves their delete-envelope / undo / snapshot contracts while
//! this module owns the shared fan-out that is actually produced by
//! completion, cancel, reopen, and status-change transitions.

use crate::status_side_effects::StatusSideEffectResult;

use super::{
    CancelLifecycleTransitionResult, CompletionLifecycleTransitionResult, CopiedTagEdge,
    DeletedDependencyEdge, LifecycleTransitionResult, ReopenLifecycleTransitionResult,
    SuccessorCancelSideEffects,
};

/// Reminder/dependency side effects produced by a status transition.
#[derive(Debug, Clone, Copy)]
pub struct StatusSideEffectSyncPlan<'a> {
    pub cancelled_reminder_ids: &'a [String],
    pub affected_dependent_ids: &'a [String],
    pub deleted_dependency_edges: &'a [DeletedDependencyEdge],
}

impl<'a> StatusSideEffectSyncPlan<'a> {
    pub const fn empty() -> Self {
        Self {
            cancelled_reminder_ids: &[],
            affected_dependent_ids: &[],
            deleted_dependency_edges: &[],
        }
    }

    fn from_status_effects(effects: &'a StatusSideEffectResult) -> Self {
        Self {
            cancelled_reminder_ids: &effects.cancelled_reminder_ids,
            affected_dependent_ids: &effects.affected_dependent_ids,
            deleted_dependency_edges: &effects.deleted_dependency_edges,
        }
    }

    fn from_successor_cancel(effects: &'a SuccessorCancelSideEffects) -> Self {
        Self {
            cancelled_reminder_ids: &effects.cancelled_reminder_ids,
            affected_dependent_ids: &effects.affected_dependent_ids,
            deleted_dependency_edges: &effects.deleted_dependency_edges,
        }
    }

    fn from_cancel(result: &'a CancelLifecycleTransitionResult) -> Self {
        Self {
            cancelled_reminder_ids: &result.cancelled_reminder_ids,
            affected_dependent_ids: &result.affected_dependent_ids,
            deleted_dependency_edges: &result.deleted_dependency_edges,
        }
    }
}

/// Complete related-entity sync inventory for a lifecycle transition.
#[derive(Debug, Clone, Copy)]
pub struct LifecycleSyncPlan<'a> {
    pub status: StatusSideEffectSyncPlan<'a>,
    pub reopened_reminder_ids: &'a [String],
    pub spawned_successor_id: Option<&'a str>,
    pub spawned_successor_tag_edges: &'a [CopiedTagEdge],
    pub spawned_successor_checklist_item_ids: &'a [String],
    pub spawned_successor_reminder_ids: &'a [String],
    pub cancelled_successor_ids: &'a [String],
    pub successor_cancel: StatusSideEffectSyncPlan<'a>,
    pub rewired_focus_schedule_dates: &'a [String],
    pub rewired_current_focus_dates: &'a [String],
}

impl<'a> LifecycleSyncPlan<'a> {
    pub const fn empty() -> Self {
        Self {
            status: StatusSideEffectSyncPlan::empty(),
            reopened_reminder_ids: &[],
            spawned_successor_id: None,
            spawned_successor_tag_edges: &[],
            spawned_successor_checklist_item_ids: &[],
            spawned_successor_reminder_ids: &[],
            cancelled_successor_ids: &[],
            successor_cancel: StatusSideEffectSyncPlan::empty(),
            rewired_focus_schedule_dates: &[],
            rewired_current_focus_dates: &[],
        }
    }

    pub fn from_completion(result: &'a CompletionLifecycleTransitionResult) -> Self {
        Self {
            status: StatusSideEffectSyncPlan {
                cancelled_reminder_ids: &result.cancelled_reminder_ids,
                affected_dependent_ids: &[],
                deleted_dependency_edges: &[],
            },
            spawned_successor_id: result.spawned_successor_id.as_deref(),
            spawned_successor_tag_edges: &result.spawned_successor_tag_edges,
            spawned_successor_checklist_item_ids: &result.spawned_successor_checklist_item_ids,
            spawned_successor_reminder_ids: &result.spawned_successor_reminder_ids,
            rewired_focus_schedule_dates: &result.rewired_focus_schedule_dates,
            rewired_current_focus_dates: &result.rewired_current_focus_dates,
            ..Self::empty()
        }
    }

    pub fn from_cancel(result: &'a CancelLifecycleTransitionResult) -> Self {
        Self {
            status: StatusSideEffectSyncPlan::from_cancel(result),
            spawned_successor_id: result.spawned_successor_id.as_deref(),
            spawned_successor_tag_edges: &result.spawned_successor_tag_edges,
            spawned_successor_checklist_item_ids: &result.spawned_successor_checklist_item_ids,
            spawned_successor_reminder_ids: &result.spawned_successor_reminder_ids,
            rewired_focus_schedule_dates: &result.rewired_focus_schedule_dates,
            rewired_current_focus_dates: &result.rewired_current_focus_dates,
            ..Self::empty()
        }
    }

    pub fn from_transition(result: &'a LifecycleTransitionResult) -> Self {
        Self {
            status: StatusSideEffectSyncPlan::from_status_effects(&result.side_effects),
            spawned_successor_id: result.spawned_successor_id.as_deref(),
            spawned_successor_tag_edges: &result.spawned_successor_tag_edges,
            spawned_successor_checklist_item_ids: &result.spawned_successor_checklist_item_ids,
            spawned_successor_reminder_ids: &result.spawned_successor_reminder_ids,
            cancelled_successor_ids: &result.cancelled_successor_ids,
            successor_cancel: StatusSideEffectSyncPlan::from_successor_cancel(
                &result.successor_cancel_side_effects,
            ),
            rewired_focus_schedule_dates: &result.rewired_focus_schedule_dates,
            rewired_current_focus_dates: &result.rewired_current_focus_dates,
            reopened_reminder_ids: &[],
        }
    }

    pub fn from_reopen(result: &'a ReopenLifecycleTransitionResult) -> Self {
        Self {
            reopened_reminder_ids: &result.reopened_reminder_ids,
            ..Self::from_transition(&result.transition)
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::lifecycle::{
        CancelLifecycleTransitionResult, CompletionLifecycleTransitionResult, CopiedTagEdge,
        DeletedDependencyEdge, LifecycleTransitionResult, ReopenLifecycleTransitionResult,
        SuccessorCancelSideEffects,
    };
    use crate::status_side_effects::StatusSideEffectResult;

    use super::LifecycleSyncPlan;

    fn edge() -> DeletedDependencyEdge {
        DeletedDependencyEdge {
            task_id: "dependent".to_string(),
            depends_on_task_id: "blocked".to_string(),
            created_at: "2026-05-08T00:00:00Z".to_string(),
            version: "v-edge".to_string(),
        }
    }

    fn tag_edge() -> CopiedTagEdge {
        CopiedTagEdge {
            task_id: "successor".to_string(),
            tag_id: "tag-a".to_string(),
            version: "v-tag".to_string(),
            created_at: "2026-05-08T00:00:00Z".to_string(),
        }
    }

    #[test]
    fn completion_plan_exposes_spawn_and_rewire_buckets() {
        let result = CompletionLifecycleTransitionResult {
            updated: true,
            cancelled_reminder_ids: vec!["cancelled-reminder".to_string()],
            spawned_successor_id: Some("successor".to_string()),
            spawned_successor_tag_edges: vec![tag_edge()],
            spawned_successor_checklist_item_ids: vec!["check-1".to_string()],
            spawned_successor_reminder_ids: vec!["reminder-1".to_string()],
            rewired_focus_schedule_dates: vec!["2026-05-09".to_string()],
            rewired_current_focus_dates: vec!["2026-05-08".to_string()],
        };

        let plan = LifecycleSyncPlan::from_completion(&result);

        assert_eq!(plan.status.cancelled_reminder_ids, ["cancelled-reminder"]);
        assert_eq!(plan.spawned_successor_id, Some("successor"));
        assert_eq!(plan.spawned_successor_tag_edges.len(), 1);
        assert_eq!(plan.spawned_successor_checklist_item_ids, ["check-1"]);
        assert_eq!(plan.spawned_successor_reminder_ids, ["reminder-1"]);
        assert_eq!(plan.rewired_focus_schedule_dates, ["2026-05-09"]);
        assert_eq!(plan.rewired_current_focus_dates, ["2026-05-08"]);
    }

    #[test]
    fn cancel_plan_exposes_dependency_and_spawn_buckets() {
        let result = CancelLifecycleTransitionResult {
            updated: true,
            cancelled_reminder_ids: vec!["cancelled-reminder".to_string()],
            affected_dependent_ids: vec!["dependent".to_string()],
            deleted_dependency_edges: vec![edge()],
            spawned_successor_id: Some("successor".to_string()),
            spawned_successor_tag_edges: vec![tag_edge()],
            spawned_successor_checklist_item_ids: vec!["check-1".to_string()],
            spawned_successor_reminder_ids: vec!["reminder-1".to_string()],
            rewired_focus_schedule_dates: vec!["2026-05-09".to_string()],
            rewired_current_focus_dates: vec!["2026-05-08".to_string()],
        };

        let plan = LifecycleSyncPlan::from_cancel(&result);

        assert_eq!(plan.status.cancelled_reminder_ids, ["cancelled-reminder"]);
        assert_eq!(plan.status.affected_dependent_ids, ["dependent"]);
        assert_eq!(plan.status.deleted_dependency_edges.len(), 1);
        assert_eq!(plan.spawned_successor_id, Some("successor"));
        assert_eq!(plan.spawned_successor_tag_edges.len(), 1);
    }

    #[test]
    fn reopen_plan_keeps_reopened_reminders_separate_from_successor_cancel_reminders() {
        let transition = LifecycleTransitionResult {
            side_effects: StatusSideEffectResult {
                cancelled_reminder_ids: vec!["status-reminder".to_string()],
                affected_dependent_ids: vec!["status-dependent".to_string()],
                deleted_dependency_edges: vec![edge()],
            },
            spawned_successor_id: None,
            spawned_successor_tag_edges: vec![],
            spawned_successor_checklist_item_ids: vec![],
            spawned_successor_reminder_ids: vec![],
            cancelled_successor_ids: vec!["cancelled-successor".to_string()],
            successor_cancel_side_effects: SuccessorCancelSideEffects {
                cancelled_reminder_ids: vec!["successor-reminder".to_string()],
                affected_dependent_ids: vec!["successor-dependent".to_string()],
                deleted_dependency_edges: vec![edge()],
            },
            rewired_focus_schedule_dates: vec!["2026-05-09".to_string()],
            rewired_current_focus_dates: vec!["2026-05-08".to_string()],
        };
        let result = ReopenLifecycleTransitionResult {
            updated: true,
            reopened_reminder_ids: vec!["reopened-reminder".to_string()],
            transition,
        };

        let plan = LifecycleSyncPlan::from_reopen(&result);

        assert_eq!(plan.reopened_reminder_ids, ["reopened-reminder"]);
        assert_eq!(plan.status.cancelled_reminder_ids, ["status-reminder"]);
        assert_eq!(plan.cancelled_successor_ids, ["cancelled-successor"]);
        assert_eq!(
            plan.successor_cancel.cancelled_reminder_ids,
            ["successor-reminder"]
        );
        assert_eq!(
            plan.successor_cancel.affected_dependent_ids,
            ["successor-dependent"]
        );
    }
}
