use super::*;
use serde_json::json;

#[test]
#[serial_test::serial(hlc)]
fn wraps_plain_text_with_sentinel() {
    let wrapped = mcp_untrusted_text("hello");
    assert!(wrapped.starts_with(UNTRUSTED_OPEN));
    assert!(wrapped.ends_with(UNTRUSTED_CLOSE));
    assert!(wrapped.contains("hello"));
}

#[test]
#[serial_test::serial(hlc)]
fn strips_c0_controls_preserving_tab_newline() {
    let wrapped = mcp_untrusted_text("a\x00b\x07c\td\ne");
    assert!(wrapped.contains("abc\td\ne"));
}

#[test]
#[serial_test::serial(hlc)]
fn strips_bidi_overrides() {
    let wrapped = mcp_untrusted_text("safe\u{202E}attack");
    assert!(!wrapped.contains('\u{202E}'));
    assert!(wrapped.contains("safeattack"));
}

#[test]
#[serial_test::serial(hlc)]
fn strips_zero_width_characters() {
    let wrapped = mcp_untrusted_text("hel\u{200B}lo\u{FEFF}");
    assert!(!wrapped.contains('\u{200B}'));
    assert!(!wrapped.contains('\u{FEFF}'));
    assert!(wrapped.contains("hello"));
}

#[test]
#[serial_test::serial(hlc)]
fn strips_unicode_tag_smuggling_range() {
    let wrapped = mcp_untrusted_text("visible\u{E0041}\u{E007F}");
    assert!(!wrapped.contains('\u{E0041}'));
    assert!(!wrapped.contains('\u{E007F}'));
    assert!(wrapped.contains("visible"));
}

#[test]
#[serial_test::serial(hlc)]
fn fence_task_wraps_core_fields_and_tags() {
    let mut task = json!({
        "id": "t1",
        "title": "Clean kitchen",
        "body": "with bleach",
        "ai_notes": "noted",
        "raw_input": "clean kitchen tomorrow",
        "tags": ["urgent", "home"],
        "status": "open",
        "priority": 2,
    });
    fence_task_user_fields(&mut task);
    for field in ["title", "body", "ai_notes", "raw_input"] {
        let s = task[field].as_str().expect("string field");
        assert!(s.starts_with(UNTRUSTED_OPEN), "{field} missing open");
        assert!(s.ends_with(UNTRUSTED_CLOSE), "{field} missing close");
    }
    let tags = task["tags"].as_array().expect("tags array");
    for tag in tags {
        let s = tag.as_str().expect("tag string");
        assert!(s.starts_with(UNTRUSTED_OPEN));
        assert!(s.ends_with(UNTRUSTED_CLOSE));
    }
    // Non-string fields are untouched.
    assert_eq!(task["status"], json!("open"));
    assert_eq!(task["priority"], json!(2));
}

#[test]
#[serial_test::serial(hlc)]
fn fence_task_fences_checklist_item_text() {
    let mut task = json!({
        "id": "t1",
        "checklist_items": [
            { "id": "c1", "text": "step one", "done": false },
            { "id": "c2", "text": "step two", "done": true },
        ],
    });
    fence_task_user_fields(&mut task);
    let items = task["checklist_items"].as_array().expect("items array");
    for item in items {
        let s = item["text"].as_str().expect("text string");
        assert!(s.starts_with(UNTRUSTED_OPEN));
        assert!(s.ends_with(UNTRUSTED_CLOSE));
    }
}

#[test]
#[serial_test::serial(hlc)]
fn fence_task_tolerates_missing_fields() {
    let mut task = json!({ "id": "t1" });
    fence_task_user_fields(&mut task);
    assert_eq!(task, json!({ "id": "t1" }));
}

#[test]
#[serial_test::serial(hlc)]
fn fence_calendar_wraps_title_description_location_attendees() {
    let mut event = json!({
        "id": "e1",
        "title": "Team sync",
        "description": "weekly",
        "location": "HQ",
        "attendees": [
            { "email": "a@example.com", "name": "Ada", "status": "accepted" },
        ],
    });
    fence_calendar_event_user_fields(&mut event);
    for field in ["title", "description", "location"] {
        let s = event[field].as_str().expect("string field");
        assert!(s.starts_with(UNTRUSTED_OPEN), "{field} missing open");
        assert!(s.ends_with(UNTRUSTED_CLOSE), "{field} missing close");
    }
    let attendee = &event["attendees"][0];
    assert!(attendee["name"]
        .as_str()
        .unwrap()
        .starts_with(UNTRUSTED_OPEN));
    assert!(attendee["email"]
        .as_str()
        .unwrap()
        .starts_with(UNTRUSTED_OPEN));
}
