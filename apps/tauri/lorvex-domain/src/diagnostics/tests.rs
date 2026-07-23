use super::*;

#[test]
fn redacts_whitespace_separated_bearer_token() {
    let s = "GET /api failed: Authorization: Bearer eyJhbGciOi...xyz server=unreachable";
    let out = redact_diagnostic_text(s);
    assert!(!out.contains("eyJhbGci"));
    assert!(out.contains("[REDACTED]"));
    assert!(out.contains("server=unreachable"));
}

#[test]
fn redacts_inline_bearer_colon_value() {
    let s = "header bearer:eyJhbGci.xyz more";
    let out = redact_diagnostic_text(s);
    assert!(!out.contains("eyJhbGci"));
    assert!(out.contains("Bearer [REDACTED]"));
}

#[test]
fn redacts_api_key_prefixes() {
    let out = redact_diagnostic_text("failed with sk_live_abcdef and AKIAEXAMPLE123");
    assert!(!out.contains("sk_live_abcdef"));
    assert!(!out.contains("AKIAEXAMPLE123"));
    assert!(out.matches("[REDACTED_TOKEN]").count() == 2);
}

#[test]
fn redacts_json_secret_fields() {
    let s = r#"response: {"token":"abc","password":"pw","user":"alice"}"#;
    let out = redact_diagnostic_text(s);
    assert!(!out.contains("abc"));
    assert!(!out.contains(r#""password":"pw""#));
    assert!(out.contains("[REDACTED_JSON_SECRET]"));
}

#[test]
fn redacts_kv_password() {
    let out = redact_diagnostic_text("ssh password=hunter2 failed");
    assert!(!out.contains("hunter2"));
    assert!(out.contains("password=[REDACTED]"));
}

#[test]
fn preserves_safe_content() {
    let out = redact_diagnostic_text("task id 018fef8c failed on line 42");
    assert_eq!(out, "task id 018fef8c failed on line 42");
}

#[test]
fn redacts_email_addresses() {
    let out = redact_diagnostic_text(
        "login failed for alice@example.com retrying with bob+tag@mail.example.co.uk",
    );
    assert!(!out.contains("alice@"));
    assert!(!out.contains("bob+tag@"));
    assert_eq!(out.matches("[REDACTED_EMAIL]").count(), 2);
}

#[test]
fn does_not_redact_at_mentions_or_keys_as_email() {
    let out = redact_diagnostic_text("ping @alice failed key@value=1 a@b missing");
    assert!(out.contains("@alice"));
    assert!(out.contains("key@value=1"));
    assert!(out.contains("a@b"));
    assert!(!out.contains("[REDACTED_EMAIL]"));
}

#[test]
fn redacts_macos_home_path_leaking_account_name() {
    let out = redact_diagnostic_text(
        "failed at /Users/alex/Library/Application/db.sqlite reading line 42",
    );
    assert!(!out.contains("/Users/alex/"));
    assert!(out.contains("[~]/Library/Application/db.sqlite"));
}

#[test]
fn redacts_linux_home_path() {
    let out = redact_diagnostic_text("at /home/alice/.local/share/file.db line 12");
    assert!(!out.contains("/home/alice/"));
    assert!(out.contains("[~]/.local/share/file.db"));
}

#[test]
fn redacts_windows_home_path_both_separators() {
    let forward = redact_diagnostic_text(r"at C:/Users/Alex/AppData/log.txt line 1");
    assert!(!forward.contains("Users/Alex"));
    assert!(forward.contains("[~]/AppData/log.txt"));
    let back = redact_diagnostic_text(r"at C:\Users\Alex\AppData\log.txt line 1");
    assert!(!back.contains("Users\\Alex"));
    assert!(back.contains("[~]/AppData\\log.txt"));
}

#[test]
fn preserves_non_home_absolute_paths() {
    let out = redact_diagnostic_text("wrote /tmp/cache/file.blob to disk");
    assert_eq!(out, "wrote /tmp/cache/file.blob to disk");
}

#[test]
fn redacts_url_query_string_tokens() {
    let out = redact_diagnostic_text(
        "HTTP 401: https://p123-caldav.icloud.com/published/2/MTg4?token=ABCDEF fetch failed",
    );
    assert!(!out.contains("token=ABCDEF"));
    assert!(!out.contains("?token"));
    assert!(out.contains("[REDACTED_QUERY]"));
    assert!(out.contains("p123-caldav.icloud.com"));
}

#[test]
fn redacts_url_userinfo() {
    let out = redact_diagnostic_text("connect failed https://alice:hunter2@calendar.example/ics");
    assert!(!out.contains("alice:hunter2"));
    assert!(out.contains("[REDACTED_USERINFO]@calendar.example/ics"));
}

#[test]
fn preserves_bare_url_without_query() {
    let out = redact_diagnostic_text("redirect to https://example.com/path/feed.ics now");
    assert!(out.contains("https://example.com/path/feed.ics"));
    assert!(!out.contains("[REDACTED_QUERY]"));
}

#[test]
fn preserves_trailing_punctuation_on_urls() {
    let out = redact_diagnostic_text("saw https://example.com/a?token=xyz. retry please");
    assert!(out.contains("[REDACTED_QUERY]."));
    assert!(out.contains("retry please"));
}
