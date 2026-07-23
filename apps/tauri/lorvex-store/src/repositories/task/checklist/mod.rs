//! `task_checklist_items` repository: per-item read API (`read`) plus
//! the cold-open markdown-body promotion migration (`promote`).
//!
//! The two concerns share the table but not their lifecycle: `read`
//! is the runtime query surface used everywhere, while `promote` runs
//! exactly once per cold-open connection and rewrites bodies into
//! rows.

mod promote;
mod read;

#[cfg(test)]
mod promote_tests;
#[cfg(test)]
mod read_tests;

pub(crate) use promote::promote_markdown_task_checklists;
pub use read::{
    list_task_checklist_items, list_task_checklist_items_for_tasks, TaskChecklistItemRow,
};
