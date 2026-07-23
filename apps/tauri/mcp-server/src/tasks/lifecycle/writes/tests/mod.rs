//! Task-lifecycle write-tool tests, split by domain so a failing
//! assertion localizes to a single concern (defer / complete-cancel /
//! AI notes / checklist / reminders / permanent delete).

mod ai_notes;
mod checklist;
mod complete_cancel;
mod defer;
mod permanent_delete;
mod reminders;
mod support;
