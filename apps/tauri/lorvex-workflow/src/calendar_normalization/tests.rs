use super::*;

fn create_input() -> CalendarCreateInput {
    CalendarCreateInput {
        title: "Team sync".to_string(),
        recurrence: None,
        timezone: Some("America/New_York".to_string()),
        start_date: "2026-05-01".to_string(),
        start_time: Some("09:00".to_string()),
        end_date: None,
        end_time: Some("10:00".to_string()),
        all_day: None,
        description: None,
        location: None,
        url: None,
        color: None,
        event_type: None,
        person_name: None,
    }
}

fn update_input() -> CalendarUpdateInput {
    CalendarUpdateInput {
        title: None,
        recurrence: Patch::Unset,
        timezone: Patch::Unset,
        start_date: None,
        start_time: Patch::Unset,
        end_date: Patch::Unset,
        end_time: Patch::Unset,
        all_day: None,
        description: Patch::Unset,
        location: Patch::Unset,
        url: Patch::Unset,
        color: Patch::Unset,
        event_type: Patch::Unset,
        person_name: Patch::Unset,
    }
}

fn existing() -> CalendarUpdateExisting {
    CalendarUpdateExisting {
        start_date: "2026-05-01".to_string(),
        start_time: Some("09:00".to_string()),
        end_date: None,
        end_time: Some("10:00".to_string()),
        all_day: false,
        timezone: Some("America/New_York".to_string()),
    }
}

#[test]
fn create_rejects_empty_title_after_unicode_hygiene() {
    let mut input = create_input();
    input.title = "\u{200B}\u{202E}   ".to_string();

    let err = normalize_calendar_create(input).expect_err("empty title must fail");

    assert!(err.to_string().contains("title must not be empty"));
}

#[test]
fn create_trims_and_canonicalizes_allowed_url() {
    let mut input = create_input();
    input.url = Some("  HTTPS://Example.com/Path  ".to_string());

    let normalized = normalize_calendar_create(input).expect("valid URL should pass");

    assert_eq!(normalized.url.as_deref(), Some("https://Example.com/Path"));
}

#[test]
fn create_rejects_disallowed_url_scheme() {
    let mut input = create_input();
    input.url = Some("javascript:alert(1)".to_string());

    let err = normalize_calendar_create(input).expect_err("unsafe URL must fail");

    assert!(err.to_string().contains("scheme"));
}

#[test]
fn create_rejects_invalid_timezone() {
    let mut input = create_input();
    input.timezone = Some("America/Not_A_Zone".to_string());

    let err = normalize_calendar_create(input).expect_err("timezone must fail");

    assert!(err.to_string().contains("timezone"));
}

#[test]
fn create_all_day_clears_times() {
    let mut input = create_input();
    input.all_day = Some(true);

    let normalized = normalize_calendar_create(input).expect("all-day should pass");

    assert!(normalized.all_day);
    assert_eq!(normalized.start_time, None);
    assert_eq!(normalized.end_time, None);
}

#[test]
fn create_injects_month_end_bymonthday_as_minus_one() {
    let mut input = create_input();
    // Jan 31 is the last day of its month, so authoring injects
    // BYMONTHDAY=-1 (count-from-end) rather than a literal 31 — the
    // friendly Jan31->Feb28->Mar31 series then flows through expansion
    // RFC-faithfully instead of skipping short months. Emitted as the
    // one-element array wire form.
    input.start_date = "2026-01-31".to_string();
    input.recurrence = Some(r#"{"FREQ":"MONTHLY","INTERVAL":1}"#.to_string());

    let normalized = normalize_calendar_create(input).expect("monthly recurrence should pass");

    assert_eq!(
        normalized.recurrence.as_deref(),
        Some(r#"{"BYMONTHDAY":[-1],"FREQ":"MONTHLY","INTERVAL":1}"#)
    );
}

#[test]
fn create_rejects_end_date_before_start_date() {
    let mut input = create_input();
    input.end_date = Some("2026-04-30".to_string());

    let err = normalize_calendar_create(input).expect_err("date range must fail");

    assert!(err.to_string().contains("end_date"));
}

#[test]
fn create_rejects_same_day_end_time_before_start_time() {
    let mut input = create_input();
    input.end_time = Some("08:00".to_string());

    let err = normalize_calendar_create(input).expect_err("time range must fail");

    assert!(err.to_string().contains("end_time"));
}

#[test]
fn create_rejects_dst_gap() {
    let mut input = create_input();
    input.start_date = "2026-03-08".to_string();
    input.start_time = Some("02:30".to_string());
    input.end_time = Some("03:30".to_string());

    let err = normalize_calendar_create(input).expect_err("DST gap must fail");

    assert!(err.to_string().contains("does not exist"));
}

#[test]
fn create_accepts_dst_ambiguity_with_warning_payload() {
    let mut input = create_input();
    input.start_date = "2026-11-01".to_string();
    input.start_time = Some("01:30".to_string());
    input.end_time = Some("02:30".to_string());

    let normalized = normalize_calendar_create(input).expect("ambiguous time should pass");

    assert_eq!(
        normalized.dst_guard,
        CalendarDstGuard::Ambiguous {
            wall_clock: "2026-11-01 01:30".to_string(),
            timezone: "America/New_York".to_string(),
        }
    );
}

#[test]
fn update_normalizes_patches_and_effective_fields() {
    let mut input = update_input();
    input.title = Some("  Planning  ".to_string());
    input.url = Patch::Set("MAILTO:team@example.com".to_string());
    input.timezone = Patch::Clear;
    input.end_time = Patch::Clear;

    let normalized =
        normalize_calendar_update(input, existing()).expect("patch normalization should pass");

    assert_eq!(normalized.title.as_deref(), Some("Planning"));
    assert_eq!(
        normalized.url,
        Patch::Set("mailto:team@example.com".to_string())
    );
    assert_eq!(normalized.timezone, Patch::Clear);
    assert_eq!(normalized.end_time, Patch::Clear);
    assert_eq!(normalized.effective.timezone, None);
    assert_eq!(normalized.effective.end_time, None);
}

#[test]
fn update_all_day_forces_time_clears() {
    let mut input = update_input();
    input.all_day = Some(true);

    let normalized =
        normalize_calendar_update(input, existing()).expect("all-day patch should pass");

    assert_eq!(normalized.start_time, Patch::Clear);
    assert_eq!(normalized.end_time, Patch::Clear);
    assert_eq!(normalized.effective.start_time, None);
    assert_eq!(normalized.effective.end_time, None);
}

#[test]
fn update_rejects_dst_gap_against_effective_timezone() {
    let mut input = update_input();
    input.start_date = Some("2026-03-08".to_string());
    input.start_time = Patch::Set("02:30".to_string());

    let err = normalize_calendar_update(input, existing()).expect_err("DST gap must fail");

    assert!(err.to_string().contains("does not exist"));
}
