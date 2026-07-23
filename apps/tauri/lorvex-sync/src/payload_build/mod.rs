//! Canonical sync-payload builders.
//!
//! Canonical aggregate-payload builders.
//!
//! [`aggregate`] is the single source of truth for the envelope shape
//! of aggregate roots that own materialized child collections rebuilt
//! on the receiving peer (`current_focus.task_ids`,
//! `focus_schedule.blocks`, `daily_review.linked_task_ids` +
//! `linked_list_ids`, `calendar_event.attendees`). Every site that
//! emits aggregate JSON for one of these four entity types delegates
//! here, so the apply-side materialization logic in
//! `crate::apply::day_scoped` /
//! `crate::apply::aggregate::calendar_event` always sees the children
//! it needs to rebuild.
//!
//! Companion "simple per-entity row → JSON" loaders live in
//! [`lorvex_store::payload_loaders`] — those are pure SELECTs that
//! the `lorvex-workflow` mutation paths reach for when emitting
//! tombstone snapshots. Keeping them in `lorvex-store` preserves the
//! `workflow → sync` dependency direction; hoisting them here would
//! invert it.

pub mod aggregate;
