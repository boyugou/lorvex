//! `TaskRow` — the parent envelope assembling the four sub-structs into one
//! flat-serializing row. See the per-concern files (`core.rs`, `scheduling.rs`,
//! `recurrence.rs`, `lifecycle.rs`) for the field-level types.

use super::core::TaskCore;
use super::lifecycle::TaskLifecycleTimestamps;
use super::recurrence::TaskRecurrenceState;
use super::scheduling::TaskScheduling;

/// A row read from the `tasks` table. Mirrors the full column set including
/// convergence-era columns (`version`, `recurrence_instance_key`).
///
/// split the original 28-field flat struct into four
/// focused sub-structs by lifecycle role. `#[serde(flatten)]` keeps the
/// JSON wire format byte-identical so on-disk `payload_shadow` JSON and
/// cross-peer apply continue to parse without migration.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TaskRow {
    #[serde(flatten)]
    pub(crate) core: TaskCore,
    #[serde(flatten)]
    pub(crate) scheduling: TaskScheduling,
    #[serde(flatten)]
    pub(crate) recurrence: TaskRecurrenceState,
    #[serde(flatten)]
    pub(crate) lifecycle: TaskLifecycleTimestamps,
}

impl TaskRow {
    /// Compose a [`TaskRow`] from its four already-validated sub-structs.
    /// External constructors (capture/duplicate, fixtures) build the four
    /// pieces separately and assemble them here so the row-level fields
    /// stay sealed (#3289).
    pub const fn from_parts(
        core: TaskCore,
        scheduling: TaskScheduling,
        recurrence: TaskRecurrenceState,
        lifecycle: TaskLifecycleTimestamps,
    ) -> Self {
        Self {
            core,
            scheduling,
            recurrence,
            lifecycle,
        }
    }

    pub const fn core(&self) -> &TaskCore {
        &self.core
    }
    pub const fn scheduling(&self) -> &TaskScheduling {
        &self.scheduling
    }
    pub const fn recurrence(&self) -> &TaskRecurrenceState {
        &self.recurrence
    }
    pub const fn lifecycle(&self) -> &TaskLifecycleTimestamps {
        &self.lifecycle
    }

    /// Borrow the row as four sub-struct refs at once. Convenience for
    /// callers that need all four pieces (e.g. SQL bind sites copying
    /// every field) without four separate accessor calls.
    pub const fn parts(
        &self,
    ) -> (
        &TaskCore,
        &TaskScheduling,
        &TaskRecurrenceState,
        &TaskLifecycleTimestamps,
    ) {
        (
            &self.core,
            &self.scheduling,
            &self.recurrence,
            &self.lifecycle,
        )
    }

    /// Consume the row, yielding owned sub-structs. Pairs with
    /// [`TaskCore::into_fields`] etc. for callers that need to move the
    /// inner `String` fields into a downstream model without cloning.
    pub fn into_parts(
        self,
    ) -> (
        TaskCore,
        TaskScheduling,
        TaskRecurrenceState,
        TaskLifecycleTimestamps,
    ) {
        (self.core, self.scheduling, self.recurrence, self.lifecycle)
    }
}
