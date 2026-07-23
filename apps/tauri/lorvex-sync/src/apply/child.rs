//! Apply handlers for independent child entities.
//!
//! These entities reference a parent aggregate root via FK but are synced as
//! independent envelopes (each has its own `id` PK and `version` column).
//!
//! The submodules below `use super::*;` to pick up these imports — that
//! glob is the canonical sharing channel, not a stylistic choice.

use rusqlite::{named_params, params, Connection, OptionalExtension};

use super::{ApplyError, LwwTieBreak};

mod habit_reminder_policy;
mod helpers;
mod memory_revision;
mod task_checklist_item;
mod task_reminder;

#[cfg(test)]
mod tests;

pub(crate) use habit_reminder_policy::{
    apply_habit_reminder_policy_delete, apply_habit_reminder_policy_upsert,
};
pub(crate) use memory_revision::{apply_memory_revision_delete, apply_memory_revision_upsert};
pub(crate) use task_checklist_item::{
    apply_task_checklist_item_delete, apply_task_checklist_item_upsert,
};
pub(crate) use task_reminder::{apply_task_reminder_delete, apply_task_reminder_upsert};
