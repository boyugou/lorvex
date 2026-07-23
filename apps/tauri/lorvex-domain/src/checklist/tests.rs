use super::*;

#[test]
fn extract_markdown_checklist_splits_items_from_notes() {
    let body = "Context line\n- [ ] First item\n- [x] Second item\nMore notes";
    let extracted = extract_markdown_checklist(body);
    assert_eq!(extracted.remaining_body, "Context line\nMore notes");
    assert_eq!(extracted.items.len(), 2);
    assert_eq!(extracted.items[0].text, "First item");
    assert!(!extracted.items[0].completed);
    assert_eq!(extracted.items[1].text, "Second item");
    assert!(extracted.items[1].completed);
}

/// a Chinese-text checklist item at exactly
/// `MAX_TASK_CHECKLIST_ITEM_TEXT_LENGTH` codepoints must validate
/// successfully. Pre-fix the validator measured bytes, so each
/// 3-byte UTF-8 CJK codepoint counted triple — a 1000-codepoint
/// Chinese item rejected at ~333 chars even though sister
/// validators (title / body / tag name) all count codepoints.
#[test]
fn validate_chinese_text_at_max_codepoints_passes() {
    let text: String = "工".repeat(MAX_TASK_CHECKLIST_ITEM_TEXT_LENGTH);
    assert_eq!(text.chars().count(), MAX_TASK_CHECKLIST_ITEM_TEXT_LENGTH);
    assert!(
        text.len() > MAX_TASK_CHECKLIST_ITEM_TEXT_LENGTH,
        "byte length should exceed codepoint cap so this test exercises the codepoint path"
    );
    validate_task_checklist_item_text(&text)
        .expect("Chinese text at exactly MAX codepoints must validate");
}

/// Companion to the above: one codepoint past the cap must fail
/// with a `TooLong` error whose `actual` is reported in codepoints.
#[test]
fn validate_chinese_text_one_past_max_codepoints_rejects() {
    let text: String = "工".repeat(MAX_TASK_CHECKLIST_ITEM_TEXT_LENGTH + 1);
    match validate_task_checklist_item_text(&text) {
        Err(ValidationError::TooLong { field, max, actual }) => {
            assert_eq!(field, "task_checklist_item.text");
            assert_eq!(max, MAX_TASK_CHECKLIST_ITEM_TEXT_LENGTH);
            assert_eq!(
                actual,
                MAX_TASK_CHECKLIST_ITEM_TEXT_LENGTH + 1,
                "actual must be reported in codepoints, not bytes",
            );
        }
        other => panic!("expected TooLong, got {other:?}"),
    }
}

#[test]
fn extract_markdown_checklist_keeps_indented_lines_in_body() {
    let body = "  - [ ] Nested-ish item\n- [ ] Top level item";
    let extracted = extract_markdown_checklist(body);
    assert_eq!(extracted.remaining_body, "  - [ ] Nested-ish item");
    assert_eq!(extracted.items.len(), 1);
    assert_eq!(extracted.items[0].text, "Top level item");
}
