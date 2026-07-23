//! `Date` — typed wrapper around a `chrono::NaiveDate` rendered in the
//! canonical hyphenated ISO form.

use std::fmt;
use std::str::FromStr;

use chrono::NaiveDate;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

use crate::validation::ValidationError;

use super::iso_date::parse_iso_date;

/// Canonical typed wrapper around a `chrono::NaiveDate` rendered in the
/// canonical schema-storage form (`YYYY-MM-DD`).
///
/// Issue #3286: every `due_date`, `planned_date`, `start_date`,
/// `canonical_occurrence_date`, etc. column flows through the codebase
/// as this newtype rather than a bare `String`. The schema enforces
/// the format at write time via CHECK constraints; the Rust type
/// enforces it at the boundary so a malformed date is rejected with a
/// typed parse error at construction instead of either silently
/// writing garbage to SQLite or surfacing a `chrono::parse` failure
/// as a generic `StoreError` far from the source.
///
/// `Date` closes both gaps: the only way to construct one is through
/// [`Date::parse`] / [`From<NaiveDate>`] — both of which route through
/// [`parse_iso_date`] / `NaiveDate::format("%Y-%m-%d")`. JSON
/// serialization is `#[serde(transparent)]`-shaped so the wire format
/// is byte-identical to the bare `String` it replaces.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Date(NaiveDate);

impl Date {
    /// Parse a canonical hyphenated ISO date (`YYYY-MM-DD`).
    ///
    /// Returns a [`ValidationError::InvalidFormat`] with field label
    /// `"date"` for malformed inputs — the same shape every other
    /// domain validator returns, so caller surfaces (MCP server, Tauri
    /// commands, sync apply) keep using the unified `ValidationError`
    /// carrier.
    pub fn parse(raw: &str) -> Result<Self, ValidationError> {
        parse_iso_date(raw).map(Self)
    }

    /// Borrow the underlying `NaiveDate` for chrono-native math.
    #[inline]
    pub const fn as_naive_date(&self) -> NaiveDate {
        self.0
    }

    /// Render the date as the canonical hyphenated ISO string
    /// (`YYYY-MM-DD`). Allocation site: `format!`-via-`format()`.
    pub fn as_string(&self) -> String {
        self.0.format("%Y-%m-%d").to_string()
    }
}

impl From<NaiveDate> for Date {
    #[inline]
    fn from(date: NaiveDate) -> Self {
        Self(date)
    }
}

impl From<Date> for NaiveDate {
    #[inline]
    fn from(date: Date) -> Self {
        date.0
    }
}

impl fmt::Display for Date {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0.format("%Y-%m-%d"))
    }
}

impl FromStr for Date {
    type Err = ValidationError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Self::parse(s)
    }
}

impl Serialize for Date {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.collect_str(&self.0.format("%Y-%m-%d"))
    }
}

impl<'de> Deserialize<'de> for Date {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let raw = String::deserialize(deserializer)?;
        Self::parse(&raw).map_err(serde::de::Error::custom)
    }
}

#[cfg(feature = "rusqlite")]
impl rusqlite::ToSql for Date {
    fn to_sql(&self) -> rusqlite::Result<rusqlite::types::ToSqlOutput<'_>> {
        Ok(rusqlite::types::ToSqlOutput::Owned(
            rusqlite::types::Value::Text(self.as_string()),
        ))
    }
}

#[cfg(feature = "rusqlite")]
impl rusqlite::types::FromSql for Date {
    fn column_result(value: rusqlite::types::ValueRef<'_>) -> rusqlite::types::FromSqlResult<Self> {
        let raw = String::column_result(value)?;
        Date::parse(&raw).map_err(|e| {
            rusqlite::types::FromSqlError::Other(Box::new(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                e.to_string(),
            )))
        })
    }
}
