use super::*;

// ── MemoryRevisionActor::parse ──────────────────────────────────

#[test]
fn parse_ai() {
    assert_eq!(
        MemoryRevisionActor::parse("ai"),
        Some(MemoryRevisionActor::Ai)
    );
}

#[test]
fn parse_human() {
    assert_eq!(
        MemoryRevisionActor::parse("human"),
        Some(MemoryRevisionActor::Human)
    );
}

#[test]
fn parse_unknown_returns_none() {
    assert_eq!(MemoryRevisionActor::parse("system"), None);
    assert_eq!(MemoryRevisionActor::parse("admin"), None);
    assert_eq!(MemoryRevisionActor::parse("bot"), None);
}

#[test]
fn parse_empty_string_returns_none() {
    assert_eq!(MemoryRevisionActor::parse(""), None);
}

#[test]
fn parse_is_case_sensitive() {
    assert_eq!(MemoryRevisionActor::parse("AI"), None);
    assert_eq!(MemoryRevisionActor::parse("Ai"), None);
    assert_eq!(MemoryRevisionActor::parse("Human"), None);
    assert_eq!(MemoryRevisionActor::parse("HUMAN"), None);
}

#[test]
fn parse_rejects_whitespace_padding() {
    assert_eq!(MemoryRevisionActor::parse(" ai"), None);
    assert_eq!(MemoryRevisionActor::parse("ai "), None);
    assert_eq!(MemoryRevisionActor::parse(" human "), None);
}

// ── MemoryRevisionActor::as_str ─────────────────────────────────

#[test]
fn as_str_roundtrips() {
    assert_eq!(
        MemoryRevisionActor::parse(MemoryRevisionActor::Ai.as_str()),
        Some(MemoryRevisionActor::Ai)
    );
    assert_eq!(
        MemoryRevisionActor::parse(MemoryRevisionActor::Human.as_str()),
        Some(MemoryRevisionActor::Human)
    );
}

// ── Display impl ────────────────────────────────────────────────

#[test]
fn display_matches_as_str() {
    assert_eq!(format!("{}", MemoryRevisionActor::Ai), "ai");
    assert_eq!(format!("{}", MemoryRevisionActor::Human), "human");
}

// ── is_human_owned_memory_key ───────────────────────────────────

#[test]
fn notes_for_ai_is_human_owned() {
    assert!(is_human_owned_memory_key("notes_for_ai"));
}

#[test]
fn arbitrary_keys_are_not_human_owned() {
    assert!(!is_human_owned_memory_key("preferences"));
    assert!(!is_human_owned_memory_key("work_schedule"));
    assert!(!is_human_owned_memory_key("user_context"));
}

#[test]
fn empty_key_is_not_human_owned() {
    assert!(!is_human_owned_memory_key(""));
}

#[test]
fn human_owned_key_is_exact_match_not_prefix() {
    assert!(!is_human_owned_memory_key("notes_for_ai_extra"));
    assert!(!is_human_owned_memory_key("notes_for_a"));
    assert!(!is_human_owned_memory_key("notes_for_ai_"));
}

#[test]
fn human_owned_key_is_case_sensitive() {
    assert!(!is_human_owned_memory_key("Notes_For_AI"));
    assert!(!is_human_owned_memory_key("NOTES_FOR_AI"));
    assert!(!is_human_owned_memory_key("Notes_for_ai"));
}

#[test]
fn human_owned_key_rejects_whitespace_padding() {
    assert!(!is_human_owned_memory_key(" notes_for_ai"));
    assert!(!is_human_owned_memory_key("notes_for_ai "));
}

// ── Constant value ──────────────────────────────────────────────

#[test]
fn constant_value_is_stable() {
    assert_eq!(MEMORY_KEY_NOTES_FOR_AI, "notes_for_ai");
}

#[test]
fn normalize_memory_key_trims_strips_invisibles_and_nfc_normalizes() {
    assert_eq!(
        normalize_memory_key("  Cafe\u{0301}.\u{202E}\u{200B}tone  "),
        "Café.tone"
    );
}

#[test]
fn normalize_memory_key_preserves_visible_case_and_internal_whitespace() {
    assert_eq!(
        normalize_memory_key("Project  Alpha"),
        "Project  Alpha",
        "memory keys are structural identifiers; do not casefold or collapse visible spacing"
    );
}

// -- regressions

/// `is_ai_writable_memory_key` is the symmetric
/// counterpart to `is_human_owned_memory_key`. Every key gets
/// classified as exactly one of the two, so the predicates are
/// always disjoint and exhaustive.
#[test]
fn ai_writable_is_disjoint_from_human_owned() {
    let keys = [
        "notes_for_ai",
        "preferences",
        "work_schedule",
        "user_context",
        "",
        "Notes_For_AI",
    ];
    for key in keys {
        assert_ne!(
            is_human_owned_memory_key(key),
            is_ai_writable_memory_key(key),
            "key {key:?} must classify as exactly one of human-only / AI-writable"
        );
    }
}

#[test]
fn ai_writable_excludes_notes_for_ai() {
    assert!(!is_ai_writable_memory_key("notes_for_ai"));
}

#[test]
fn ai_writable_includes_arbitrary_keys() {
    assert!(is_ai_writable_memory_key("preferences"));
    assert!(is_ai_writable_memory_key("work_schedule"));
    assert!(is_ai_writable_memory_key("user_context"));
}

#[test]
fn ai_writable_is_case_sensitive() {
    // Same case-sensitive contract as `is_human_owned_memory_key`.
    // `Notes_For_AI` is NOT the human-reserved key, so it counts
    // as AI-writable.
    assert!(is_ai_writable_memory_key("Notes_For_AI"));
    assert!(is_ai_writable_memory_key("NOTES_FOR_AI"));
}

#[test]
fn memory_key_ownership_classify_routes_through_one_set() {
    assert_eq!(
        MemoryKeyOwnership::classify("notes_for_ai"),
        MemoryKeyOwnership::HumanOnly
    );
    assert_eq!(
        MemoryKeyOwnership::classify("preferences"),
        MemoryKeyOwnership::AiWritable
    );
}

/// the sentinel string is now lazily built from
/// `MAX_MEMORY_CONTENT_LENGTH` so the byte-cap literal lives in
/// exactly one place. The earlier guard test (#2925-M7) is kept
/// because it still pins the contract that the rendered sentinel
/// references the current cap — even with `LazyLock` the literal
/// could drift if the format string is edited carelessly.
#[test]
fn memory_truncation_sentinel_byte_cap_matches_constant() {
    let expected = format!("exceeded {MAX_MEMORY_CONTENT_LENGTH} byte cap");
    assert!(
        MEMORY_TRUNCATION_SENTINEL.contains(&expected),
        "MEMORY_TRUNCATION_SENTINEL must reference the current \
         MAX_MEMORY_CONTENT_LENGTH ({MAX_MEMORY_CONTENT_LENGTH}); \
         rendered sentinel was {sentinel:?}",
        sentinel = &*MEMORY_TRUNCATION_SENTINEL,
    );
}
