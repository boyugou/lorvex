//! Metrics collection for task pattern analysis.
//!
//! Per-concern siblings:
//!
//! * `thresholds.rs` — `InsightThresholds` + `InsightPreferenceKey` +
//!   `load_insight_thresholds`: configurable severity / window / count
//!   thresholds loaded from the `preferences` table via a single
//!   batched `WHERE key IN (...)` scan with typed enum dispatch.
//! * `collect.rs` — `LearningMetrics` + `collect_task_pattern_metrics`:
//!   the SQL aggregation pipeline that walks `tasks` / `lists` / the
//!   estimate summary to produce the per-window pattern snapshot.

mod collect;
mod thresholds;

pub(super) use collect::{collect_task_pattern_metrics, LearningMetrics};
#[cfg(test)]
pub(super) use thresholds::load_insight_thresholds;

#[cfg(test)]
mod tests;
