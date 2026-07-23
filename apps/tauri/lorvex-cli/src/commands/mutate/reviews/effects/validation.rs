pub(super) fn validate_daily_review_scale(
    field: &str,
    value: Option<u8>,
) -> Result<(), crate::error::CliError> {
    if let Some(value) = value {
        if !(1..=5).contains(&value) {
            return Err(crate::error::CliError::Validation(format!(
                "{field} must be between 1 and 5"
            )));
        }
    }
    Ok(())
}

pub(super) fn sanitize_daily_review_required_text(
    field: &str,
    value: &str,
) -> Result<String, crate::error::CliError> {
    const MAX_REVIEW_TEXT: usize = 50_000;
    let sanitized = lorvex_domain::sanitize_user_text(value);
    if sanitized.trim().is_empty() {
        return Err(crate::error::CliError::Validation(format!(
            "{field} must not be empty"
        )));
    }
    if sanitized.chars().count() > MAX_REVIEW_TEXT {
        return Err(crate::error::CliError::Validation(format!(
            "{field} is too long (max {MAX_REVIEW_TEXT} chars)"
        )));
    }
    Ok(sanitized)
}

pub(super) fn sanitize_daily_review_optional_text(
    field: &str,
    value: Option<&str>,
) -> Result<Option<String>, crate::error::CliError> {
    const MAX_REVIEW_TEXT: usize = 50_000;
    let Some(value) = value else {
        return Ok(None);
    };
    let sanitized = lorvex_domain::sanitize_user_text(value);
    if sanitized.chars().count() > MAX_REVIEW_TEXT {
        return Err(crate::error::CliError::Validation(format!(
            "{field} is too long (max {MAX_REVIEW_TEXT} chars)"
        )));
    }
    Ok(Some(sanitized))
}

pub(super) fn normalize_review_link_ids(
    field: &str,
    ids: &[String],
) -> Result<Vec<String>, crate::error::CliError> {
    const MAX_REVIEW_LINKS: usize = 500;
    if ids.len() > MAX_REVIEW_LINKS {
        return Err(crate::error::CliError::Validation(format!(
            "{field} supports at most {MAX_REVIEW_LINKS} ids"
        )));
    }
    let mut normalized = Vec::with_capacity(ids.len());
    let mut seen = std::collections::HashSet::with_capacity(ids.len());
    for id in ids {
        let id = id.trim();
        if id.is_empty() {
            return Err(crate::error::CliError::Validation(format!(
                "{field} must not contain empty ids"
            )));
        }
        // enforce the canonical UUID shape at
        // the trust boundary.
        // emptiness post-trim, so callers that bypass the clap
        // parser (`run_review_add` ingesting JSON, programmatic
        // callers in tests) could land arbitrary strings into
        // `daily_review_task_links` / `daily_review_list_links`.
        // Mirrors the parser-side validation now wired on
        // `cli/args/review.rs::ReviewAddArgs::linked_task_ids` and
        // `linked_list_ids` (also CL-H14 / CL-M32).
        //
        // Carry-through for the schema-seeded `inbox` sentinel: list
        // links accept the canonical `INBOX_LIST_ID`. Task links
        // never accept a sentinel — every task carries a UUID.
        let allow_inbox_sentinel = field == "linked_list_ids" && id == lorvex_store::INBOX_LIST_ID;
        if !allow_inbox_sentinel && uuid::Uuid::parse_str(id).is_err() {
            return Err(crate::error::CliError::Validation(format!(
                "{field} must contain valid UUIDs; got {id:?}"
            )));
        }
        if seen.insert(id.to_string()) {
            normalized.push(id.to_string());
        }
    }
    Ok(normalized)
}
