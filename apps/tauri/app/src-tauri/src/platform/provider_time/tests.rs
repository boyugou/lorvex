use super::{
    project_epoch_seconds_to_local, project_windows_filetime_range_to_local,
    resolve_provider_source_timezone_name, UNIX_TO_FILETIME_OFFSET, WINDOWS_TICKS_PER_SECOND,
};

#[test]
fn project_epoch_seconds_rejects_end_before_start() {
    let error = project_epoch_seconds_to_local(200, 100, false).unwrap_err();
    assert!(error
        .to_string()
        .contains("provider event end precedes start"));
}

#[test]
fn project_epoch_seconds_rejects_out_of_range_timestamps() {
    let error = project_epoch_seconds_to_local(i64::MAX, i64::MAX, false).unwrap_err();
    assert!(error.to_string().contains("out of range"));
}

#[test]
fn project_epoch_seconds_all_day_omits_times() {
    let projection = project_epoch_seconds_to_local(0, 3600, true).unwrap();
    assert!(projection.start_time.is_none());
    assert!(projection.end_time.is_none());
}

#[test]
fn project_windows_filetime_range_rejects_negative_duration() {
    let error = project_windows_filetime_range_to_local(
        UNIX_TO_FILETIME_OFFSET,
        -WINDOWS_TICKS_PER_SECOND,
        false,
    )
    .unwrap_err();
    assert!(error.to_string().contains("duration is negative"));
}

#[test]
fn resolve_provider_source_timezone_name_rejects_lookup_failures() {
    let error = resolve_provider_source_timezone_name(Err("timezone lookup failed".to_string()))
        .unwrap_err();
    assert!(error
        .to_string()
        .contains("provider sync requires a resolvable system IANA timezone"));
}

#[test]
fn resolve_provider_source_timezone_name_rejects_invalid_iana_names() {
    let error = resolve_provider_source_timezone_name(Ok("Mars/Phobos".to_string())).unwrap_err();
    assert!(error
        .to_string()
        .contains("provider sync requires a valid IANA timezone"));
}
