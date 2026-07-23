//! Typed validation failures.
//!
//! Every domain-side validator in this module returns
//! `Result<(), ValidationError>` so caller surfaces (MCP server,
//! Tauri commands, sync apply) can format domain-aware error messages
//! without recreating the discriminant set.

/// Describes a single validation failure.
#[derive(Debug, PartialEq, Eq)]
pub enum ValidationError {
    /// A required string field is empty (or whitespace-only).
    Empty(&'static str),

    /// A string field exceeds its maximum length.
    ///
    /// `max` and `actual` are measured in Unicode codepoints for
    /// text-facing fields (titles, bodies, tag names, short-text
    /// strings). Byte-counted checks (SQL identifiers, raw JSON
    /// blobs) bypass this enum entirely.
    TooLong {
        field: &'static str,
        max: usize,
        actual: usize,
    },

    /// A numeric field is outside its allowed range.
    OutOfRange {
        field: &'static str,
        min: i64,
        max: i64,
        actual: i64,
    },

    /// A string field does not match the expected format.
    InvalidFormat {
        field: &'static str,
        expected: &'static str,
        actual: String,
    },

    /// A free-form ad-hoc validation message that does not yet have a
    /// structured discriminant.
    ///
    /// every Tauri/MCP/CLI write surface previously
    /// constructed `*Error::Validation(format!(...))` directly with a
    /// caller-built string, sidestepping the typed
    /// `Empty`/`TooLong`/`OutOfRange`/`InvalidFormat` discriminants
    /// above. The `Message` variant lets call sites that have not yet
    /// migrated to the structured form still flow through the typed
    /// `ValidationError` carrier (so `From<ValidationError>` impls on
    /// `StoreError`, `McpError`, `AppError` remain the single conversion
    /// boundary), while new code should reach for the structured
    /// variants whenever the field/limit/value are known. Treating
    /// `Message` as the migration off-ramp keeps the typed enum the
    /// canonical carrier without forcing a 700-site rewrite of legacy
    /// `format!`-built validation strings in the same change.
    Message(String),
}

impl From<String> for ValidationError {
    fn from(message: String) -> Self {
        Self::Message(message)
    }
}

impl From<&str> for ValidationError {
    fn from(message: &str) -> Self {
        Self::Message(message.to_string())
    }
}

impl std::fmt::Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty(field) => write!(f, "{field} must not be empty"),
            // wording aligned with the
            // `validate_string_length` callers across Tauri / MCP
            // (the surfaces that issue #2994 H1 unified on
            // `"{field} exceeds maximum length ({actual} chars,
            // limit {max})"`). The previous `"is too long"` wording
            // never escaped through to AI clients because no Tauri
            // / MCP / CLI write surface routed string-length checks
            // through `ValidationError::Display`. Now that the
            // promoted `validate_string_length` flows back through
            // the From impls on the way to `AppError`/`McpError`,
            // the Display IS the wire wording.
            Self::TooLong { field, max, actual } => {
                write!(
                    f,
                    "{field} exceeds maximum length ({actual} chars, limit {max})"
                )
            }
            Self::OutOfRange {
                field,
                min,
                max,
                actual,
            } => write!(
                f,
                "{field} is out of range ({actual}, must be {min}..={max})"
            ),
            Self::InvalidFormat {
                field,
                expected,
                actual,
            } => write!(
                f,
                "{field} has invalid format (got \"{actual}\", expected {expected})"
            ),
            Self::Message(message) => f.write_str(message),
        }
    }
}

impl std::error::Error for ValidationError {}
