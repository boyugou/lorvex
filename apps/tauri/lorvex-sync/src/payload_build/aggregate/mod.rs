//! Canonical sync payload builder for aggregate roots that own
//! materialized child collections.
//!
//! For aggregates that own a child collection rebuilt on the
//! receiving peer (`focus_schedule.blocks`, `current_focus.task_ids`,
//! `daily_review.linked_task_ids`/`linked_list_ids`,
//! `calendar_event.attendees`), the children must be embedded in the
//! envelope payload. A `pragma_table_info`-only enqueue (the shape
//! the generic `enqueue_entity_upsert` path emits for non-aggregate
//! rows) would ship the parent header alone, leaving the receiving
//! peer's child collection to drift across devices with no
//! diagnostic.
//!
//! This module is the single source of truth for "what does the
//! canonical sync payload of an aggregate root look like?". It owns
//! every aggregate whose payload requires structured child enrichment.
//! Aggregates whose children are independent sync entities (`task`,
//! `list`, `habit`) intentionally fall through this
//! function — the bare-columns reader in `outbox_enqueue` is correct
//! for them. The four aggregates handled here are:
//!
//! | Parent           | Embedded children                                  |
//! |------------------|----------------------------------------------------|
//! | `current_focus`  | `task_ids` (rebuilt from `current_focus_items`)    |
//! | `focus_schedule` | `blocks` (rebuilt from `focus_schedule_blocks`)    |
//! | `daily_review`   | `linked_task_ids`, `linked_list_ids` (link tables) |
//! | `calendar_event` | `attendees` with shadow extras (#2317)             |
//!
//! Every site that builds the aggregate JSON for one of these four
//! entity types delegates here, so the apply-side materialization
//! logic in `lorvex_sync::apply::day_scoped` /
//! `lorvex_sync::apply::aggregate::calendar_event` always sees the
//! children it needs to rebuild.
//!
//! The dispatcher and registry live in [`dispatch`]; each per-aggregate
//! builder lives in a focused sibling module
//! ([`current_focus`], [`focus_schedule`], [`daily_review`],
//! [`calendar_event`]). Public API is re-exported below.

mod calendar_event;
mod current_focus;
mod daily_review;
mod dispatch;
mod focus_schedule;

pub use dispatch::{
    build_aggregate_payload, kind_is_aggregate_root_with_embedded_children,
    AGGREGATE_ROOT_KINDS_WITH_EMBEDDED_CHILDREN,
};

#[cfg(test)]
mod tests;
