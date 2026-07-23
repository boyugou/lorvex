mod clock;
mod date;
mod device_state;
mod errors;
mod log_filters;
mod query_support;
mod router_glue;

#[cfg(test)]
mod tests;

#[cfg(test)]
pub(crate) use clock::reset_clock_state_for_tests;
pub(crate) use clock::{new_uuid, utc_now_iso};
pub(crate) use date::{
    canonicalize_reminder_timestamp, resolve_list_name, resolve_optional_date,
    resolve_reminder_local_anchor,
};
pub(crate) use device_state::read_calendar_ai_access_mode;
pub(crate) use errors::{load_failed_error, not_found_error, to_error_detail, to_error_message};
pub(crate) use log_filters::{merge_requested_levels, merge_requested_sources};
pub(crate) use query_support::{
    bounded_limit, bounded_limit_or_default, enrich_and_fence_tasks_for_response,
    fetch_existing_active_tasks_json, fetch_existing_tasks_json, fetch_task_json,
    fetch_tasks_json_batch, next_offset_for_page, plural_s, reload_task_json,
    required_json_i64_field, required_json_string_field,
};
pub(crate) use router_glue::{
    collect_id_strings, extract_composite_pair_id, extract_top_level_id, singleton_id_extractor,
};
