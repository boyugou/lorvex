//! Habit-domain primitives shared across the workspace.
//!
//! a single 772-line `habits.rs`; split per-concern so each
//! file holds one cohesive group (cadence wire shape, archive intent,
//! input drafts, validated outputs, completion math, sync payload).
//! The public surface is preserved verbatim through the re-exports
//! below — every external `use lorvex_domain::habits::*` continues to
//! compile, and the crate-root re-exports in `lib.rs` (which import
//! from `crate::habits::...`) are unaffected.

mod archive;
mod cadence;
mod draft;
mod progress;
mod streaks;
mod sync_payload;
mod validated;

pub use archive::ArchiveAction;
pub use cadence::{HabitCadence, HabitFrequencyFields, HabitFrequencyType, WeekDay};
pub use draft::{HabitCreateDraft, HabitUpdateDraft};
pub use progress::{
    effective_monthly_day, habit_expected_completions_in_days, habit_progress_kind,
    habit_required_completions_per_period, habit_uses_week_bucket, is_habit_reminder_day,
    is_habit_scheduled_on_day, HabitProgressKind,
};
pub use streaks::{
    compute_habit_current_streak, compute_habit_longest_streak, HabitStreakFrequency,
};
pub use sync_payload::{habit_sync_payload, HabitSyncFields};
pub use validated::{
    validate_habit_create_draft, validate_habit_update_draft, HabitCreateParts, HabitUpdateParts,
    ValidatedHabitCreate, ValidatedHabitUpdate,
};

#[cfg(test)]
mod tests;
