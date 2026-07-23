//! `SyncTimestamp` — typed wrapper around `DateTime<Utc>` rendered in
//! the canonical sync-timestamp wire form (RFC 3339, millisecond
//! precision, `Z` suffix), plus the family of `format_*` /
//! `normalize_*` helpers that share the same canonical shape.

use std::fmt;
use std::str::FromStr;

use chrono::{DateTime, SecondsFormat, Utc};
use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// Canonical typed wrapper around a `DateTime<Utc>` rendered in the
/// canonical sync-timestamp wire form (RFC 3339, millisecond precision,
/// `Z` suffix).
///
/// Every `created_at`, `updated_at`, `completed_at`, and `timestamp`
/// column flows through this newtype at the API boundary rather than
/// a bare `String`. Without it:
///
/// * Lex-comparisons spelled `a.as_str() < b.as_str()` would silently
///   misorder rows the moment a peer emits a different-precision form
///   (3 vs 6 fractional digits, `+00:00` instead of `Z`). See
///   #2306 / #2907.
/// * Producers could accidentally bind a non-canonical string into a
///   `ToSql` slot — there was no compile-time gate forcing the value
///   through `format_sync_timestamp`.
///
/// `SyncTimestamp` closes both gaps: ordering is `DateTime<Utc>`-backed
/// (so byte-compares become value-compares), and the only way to
/// produce one is through `now()` / `From<DateTime<Utc>>` /
/// `FromStr` — every constructor routes through
/// [`format_sync_timestamp`] / [`DateTime::parse_from_rfc3339`] so the
/// invariant is type-system enforced. Public JSON serialization
/// preserves the same canonical string shape that older callers wrote
/// directly, so the wire format is byte-identical.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct SyncTimestamp(DateTime<Utc>);

impl SyncTimestamp {
    /// Capture the current wall clock as a canonical sync timestamp.
    /// Equivalent to `SyncTimestamp::from(Utc::now())`.
    pub fn now() -> Self {
        Self(Utc::now())
    }

    /// Borrow the underlying `DateTime<Utc>` for chrono-native math.
    pub const fn as_datetime(&self) -> DateTime<Utc> {
        self.0
    }

    /// Owned canonical-form rendering for SQL `ToSql` bind sites that
    /// take `&str` / `String`. Mirrors `format_sync_timestamp(self.0)`.
    pub fn as_string(&self) -> String {
        format_sync_timestamp(self.0)
    }

    /// Parse a sync timestamp from the canonical wire form. Accepts any
    /// second/ms/µs precision RFC 3339 string with a UTC offset (`Z` or
    /// `+00:00`) and renders back through [`SyncTimestamp::as_string`] in
    /// canonical millisecond precision. Rejects non-UTC offsets to match
    /// the stored sync timestamp invariant.
    pub fn parse(raw: &str) -> Option<Self> {
        let dt = DateTime::parse_from_rfc3339(raw).ok()?;
        if dt.offset().local_minus_utc() != 0 {
            return None;
        }
        Some(Self(dt.with_timezone(&Utc)))
    }
}

impl From<DateTime<Utc>> for SyncTimestamp {
    fn from(dt: DateTime<Utc>) -> Self {
        Self(dt)
    }
}

impl From<SyncTimestamp> for DateTime<Utc> {
    fn from(ts: SyncTimestamp) -> Self {
        ts.0
    }
}

impl fmt::Display for SyncTimestamp {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&format_sync_timestamp(self.0))
    }
}

impl FromStr for SyncTimestamp {
    type Err = SyncTimestampParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Self::parse(s).ok_or(SyncTimestampParseError)
    }
}

/// Failure type for `<SyncTimestamp as FromStr>::from_str`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SyncTimestampParseError;

impl fmt::Display for SyncTimestampParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("invalid sync timestamp: expected RFC 3339 with a UTC offset (`Z` or `+00:00`)")
    }
}

impl std::error::Error for SyncTimestampParseError {}

impl Serialize for SyncTimestamp {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&format_sync_timestamp(self.0))
    }
}

impl<'de> Deserialize<'de> for SyncTimestamp {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let raw = String::deserialize(deserializer)?;
        SyncTimestamp::parse(&raw).ok_or_else(|| {
            serde::de::Error::custom(
                "invalid sync timestamp: expected RFC 3339 with a UTC offset (`Z` or `+00:00`)",
            )
        })
    }
}

// ---------------------------------------------------------------------------
// `SyncTimestamp::ToSql` / `FromSql` impls — gated on the `rusqlite`
// feature so storage call sites in `lorvex-store` can bind a typed sync
// timestamp directly into `params!` and read it back via `row.get(..)`
// without the `.as_string()` / parse dance at every site.
// ---------------------------------------------------------------------------

#[cfg(feature = "rusqlite")]
impl rusqlite::ToSql for SyncTimestamp {
    fn to_sql(&self) -> rusqlite::Result<rusqlite::types::ToSqlOutput<'_>> {
        Ok(rusqlite::types::ToSqlOutput::Owned(
            rusqlite::types::Value::Text(self.as_string()),
        ))
    }
}

#[cfg(feature = "rusqlite")]
impl rusqlite::types::FromSql for SyncTimestamp {
    fn column_result(value: rusqlite::types::ValueRef<'_>) -> rusqlite::types::FromSqlResult<Self> {
        let raw = String::column_result(value)?;
        SyncTimestamp::parse(&raw).ok_or_else(|| {
            rusqlite::types::FromSqlError::Other(Box::new(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "invalid sync timestamp: expected RFC 3339 with a UTC offset (`Z` or `+00:00`)",
            )))
        })
    }
}

/// Canonical sync timestamp: RFC 3339 with **millisecond** precision, UTC.
///
/// We unify on millisecond precision to match SQLite's
/// `strftime('%Y-%m-%dT%H:%M:%fZ', 'now')` and remote-provider
/// `record_builder` format. Mixing millisecond and microsecond
/// strings broke lexicographic comparisons on `updated_at` /
/// `deleted_at`: `"2026-03-20T15:30:00.123Z"` (24 chars, SQLite) vs
/// `"2026-03-20T15:30:00.123456Z"` (27 chars, chrono) lex-compared
/// wrong when an older row sat next to a newer row. HLC carries the
/// real causal ordering; the extra microsecond digits gave us
/// nothing at the sync tier.
pub fn sync_timestamp_now() -> String {
    format_sync_timestamp(Utc::now())
}

/// Format a `DateTime<Utc>` in the canonical sync timestamp shape
/// (RFC 3339, millisecond precision, trailing `Z`).
///
/// Use this in any path that needs to derive a canonical timestamp from
/// an existing `DateTime<Utc>` (e.g. computing `expires_at = now + ttl`).
/// Routing through one helper guarantees that a future precision change
/// (e.g. moving to microseconds across the entire workspace) is a
/// single-file edit and cannot drift between callers.
///
/// # Examples
///
/// ```
/// use chrono::TimeZone;
/// use lorvex_domain::time::format_sync_timestamp;
///
/// let dt = chrono::Utc
///     .with_ymd_and_hms(2026, 4, 19, 8, 30, 0)
///     .unwrap();
/// // Always millisecond-precision and `Z` suffix — never microseconds,
/// // never `+00:00`.
/// assert_eq!(format_sync_timestamp(dt), "2026-04-19T08:30:00.000Z");
/// ```
pub fn format_sync_timestamp(dt: DateTime<Utc>) -> String {
    dt.to_rfc3339_opts(SecondsFormat::Millis, true)
}

/// Format a millisecond Unix epoch as the canonical sync timestamp.
///
/// Used by sync-apply paths that need to derive `updated_at` from an
/// HLC's physical component (the wall-clock the writing device
/// observed at write time) rather than the local wall-clock — which
/// would inject local clock skew into a converged column. Returns
/// `None` if the timestamp is out of `DateTime<Utc>`'s representable
/// range (≈ years 1677..2262 in millisecond resolution).
pub fn format_sync_timestamp_from_unix_ms(unix_ms: i64) -> Option<String> {
    DateTime::<Utc>::from_timestamp_millis(unix_ms).map(format_sync_timestamp)
}

/// Canonicalize a user-supplied RFC 3339 instant into the stored sync
/// timestamp form.
///
/// Unlike [`normalize_sync_timestamp`], this accepts non-UTC offsets
/// because caller-facing inputs such as reminders may legitimately be
/// expressed as local instants (`2026-12-01T09:00:00-05:00`). The value
/// persisted into sync timestamp columns is always converted to UTC and
/// rendered through [`format_sync_timestamp`].
pub fn canonicalize_rfc3339_instant(raw: &str) -> Option<String> {
    let dt = DateTime::parse_from_rfc3339(raw).ok()?;
    Some(format_sync_timestamp(dt.with_timezone(&Utc)))
}

/// Normalize an RFC 3339 UTC timestamp to the canonical millisecond
/// form produced by `sync_timestamp_now`. Accepts inputs at second,
/// millisecond, or microsecond precision; always returns a 24-char
/// `YYYY-MM-DDTHH:MM:SS.mmmZ` string.
///
/// This exists so any lex-comparison site (tombstone GC,
/// payload-shadow merge, filesystem-bridge cursor) can normalize
/// mixed-precision timestamps emitted by older peers before
/// comparing. Returns `None` if the input cannot be parsed.
///
/// Rejects non-UTC inputs. Earlier behavior silently
/// converted offsets like `+05:30` into UTC, but callers that
/// compare raw stored strings against post-normalized ones (e.g.
/// tombstone-GC steps that pre-filter on the raw column) would
/// then compare apples to oranges. The Lorvex schema only stores
/// UTC timestamps in `Z` form, so the strict check matches the
/// invariant the comment already advertises.
pub fn normalize_sync_timestamp(raw: &str) -> Option<String> {
    let dt = DateTime::parse_from_rfc3339(raw).ok()?;
    if dt.offset().local_minus_utc() != 0 {
        return None;
    }
    Some(
        dt.with_timezone(&Utc)
            .to_rfc3339_opts(SecondsFormat::Millis, true),
    )
}
