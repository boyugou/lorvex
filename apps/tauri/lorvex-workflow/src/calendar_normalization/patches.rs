//! Field-shape normalizers — both `Option<T>` (create path) and
//! `Patch<T>` (update path) variants of text / url / timezone /
//! recurrence / date / time / color. Each normalizer trims and
//! delegates the actual shape check to `validation`.
//!
//! Title and existing-row validation live near their drivers in
//! `create` / `update`.

use lorvex_domain::Patch;

use super::validation::{validate_date, validate_length, validate_optional_color, validate_time};
use super::{CalendarNormalizationError, CalendarNormalizationResult};

pub(super) fn normalize_optional_text(
    value: Option<String>,
    field: &'static str,
    max: usize,
) -> CalendarNormalizationResult<Option<String>> {
    value
        .map(|value| {
            let normalized = lorvex_domain::sanitize_user_text(&value);
            validate_length(&normalized, field, max)?;
            Ok(normalized)
        })
        .transpose()
}

pub(super) fn normalize_text_patch(
    value: Patch<String>,
    field: &'static str,
    max: usize,
) -> CalendarNormalizationResult<Patch<String>> {
    value.try_map(|value| {
        let normalized = lorvex_domain::sanitize_user_text(&value);
        validate_length(&normalized, field, max)?;
        Ok(normalized)
    })
}

pub(super) fn normalize_optional_url(
    value: Option<String>,
) -> CalendarNormalizationResult<Option<String>> {
    let Some(value) = value else {
        return Ok(None);
    };
    let sanitized = lorvex_domain::sanitize_user_text(&value);
    let trimmed = sanitized.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    validate_length(
        trimmed,
        "url",
        lorvex_domain::validation::MAX_SHORT_TEXT_LENGTH,
    )?;
    lorvex_domain::validation::validate_user_url(trimmed)
        .map(Some)
        .map_err(|e| CalendarNormalizationError::validation(e.to_string()))
}

pub(super) fn normalize_url_patch(
    value: Patch<String>,
) -> CalendarNormalizationResult<Patch<String>> {
    match value {
        Patch::Unset => Ok(Patch::Unset),
        Patch::Clear => Ok(Patch::Clear),
        Patch::Set(value) => {
            let sanitized = lorvex_domain::sanitize_user_text(&value);
            let trimmed = sanitized.trim();
            if trimmed.is_empty() {
                return Err(CalendarNormalizationError::validation(
                    "url must not be empty; clear the field instead",
                ));
            }
            validate_length(
                trimmed,
                "url",
                lorvex_domain::validation::MAX_SHORT_TEXT_LENGTH,
            )?;
            Ok(Patch::Set(
                lorvex_domain::validation::validate_user_url(trimmed)
                    .map_err(|e| CalendarNormalizationError::validation(e.to_string()))?,
            ))
        }
    }
}

pub(super) fn normalize_optional_timezone(
    value: Option<String>,
) -> CalendarNormalizationResult<Option<String>> {
    let Some(value) = value else {
        return Ok(None);
    };
    let trimmed = value.trim();
    lorvex_domain::normalize_timezone_name(Some(trimmed))
        .map(Some)
        .ok_or_else(|| {
            CalendarNormalizationError::validation(format!("invalid IANA timezone: '{value}'"))
        })
}

pub(super) fn normalize_timezone_patch(
    value: Patch<String>,
) -> CalendarNormalizationResult<Patch<String>> {
    match value {
        Patch::Unset => Ok(Patch::Unset),
        Patch::Clear => Ok(Patch::Clear),
        Patch::Set(value) => normalize_optional_timezone(Some(value)).map(|value| match value {
            Some(value) => Patch::Set(value),
            None => Patch::Clear,
        }),
    }
}

pub(super) fn normalize_recurrence_patch(
    value: Patch<String>,
    start_date: &str,
) -> CalendarNormalizationResult<Patch<String>> {
    match value {
        Patch::Unset => Ok(Patch::Unset),
        Patch::Clear => Ok(Patch::Clear),
        Patch::Set(value) => {
            let normalized = lorvex_domain::validation::normalize_calendar_recurrence(Some(&value))
                .map_err(|e| CalendarNormalizationError::validation(e.to_string()))?;
            let normalized = match normalized {
                Some(ref rec_json) => {
                    lorvex_store::calendar_timeline::recurrence::inject_bymonthday(
                        rec_json, start_date,
                    )
                    .map_err(|e| CalendarNormalizationError::validation(e.to_string()))?
                    .or(normalized)
                }
                None => None,
            };
            Ok(match normalized {
                Some(value) => Patch::Set(value),
                None => Patch::Clear,
            })
        }
    }
}

pub(super) fn normalize_date_patch(
    value: Patch<String>,
    field: &'static str,
) -> CalendarNormalizationResult<Patch<String>> {
    match value {
        Patch::Unset => Ok(Patch::Unset),
        Patch::Clear => Ok(Patch::Clear),
        Patch::Set(value) => {
            validate_date(&value, field)?;
            Ok(Patch::Set(value))
        }
    }
}

pub(super) fn normalize_time_patch(
    value: Patch<String>,
    field: &'static str,
) -> CalendarNormalizationResult<Patch<String>> {
    match value {
        Patch::Unset => Ok(Patch::Unset),
        Patch::Clear => Ok(Patch::Clear),
        Patch::Set(value) => {
            validate_time(&value, field)?;
            Ok(Patch::Set(value))
        }
    }
}

pub(super) fn normalize_color_patch(
    value: Patch<String>,
) -> CalendarNormalizationResult<Patch<String>> {
    if let Patch::Set(ref value) = value {
        validate_optional_color(Some(value))?;
    }
    Ok(value)
}
