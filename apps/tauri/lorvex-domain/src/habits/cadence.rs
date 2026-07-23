use chrono::{Datelike, NaiveDate};
use serde::{Deserialize, Serialize};

use crate::validation::ValidationError;

/// The closed vocabulary of `habits.frequency_type` wire values —
/// mirrors the schema CHECK constraint at `001_schema.sql` and the
/// TypeScript `HabitFrequencyType` union in `shared/src/types.ts`.
///
/// The richer typed primitive is [`HabitCadence`], which carries each
/// cadence's detail (the `weekly` weekday set, the `monthly`
/// day-of-month, the `times_per_week` count) in a dedicated field.
/// `HabitFrequencyType` is the bare rhythm tag — useful for IPC structs
/// that need to surface the wire-format string back to the UI without
/// reconstructing the full [`HabitCadence`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HabitFrequencyType {
    Daily,
    Weekly,
    Monthly,
    TimesPerWeek,
}

impl HabitFrequencyType {
    /// Stable wire-format token for this frequency type. Matches the
    /// `HABIT_FREQUENCY_*` constants in `naming/habit.rs` so the
    /// schema CHECK / round-trip parsers see the identical token.
    pub const fn as_wire_str(self) -> &'static str {
        match self {
            Self::Daily => crate::naming::HABIT_FREQUENCY_DAILY,
            Self::Weekly => crate::naming::HABIT_FREQUENCY_WEEKLY,
            Self::Monthly => crate::naming::HABIT_FREQUENCY_MONTHLY,
            Self::TimesPerWeek => crate::naming::HABIT_FREQUENCY_TIMES_PER_WEEK,
        }
    }

    /// Parse a wire-format token (`"daily"`, `"weekly"`, `"monthly"`,
    /// `"times_per_week"`) into the typed enum. Returns `None` for any
    /// other value so callers can fall back to a `ValidationError` with a
    /// caller-shaped message.
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            crate::naming::HABIT_FREQUENCY_DAILY => Some(Self::Daily),
            crate::naming::HABIT_FREQUENCY_WEEKLY => Some(Self::Weekly),
            crate::naming::HABIT_FREQUENCY_MONTHLY => Some(Self::Monthly),
            crate::naming::HABIT_FREQUENCY_TIMES_PER_WEEK => Some(Self::TimesPerWeek),
            _ => None,
        }
    }
}

/// Typed representation of a habit's recurrence rule.
///
/// The single source of truth for cadence detail; the schema, sync wire,
/// and DTOs store it as typed columns via [`HabitFrequencyFields`]
/// (`frequency_type` + `per_period_target` + `day_of_month`) plus the
/// `habit_weekdays` child. Bridge with
/// [`HabitCadence::from_fields`] / [`HabitCadence::to_fields`].
///
/// Variants:
/// - `Daily` — every day.
/// - `Weekly { days }` — weekly cadence. `None` `days` (or an empty set)
///   means "every day"; a non-empty set pins the specific weekdays. The
///   set is materialized into the `habit_weekdays` child rows.
/// - `Monthly { day_of_month }` — once per calendar month. `day_of_month`
///   (1–31, clamped to the month's last day at use sites) is the day
///   reminders fire on; `None` leaves it unspecified (reminders fall back
///   to the 1st). A completion on *any* day of the month counts toward
///   the month's target regardless.
/// - `TimesPerWeek { count }` — N completions per week with no weekday
///   pinning.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HabitCadence {
    Daily,
    Weekly { days: Option<Vec<WeekDay>> },
    Monthly { day_of_month: Option<i64> },
    TimesPerWeek { count: i64 },
}

/// Typed carrier for a habit's cadence columns — the storage / wire shape
/// of [`HabitCadence`]. Mirrors the `habits` schema columns:
/// `frequency_type` selects the rhythm; `weekdays` materializes into the
/// `habit_weekdays` child (weekly only); `per_period_target` is the N for
/// `times_per_week`; `day_of_month` is the monthly reminder day. Produced by
/// [`HabitCadence::to_fields`]; consumed by [`HabitCadence::from_fields`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HabitFrequencyFields {
    pub frequency_type: String,
    pub weekdays: Option<Vec<WeekDay>>,
    pub per_period_target: i64,
    pub day_of_month: Option<i64>,
}

impl HabitFrequencyFields {
    /// Build a fields carrier for `frequency_type` with the schema
    /// DEFAULTs (`per_period_target` 1, everything else absent).
    /// Detail-carrying constructors set the relevant field on top of this
    /// base.
    pub fn new(frequency_type: impl Into<String>) -> Self {
        Self {
            frequency_type: frequency_type.into(),
            weekdays: None,
            per_period_target: 1,
            day_of_month: None,
        }
    }
}

impl HabitCadence {
    /// Bridge the typed column fields (`frequency_type` + `weekdays` +
    /// `per_period_target` + `day_of_month`) into the typed
    /// [`HabitCadence`] enum. Returns `ValidationError` (the
    /// `From<ValidationError>` impls on `StoreError`, `McpError`,
    /// `AppError`, `CliError` let consumers `?`-propagate end-to-end) on
    /// an unsupported `frequency_type` or a non-positive
    /// `per_period_target` for a `times_per_week` cadence.
    pub fn from_fields(fields: &HabitFrequencyFields) -> Result<Self, ValidationError> {
        match fields.frequency_type.as_str() {
            crate::naming::HABIT_FREQUENCY_DAILY => Ok(Self::Daily),
            crate::naming::HABIT_FREQUENCY_WEEKLY => Ok(Self::Weekly {
                days: normalize_weekdays(fields.weekdays.clone()),
            }),
            crate::naming::HABIT_FREQUENCY_MONTHLY => Ok(Self::Monthly {
                day_of_month: normalize_day_of_month(fields.day_of_month),
            }),
            crate::naming::HABIT_FREQUENCY_TIMES_PER_WEEK => {
                if fields.per_period_target > 0 {
                    Ok(Self::TimesPerWeek {
                        count: fields.per_period_target,
                    })
                } else {
                    Err(ValidationError::Message(
                        "per_period_target must be positive for times_per_week".to_string(),
                    ))
                }
            }
            other => Err(ValidationError::Message(format!(
                "unsupported frequency_type '{other}'"
            ))),
        }
    }

    /// Render the typed cadence into its typed column fields.
    ///
    /// Invariants:
    /// - `Daily` → type `daily`, no detail (weekdays None, per_period_target
    ///   1, day_of_month None).
    /// - `Weekly { days: None }`/empty → type `weekly`, weekdays None
    ///   ("every day"); with a non-empty set → weekdays sorted+deduped
    ///   Mon..Sun.
    /// - `Monthly { day_of_month }` → type `monthly`, day_of_month carried
    ///   through (None allowed, clamped to 1..=31).
    /// - `TimesPerWeek { count }` → type `times_per_week`,
    ///   per_period_target = count.
    pub fn to_fields(&self) -> HabitFrequencyFields {
        match self {
            Self::Daily => HabitFrequencyFields::new(crate::naming::HABIT_FREQUENCY_DAILY),
            Self::Weekly { days } => HabitFrequencyFields {
                weekdays: normalize_weekdays(days.clone()),
                ..HabitFrequencyFields::new(crate::naming::HABIT_FREQUENCY_WEEKLY)
            },
            Self::Monthly { day_of_month } => HabitFrequencyFields {
                day_of_month: normalize_day_of_month(*day_of_month),
                ..HabitFrequencyFields::new(crate::naming::HABIT_FREQUENCY_MONTHLY)
            },
            Self::TimesPerWeek { count } => HabitFrequencyFields {
                per_period_target: (*count).max(1),
                ..HabitFrequencyFields::new(crate::naming::HABIT_FREQUENCY_TIMES_PER_WEEK)
            },
        }
    }

    /// The weekday set a `weekly` cadence pins, sorted Mon..Sun; `None` for
    /// every other cadence and for weekly-every-day. The materialized
    /// `habit_weekdays` child rows are exactly this set.
    pub fn weekdays(&self) -> Option<Vec<WeekDay>> {
        match self {
            Self::Weekly { days } => normalize_weekdays(days.clone()),
            _ => None,
        }
    }
}

/// Sort ascending (Mon..Sun) and drop duplicates; an empty/`None` input
/// maps to `None` (the "every day" idiom for a weekly cadence).
pub(crate) fn normalize_weekdays(days: Option<Vec<WeekDay>>) -> Option<Vec<WeekDay>> {
    let mut days = days?;
    days.sort_unstable();
    days.dedup();
    if days.is_empty() {
        None
    } else {
        Some(days)
    }
}

/// Clamp a `day_of_month` to `1..=31`, mapping anything outside that range
/// (or `None`) to `None` ("unspecified"). Lenient so a malformed value
/// degrades rather than blocking the habit from loading.
pub(crate) fn normalize_day_of_month(day: Option<i64>) -> Option<i64> {
    day.filter(|d| (1..=31).contains(d))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum WeekDay {
    Mon,
    Tue,
    Wed,
    Thu,
    Fri,
    Sat,
    Sun,
}

impl WeekDay {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "mon" => Some(Self::Mon),
            "tue" => Some(Self::Tue),
            "wed" => Some(Self::Wed),
            "thu" => Some(Self::Thu),
            "fri" => Some(Self::Fri),
            "sat" => Some(Self::Sat),
            "sun" => Some(Self::Sun),
            _ => None,
        }
    }

    pub fn from_naive_date(date: NaiveDate) -> Self {
        match date.weekday() {
            chrono::Weekday::Mon => Self::Mon,
            chrono::Weekday::Tue => Self::Tue,
            chrono::Weekday::Wed => Self::Wed,
            chrono::Weekday::Thu => Self::Thu,
            chrono::Weekday::Fri => Self::Fri,
            chrono::Weekday::Sat => Self::Sat,
            chrono::Weekday::Sun => Self::Sun,
        }
    }

    /// Stable lowercase three-letter wire token for this weekday.
    /// Matches what [`WeekDay::parse`] accepts so the round-trip
    /// `parse(as_wire_str(d)) == Some(d)` holds for every variant.
    pub const fn as_wire_str(self) -> &'static str {
        match self {
            Self::Mon => "mon",
            Self::Tue => "tue",
            Self::Wed => "wed",
            Self::Thu => "thu",
            Self::Fri => "fri",
            Self::Sat => "sat",
            Self::Sun => "sun",
        }
    }

    /// Monday-first integer index (0=Mon … 6=Sun) — the `habit_weekdays.weekday`
    /// column encoding and the `weekdays` sync-payload array element form.
    /// Matches Apple's `WeekDay` raw value so the two implementations
    /// materialize identical child rows.
    pub const fn as_index(self) -> i64 {
        match self {
            Self::Mon => 0,
            Self::Tue => 1,
            Self::Wed => 2,
            Self::Thu => 3,
            Self::Fri => 4,
            Self::Sat => 5,
            Self::Sun => 6,
        }
    }

    /// Parse a Monday-first integer index (0=Mon … 6=Sun). Returns `None`
    /// for any value outside `0..=6`.
    pub const fn from_index(index: i64) -> Option<Self> {
        match index {
            0 => Some(Self::Mon),
            1 => Some(Self::Tue),
            2 => Some(Self::Wed),
            3 => Some(Self::Thu),
            4 => Some(Self::Fri),
            5 => Some(Self::Sat),
            6 => Some(Self::Sun),
            _ => None,
        }
    }
}
