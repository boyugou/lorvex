//! Validation/projection helpers for the sync-status snapshot.
//! Each function thinly wraps a `lorvex_domain::parsing` parser so
//! the snapshot loader can consume the canonical `(value, malformed,
//! reason)` shape without re-implementing field-level parsing.
//!
//! `TimestampFieldState` and `observe_timestamp_field` co-locate
//! the malformed-flag tracking that the snapshot uses to project
//! aggregate MIN/MAX boundaries while still surfacing the
//! "any malformed row exists" diagnostic flag.

#[derive(Default)]
pub(super) struct TimestampFieldState {
    pub(super) value: Option<String>,
    pub(super) malformed: bool,
    pub(super) malformed_reason: Option<String>,
}

pub(super) type CursorProjection = (
    Option<String>,
    Option<String>,
    Option<String>,
    bool,
    Option<String>,
);

pub(super) fn deconstruct_sync_backend_preference(
    raw: Option<&str>,
) -> (Option<String>, bool, Option<String>) {
    match lorvex_domain::parsing::parse_sync_backend_preference(raw) {
        lorvex_domain::parsing::SyncBackendPreference::Unset => (None, false, None),
        lorvex_domain::parsing::SyncBackendPreference::Valid(kind) => {
            (Some(kind.to_string()), false, None)
        }
        lorvex_domain::parsing::SyncBackendPreference::Malformed(reason) => {
            (None, true, Some(reason.to_string()))
        }
    }
}

pub(super) fn parse_optional_rfc3339_state(
    raw: Option<&str>,
) -> (Option<String>, bool, Option<String>) {
    let (value, malformed, reason) = lorvex_domain::parse_optional_rfc3339_state(raw);
    (value, malformed, reason.map(str::to_string))
}

pub(super) fn parse_optional_i64_state(raw: Option<&str>) -> (i64, bool, Option<String>) {
    let (value, malformed, reason) = lorvex_domain::parse_optional_i64_state(raw);
    (value, malformed, reason.map(str::to_string))
}

pub(super) fn parse_optional_bool_state(raw: Option<&str>) -> (bool, bool, Option<String>) {
    let (value, malformed, reason) = lorvex_domain::parse_optional_bool_state(raw);
    (value, malformed, reason.map(str::to_string))
}

pub(super) fn parse_hlc_cursor_projection(raw: Option<&str>) -> CursorProjection {
    let (updated_at, device_id, event_id, malformed, reason) =
        lorvex_domain::parse_hlc_cursor_projection_state(raw);
    (updated_at, device_id, event_id, malformed, reason)
}

pub(super) fn observe_timestamp_field(
    state: &mut TimestampFieldState,
    raw: Option<&str>,
    prefer_newer: bool,
) {
    let (parsed, malformed, malformed_reason) = parse_optional_rfc3339_state(raw);
    if malformed && !state.malformed {
        state.malformed = true;
        state.malformed_reason = malformed_reason;
    }
    let Some(parsed) = parsed else {
        return;
    };

    let replace = state.value.as_ref().is_none_or(|current| {
        if prefer_newer {
            parsed > *current
        } else {
            parsed < *current
        }
    });
    if replace {
        state.value = Some(parsed);
    }
}
