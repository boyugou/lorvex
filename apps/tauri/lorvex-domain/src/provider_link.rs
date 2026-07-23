//! Canonical validation for task-provider calendar link keys.
//!
//! These fields are a composite SQL key shared by provider link writers.
//! Human/agent-facing trust-boundary writers sanitize and validate through
//! this module so provider kind allowlists, empty-field policy, and
//! short-text caps do not drift per surface.

use crate::validation::{ValidationError, MAX_SHORT_TEXT_LENGTH};

pub const MAX_PROVIDER_LINK_FIELD_LEN: usize = MAX_SHORT_TEXT_LENGTH;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProviderLinkFields {
    pub provider_kind: String,
    pub provider_scope: String,
    pub provider_event_key: String,
}

pub fn normalize_required_provider_link_field(
    value: &str,
    field: &'static str,
) -> Result<String, ValidationError> {
    let normalized = crate::sanitize_user_text(value).trim().to_string();
    if normalized.is_empty() {
        return Err(ValidationError::Empty(field));
    }
    let actual = normalized.chars().count();
    if actual > MAX_PROVIDER_LINK_FIELD_LEN {
        return Err(ValidationError::TooLong {
            field,
            max: MAX_PROVIDER_LINK_FIELD_LEN,
            actual,
        });
    }
    Ok(normalized)
}

pub fn normalize_provider_link_scope(value: &str) -> Result<String, ValidationError> {
    let normalized = crate::sanitize_user_text(value).trim().to_string();
    let actual = normalized.chars().count();
    if actual > MAX_PROVIDER_LINK_FIELD_LEN {
        return Err(ValidationError::TooLong {
            field: "provider_scope",
            max: MAX_PROVIDER_LINK_FIELD_LEN,
            actual,
        });
    }
    Ok(normalized)
}

pub fn normalize_provider_link_fields(
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
) -> Result<ProviderLinkFields, ValidationError> {
    let provider_kind = normalize_required_provider_link_field(provider_kind, "provider_kind")?;
    if !crate::is_allowed_provider_kind(&provider_kind) {
        return Err(ValidationError::Message(format!(
            "provider_kind '{provider_kind}' is not in the allowlist; expected one of: {}",
            crate::provider_kind_allowlist_display()
        )));
    }
    let provider_scope = normalize_provider_link_scope(provider_scope)?;
    let provider_event_key =
        normalize_required_provider_link_field(provider_event_key, "provider_event_key")?;
    Ok(ProviderLinkFields {
        provider_kind,
        provider_scope,
        provider_event_key,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_and_validates_provider_link_fields() {
        let fields = normalize_provider_link_fields(
            "eventkit",
            "  default\u{200B}  ",
            "\u{202E}event-1\u{202C}",
        )
        .expect("valid fields");

        assert_eq!(fields.provider_kind, "eventkit");
        assert_eq!(fields.provider_scope, "default");
        assert_eq!(fields.provider_event_key, "event-1");
    }

    #[test]
    fn accepts_empty_scope_for_single_scope_providers() {
        let fields = normalize_provider_link_fields("eventkit", "", "event-1").expect("valid");

        assert_eq!(fields.provider_scope, "");
    }

    #[test]
    fn rejects_overlong_scope_and_unknown_kind() {
        let too_long = "a".repeat(MAX_PROVIDER_LINK_FIELD_LEN + 1);
        assert!(matches!(
            normalize_provider_link_fields("eventkit", &too_long, "event-1"),
            Err(ValidationError::TooLong {
                field: "provider_scope",
                ..
            })
        ));
        assert!(
            normalize_provider_link_fields("evernote", "default", "event-1")
                .unwrap_err()
                .to_string()
                .contains("not in the allowlist")
        );
    }
}
