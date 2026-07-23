//! Entity identity helpers backed by UUIDv7.
//!
//! UUIDv7 (RFC 9562) is time-sortable: the most significant bits encode a Unix
//! millisecond timestamp, followed by random bits. This means:
//! - `min(id)` = "first-created" semantics
//! - Lexicographic string ordering = chronological ordering
//! - Natural collision resistance (122 bits of entropy after timestamp)
//!
//! ## Granularity caveat
//!
//! The timestamp prefix is **millisecond-granularity**. Two ids minted
//! within the same millisecond differ only in their random suffix, so
//! lexicographic compare on those two ids is effectively a coin flip —
//! *not* "earlier-created < later-created". The chronological-ordering
//! invariants the rest of the codebase relies on (canonical task sort
//! `id ASC` tiebreaker, `min(id) = first-created`) hold across
//! milliseconds; within a single millisecond they degrade to a stable
//! but arbitrary order.
//!
//! This is fine for production traffic — Lorvex never mints thousands
//! of ids in a single ms — but property tests and tight loops should
//! either spread allocations across ms boundaries (see
//! `lexicographic_ordering_matches_chronological`) or accept that
//! same-ms compares are coin-flip. Sub-millisecond counters were
//! considered and rejected as over-engineering for the present
//! workload; document the trade-off here so the next person doesn't
//! rediscover it the hard way.

use crate::validation::ValidationError;

const CANONICAL_UUID_EXPECTED: &str = "canonical hyphenated lowercase UUID";
const CANONICAL_DATE_EXPECTED: &str = "YYYY-MM-DD";
const CANONICAL_MEMORY_KEY_EXPECTED: &str =
    "canonical memory key (trimmed, NFC, no unsafe invisible controls)";
const CANONICAL_SYNCED_PREFERENCE_KEY_EXPECTED: &str = "known synced preference key";
const SYNCABLE_ENTITY_KIND_EXPECTED: &str = "syncable entity kind";

fn invalid_entity_id(expected: &'static str, actual: &str) -> ValidationError {
    ValidationError::InvalidFormat {
        field: "entity_id",
        expected,
        actual: actual.to_string(),
    }
}

fn validate_canonical_uuid_entity_id(value: &str) -> Result<(), ValidationError> {
    let parsed = uuid::Uuid::parse_str(value)
        .map_err(|_| invalid_entity_id(CANONICAL_UUID_EXPECTED, value))?;
    if parsed.to_string() == value {
        Ok(())
    } else {
        Err(invalid_entity_id(CANONICAL_UUID_EXPECTED, value))
    }
}

fn validate_date_entity_id(value: &str) -> Result<(), ValidationError> {
    crate::time::parse_iso_date(value)
        .map(|_| ())
        .map_err(|_| invalid_entity_id(CANONICAL_DATE_EXPECTED, value))
}

fn validate_preference_entity_id(value: &str) -> Result<(), ValidationError> {
    if crate::preference_keys::is_known_preference_key(value)
        && !crate::preference_keys::is_local_only_preference(value)
    {
        Ok(())
    } else {
        Err(invalid_entity_id(
            CANONICAL_SYNCED_PREFERENCE_KEY_EXPECTED,
            value,
        ))
    }
}

fn validate_memory_entity_id(value: &str) -> Result<(), ValidationError> {
    let normalized = crate::memory::normalize_memory_key(value);
    if normalized.is_empty() {
        return Err(ValidationError::Empty("entity_id"));
    }
    if normalized != value {
        return Err(invalid_entity_id(CANONICAL_MEMORY_KEY_EXPECTED, value));
    }
    let actual = value.chars().count();
    if actual > crate::validation::KV_KEY_MAX_CHARS {
        return Err(ValidationError::TooLong {
            field: "entity_id",
            max: crate::validation::KV_KEY_MAX_CHARS,
            actual,
        });
    }
    Ok(())
}

fn split_canonical_composite_entity_id<'a>(
    value: &'a str,
    expected: &'static str,
) -> Result<(&'a str, &'a str), ValidationError> {
    let colon_count = value.bytes().filter(|b| *b == b':').count();
    let Some((left, right)) = value.split_once(':') else {
        return Err(invalid_entity_id(expected, value));
    };
    if colon_count == 1 && !left.is_empty() && !right.is_empty() {
        Ok((left, right))
    } else {
        Err(invalid_entity_id(expected, value))
    }
}

fn validate_uuid_uuid_edge(value: &str, expected: &'static str) -> Result<(), ValidationError> {
    let (left, right) = split_canonical_composite_entity_id(value, expected)?;
    validate_canonical_uuid_entity_id(left)?;
    validate_canonical_uuid_entity_id(right)?;
    Ok(())
}

fn validate_habit_completion_entity_id(value: &str) -> Result<(), ValidationError> {
    let (habit_id, completed_date) =
        split_canonical_composite_entity_id(value, "canonical habit UUID:YYYY-MM-DD")?;
    validate_canonical_uuid_entity_id(habit_id)?;
    validate_date_entity_id(completed_date)
}

/// Validate the canonical `entity_id` shape for a sync envelope's entity kind.
///
/// This is stricter than the human-facing Tauri/MCP/CLI parsers: sync payloads
/// are already serialized storage identities, so this function rejects values
/// that would require trimming, normalization, or format repair before storage.
pub fn validate_sync_entity_id_for_kind(
    kind: crate::naming::EntityKind,
    entity_id: &str,
) -> Result<(), ValidationError> {
    use crate::naming::EntityKind;

    match kind {
        EntityKind::Task
        | EntityKind::Habit
        | EntityKind::Tag
        | EntityKind::CalendarEvent
        | EntityKind::CalendarSubscription
        | EntityKind::MemoryRevision
        | EntityKind::TaskReminder
        | EntityKind::TaskChecklistItem
        | EntityKind::HabitReminderPolicy
        | EntityKind::AiChangelog => validate_canonical_uuid_entity_id(entity_id),
        EntityKind::List => {
            if entity_id == crate::ids::ListId::inbox().as_str() {
                Ok(())
            } else {
                validate_canonical_uuid_entity_id(entity_id)
            }
        }
        EntityKind::Preference => validate_preference_entity_id(entity_id),
        EntityKind::Memory => validate_memory_entity_id(entity_id),
        EntityKind::DailyReview | EntityKind::CurrentFocus | EntityKind::FocusSchedule => {
            validate_date_entity_id(entity_id)
        }
        EntityKind::TaskTag => validate_uuid_uuid_edge(entity_id, "canonical task UUID:tag UUID"),
        EntityKind::TaskDependency => {
            validate_uuid_uuid_edge(entity_id, "canonical task UUID:dependency task UUID")
        }
        EntityKind::TaskCalendarEventLink => {
            validate_uuid_uuid_edge(entity_id, "canonical task UUID:calendar event UUID")
        }
        EntityKind::HabitCompletion => validate_habit_completion_entity_id(entity_id),
        EntityKind::TaskProviderEventLink
        | EntityKind::DeviceState
        | EntityKind::SavedQuery
        | EntityKind::ImportSession => {
            Err(invalid_entity_id(SYNCABLE_ENTITY_KIND_EXPECTED, entity_id))
        }
    }
}

/// Parse a UUID-shaped entity ID at a trust boundary, with optional
/// support for a single non-UUID sentinel value (e.g. the schema-seeded
/// `INBOX_LIST_ID` sentinel for list IDs).
///
/// The contract is fixed across every trust-boundary surface (Tauri
/// IPC, MCP server, CLI):
///
/// 1. The input is `trim`-ed first; surrounding whitespace from a UI
///    autosave or an over-eager copy-paste is silently absorbed.
/// 2. If the trimmed value is empty, returns
///    [`ValidationError::Empty`].
/// 3. If `sentinel` is `Some(s)` and the trimmed value equals `s`,
///    returns the trimmed string verbatim — no UUID shape check
///    runs, because the sentinel by definition is not a UUID.
/// 4. Otherwise, the trimmed value must parse as a `uuid::Uuid` of
///    any version (we deliberately do not gate on v7 here because
///    historical IDs predating the v7 migration may flow through).
///    A parse failure surfaces as
///    [`ValidationError::InvalidFormat`] with the original trimmed
///    value as `actual`.
///
/// This helper carries the entire contract; each surface wraps
/// the returned `ValidationError` in its crate-local error variant
/// so the three id-parsing surfaces (Tauri IPC's
/// `validate_uuid_id`, the MCP server's `validate_uuid_shape`, and
/// the CLI's `parse_uuid_id`) stay in lockstep on wording and
/// sentinel handling. Reimplementing the contract per surface is a
/// known drift hazard: the `inbox` sentinel was once Tauri- and
/// CLI-only while MCP rejected it, requiring parallel error
/// wording fixes whenever the contract evolved.
///
/// `field` is the field label included in the typed `ValidationError`
/// so error messages remain caller-meaningful
/// (`"task_id is not a valid UUID: 'foo'"` vs the ambiguous
/// `"id is not a valid UUID"`).
pub fn parse_id_with_sentinel(
    value: &str,
    field: &'static str,
    sentinel: Option<&str>,
) -> Result<String, ValidationError> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(ValidationError::Empty(field));
    }
    if let Some(sentinel) = sentinel {
        if trimmed == sentinel {
            return Ok(trimmed.to_string());
        }
    }
    uuid::Uuid::parse_str(trimmed)
        .map(|_| trimmed.to_string())
        .map_err(|_| ValidationError::InvalidFormat {
            field,
            expected: "UUID",
            actual: trimmed.to_string(),
        })
}

#[cfg(test)]
mod parse_id_with_sentinel_tests {
    use super::*;

    const VALID_V7: &str = "01966a3f-7c8b-7d4e-8f3a-000000000001";

    #[test]
    fn rejects_empty_after_trim() {
        let err = parse_id_with_sentinel("   ", "task_id", None).unwrap_err();
        assert!(matches!(err, ValidationError::Empty("task_id")));
    }

    #[test]
    fn accepts_uuid_v4_and_v7() {
        let v4 = "f47ac10b-58cc-4372-a567-0e02b2c3d479";
        assert_eq!(parse_id_with_sentinel(v4, "task_id", None).unwrap(), v4);
        assert_eq!(
            parse_id_with_sentinel(VALID_V7, "task_id", None).unwrap(),
            VALID_V7
        );
    }

    #[test]
    fn trims_surrounding_whitespace() {
        let padded = format!("  {VALID_V7}  ");
        let out = parse_id_with_sentinel(&padded, "task_id", None).unwrap();
        assert_eq!(out, VALID_V7);
    }

    #[test]
    fn rejects_garbage_with_field_label() {
        let err = parse_id_with_sentinel("not-a-uuid", "list_id", None).unwrap_err();
        match err {
            ValidationError::InvalidFormat {
                field,
                expected,
                actual,
            } => {
                assert_eq!(field, "list_id");
                assert_eq!(expected, "UUID");
                assert_eq!(actual, "not-a-uuid");
            }
            other => panic!("expected InvalidFormat, got {other:?}"),
        }
    }

    #[test]
    fn sentinel_is_accepted_without_uuid_shape_check() {
        let out = parse_id_with_sentinel("inbox", "list_id", Some("inbox")).unwrap();
        assert_eq!(out, "inbox");
    }

    #[test]
    fn sentinel_does_not_disable_uuid_validation_for_other_inputs() {
        let err = parse_id_with_sentinel("not-a-uuid", "list_id", Some("inbox")).unwrap_err();
        assert!(matches!(err, ValidationError::InvalidFormat { .. }));
    }

    #[test]
    fn sentinel_match_respects_trim() {
        let out = parse_id_with_sentinel("  inbox  ", "list_id", Some("inbox")).unwrap();
        assert_eq!(out, "inbox");
    }
}

/// Mint a new UUIDv7-shaped entity ID as a canonical hyphenated string.
///
/// UUIDv7 (RFC 9562) is time-sortable: the most significant bits encode
/// a Unix millisecond timestamp followed by random bits, so:
/// - `min(id)` ≈ "first-created" semantics
/// - Lexicographic string ordering ≈ chronological ordering
/// - 122 bits of post-timestamp entropy → natural collision resistance
///
/// The previous typed `EntityId` wrapper plus `parse` / `as_uuid` /
/// `EntityIdParseError` / `Default` / `Ord` / `Hash` / `Serialize` /
/// `Deserialize` machinery had zero typed downstream — every
/// external caller did `EntityId::new().to_string()` immediately.
/// Replacing the wrapper with this free function removes 280 lines
/// of unused-typed-surface scaffolding without losing any production
/// capability; the canonical UUIDv7 string round-trips through every
/// storage / sync / API surface as before.
pub fn new_entity_id_string() -> String {
    uuid::Uuid::now_v7().to_string()
}

#[cfg(test)]
mod new_entity_id_string_tests {
    use super::*;

    #[test]
    fn produces_uuid_v7_shape() {
        let s = new_entity_id_string();
        assert_eq!(s.len(), 36, "UUID string should be 36 chars (8-4-4-4-12)");
        assert_eq!(s.chars().filter(|&c| c == '-').count(), 4);
        let uuid = uuid::Uuid::parse_str(&s).expect("must parse as UUID");
        assert_eq!(
            uuid.get_version(),
            Some(uuid::Version::SortRand),
            "must produce UUIDv7"
        );
    }

    #[test]
    fn lexicographic_ordering_matches_chronological() {
        // UUIDv7 has millisecond-granularity timestamps; poll until
        // we observe a strictly-greater value rather than relying on
        // `thread::sleep(2ms)`, which can undercut a coarse Windows
        // 15.6ms scheduler tick.
        let first = new_entity_id_string();
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
        loop {
            let candidate = new_entity_id_string();
            if candidate > first {
                return;
            }
            assert!(
                std::time::Instant::now() < deadline,
                "new_entity_id_string did not advance past {first} within 2s"
            );
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
    }
}

#[cfg(test)]
mod sync_entity_id_validation_tests {
    use super::*;

    use crate::naming::EntityKind;

    const UUID_A: &str = "01966a3f-7c8b-7d4e-8f3a-000000000001";
    const UUID_B: &str = "01966a3f-7c8b-7d4e-8f3a-000000000002";

    #[test]
    fn validates_uuid_backed_entity_ids_without_accepting_opaque_strings() {
        validate_sync_entity_id_for_kind(EntityKind::Task, UUID_A).unwrap();

        let err = validate_sync_entity_id_for_kind(EntityKind::Task, "not-a-uuid").unwrap_err();
        assert!(matches!(
            err,
            ValidationError::InvalidFormat {
                field: "entity_id",
                ..
            }
        ));
    }

    #[test]
    fn validates_kind_specific_sentinels_and_natural_keys() {
        validate_sync_entity_id_for_kind(EntityKind::List, "inbox").unwrap();
        validate_sync_entity_id_for_kind(EntityKind::DailyReview, "2026-05-09").unwrap();
        validate_sync_entity_id_for_kind(EntityKind::Preference, "timezone").unwrap();
        validate_sync_entity_id_for_kind(EntityKind::Memory, "project.notes").unwrap();

        validate_sync_entity_id_for_kind(EntityKind::Task, "inbox").unwrap_err();
        validate_sync_entity_id_for_kind(EntityKind::DailyReview, "2026-02-31").unwrap_err();
        validate_sync_entity_id_for_kind(EntityKind::Preference, "sync_backend_configs")
            .unwrap_err();
        validate_sync_entity_id_for_kind(EntityKind::Memory, " project.notes ").unwrap_err();
    }

    #[test]
    fn validates_composite_edge_members_by_edge_kind() {
        validate_sync_entity_id_for_kind(EntityKind::TaskTag, &format!("{UUID_A}:{UUID_B}"))
            .unwrap();
        validate_sync_entity_id_for_kind(EntityKind::TaskDependency, &format!("{UUID_A}:{UUID_B}"))
            .unwrap();
        validate_sync_entity_id_for_kind(
            EntityKind::TaskCalendarEventLink,
            &format!("{UUID_A}:{UUID_B}"),
        )
        .unwrap();
        validate_sync_entity_id_for_kind(
            EntityKind::HabitCompletion,
            &format!("{UUID_A}:2026-05-09"),
        )
        .unwrap();

        validate_sync_entity_id_for_kind(EntityKind::TaskTag, &format!("not-a-uuid:{UUID_B}"))
            .unwrap_err();
        validate_sync_entity_id_for_kind(
            EntityKind::HabitCompletion,
            &format!("{UUID_A}:bad-date"),
        )
        .unwrap_err();
    }
}
