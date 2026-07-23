//! Apply handlers for relation edge entities.
//!
//! Edge entity_ids in sync envelopes use the composite format "part1:part2".
//! The handler splits on ":" to extract the two-column primary key.

mod dependency;
mod habit_completion;
mod helpers;
mod task_calendar_event_link;
mod task_tag;

pub(crate) use dependency::{apply_task_dependency_delete, apply_task_dependency_upsert};
pub(crate) use habit_completion::{apply_habit_completion_delete, apply_habit_completion_upsert};
pub(crate) use task_calendar_event_link::{
    apply_task_calendar_event_link_delete, apply_task_calendar_event_link_upsert,
};
pub(crate) use task_tag::{apply_task_tag_delete, apply_task_tag_upsert};

#[cfg(test)]
mod tests;
