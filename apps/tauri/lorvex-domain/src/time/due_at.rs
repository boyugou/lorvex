//! `DueAt` — typed carrier for the (`due_date`, `due_time`) pair that
//! makes the implicit invariant "`due_time` without `due_date` is
//! invalid" representable in the type system, plus its wire-format
//! adapter `DueAtFlat`.

use serde::{Deserialize, Serialize};

use super::date::Date;
use super::time_of_day::TimeOfDay;

/// Tri-state carrier for a task's due moment.
///
/// and `due_time: Option<TimeOfDay>` as two independent slots, with
/// the implicit invariant — a `due_time` without a `due_date` is
/// nonsensical (a clock with no calendar) — documented only in field
/// comments. The schema CHECK enforces it on write but the Rust types
/// let any combination flow through, so the only consequence of a
/// stray `(None, Some)` was a silent SQL CHECK failure surfaced as a
/// generic `StoreError` far from the call site.
///
/// `DueAt` closes the gap: every constructor routes through one of
/// three variants, and the only way to reach the `(None, Some)` shape
/// is to pass it through [`DueAt::from_optional_pair`], which rejects
/// it as a typed `ValidationError` at the boundary.
///
/// Wire format is preserved: serialization round-trips through the two
/// flat keys (`due_date`, `due_time`) via `flatten`-compatible
/// [`DueAtFlat`] so the JSON shape on `payload_shadow`,
/// `TaskRow`, and `TaskCreated` envelopes is byte-identical to the
/// pre-typed-carrier era.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DueAt {
    /// No due assigned. Both `due_date` and `due_time` are NULL.
    #[default]
    Unscheduled,
    /// Due on a specific calendar day, with no clock time. The task
    /// is "all-day-due" — the user intends to finish it sometime
    /// during the day.
    OnDay(Date),
    /// Due at a specific moment: a calendar day and a clock time.
    AtMoment { date: Date, time: TimeOfDay },
}

impl DueAt {
    /// Parse and validate the legacy string-shaped `(due_date, due_time)`
    /// pair at write boundaries that have not yet lifted the fields into
    /// [`Date`] / [`TimeOfDay`] newtypes. This keeps the "time requires
    /// date" invariant in one place instead of re-implementing the
    /// `(None, Some)` check in every Tauri / MCP / CLI / import caller.
    pub fn from_optional_str_pair(
        date: Option<&str>,
        time: Option<&str>,
    ) -> Result<Self, crate::validation::ValidationError> {
        let date = date.map(Date::parse).transpose()?;
        let time = time.map(TimeOfDay::parse).transpose()?;
        Self::from_optional_pair(date, time)
    }

    /// Construct from the boundary `(Option<Date>, Option<TimeOfDay>)`
    /// pair that flows in from SQL row reads, sync apply payloads, and
    /// MCP arg shapes. Rejects the `(None, Some)` combination — a
    /// clock time without a calendar day is meaningless in the schema
    /// CHECK and at the user-facing UX level.
    ///
    /// `(Some, Some)` → `AtMoment`, `(Some, None)` → `OnDay`,
    /// `(None, None)` → `Unscheduled`.
    pub fn from_optional_pair(
        date: Option<Date>,
        time: Option<TimeOfDay>,
    ) -> Result<Self, crate::validation::ValidationError> {
        match (date, time) {
            (None, None) => Ok(Self::Unscheduled),
            (Some(date), None) => Ok(Self::OnDay(date)),
            (Some(date), Some(time)) => Ok(Self::AtMoment { date, time }),
            (None, Some(_)) => Err(crate::validation::ValidationError::Message(
                "due_time without due_date is invalid: a clock time requires a calendar day"
                    .to_string(),
            )),
        }
    }

    /// Decompose into the boundary `(Option<Date>, Option<TimeOfDay>)`
    /// pair. Used by SQL bind sites and wire-format adapters whose
    /// underlying schema/payload still uses two separate columns
    /// (`due_date`, `due_time`) rather than the typed pair.
    pub const fn into_optional_pair(self) -> (Option<Date>, Option<TimeOfDay>) {
        match self {
            Self::Unscheduled => (None, None),
            Self::OnDay(date) => (Some(date), None),
            Self::AtMoment { date, time } => (Some(date), Some(time)),
        }
    }

    /// The due calendar date, if any. `None` when [`DueAt::Unscheduled`].
    pub const fn date(&self) -> Option<Date> {
        match *self {
            Self::Unscheduled => None,
            Self::OnDay(d) => Some(d),
            Self::AtMoment { date, .. } => Some(date),
        }
    }

    /// The due clock time, if any. Only `Some` for [`DueAt::AtMoment`].
    pub const fn time(&self) -> Option<TimeOfDay> {
        match *self {
            Self::AtMoment { time, .. } => Some(time),
            _ => None,
        }
    }

    /// True iff the carrier holds any due moment (date-only or
    /// date+time). Mirrors `due_date.is_some()` on the legacy pair.
    pub const fn is_scheduled(&self) -> bool {
        !matches!(self, Self::Unscheduled)
    }
}

/// Wire-format adapter for [`DueAt`] that serializes / deserializes
/// as the legacy two flat keys (`due_date`, `due_time`). Used inside
/// `#[serde(flatten)]` slots so the typed carrier round-trips through
/// the same JSON shape that the pre-typed-carrier code wrote.
///
/// Construction routes through [`DueAt::from_optional_pair`] so the
/// `(None, Some)` invariant violation surfaces as a deserialize
/// error at the wire boundary instead of being silently accepted.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize)]
pub struct DueAtFlat {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub due_date: Option<Date>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub due_time: Option<TimeOfDay>,
}

impl From<DueAt> for DueAtFlat {
    fn from(due: DueAt) -> Self {
        let (due_date, due_time) = due.into_optional_pair();
        Self { due_date, due_time }
    }
}

impl TryFrom<DueAtFlat> for DueAt {
    type Error = crate::validation::ValidationError;

    fn try_from(flat: DueAtFlat) -> Result<Self, Self::Error> {
        DueAt::from_optional_pair(flat.due_date, flat.due_time)
    }
}
