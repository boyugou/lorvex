//! `TimeOfDay` — typed wrapper around a `chrono::NaiveTime` rendered in
//! the canonical `HH:MM` form used across calendar / focus / reminder
//! columns.

use std::fmt;
use std::str::FromStr;

use chrono::NaiveTime;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

use crate::validation::ValidationError;

/// Canonical typed wrapper around a `chrono::NaiveTime` rendered in the
/// canonical 24-hour `HH:MM` form.
///
/// Issue #3286: every `start_time`, `end_time`, `due_time`,
/// `reminder_time`, focus working-hours bound was a bare `String` with
/// "HH:MM" documented only in field comments. The schema CHECK enforces
/// the format on write; the Rust type let any string through.
///
/// `TimeOfDay` is `NaiveTime`-backed (so two values compare by minute,
/// not by lexicographic byte order). Wire encoding is the same
/// canonical 24-hour `HH:MM` string, so JSON / sync envelopes / SQLite
/// columns read byte-identical to the legacy `String` columns.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct TimeOfDay(NaiveTime);

impl TimeOfDay {
    /// Parse a canonical 24-hour `HH:MM` time-of-day string.
    ///
    /// Routes through `chrono::NaiveTime::parse_from_str(s, "%H:%M")`
    /// which rejects `24:00`, `09:60`, and any non-`HH:MM` input.
    /// Surfaces a `ValidationError::InvalidFormat { field: "time", .. }`
    /// shape so caller surfaces format error messages identically to
    /// every other typed-format validator.
    pub fn parse(raw: &str) -> Result<Self, ValidationError> {
        NaiveTime::parse_from_str(raw, "%H:%M")
            .map(Self)
            .map_err(|_| ValidationError::InvalidFormat {
                field: "time",
                expected: "HH:MM",
                actual: raw.to_string(),
            })
    }

    /// Borrow the underlying `NaiveTime` for chrono-native math.
    #[inline]
    pub const fn as_naive_time(&self) -> NaiveTime {
        self.0
    }

    /// Render the time as the canonical 24-hour `HH:MM` string.
    pub fn as_string(&self) -> String {
        self.0.format("%H:%M").to_string()
    }
}

impl From<NaiveTime> for TimeOfDay {
    #[inline]
    fn from(time: NaiveTime) -> Self {
        // Canonical wire shape is `HH:MM` (no seconds); a `NaiveTime`
        // with non-zero seconds round-trips through `as_string()` as
        // the truncated form. Caller-supplied `NaiveTime` values are
        // accepted as-is (tests sometimes build with seconds), and the
        // schema-storage form drops them on serialization.
        Self(time)
    }
}

impl From<TimeOfDay> for NaiveTime {
    #[inline]
    fn from(time: TimeOfDay) -> Self {
        time.0
    }
}

impl fmt::Display for TimeOfDay {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0.format("%H:%M"))
    }
}

impl FromStr for TimeOfDay {
    type Err = ValidationError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Self::parse(s)
    }
}

impl Serialize for TimeOfDay {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.collect_str(&self.0.format("%H:%M"))
    }
}

impl<'de> Deserialize<'de> for TimeOfDay {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let raw = String::deserialize(deserializer)?;
        Self::parse(&raw).map_err(serde::de::Error::custom)
    }
}

#[cfg(feature = "rusqlite")]
impl rusqlite::ToSql for TimeOfDay {
    fn to_sql(&self) -> rusqlite::Result<rusqlite::types::ToSqlOutput<'_>> {
        Ok(rusqlite::types::ToSqlOutput::Owned(
            rusqlite::types::Value::Text(self.as_string()),
        ))
    }
}

#[cfg(feature = "rusqlite")]
impl rusqlite::types::FromSql for TimeOfDay {
    fn column_result(value: rusqlite::types::ValueRef<'_>) -> rusqlite::types::FromSqlResult<Self> {
        let raw = String::column_result(value)?;
        TimeOfDay::parse(&raw).map_err(|e| {
            rusqlite::types::FromSqlError::Other(Box::new(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                e.to_string(),
            )))
        })
    }
}
