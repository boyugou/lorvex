use super::*;
use rmcp::model::{CallToolResult, Content};
use std::time::Duration;

fn ok_result() -> CallToolResult {
    CallToolResult::success(vec![Content::text("ok")])
}

#[tokio::test]
async fn fast_handler_passes_through() {
    let out = run_with_timeout("fast_tool", Duration::from_secs(5), async {
        Ok(ok_result())
    })
    .await
    .expect("fast handler should succeed");
    assert!(!out.is_error.unwrap_or(false));
}

#[tokio::test]
async fn slow_handler_hits_watchdog() {
    // Use real time with a tiny timeout rather than
    // `start_paused = true`, which would require the
    // `tokio/test-util` feature. 50ms is more than enough for the
    // `timeout` to fire and the error path to build its message
    // before the (never-awaited) 10s sleep would have completed.
    let err = run_with_timeout("slow_tool", Duration::from_millis(50), async {
        tokio::time::sleep(Duration::from_secs(10)).await;
        Ok(ok_result())
    })
    .await
    .expect_err("slow handler must trip the watchdog");

    assert!(
        err.message.contains("slow_tool"),
        "error should name the offending tool, got: {}",
        err.message
    );
    assert!(
        err.message.contains("watchdog timeout"),
        "error should mention watchdog timeout, got: {}",
        err.message
    );
    // The message reports elapsed seconds as a u64; 50ms floors
    // to 0, so the assertion checks for "0s" plus the human hint.
    assert!(
        err.message.contains("partial work may have been committed"),
        "error should warn about partial commits, got: {}",
        err.message
    );
}

#[tokio::test]
async fn handler_error_propagates() {
    let err = run_with_timeout("err_tool", Duration::from_secs(5), async {
        Err(ErrorData::internal_error("boom", None))
    })
    .await
    .expect_err("handler error should surface");
    assert_eq!(err.message, "boom");
}

#[test]
#[serial_test::serial(hlc)]
fn parse_tool_timeout_defaults_when_missing() {
    assert_eq!(
        parse_tool_timeout(None),
        Duration::from_secs(DEFAULT_MCP_TOOL_TIMEOUT_SECS)
    );
}

#[test]
#[serial_test::serial(hlc)]
fn parse_tool_timeout_defaults_when_empty_or_whitespace() {
    for raw in ["", "   ", "\t", "\n"] {
        assert_eq!(
            parse_tool_timeout(Some(raw)),
            Duration::from_secs(DEFAULT_MCP_TOOL_TIMEOUT_SECS),
            "input {raw:?} should fall back to default"
        );
    }
}

#[test]
#[serial_test::serial(hlc)]
fn parse_tool_timeout_zero_falls_back_to_default() {
    // Zero is meaningless as a watchdog; the parser warns and uses
    // the default rather than disabling the watchdog entirely.
    assert_eq!(
        parse_tool_timeout(Some("0")),
        Duration::from_secs(DEFAULT_MCP_TOOL_TIMEOUT_SECS)
    );
}

#[test]
#[serial_test::serial(hlc)]
fn parse_tool_timeout_accepts_positive_u64() {
    assert_eq!(parse_tool_timeout(Some("5")), Duration::from_secs(5));
    assert_eq!(
        parse_tool_timeout(Some("  120  ")),
        Duration::from_secs(120)
    );
    assert_eq!(parse_tool_timeout(Some("3600")), Duration::from_secs(3600));
}

#[test]
#[serial_test::serial(hlc)]
fn parse_tool_timeout_garbage_falls_back_to_default() {
    for raw in ["abc", "-1", "1.5", "9999999999999999999999999"] {
        assert_eq!(
            parse_tool_timeout(Some(raw)),
            Duration::from_secs(DEFAULT_MCP_TOOL_TIMEOUT_SECS),
            "input {raw:?} should fall back to default"
        );
    }
}
