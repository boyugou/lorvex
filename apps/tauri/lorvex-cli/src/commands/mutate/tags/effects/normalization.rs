use super::*;

pub(crate) fn normalize_capture_tags(
    tags: Option<&[String]>,
) -> Result<Vec<String>, crate::error::CliError> {
    // sanitize each tag display name BEFORE feeding
    // it to `normalize_lookup_key`. ZWSP-spoofed tag names (e.g.
    // "ad‍min" with U+200D vs "admin") would otherwise hash to
    // different lookup_keys after NFKC + casefold (NFKC does not
    // strip ZWNJ/ZWJ), so two visually identical tags would coexist
    // as separate entities and propagate via sync.
    let mut normalized = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for tag in tags.unwrap_or(&[]) {
        let sanitized = lorvex_domain::sanitize_user_text(tag);
        let display_name = sanitized.trim();
        if display_name.is_empty() {
            return Err(crate::error::CliError::Validation(
                "tag must not be empty".to_string(),
            ));
        }
        let char_count = display_name.chars().count();
        if char_count > lorvex_domain::validation::MAX_TAG_NAME_LENGTH {
            return Err(crate::error::CliError::Validation(format!(
                "tag is too long ({char_count}, max {})",
                lorvex_domain::validation::MAX_TAG_NAME_LENGTH
            )));
        }
        let lookup_key = lorvex_domain::tag::normalize_lookup_key(display_name);
        if seen.insert(lookup_key) {
            normalized.push(display_name.to_string());
        }
    }
    Ok(normalized)
}

pub(super) fn normalize_single_tag_name(
    value: &str,
    field: &str,
) -> Result<String, crate::error::CliError> {
    // same sanitize-then-normalize discipline as
    // `normalize_capture_tags` so direct rename/create paths share
    // the bidi/ZWSP-stripping invariant.
    let sanitized = lorvex_domain::sanitize_user_text(value);
    let display_name = sanitized.trim();
    if display_name.is_empty() {
        return Err(crate::error::CliError::Validation(format!(
            "{field} must not be empty"
        )));
    }
    let char_count = display_name.chars().count();
    if char_count > lorvex_domain::validation::MAX_TAG_NAME_LENGTH {
        return Err(crate::error::CliError::Validation(format!(
            "{field} is too long ({char_count}, max {})",
            lorvex_domain::validation::MAX_TAG_NAME_LENGTH
        )));
    }
    Ok(display_name.to_string())
}

pub(crate) fn validate_task_tag_count(
    tags: Option<&[String]>,
) -> Result<(), crate::error::CliError> {
    crate::commands::shared::validate_slice_max_len(tags, "tags", MAX_TASK_TAGS)
}
