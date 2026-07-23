//! Update-path driver — applies `Patch<T>` per field, reconciles each
//! patch against the pre-mutation row into `EffectiveCalendarEventFields`
//! (used by validation + the DST guard), and validates the prospective
//! state before returning.

use lorvex_domain::validation::{MAX_BODY_LENGTH, MAX_SHORT_TEXT_LENGTH};
use lorvex_domain::Patch;

use super::create::normalize_calendar_title;
use super::patches::{
    normalize_color_patch, normalize_date_patch, normalize_optional_timezone,
    normalize_recurrence_patch, normalize_text_patch, normalize_time_patch,
    normalize_timezone_patch, normalize_url_patch,
};
use super::validation::{
    check_calendar_event_dst, validate_date, validate_field_shape,
    validate_recurrence_until_after_start, validate_time,
};
use super::{
    CalendarNormalizationError, CalendarNormalizationResult, CalendarUpdateExisting,
    CalendarUpdateInput, EffectiveCalendarEventFields, NormalizedCalendarUpdate,
};

pub fn normalize_calendar_update(
    input: CalendarUpdateInput,
    existing: CalendarUpdateExisting,
) -> CalendarNormalizationResult<NormalizedCalendarUpdate> {
    validate_existing(&existing)?;
    let CalendarUpdateInput {
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

    let title = title.map(normalize_calendar_title).transpose()?;
    if let Some(value) = start_date.as_deref() {
        validate_date(value, "start_date")?;
    }
    let start_time = normalize_time_patch(start_time, "start_time")?;
    let end_date = normalize_date_patch(end_date, "end_date")?;
    let end_time = normalize_time_patch(end_time, "end_time")?;
    let description = normalize_text_patch(description, "description", MAX_BODY_LENGTH)?;
    let location = normalize_text_patch(location, "location", MAX_SHORT_TEXT_LENGTH)?;
    let person_name = normalize_text_patch(person_name, "person_name", MAX_SHORT_TEXT_LENGTH)?;
    let url = normalize_url_patch(url)?;
    let color = normalize_color_patch(color)?;
    let timezone = normalize_timezone_patch(timezone)?;

    let effective_start_date = start_date.as_deref().unwrap_or(&existing.start_date);
    let recurrence = normalize_recurrence_patch(recurrence, effective_start_date)?;
    if let Patch::Set(ref recurrence_json) = recurrence {
        validate_recurrence_until_after_start(Some(recurrence_json), effective_start_date)?;
    }

    let (start_time, end_time) = if all_day == Some(true) {
        (Patch::Clear, Patch::Clear)
    } else {
        (start_time, end_time)
    };

    let effective = resolve_effective_fields(
        &existing,
        start_date.as_deref(),
        &start_time,
        &end_date,
        &end_time,
        all_day,
        &timezone,
    );
    validate_field_shape(
        &effective.start_date,
        effective.start_time.as_deref(),
        effective.end_date.as_deref(),
        effective.end_time.as_deref(),
        effective.all_day,
    )?;
    let dst_guard = check_calendar_event_dst(
        &effective.start_date,
        effective.start_time.as_deref(),
        effective.timezone.as_deref(),
        effective.all_day,
    )?;

    Ok(NormalizedCalendarUpdate {
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
        effective,
        dst_guard,
    })
}

/// Validate the pre-mutation row fed into `normalize_calendar_update`.
/// Rejects a structurally broken row (empty / malformed date / time /
/// timezone) before the patch logic reads it.
fn validate_existing(existing: &CalendarUpdateExisting) -> CalendarNormalizationResult<()> {
    if existing.start_date.trim().is_empty() {
        return Err(CalendarNormalizationError::validation(
            "existing calendar event row missing required field 'start_date'",
        ));
    }
    validate_date(&existing.start_date, "start_date")?;
    if let Some(value) = existing.start_time.as_deref() {
        validate_time(value, "start_time")?;
    }
    if let Some(value) = existing.end_date.as_deref() {
        validate_date(value, "end_date")?;
    }
    if let Some(value) = existing.end_time.as_deref() {
        validate_time(value, "end_time")?;
    }
    if let Some(value) = existing.timezone.as_deref() {
        normalize_optional_timezone(Some(value.to_string()))?;
    }
    Ok(())
}

/// Reconcile each `Patch<T>` against the existing row so downstream
/// validation + the DST guard see the post-patch state. `Unset` keeps
/// the existing value, `Clear` drops it, `Set` overrides. `all_day=true`
/// forces both times to `None` even if `start_time` / `end_time` are
/// `Unset` (matching the all-day-clears-times invariant from create).
fn resolve_effective_fields(
    existing: &CalendarUpdateExisting,
    start_date: Option<&str>,
    start_time: &Patch<String>,
    end_date: &Patch<String>,
    end_time: &Patch<String>,
    all_day: Option<bool>,
    timezone: &Patch<String>,
) -> EffectiveCalendarEventFields {
    let mut effective = EffectiveCalendarEventFields {
        start_date: start_date.unwrap_or(&existing.start_date).to_string(),
        start_time: resolve_patch_string(start_time, existing.start_time.as_deref()),
        end_date: resolve_patch_string(end_date, existing.end_date.as_deref()),
        end_time: resolve_patch_string(end_time, existing.end_time.as_deref()),
        all_day: all_day.unwrap_or(existing.all_day),
        timezone: resolve_patch_string(timezone, existing.timezone.as_deref()),
    };
    if effective.all_day {
        effective.start_time = None;
        effective.end_time = None;
    }
    effective
}

fn resolve_patch_string(patch: &Patch<String>, existing: Option<&str>) -> Option<String> {
    match patch {
        Patch::Unset => existing.map(str::to_string),
        Patch::Clear => None,
        Patch::Set(value) => Some(value.clone()),
    }
}
