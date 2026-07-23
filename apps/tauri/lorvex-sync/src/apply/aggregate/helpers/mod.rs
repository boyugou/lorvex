//! Shared payload-parsing primitives and cascading-tombstone helpers
//! for the per-entity aggregate handlers.
//!
//! Every aggregate-root entity (`task`, `list`, `habit`, `calendar_event`,
//! `calendar_subscription`, `preference`, `memory`) decodes
//! its JSON payload through these helpers so the "absent vs null vs empty
//! string" semantics, the Unicode-scrub policy, and the `ApplyError`
//! shape all stay consistent across handlers. The tombstone-cascade
//! helpers reused by every entity whose delete must pre-tombstone its
//! child / edge rows ahead of SQLite's `ON DELETE CASCADE`.
//!
//! #3303 P2 split — the previous 606-LOC `helpers.rs` was a grab-bag
//! of three independent concerns. Each now lives in its own sibling
//! so the LWW gate, the JSON tri-state extraction, and the cascade
//! tombstone fanout can be reasoned about independently:
//!
//!   * `lww_gates` — `DeleteLwwDecision`, `evaluate_delete_lww`,
//!     `CascadingDeleteDecision`, `gate_then_cascade`,
//!     `gate_then_cascade_into_outcome`.
//!   * `partial_patch` — `optional_object_array`,
//!     `optional_str_preserving_empty`, `nullable_str_or_clear`,
//!     `split_partial_str_value`, `split_partial_i64_value`,
//!     `optional_i64_preserving_null`, `scrub`, `scrub_opt`.
//!   * `tombstone_cascade` — `tombstone_composite_edges`,
//!     `tombstone_child_rows` (and the private `max_cascade_version`
//!     they share).

mod lww_gates;
mod partial_patch;
mod tombstone_cascade;

/// Status string constants (mirrors `tasks.status` CHECK).
///
/// redeclared as local `&str` constants
/// inside this module; replaced with a re-export of the canonical
/// definitions in `lorvex_domain::naming` to eliminate the silent-drift
/// hazard.
pub(in crate::apply::aggregate) use lorvex_domain::naming::{
    STATUS_CANCELLED, STATUS_COMPLETED, STATUS_OPEN, STATUS_SOMEDAY,
};

/// Re-export the canonical `version_cmp` so existing call sites
/// (`use super::helpers::version_cmp`) keep compiling.
///
/// definition lives in `apply/mod.rs`; this is the
/// only place inside the aggregate-helpers tree that still names it.
pub(in crate::apply::aggregate) use crate::apply::version_cmp;

// The shared primitives (`str_field`, `i64_field`, `required_str`,
// `required_i64`, `optional_str`, `optional_bool_as_i64`) live in
// `apply::json_helpers` so every apply submodule shares one
// definition. Only the aggregate-specific helpers live in
// `partial_patch`; the rest are re-exported from here so existing
// `use super::helpers::*` import sites keep compiling.
pub(in crate::apply::aggregate) use crate::apply::json_helpers::{
    optional_bool_as_i64, optional_i64, optional_str, required_i64, required_str,
};

pub(in crate::apply::aggregate) use lww_gates::{
    evaluate_delete_lww, gate_then_cascade_into_outcome, DeleteLwwDecision,
};
pub(in crate::apply::aggregate) use partial_patch::{
    nullable_str_or_clear, optional_i64_preserving_null, optional_object_array,
    optional_str_preserving_empty, scrub, scrub_opt, split_partial_i64_value,
    split_partial_str_value,
};
pub(in crate::apply::aggregate) use tombstone_cascade::{
    tombstone_child_rows, tombstone_composite_edges,
};
