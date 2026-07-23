use serde_json::Value;

use crate::hlc::Hlc;

const SYNC_BACKEND_FILESYSTEM_BRIDGE: &str = "filesystem_bridge";

/// Closed set of sync transports whose preference value can be
/// canonical. The enum carries the discriminator in the type
/// itself; a 3-tuple-as-struct shape (`value: Option<String>,
/// malformed: bool, malformed_reason: Option<&'static str>`) would
/// force callers to reconstruct the discriminated union by
/// inspecting `malformed` alongside `value`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncBackendKind {
    FilesystemBridge,
}

impl SyncBackendKind {
    pub const fn as_str(self) -> &'static str {
        match self {
            SyncBackendKind::FilesystemBridge => SYNC_BACKEND_FILESYSTEM_BRIDGE,
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            SYNC_BACKEND_FILESYSTEM_BRIDGE => Some(SyncBackendKind::FilesystemBridge),
            _ => None,
        }
    }

    /// Platform-default backend kind. The closed-set return type
    /// makes the call shape statically enforceable; callers that need
    /// the wire string reach `.as_str()`.
    pub const fn platform_default() -> Self {
        SyncBackendKind::FilesystemBridge
    }
}

impl std::fmt::Display for SyncBackendKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Reasons a parser may reject a stored preference value.
///
/// Closed set of rejection reasons every preference parser surfaces.
/// Lifting the reason into a typed enum collapses the
/// empty-vs-malformed-vs-default-fallback distinction into the type
/// system so call sites match exhaustively instead of threading
/// `(malformed: bool, malformed_reason: Option<&'static str>)` tuples
/// by hand.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MalformedPreferenceReason {
    /// `serde_json::from_str::<String>` rejected the raw JSON.
    InvalidJson,
    /// JSON parsed but the inner string is not in the closed
    /// allowlist.
    UnknownBackendKind,
}

impl MalformedPreferenceReason {
    pub const fn as_str(self) -> &'static str {
        match self {
            MalformedPreferenceReason::InvalidJson => "invalid_json",
            MalformedPreferenceReason::UnknownBackendKind => "unknown_backend_kind",
        }
    }
}

impl std::fmt::Display for MalformedPreferenceReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Discriminated union for the sync backend preference parse result.
///
/// replaces the old 3-tuple state shape. The variants encode the three meaningful
/// outcomes — column absent, column present-and-valid, column
/// present-and-malformed — without overloading `Option<String>` and
/// `bool` to mean different things in combination.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncBackendPreference {
    /// The preference row was absent from the DB. Distinct from
    /// `Malformed` — UI surfaces typically default to
    /// [`SyncBackendKind::platform_default`] in this case rather than
    /// rendering an error.
    Unset,
    /// The preference row parsed cleanly into a known backend.
    Valid(SyncBackendKind),
    /// The preference row was present but unparseable. The reason
    /// flows to the caller for telemetry / UI.
    Malformed(MalformedPreferenceReason),
}

/// Parse a canonical JSON string preference value.
///
/// Returns `None` when the input is missing, blank, malformed, or not a JSON
/// string. Raw unquoted fallback strings are intentionally rejected.
pub fn parse_json_string_preference(raw: Option<&str>) -> Option<String> {
    let raw = raw?;
    let parsed = serde_json::from_str::<String>(raw).ok()?;
    let trimmed = parsed.trim();
    if serde_json::from_str::<String>(trimmed).is_ok() {
        return None;
    }
    (!trimmed.is_empty()).then(|| trimmed.to_string())
}

/// Reasons a strict JSON-string field parse can fail.
///
/// replaces the duplicate
/// `mcp-server/src/preferences/ui/parsing.rs::parse_json_string_value`
/// helper. The error variants carry the offending field name plus
/// optional `serde_json` detail so the MCP/CLI/IPC boundary can format a
/// validation error with consistent wording across crates.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum JsonStringFieldError {
    /// `serde_json::from_str::<Value>` rejected the raw payload.
    InvalidJson { field: &'static str, detail: String },
    /// Parsed JSON was not a string.
    NotAString { field: &'static str },
}

impl std::fmt::Display for JsonStringFieldError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            JsonStringFieldError::InvalidJson { field, detail } => {
                write!(f, "{field} must contain valid JSON string: {detail}")
            }
            JsonStringFieldError::NotAString { field } => {
                write!(f, "{field} must contain a JSON string")
            }
        }
    }
}

impl std::error::Error for JsonStringFieldError {}

/// Strict JSON-string field parser.
///
/// Canonical home for the strict JSON-string preference parser.
/// Unlike [`parse_json_string_preference`], this variant distinguishes
/// "missing column" (`Ok(None)`) from "malformed payload" (`Err(_)`)
/// and surfaces the offending `field_name` to the caller for use in
/// validation messages.
pub fn parse_json_string_field(
    raw: Option<&str>,
    field_name: &'static str,
) -> Result<Option<String>, JsonStringFieldError> {
    let Some(raw) = raw else {
        return Ok(None);
    };
    let parsed =
        serde_json::from_str::<Value>(raw).map_err(|error| JsonStringFieldError::InvalidJson {
            field: field_name,
            detail: error.to_string(),
        })?;
    let value = parsed
        .as_str()
        .map(str::to_string)
        .ok_or(JsonStringFieldError::NotAString { field: field_name })?;
    Ok(Some(value))
}

/// Parse a canonical JSON boolean preference value.
///
/// Returns `None` when the input is missing or malformed. JSON strings like
/// `"true"` are intentionally rejected.
pub fn parse_json_bool_preference(raw: Option<&str>) -> Option<bool> {
    let raw = raw?;
    serde_json::from_str::<bool>(raw).ok()
}

/// Parse a preference that must contain a positive integer.
///
/// Accepts only JSON integers (`30`). Missing values are handled by the
/// caller; malformed, non-scalar, non-integer, and non-positive values
/// surface as `ValidationError` so consumers can `?`-propagate through
/// the existing `From<ValidationError>` impls on `StoreError`,
/// `McpError`, `AppError`, and `CliError` instead of stringifying at
/// every boundary (#3288).
pub fn parse_positive_i64_preference(
    raw: &str,
    key: &str,
) -> Result<i64, crate::validation::ValidationError> {
    let parsed = serde_json::from_str::<Value>(raw).map_err(|error| {
        crate::validation::ValidationError::Message(format!(
            "invalid {key} preference: expected JSON integer: {error}"
        ))
    })?;

    let value = match parsed {
        Value::Number(number) => number.as_i64().ok_or_else(|| {
            crate::validation::ValidationError::Message(format!(
                "invalid {key} preference: expected integer value"
            ))
        })?,
        _ => {
            return Err(crate::validation::ValidationError::Message(format!(
                "invalid {key} preference: expected JSON integer"
            )));
        }
    };

    if value <= 0 {
        return Err(crate::validation::ValidationError::Message(format!(
            "invalid {key} preference: expected positive integer"
        )));
    }

    Ok(value)
}

/// Parse a canonical JSON sync backend kind preference value into the
/// typed [`SyncBackendPreference`] discriminated union.
///
/// returns "absent" vs "valid" vs "malformed" as a discriminated union so
/// callers exhaustive-match without inspecting parallel value/malformed fields.
pub fn parse_sync_backend_preference(raw: Option<&str>) -> SyncBackendPreference {
    let Some(raw) = raw else {
        return SyncBackendPreference::Unset;
    };

    let Ok(parsed) = serde_json::from_str::<String>(raw) else {
        return SyncBackendPreference::Malformed(MalformedPreferenceReason::InvalidJson);
    };

    SyncBackendKind::parse(parsed.as_str()).map_or(
        SyncBackendPreference::Malformed(MalformedPreferenceReason::UnknownBackendKind),
        SyncBackendPreference::Valid,
    )
}

/// Parse an optional RFC 3339 timestamp preference into the 3-tuple
/// `(Option<String>, malformed, reason)` shape used by `sync_status`'s
/// projection sentinels. The 3-tuple is the only consumer-facing
/// shape; the parser returns it directly rather than threading an
/// intermediate typed wrapper.
pub fn parse_optional_rfc3339_state(
    raw: Option<&str>,
) -> (Option<String>, bool, Option<&'static str>) {
    raw.map_or((None, false, None), |value| {
        let candidate = value.trim();
        if candidate.is_empty() {
            (None, true, Some("empty_timestamp"))
        } else if chrono::DateTime::parse_from_rfc3339(candidate).is_ok() {
            (Some(candidate.to_string()), false, None)
        } else {
            (None, true, Some("invalid_rfc3339"))
        }
    })
}

/// Parse an optional `i64` preference into the 3-tuple `(value,
/// malformed, reason)` shape used by `sync_status`'s projection
/// sentinels. See [`parse_optional_rfc3339_state`] for the same
/// rationale on why the typed `OptionalI64Preference` enum was
/// removed.
pub fn parse_optional_i64_state(raw: Option<&str>) -> (i64, bool, Option<&'static str>) {
    raw.map_or((0, false, None), |value| {
        let candidate = value.trim();
        if candidate.is_empty() {
            (0, true, Some("empty_i64"))
        } else {
            candidate
                .parse::<i64>()
                .map_or((0, true, Some("invalid_i64")), |parsed| {
                    (parsed, false, None)
                })
        }
    })
}

/// Parse an optional bool preference into the 3-tuple `(value,
/// malformed, reason)` shape used by `sync_status`'s projection
/// sentinels. Mirrors [`parse_optional_i64_state`] / [`parse_optional_rfc3339_state`]:
///
/// - `None` → `(false, false, None)` (preference simply unset)
/// - `Some("")` / whitespace-only → `(false, true, Some("empty_bool"))`
/// - `Some("true")` / `Some("false")` after trim → parsed cleanly
/// - anything else → `(false, true, Some("invalid_bool"))`
///
/// Canonical home for boolean-state parsing. The parser trims before
/// comparing to `"true"`/`"false"` so `" true"` and `"true"` both
/// parse cleanly, matching the strictness of the i64/rfc3339 siblings
/// (every parser trims before comparing).
pub fn parse_optional_bool_state(raw: Option<&str>) -> (bool, bool, Option<&'static str>) {
    raw.map_or((false, false, None), |value| {
        let candidate = value.trim();
        if candidate.is_empty() {
            (false, true, Some("empty_bool"))
        } else if candidate == "true" {
            (true, false, None)
        } else if candidate == "false" {
            (false, false, None)
        } else {
            (false, true, Some("invalid_bool"))
        }
    })
}

pub fn decode_hlc_cursor_projection(raw: &str) -> Result<(String, String, String), &'static str> {
    let cursor: Value = serde_json::from_str(raw).map_err(|_| "invalid_json")?;
    let object = cursor.as_object().ok_or("invalid_json")?;

    let updated_at = object
        .get("updated_at")
        .and_then(Value::as_str)
        .ok_or("missing_or_invalid_updated_at")?;
    if updated_at.trim().is_empty() {
        return Err("empty_updated_at");
    }
    if Hlc::parse(updated_at).is_err() {
        return Err("invalid_updated_at_hlc");
    }

    let device_id = object
        .get("device_id")
        .and_then(Value::as_str)
        .ok_or("missing_or_invalid_device_id")?;
    if device_id.trim().is_empty() {
        return Err("empty_device_id");
    }

    let event_id = object
        .get("event_id")
        .and_then(Value::as_str)
        .ok_or("missing_or_invalid_event_id")?;
    if event_id.trim().is_empty() {
        return Err("empty_event_id");
    }

    Ok((
        updated_at.to_string(),
        device_id.to_string(),
        event_id.to_string(),
    ))
}

pub fn parse_hlc_cursor_projection_state(
    raw: Option<&str>,
) -> (
    Option<String>,
    Option<String>,
    Option<String>,
    bool,
    Option<String>,
) {
    raw.map_or(
        (None, None, None, false, None),
        |value| match decode_hlc_cursor_projection(value) {
            Ok((updated_at, device_id, event_id)) => (
                Some(updated_at),
                Some(device_id),
                Some(event_id),
                false,
                None,
            ),
            Err(reason) => (None, None, None, true, Some(reason.to_string())),
        },
    )
}

/// Parse an "HH:MM" string into minute-of-day (0–1439).
///
/// Returns `None` if the format is invalid or out of range.
///
/// The check requires both halves to be exactly two ASCII digits
/// before parsing, so signs, whitespace, and non-ASCII digits all
/// reject up front. A bare 5-byte length check + `i64::parse`
/// would accept `+9:00` and `-1:30` because Rust's integer parser
/// accepts a leading sign — and
/// `format_minutes_hhmm(parse_hhmm_to_minutes("+9:00"))` would then
/// return `09:00`, breaking round-trip and flagging clean writes
/// as dirty in preference normalization that compares canonical vs
/// stored forms.
pub fn parse_hhmm_to_minutes(value: &str) -> Option<i64> {
    let bytes = value.as_bytes();
    if bytes.len() != 5 || bytes[2] != b':' {
        return None;
    }
    // Both halves must be exactly two ASCII digits — no sign, no
    // whitespace, no full-width digits. `bytes[i].is_ascii_digit()`
    // is enough because we already pinned the byte length to 5.
    if !bytes[0].is_ascii_digit()
        || !bytes[1].is_ascii_digit()
        || !bytes[3].is_ascii_digit()
        || !bytes[4].is_ascii_digit()
    {
        return None;
    }
    let hour = i64::from(bytes[0] - b'0') * 10 + i64::from(bytes[1] - b'0');
    let minute = i64::from(bytes[3] - b'0') * 10 + i64::from(bytes[4] - b'0');
    if !(0..=23).contains(&hour) || !(0..=59).contains(&minute) {
        return None;
    }
    Some(hour * 60 + minute)
}

/// Format a minute-of-day integer (0–1439) as "HH:MM".
///
/// Returns `None` if `value` is outside the valid range (< 0 or >= 1440),
/// matching the strictness of [`parse_hhmm_to_minutes`].
pub fn format_minutes_hhmm(value: i64) -> Option<String> {
    if !(0..1440).contains(&value) {
        return None;
    }
    let hour = value / 60;
    let minute = value % 60;
    Some(format!("{hour:02}:{minute:02}"))
}

/// Escape LIKE wildcards (`%`, `_`, `\`) so a literal substring match is
/// performed when using `LIKE ? ESCAPE '\'`.
pub fn escape_like(input: &str) -> String {
    let mut escaped = String::with_capacity(input.len());
    for ch in input.chars() {
        if matches!(ch, '%' | '_' | '\\') {
            escaped.push('\\');
        }
        escaped.push(ch);
    }
    escaped
}

#[cfg(test)]
mod tests;
