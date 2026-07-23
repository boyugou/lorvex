use super::{optional_windows_string, resolve_source_time_semantics};
use crate::error::AppError;
use std::cell::Cell;

#[test]
fn optional_windows_string_preserves_non_empty_values() {
    let value = optional_windows_string::<_, &str>(Ok("Meeting"), "read subject").expect("ok");

    assert_eq!(value.as_deref(), Some("Meeting"));
}

#[test]
fn optional_windows_string_maps_empty_values_to_none() {
    let value = optional_windows_string::<_, &str>(Ok(""), "read location").expect("ok");

    assert_eq!(value, None);
}

#[test]
fn optional_windows_string_surfaces_read_failures() {
    let error = optional_windows_string::<String, _>(Err("boom"), "read details")
        .expect_err("windows property read failures should surface");

    assert!(
        error.to_string().contains("read details: boom"),
        "unexpected error: {error}"
    );
}

#[test]
fn resolve_source_time_semantics_returns_floating_for_all_day_events() {
    let init_calls = Cell::new(0);
    let mut cached = None;

    let semantics = resolve_source_time_semantics(&mut cached, true, || {
        init_calls.set(init_calls.get() + 1);
        Ok("America/Los_Angeles".to_string())
    })
    .expect("all-day events should not require timezone initialization");

    assert_eq!(semantics.kind, "floating");
    assert_eq!(semantics.tzid, None);
    assert_eq!(init_calls.get(), 0);
    assert_eq!(cached, None);
}

#[test]
fn resolve_source_time_semantics_reuses_cached_timezone() {
    let init_calls = Cell::new(0);
    let mut cached = Some("America/New_York".to_string());

    let semantics = resolve_source_time_semantics(&mut cached, false, || {
        init_calls.set(init_calls.get() + 1);
        Ok("America/Los_Angeles".to_string())
    })
    .expect("cached timezone should be reused");

    assert_eq!(semantics.kind, "tzid");
    assert_eq!(semantics.tzid.as_deref(), Some("America/New_York"));
    assert_eq!(init_calls.get(), 0);
}

#[test]
fn resolve_source_time_semantics_initializes_timezone_once_when_missing() {
    let init_calls = Cell::new(0);
    let mut cached = None;

    let semantics = resolve_source_time_semantics(&mut cached, false, || {
        init_calls.set(init_calls.get() + 1);
        Ok("Europe/Berlin".to_string())
    })
    .expect("missing timezone should initialize");

    assert_eq!(semantics.kind, "tzid");
    assert_eq!(semantics.tzid.as_deref(), Some("Europe/Berlin"));
    assert_eq!(cached.as_deref(), Some("Europe/Berlin"));
    assert_eq!(init_calls.get(), 1);
}

#[test]
fn resolve_source_time_semantics_surfaces_timezone_init_failures() {
    let mut cached = None;

    let error = resolve_source_time_semantics(&mut cached, false, || {
        Err(AppError::Internal("boom".to_string()))
    })
    .expect_err("timezone initialization failures should surface");

    assert!(
        error.to_string().contains("boom"),
        "unexpected error: {error}"
    );
    assert_eq!(cached, None);
}
