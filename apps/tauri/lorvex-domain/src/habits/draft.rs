use super::archive::ArchiveAction;
use super::cadence::HabitCadence;
use crate::Patch;

/// Boundary draft shape for `create_habit` callers.
///
/// The cadence rides as a single typed [`HabitCadence`] field so the
/// `(frequency_type, detail)` consistency invariants cannot be expressed
/// inconsistently at the construction seam (there is no way to pair a
/// `daily` type with a weekday set). Callers either build the variant
/// directly or bridge their typed columns through
/// [`HabitCadence::from_fields`]. A `None` cadence defaults to
/// [`HabitCadence::Daily`] during validation.
#[derive(Debug, Clone)]
pub struct HabitCreateDraft<'a> {
    pub name: &'a str,
    pub icon: Option<&'a str>,
    pub color: Option<&'a str>,
    pub cue: Option<&'a str>,
    pub frequency: Option<HabitCadence>,
    pub target_count: Option<i64>,
}

/// Boundary draft shape for `update_habit` patches.
///
/// `frequency: Option<HabitCadence>` is an all-or-nothing cadence patch:
/// `Some(cadence)` replaces the entire cadence atomically, `None` leaves it
/// untouched. Switching e.g. `Weekly { days: [mon] }` → `Daily` is
/// expressed by setting `frequency: Some(HabitCadence::Daily)`; the
/// cadence-detail columns clear implicitly because
/// [`HabitCadence::to_fields`] emits the schema DEFAULTs (weekdays cleared,
/// `day_of_month` NULL) for the variant.
#[derive(Debug, Clone, Default)]
pub struct HabitUpdateDraft<'a> {
    pub name: Option<&'a str>,
    pub icon: Patch<&'a str>,
    pub color: Patch<&'a str>,
    pub cue: Patch<&'a str>,
    pub frequency: Option<HabitCadence>,
    pub target_count: Option<i64>,
    pub archived: ArchiveAction,
}
