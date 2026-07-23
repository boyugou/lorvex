use super::super::*;

#[test]
fn title_valid() {
    assert!(validate_title("Buy groceries").is_ok());
}

#[test]
fn title_at_max_length() {
    let title = "a".repeat(MAX_TITLE_LENGTH);
    assert!(validate_title(&title).is_ok());
}

#[test]
fn title_empty() {
    assert_eq!(validate_title(""), Err(ValidationError::Empty("title")));
}

#[test]
fn title_whitespace_only() {
    assert_eq!(
        validate_title("   \t\n  "),
        Err(ValidationError::Empty("title"))
    );
}

#[test]
fn title_too_long() {
    let title = "a".repeat(MAX_TITLE_LENGTH + 1);
    assert_eq!(
        validate_title(&title),
        Err(ValidationError::TooLong {
            field: "title",
            max: MAX_TITLE_LENGTH,
            actual: MAX_TITLE_LENGTH + 1,
        })
    );
}

#[test]
fn title_unicode_valid() {
    assert!(validate_title("工作计划 🎯").is_ok());
}

/// a title built entirely from zero-width / bidi /
/// control codepoints reads as empty in every UI but used to slip
/// past `validate_title` because `str::trim` only strips ASCII /
/// Unicode whitespace, not the invisible-control set the rest of
/// Lorvex sanitizes elsewhere. Reject as Empty.
#[test]
fn title_pure_invisible_rejects() {
    // Mix of ZWS, BOM, RLO, and word-joiner — all invisible.
    let title = "\u{200B}\u{FEFF}\u{202E}\u{2060}";
    assert_eq!(
        validate_title(title),
        Err(ValidationError::Empty("title")),
        "pure-invisible title must reject as Empty",
    );
}

/// ZWS-padded `"x\u{200B}"` repeated
/// `MAX_TITLE_LENGTH` times must be rejected. The exact failure
/// mode (Empty vs TooLong) is implementation-defined — the only
/// invariant is that the validator does not return `Ok(())`.
#[test]
fn title_zws_padded_x_rejects() {
    let title = "x\u{200B}".repeat(MAX_TITLE_LENGTH);
    assert!(
        validate_title(&title).is_err(),
        "ZWS-padded title must not pass validation",
    );
}

/// the shared validator used to count bytes while
/// the downstream MCP + Tauri surfaces counted codepoints, so a
/// `MAX_TITLE_LENGTH`-long codepoint title passed MCP but was
/// rejected as "too long" when routed through this helper. Pin
/// the unit so the three surfaces can't drift again.
#[test]
fn title_at_max_length_of_multi_byte_codepoints_passes() {
    let title: String = std::iter::repeat_n('🎯', MAX_TITLE_LENGTH).collect();
    assert_eq!(title.chars().count(), MAX_TITLE_LENGTH);
    assert!(
        validate_title(&title).is_ok(),
        "{MAX_TITLE_LENGTH} emoji codepoints must be accepted"
    );
}

#[test]
fn body_at_max_length_of_multi_byte_codepoints_passes() {
    let body: String = std::iter::repeat_n('文', MAX_BODY_LENGTH).collect();
    assert!(validate_body(&body).is_ok());
}

#[test]
fn body_over_max_codepoints_rejected() {
    let body: String = std::iter::repeat_n('文', MAX_BODY_LENGTH + 1).collect();
    assert!(matches!(
        validate_body(&body),
        Err(ValidationError::TooLong { actual, .. }) if actual == MAX_BODY_LENGTH + 1
    ));
}

// -- validate_body -------------------------------------------------

#[test]
fn body_valid() {
    assert!(validate_body("Some notes here.").is_ok());
}

#[test]
fn body_empty_is_ok() {
    assert!(validate_body("").is_ok());
}

#[test]
fn body_at_max_length() {
    let body = "x".repeat(MAX_BODY_LENGTH);
    assert!(validate_body(&body).is_ok());
}

#[test]
fn body_too_long() {
    let body = "x".repeat(MAX_BODY_LENGTH + 1);
    assert_eq!(
        validate_body(&body),
        Err(ValidationError::TooLong {
            field: "body",
            max: MAX_BODY_LENGTH,
            actual: MAX_BODY_LENGTH + 1,
        })
    );
}

/// a body composed entirely of zero-width / bidi /
/// control codepoints reads as empty in every UI surface yet
/// consumes the per-task body budget. Pre-fix `validate_body` only
/// gated on length; a 50KB blob of `\u{200B}\u{FEFF}\u{202E}…`
/// repeats sailed through. Reject visually-empty bodies the same
/// way `validate_title` was hardened in #2962-M4.
#[test]
fn body_visually_empty_rejects() {
    let body = "\u{200B}\u{FEFF}\u{202E}\u{2060}";
    assert_eq!(validate_body(body), Err(ValidationError::Empty("body")));
}

#[test]
fn body_zws_padded_repeat_rejects() {
    let body = "\u{200B}".repeat(1024);
    assert_eq!(validate_body(&body), Err(ValidationError::Empty("body")));
}

// -- validate_tag_name ---------------------------------------------

#[test]
fn tag_name_valid() {
    assert!(validate_tag_name("work").is_ok());
}

#[test]
fn tag_name_empty() {
    assert_eq!(
        validate_tag_name(""),
        Err(ValidationError::Empty("tag_name"))
    );
}

#[test]
fn tag_name_whitespace_only() {
    assert_eq!(
        validate_tag_name("   "),
        Err(ValidationError::Empty("tag_name"))
    );
}

#[test]
fn tag_name_too_long() {
    let name = "a".repeat(MAX_TAG_NAME_LENGTH + 1);
    assert_eq!(
        validate_tag_name(&name),
        Err(ValidationError::TooLong {
            field: "tag_name",
            max: MAX_TAG_NAME_LENGTH,
            actual: MAX_TAG_NAME_LENGTH + 1,
        })
    );
}

#[test]
fn tag_name_at_max() {
    let name = "a".repeat(MAX_TAG_NAME_LENGTH);
    assert!(validate_tag_name(&name).is_ok());
}

#[test]
fn tag_name_unicode() {
    assert!(validate_tag_name("工作").is_ok());
}

/// a tag display name that is non-empty in raw
/// codepoints but visually empty after stripping zero-width / bidi
/// / control codepoints reads as `""` in every rendering surface.
/// Pre-fix `validate_tag_name` only checked `trim().is_empty()`,
/// which doesn't strip ZW/BOM/RLO — same hazard the title
/// validator was hardened against in #2962-M4.
#[test]
fn tag_name_visually_empty_rejects() {
    let name = "\u{200B}\u{FEFF}\u{202E}\u{2060}";
    assert_eq!(
        validate_tag_name(name),
        Err(ValidationError::Empty("tag_name"))
    );
}
