use lorvex_domain::validation::{validate_date_format, validate_title};
use percent_encoding::percent_decode_str;
use tauri::Url;

use super::{DeepLinkTarget, MAX_LIST_SLUG_LENGTH};

const APP_SCHEME: &str = "lorvex";

/// Extract a percent-decoded query parameter value by key.
fn query_param(url: &Url, key: &str) -> Option<String> {
    url.query_pairs()
        .find(|(k, _)| k == key)
        .map(|(_, v)| v.into_owned())
        .filter(|v| !v.is_empty())
}

fn required_query_param(url: &Url, key: &str, route: &str) -> Result<String, String> {
    let Some(value) = query_param(url, key) else {
        return Err(format!("{route} deep link requires non-empty '{key}'"));
    };
    if value.trim().is_empty() {
        return Err(format!("{route} deep link requires non-empty '{key}'"));
    }
    Ok(value)
}

/// Validate a task_id from an untrusted source (deep-link query/path) as a
/// canonical UUIDv7. Deep-links can be triggered by any app on the user's
/// machine, so the id is treated as hostile input: it must not be a control
/// character, path separator, or arbitrary blob that downstream consumers
/// might feed to FS or SQL without further validation.
pub(crate) fn validate_task_id(raw: &str, route: &str) -> Result<String, String> {
    match uuid::Uuid::parse_str(raw) {
        Ok(uuid) if uuid.get_version_num() == 7 => Ok(uuid.to_string()),
        _ => Err(format!(
            "{route} deep link task id must be a canonical UUIDv7"
        )),
    }
}

fn parse_task_priority(url: &Url) -> Result<Option<i64>, String> {
    let Some(raw_priority) = query_param(url, "priority") else {
        return Ok(None);
    };

    let priority = raw_priority.parse::<i64>().map_err(|_| {
        "add-task deep link priority must be an integer between 1 and 3".to_string()
    })?;
    if !(1..=3).contains(&priority) {
        return Err("add-task deep link priority must be an integer between 1 and 3".to_string());
    }

    Ok(Some(priority))
}

pub fn parse_opened_url_result(url: &Url) -> Result<Option<DeepLinkTarget>, String> {
    let scheme = url.scheme();
    if !scheme.eq_ignore_ascii_case(APP_SCHEME) {
        return Ok(None);
    }
    let host = url
        .host_str()
        .map(str::trim)
        .filter(|host| !host.is_empty())
        .ok_or_else(|| "deep link must include a route host".to_string())?
        .to_ascii_lowercase();
    let segments: Vec<&str> = url
        .path_segments()
        .map(|parts| parts.filter(|part| !part.trim().is_empty()).collect())
        .unwrap_or_default();

    match host.as_str() {
        "today" if segments.is_empty() => Ok(Some(DeepLinkTarget::Today)),
        "quick-capture" if segments.is_empty() => Ok(Some(DeepLinkTarget::QuickCapture)),
        "search" if segments.is_empty() => {
            let query = required_query_param(url, "q", "search")?;
            Ok(Some(DeepLinkTarget::Search { query }))
        }
        "add-task" if segments.is_empty() => {
            // cap each field and format-validate the due
            // date so an `open 'lorvex://add-task?title=<10MB>'`
            // invocation from another app can't DoS the renderer or
            // persist an unparseable `due_date` string.
            let title = required_query_param(url, "title", "add-task")?;
            validate_title(&title).map_err(|e| format!("add-task deep link title: {e}"))?;

            let list = query_param(url, "list");
            if let Some(list_ref) = list.as_ref() {
                if list_ref.chars().count() > MAX_LIST_SLUG_LENGTH {
                    return Err(format!(
                        "add-task deep link list is too long ({} chars; max {})",
                        list_ref.chars().count(),
                        MAX_LIST_SLUG_LENGTH
                    ));
                }
            }

            let due = query_param(url, "due");
            if let Some(due_ref) = due.as_ref() {
                validate_date_format(due_ref)
                    .map_err(|e| format!("add-task deep link due: {e}"))?;
            }

            let priority = parse_task_priority(url)?;
            Ok(Some(DeepLinkTarget::AddTask {
                title,
                list,
                due,
                priority,
            }))
        }
        "complete-task" if segments.is_empty() => {
            // this route only *parses* a complete-task
            // target; it never mutates state. The frontend handler in
            // `useMainWindowNavigation.ts` treats `CompleteTask` as a
            // navigate-only target — it selects the task in TodayView
            // and lets the user confirm completion with their own
            // click. A drive-by deep link therefore cannot complete a
            // task without an explicit user gesture. Preserve this
            // invariant when adding new CompleteTask consumers
            // (popover, mobile, push notifications): never wire the
            // deep-link result directly into a mutation handler.
            let raw = required_query_param(url, "id", "complete-task")?;
            let task_id = validate_task_id(&raw, "complete-task")?;
            Ok(Some(DeepLinkTarget::CompleteTask { task_id }))
        }
        "task" if segments.len() == 1 => match percent_decode_str(segments[0]).decode_utf8() {
            Ok(decoded) if !decoded.is_empty() => {
                let task_id = validate_task_id(&decoded, "task")?;
                Ok(Some(DeepLinkTarget::Task { task_id }))
            }
            Ok(_) => Err("task deep link requires non-empty task id".to_string()),
            Err(error) => Err(format!(
                "task deep link task id must be valid UTF-8 after percent-decoding: {error}"
            )),
        },
        "today" | "quick-capture" | "search" | "add-task" | "complete-task" | "task" => {
            Err(format!("{host} deep link has an invalid path shape"))
        }
        _ => Ok(None),
    }
}
