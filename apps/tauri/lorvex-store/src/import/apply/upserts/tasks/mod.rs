//! Task aggregate, edge, and child upserts for snapshot import.

mod aggregate;
mod checklist;
mod children;
mod edges;
#[cfg(test)]
mod tests;

pub(in crate::import::apply::upserts) use aggregate::upsert_task;
pub(in crate::import::apply::upserts) use children::{
    upsert_task_checklist_item, upsert_task_reminder,
};
pub(in crate::import::apply::upserts) use edges::{
    upsert_task_calendar_event_link, upsert_task_dependency, upsert_task_tag,
};
