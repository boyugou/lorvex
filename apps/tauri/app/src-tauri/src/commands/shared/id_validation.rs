//! UUID-shape validators for entity-ID arguments at the IPC boundary.
//!
//! UUIDs are programmatic identifiers — they have no bidi or zero-width
//! risk and should not flow through `sanitize_user_text`. Instead,
//! parse them strictly so a frontend bug like `"  task-1  "` (post-
//! trim still wrong shape) or a malformed IPC call can't reach the
//! repositories with a value that doesn't match the schema's `id TEXT`
//! column contract.

/// trim, reject empty, parse as UUID.
/// Returns the canonical owned string on success; the parsed UUID is
/// not returned because every caller stores or pipes the original
/// string form.
///
/// the three trust-boundary UUID validators (Tauri
/// `validate_uuid_id`, MCP `validate_uuid_shape`, CLI `parse_uuid_id`)
/// were promoted to
/// [`lorvex_domain::entity_id::parse_id_with_sentinel`] and this
/// helper is now a thin wrapper that pipes the typed
/// `ValidationError` into the legacy `Result<String, String>` shape
/// every Tauri caller already uses. The wording stays exactly as
/// issue #2994 H5 standardized (`"<field> must not be empty"` /
/// `"<field> is not a valid UUID: '<id>'"`) because both
/// `ValidationError::Empty` and `ValidationError::InvalidFormat`
/// emit identical sentences via the helper below.
pub(crate) fn validate_uuid_id(value: &str, field: &'static str) -> Result<String, String> {
    map_id_error(
        lorvex_domain::entity_id::parse_id_with_sentinel(value, field, None),
        field,
    )
}

/// list-id-typed shape check at the IPC boundary.
///
/// Mirrors the CLI's `parse_list_id` (typed-`IdKind::ListId`) carve-
/// out so both surfaces accept the schema-seeded `INBOX_LIST_ID`
/// ("inbox") sentinel. Without this carve-out the CLI would accept
/// `inbox` for any `list id`-shaped argument while Tauri's
/// `validate_uuid_id` rejected it strictly, leaving the two trust
/// boundaries silently inconsistent.
///
/// Every other ID-shaped field (`task_id`, `event_id`, `habit_id`,
/// etc.) keeps using `validate_uuid_id` directly because no other
/// entity has a sentinel-named instance in the schema.
pub(crate) fn validate_list_id(value: &str, field: &'static str) -> Result<String, String> {
    map_id_error(
        lorvex_domain::entity_id::parse_id_with_sentinel(
            value,
            field,
            Some(lorvex_store::INBOX_LIST_ID),
        ),
        field,
    )
}

/// Translate the typed `ValidationError` returned by
/// [`lorvex_domain::entity_id::parse_id_with_sentinel`] into the
/// `Result<String, String>` shape the Tauri IPC boundary already
/// emits, preserving the wording issue #2994 H5 unified across the
/// three surfaces.
fn map_id_error(
    result: Result<String, lorvex_domain::validation::ValidationError>,
    field: &'static str,
) -> Result<String, String> {
    use lorvex_domain::validation::ValidationError;
    result.map_err(|err| match err {
        ValidationError::Empty(_) => format!("{field} must not be empty"),
        ValidationError::InvalidFormat { actual, .. } => {
            format!("{field} is not a valid UUID: '{actual}'")
        }
        // The helper only ever returns Empty or InvalidFormat, but
        // keep an exhaustive catch-all so a future ValidationError
        // variant doesn't silently change the wire wording.
        other => other.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_empty_after_trim() {
        assert_eq!(
            validate_uuid_id("   ", "task_id"),
            Err("task_id must not be empty".to_string())
        );
        assert_eq!(
            validate_uuid_id("", "event_id"),
            Err("event_id must not be empty".to_string())
        );
    }

    #[test]
    fn rejects_non_uuid_shapes() {
        assert_eq!(
            validate_uuid_id("not-a-uuid", "task_id"),
            Err("task_id is not a valid UUID: 'not-a-uuid'".to_string())
        );
        // Trim sucks up surrounding whitespace; the shape check still fires.
        assert_eq!(
            validate_uuid_id("  task-1  ", "task_id"),
            Err("task_id is not a valid UUID: 'task-1'".to_string())
        );
    }

    #[test]
    fn accepts_valid_uuid_v7() {
        let id = lorvex_domain::new_entity_id_string();
        let out = validate_uuid_id(&format!("  {id}  "), "task_id").expect("should parse");
        assert_eq!(out, id);
    }

    #[test]
    fn field_label_propagates_to_error_message() {
        let err = validate_uuid_id("xxx", "calendar_event_id").expect_err("invalid");
        assert!(err.contains("calendar_event_id"));
    }

    /// `validate_list_id` accepts the schema-seeded
    /// `INBOX_LIST_ID` sentinel, mirroring the CLI's `parse_list_id`
    /// (typed `IdKind::ListId`) carve-out.
    #[test]
    fn validate_list_id_accepts_inbox_sentinel() {
        let out = validate_list_id(lorvex_store::INBOX_LIST_ID, "list_id")
            .expect("inbox sentinel must be accepted");
        assert_eq!(out, lorvex_store::INBOX_LIST_ID);
        // Surrounding whitespace is trimmed, then the trimmed value
        // hits the sentinel carve-out.
        let out = validate_list_id("  inbox  ", "list_id").expect("trimmed inbox must be accepted");
        assert_eq!(out, lorvex_store::INBOX_LIST_ID);
    }

    #[test]
    fn validate_list_id_accepts_uuid_v7() {
        let id = lorvex_domain::new_entity_id_string();
        let out = validate_list_id(&id, "list_id").expect("UUIDv7 must be accepted");
        assert_eq!(out, id);
    }

    #[test]
    fn validate_list_id_rejects_other_non_uuid_strings() {
        // Only the literal `INBOX_LIST_ID` sentinel survives the
        // carve-out — every other non-UUID input still fails.
        let err = validate_list_id("not-a-uuid", "list_id").expect_err("non-UUID must reject");
        assert!(err.contains("list_id"));
        assert!(err.contains("not a valid UUID"));
    }

    #[test]
    fn validate_list_id_rejects_empty() {
        assert_eq!(
            validate_list_id("   ", "list_id"),
            Err("list_id must not be empty".to_string())
        );
    }
}
