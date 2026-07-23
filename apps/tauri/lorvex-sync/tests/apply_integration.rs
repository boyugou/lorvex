// trust: integration tests intentionally use unwrap() for assertion clarity —
// panics ARE the failure mode.
#![allow(clippy::unwrap_used)]

//! Integration tests for the lorvex-sync apply pipeline.
//!
//! Covers the Section 25 test matrix: idempotent apply, LWW ordering,
//! tombstone + upsert interactions, tag convergence, day-scoped aggregates,
//! edges, child entities, and changelog dedup.

#[path = "apply_integration/aggregates.rs"]
mod aggregates;
#[path = "apply_integration/calendar.rs"]
mod calendar;
#[path = "apply_integration/changelog.rs"]
mod changelog;
#[path = "apply_integration/edges_children.rs"]
mod edges_children;
#[path = "apply_integration/redirects.rs"]
mod redirects;
#[path = "apply_integration/support.rs"]
mod support;
#[path = "apply_integration/tags.rs"]
mod tags;
#[path = "apply_integration/task_lww.rs"]
mod task_lww;
