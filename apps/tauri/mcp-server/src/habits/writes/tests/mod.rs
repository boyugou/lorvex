//! Habit write-tool tests, split by domain so a failing assertion
//! localizes to a single concern (create / update / unarchive,
//! complete / uncomplete, delete cascade, batch-complete atomicity).

mod batch_complete;
mod complete_uncomplete;
mod create_update;
mod delete_habit;
mod support;
