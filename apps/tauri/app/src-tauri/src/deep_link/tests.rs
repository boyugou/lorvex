use super::queue::poison_pending_queue_for_test;
use super::{
    acknowledge_pending_payload, enqueue_pending, parse_opened_url_result, take_pending_payload,
};
use super::{DeepLinkTarget, DeepLinkTargetPayload};
use std::sync::{Mutex, OnceLock};

fn queue_test_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

fn clear_pending_queue() {
    while take_pending_payload().is_some() {}
}

fn parse_success(url: &str) -> Option<DeepLinkTarget> {
    let url = url.parse().expect("parse deep link url");
    parse_opened_url_result(&url).expect("deep link should parse successfully")
}

fn parse_unsupported(url: &str) -> Option<DeepLinkTarget> {
    let url = url.parse().expect("parse deep link url");
    parse_opened_url_result(&url).expect("unsupported deep link should not error")
}

fn parse_error(url: &str) -> String {
    let url = url.parse().expect("parse deep link url");
    parse_opened_url_result(&url).expect_err("deep link should be rejected with a reason")
}

#[test]
fn deep_link_parse_today_route() {
    let parsed = parse_success("lorvex://today");

    assert_eq!(parsed, Some(DeepLinkTarget::Today));
}

#[test]
fn deep_link_parse_today_route_case_insensitive_scheme() {
    let parsed = parse_success("LORVEX://today");

    assert_eq!(parsed, Some(DeepLinkTarget::Today));
}

#[test]
fn deep_link_parse_quick_capture_route() {
    let parsed = parse_success("lorvex://quick-capture");

    assert_eq!(parsed, Some(DeepLinkTarget::QuickCapture));
}

#[test]
fn deep_link_parse_task_route_with_id() {
    // A real UUIDv7: version nibble is 7 at position 14. Lorvex treats
    // deep-link task ids as hostile input and rejects anything that isn't
    // canonical UUIDv7 (see `validate_task_id` in deep_link/parse.rs).
    let parsed = parse_success("lorvex://task/018fefc6-9f7b-7c5e-bc4f-6f3a8a9b1234");

    assert_eq!(
        parsed,
        Some(DeepLinkTarget::Task {
            task_id: "018fefc6-9f7b-7c5e-bc4f-6f3a8a9b1234".to_string(),
        }),
    );
}

#[test]
fn deep_link_parse_task_route_rejects_non_uuidv7_id() {
    // Reserved-character payloads (opaque-id shapes) must be
    // rejected — the deep-link surface enforces UUIDv7.
    let error = parse_error("lorvex://task/ops%2Fplan%20%23ready");
    assert!(error.contains("UUIDv7"), "unexpected error: {error}");

    // Whitespace-padded ids are also rejected.
    let error = parse_error("lorvex://task/%20focus-task%20");
    assert!(error.contains("UUIDv7"), "unexpected error: {error}");

    // A v4 UUID (version nibble 4) is rejected — only v7 is accepted.
    let error = parse_error("lorvex://task/123e4567-e89b-12d3-a456-426614174000");
    assert!(error.contains("UUIDv7"), "unexpected error: {error}");
}

#[test]
fn deep_link_rejects_non_app_scheme() {
    let parsed = parse_unsupported("https://example.com/today");

    assert!(parsed.is_none());
}

#[test]
fn deep_link_rejects_task_without_id() {
    let error = parse_error("lorvex://task");
    assert!(error.contains("invalid path shape"));
}

#[test]
fn deep_link_rejects_raw_task_route_with_multiple_path_segments() {
    let error = parse_error("lorvex://task/ops/plan");
    assert!(error.contains("invalid path shape"));
}

#[test]
fn deep_link_rejects_unknown_host() {
    let parsed = parse_unsupported("lorvex://settings");

    assert!(parsed.is_none());
}

#[test]
fn deep_link_acknowledge_removes_matching_pending_entry() {
    let _guard = queue_test_lock().lock().expect("lock deep-link queue test");
    clear_pending_queue();
    let target = DeepLinkTarget::Task {
        task_id: "018fefc6-9f7b-7c5e-bc4f-6f3a8a9b1234".to_string(),
    };
    enqueue_pending(target.clone());

    let acknowledged = acknowledge_pending_payload(&target.to_payload());
    assert!(acknowledged);

    let pending = take_pending_payload();
    assert!(pending.is_none());
    clear_pending_queue();
}

#[test]
fn deep_link_acknowledge_removes_matching_quick_capture_pending_entry() {
    let _guard = queue_test_lock().lock().expect("lock deep-link queue test");
    clear_pending_queue();
    let target = DeepLinkTarget::QuickCapture;
    enqueue_pending(target.clone());

    let acknowledged = acknowledge_pending_payload(&target.to_payload());
    assert!(acknowledged);

    let pending = take_pending_payload();
    assert!(pending.is_none());
    clear_pending_queue();
}

#[test]
fn deep_link_queue_recovers_after_poison() {
    let _guard = queue_test_lock().lock().expect("lock deep-link queue test");
    clear_pending_queue();
    poison_pending_queue_for_test();

    enqueue_pending(DeepLinkTarget::Today);
    let pending = take_pending_payload();
    assert_eq!(pending, Some(DeepLinkTarget::Today.to_payload()));
    clear_pending_queue();
}

// ---------- URL scheme: search ----------

#[test]
fn deep_link_parse_search_with_query() {
    let parsed = parse_success("lorvex://search?q=buy%20groceries");

    assert_eq!(
        parsed,
        Some(DeepLinkTarget::Search {
            query: "buy groceries".to_string(),
        }),
    );
}

#[test]
fn deep_link_search_rejects_missing_query() {
    let error = parse_error("lorvex://search");
    assert!(error.contains("requires non-empty 'q'"));
}

#[test]
fn deep_link_search_rejects_empty_query() {
    let error = parse_error("lorvex://search?q=");
    assert!(error.contains("requires non-empty 'q'"));
}

#[test]
fn deep_link_search_rejects_whitespace_only_query() {
    let error = parse_error("lorvex://search?q=%20%20%20");
    assert!(error.contains("requires non-empty 'q'"));
}

// ---------- URL scheme: add-task ----------

#[test]
fn deep_link_parse_add_task_with_title_only() {
    let parsed = parse_success("lorvex://add-task?title=Buy%20milk");

    assert_eq!(
        parsed,
        Some(DeepLinkTarget::AddTask {
            title: "Buy milk".to_string(),
            list: None,
            due: None,
            priority: None,
        }),
    );
}

#[test]
fn deep_link_parse_add_task_with_all_params() {
    let parsed = parse_success(
        "lorvex://add-task?title=Finish%20report&list=Work&due=2026-04-01&priority=2",
    );

    assert_eq!(
        parsed,
        Some(DeepLinkTarget::AddTask {
            title: "Finish report".to_string(),
            list: Some("Work".to_string()),
            due: Some("2026-04-01".to_string()),
            priority: Some(2),
        }),
    );
}

#[test]
fn deep_link_add_task_rejects_missing_title() {
    let error = parse_error("lorvex://add-task?list=Work");
    assert!(error.contains("requires non-empty 'title'"));
}

#[test]
fn deep_link_add_task_rejects_empty_title() {
    let error = parse_error("lorvex://add-task?title=");
    assert!(error.contains("requires non-empty 'title'"));
}

#[test]
fn deep_link_add_task_rejects_whitespace_only_title() {
    let error = parse_error("lorvex://add-task?title=%20%20%20");
    assert!(error.contains("requires non-empty 'title'"));
}

#[test]
fn deep_link_add_task_rejects_out_of_range_priority() {
    let error = parse_error("lorvex://add-task?title=Test&priority=4");
    assert!(error.contains("priority"));
}

#[test]
fn deep_link_add_task_rejects_non_numeric_priority() {
    let error = parse_error("lorvex://add-task?title=Test&priority=high");
    assert!(error.contains("priority"));
}

// the add-task deep link must bound payload size and
// validate the `due` field format. These tests lock that in — a
// malicious caller invoking `open lorvex://...` cannot DoS the
// renderer with a 10 MB title or persist a nonsensical due date.

#[test]
fn deep_link_add_task_rejects_oversized_title() {
    // `ValidationError::TooLong` Display was unified
    // on the `"exceeds maximum length"` wording every Tauri / MCP /
    // habit-write surface already used (#2994 H1). The deep-link
    // surface routes through `validate_title`, so the same wording
    // bubbles up here.
    let long = "a".repeat(1_001);
    let error = parse_error(&format!("lorvex://add-task?title={long}"));
    assert!(
        error.contains("title") && error.to_lowercase().contains("exceeds maximum length"),
        "expected title-exceeds-max-length error, got: {error}"
    );
}

#[test]
fn deep_link_add_task_rejects_oversized_list_slug() {
    let long_list = "b".repeat(1_001);
    let error = parse_error(&format!("lorvex://add-task?title=Test&list={long_list}"));
    assert!(
        error.contains("list") && error.contains("too long"),
        "expected list-too-long error, got: {error}"
    );
}

#[test]
fn deep_link_add_task_rejects_malformed_due_date() {
    let error = parse_error("lorvex://add-task?title=Test&due=not-a-date");
    assert!(
        error.contains("due"),
        "expected due-date validation error, got: {error}"
    );
}

#[test]
fn deep_link_add_task_rejects_due_date_with_wrong_separator() {
    let error = parse_error("lorvex://add-task?title=Test&due=2026/01/01");
    assert!(
        error.contains("due"),
        "expected due-date validation error, got: {error}"
    );
}

#[test]
fn deep_link_parse_result_rejects_non_numeric_priority_with_reason() {
    let error = parse_error("lorvex://add-task?title=Test&priority=high");

    assert!(
        error.contains("priority"),
        "unexpected parse error message: {error}"
    );
}

#[test]
fn deep_link_parse_result_rejects_invalid_percent_encoded_task_id_with_reason() {
    let error = parse_error("lorvex://task/%FF");

    assert!(
        error.contains("task id"),
        "unexpected parse error message: {error}"
    );
}

// ---------- URL scheme: complete-task ----------

#[test]
fn deep_link_parse_complete_task() {
    let parsed = parse_success("lorvex://complete-task?id=018fefc6-9f7b-7c5e-bc4f-6f3a8a9b1234");

    assert_eq!(
        parsed,
        Some(DeepLinkTarget::CompleteTask {
            task_id: "018fefc6-9f7b-7c5e-bc4f-6f3a8a9b1234".to_string(),
        }),
    );
}

#[test]
fn deep_link_parse_complete_task_rejects_non_uuidv7_id() {
    let error = parse_error("lorvex://complete-task?id=abc-123");
    assert!(error.contains("UUIDv7"), "unexpected error: {error}");
}

#[test]
fn deep_link_complete_task_rejects_missing_id() {
    let error = parse_error("lorvex://complete-task");
    assert!(error.contains("requires non-empty 'id'"));
}

#[test]
fn deep_link_complete_task_rejects_empty_id() {
    let error = parse_error("lorvex://complete-task?id=");
    assert!(error.contains("requires non-empty 'id'"));
}

// ---------- Payload round-trips for new variants ----------

#[test]
fn deep_link_search_payload_roundtrip() {
    let target = DeepLinkTarget::Search {
        query: "urgent".to_string(),
    };
    let payload = target.to_payload();
    assert_eq!(payload.route, "search");
    assert_eq!(
        payload.params.get("q").map(std::string::String::as_str),
        Some("urgent")
    );
    let recovered = DeepLinkTarget::from_payload_result(&payload).expect("decode search payload");
    assert_eq!(recovered, Some(target));
}

#[test]
fn deep_link_add_task_payload_roundtrip() {
    let target = DeepLinkTarget::AddTask {
        title: "Buy milk".to_string(),
        list: Some("Shopping".to_string()),
        due: Some("2026-04-01".to_string()),
        priority: Some(2),
    };
    let payload = target.to_payload();
    assert_eq!(payload.route, "add_task");
    let recovered = DeepLinkTarget::from_payload_result(&payload).expect("decode add-task payload");
    assert_eq!(recovered, Some(target));
}

#[test]
fn deep_link_complete_task_payload_roundtrip() {
    let target = DeepLinkTarget::CompleteTask {
        task_id: "018fefc6-9f7b-7c5e-bc4f-6f3a8a9b1234".to_string(),
    };
    let payload = target.to_payload();
    assert_eq!(payload.route, "complete_task");
    let recovered =
        DeepLinkTarget::from_payload_result(&payload).expect("decode complete-task payload");
    assert_eq!(recovered, Some(target));
}

#[test]
fn deep_link_from_payload_result_rejects_non_uuidv7_task_id() {
    // `acknowledge_pending_payload` must enforce the same UUIDv7
    // gate as the URL parser; accepting any non-empty string as
    // `task_id` would let a malicious deep link routed via the
    // restore-on-launch queue bypass the gate. Both `task` and
    // `complete_task` payloads fail the same way the URL path fails.
    for bad in ["task-xyz", "", "018fefc6-9f7b-4c5e-bc4f-6f3a8a9b1234"] {
        if bad.is_empty() {
            continue;
        }
        let payload = DeepLinkTargetPayload {
            route: "task".to_string(),
            task_id: Some(bad.to_string()),
            params: Default::default(),
        };
        let error = DeepLinkTarget::from_payload_result(&payload)
            .expect_err(&format!("task payload id {bad:?} must be rejected"));
        assert!(
            error.contains("UUIDv7"),
            "expected UUIDv7 rejection for {bad:?}, got: {error}"
        );

        let payload = DeepLinkTargetPayload {
            route: "complete_task".to_string(),
            task_id: Some(bad.to_string()),
            params: Default::default(),
        };
        let error = DeepLinkTarget::from_payload_result(&payload).expect_err(&format!(
            "complete_task payload id {bad:?} must be rejected"
        ));
        assert!(
            error.contains("UUIDv7"),
            "expected UUIDv7 rejection for {bad:?}, got: {error}"
        );
    }
}

#[test]
fn deep_link_from_payload_result_rejects_non_numeric_priority_with_reason() {
    let payload = DeepLinkTargetPayload {
        route: "add_task".to_string(),
        task_id: None,
        params: [
            ("title".to_string(), "Test".to_string()),
            ("priority".to_string(), "high".to_string()),
        ]
        .into_iter()
        .collect(),
    };

    let error = DeepLinkTarget::from_payload_result(&payload)
        .expect_err("non-numeric payload priority should surface malformed reason");
    assert!(
        error.contains("priority"),
        "unexpected payload parse error: {error}"
    );
}

#[test]
fn deep_link_from_payload_result_rejects_out_of_range_priority() {
    // The JSON-payload path must enforce the same 1..=3 guard as
    // the URL-query path so out-of-range integers (-5, 0, 99999)
    // are rejected at the deep-link boundary instead of breaking
    // downstream queries that assume priority ∈ {1, 2, 3, NULL}.
    for bad in ["0", "-1", "4", "99", "-99999"] {
        let payload = DeepLinkTargetPayload {
            route: "add_task".to_string(),
            task_id: None,
            params: [
                ("title".to_string(), "Test".to_string()),
                ("priority".to_string(), bad.to_string()),
            ]
            .into_iter()
            .collect(),
        };
        let error = DeepLinkTarget::from_payload_result(&payload)
            .expect_err(&format!("priority {bad:?} must be rejected"));
        assert!(
            error.contains("between 1 and 3"),
            "expected range-error for priority {bad:?}, got: {error}"
        );
    }
}

#[test]
fn deep_link_acknowledge_rejects_malformed_payload_without_removing_pending_entry() {
    let _guard = queue_test_lock().lock().expect("lock deep-link queue test");
    clear_pending_queue();
    let target = DeepLinkTarget::AddTask {
        title: "Queued task".to_string(),
        list: None,
        due: None,
        priority: Some(2),
    };
    enqueue_pending(target.clone());

    let malformed_payload = DeepLinkTargetPayload {
        route: "add_task".to_string(),
        task_id: None,
        params: [
            ("title".to_string(), "Queued task".to_string()),
            ("priority".to_string(), "high".to_string()),
        ]
        .into_iter()
        .collect(),
    };

    assert!(!acknowledge_pending_payload(&malformed_payload));

    let pending = take_pending_payload();
    assert_eq!(pending, Some(target.to_payload()));
    clear_pending_queue();
}
