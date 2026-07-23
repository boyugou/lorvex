//! Create-path driver — title + optional-field normalization, recurrence
//! injection, all-day time-clearing, field-shape validation, DST guard.

use lorvex_domain::validation::{MAX_BODY_LENGTH, MAX_SHORT_TEXT_LENGTH, MAX_TITLE_LENGTH};
use lorvex_domain::{CanonicalCalendarEventType, Patch};

use super::patches::{
    normalize_optional_text, normalize_optional_timezone, normalize_optional_url,
    normalize_recurrence_patch,
};
use super::validation::{
    check_calendar_event_dst, validate_date, validate_field_shape, validate_length,
    validate_optional_color, validate_recurrence_until_after_start, validate_time,
};
use super::{
    CalendarCreateInput, CalendarNormalizationError, CalendarNormalizationResult,
    NormalizedCalendarCreate,
};

pub fn normalize_calendar_create(
    input: CalendarCreateInput,
) -> CalendarNormalizationResult<NormalizedCalendarCreate> {
    let CalendarCreateInput {
        title,
        recurrence,
        timezone,
        start_date,
        start_time,
        end_date,
        end_time,
        all_day,
        description,
        location,
        url,
        color,
        event_type,
        person_name,
    } = input;

    let title = normalize_calendar_title(title)?;
    let description = normalize_optional_text(description, "description", MAX_BODY_LENGTH)?;
    let location = normalize_optional_text(location, "location", MAX_SHORT_TEXT_LENGTH)?;
    let person_name = normalize_optional_text(person_name, "person_name", MAX_SHORT_TEXT_LENGTH)?;
    let url = normalize_optional_url(url)?;
    validate_optional_color(color.as_deref())?;
    let timezone = normalize_optional_timezone(timezone)?;
    validate_date(&start_date, "start_date")?;
    if let Some(value) = start_time.as_deref() {
        validate_time(value, "start_time")?;
    }
    if let Some(value) = end_date.as_deref() {
        validate_date(value, "end_date")?;
    }
    if let Some(value) = end_time.as_deref() {
        validate_time(value, "end_time")?;
    }
    let recurrence = match recurrence {
        Some(value) => match normalize_recurrence_patch(Patch::Set(value), &start_date)? {
            Patch::Set(value) => Some(value),
            Patch::Clear | Patch::Unset => None,
        },
        None => None,
    };
    validate_recurrence_until_after_start(recurrence.as_deref(), &start_date)?;

    let all_day = all_day.unwrap_or(false);
    let start_time = if all_day { None } else { start_time };
    let end_time = if all_day { None } else { end_time };
    validate_field_shape(
        &start_date,
        start_time.as_deref(),
        end_date.as_deref(),
        end_time.as_deref(),
        all_day,
    )?;
    let dst_guard = check_calendar_event_dst(
        &start_date,
        start_time.as_deref(),
        timezone.as_deref(),
        all_day,
    )?;

    Ok(NormalizedCalendarCreate {
        title,
        recurrence,
        timezone,
        start_date,
        start_time,
        end_date,
        end_time,
        all_day,
        description,
        location,
        url,
        color,
        event_type: event_type.unwrap_or(CanonicalCalendarEventType::Event),
        person_name,
        dst_guard,
    })
}

/// Trim, sanitize, and length-check the create-path title. The update
/// path reuses this helper via `super::update`.
pub(super) fn normalize_calendar_title(title: String) -> CalendarNormalizationResult<String> {
    let normalized = lorvex_domain::sanitize_user_text(&title).trim().to_string();
    if normalized.is_empty() {
        return Err(CalendarNormalizationError::validation(
            "calendar event title must not be empty",
        ));
    }
    validate_length(&normalized, "title", MAX_TITLE_LENGTH)?;
    Ok(normalized)
}
