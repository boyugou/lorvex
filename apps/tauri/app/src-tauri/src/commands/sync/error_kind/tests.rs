use super::*;

#[test]
fn classifies_offline_errors() {
    assert_eq!(
        classify_sync_error("reqwest error: failed to lookup address information"),
        SyncErrorKind::Offline,
    );
    assert_eq!(
        classify_sync_error("NSURLErrorDomain error -1009"),
        SyncErrorKind::Offline,
    );
    assert_eq!(
        classify_sync_error("Connection refused (os error 61)"),
        SyncErrorKind::Offline,
    );
}

#[test]
fn classifies_permissions() {
    assert_eq!(
        classify_sync_error("failed to write /Users/a/box/sync.json: EACCES"),
        SyncErrorKind::Permissions,
    );
    assert_eq!(
        classify_sync_error("Permission denied (os error 13)"),
        SyncErrorKind::Permissions,
    );
}

#[test]
fn classifies_timeout() {
    assert_eq!(
        classify_sync_error("filesystem bridge push timeout: operation timed out"),
        SyncErrorKind::Timeout,
    );
    assert_eq!(
        classify_sync_error("NSURLErrorDomain error -1001"),
        SyncErrorKind::Timeout,
    );
}

#[test]
fn unknown_fallback() {
    assert_eq!(
        classify_sync_error("some random unrecognized failure"),
        SyncErrorKind::Unknown,
    );
}

#[test]
fn extract_path_handles_unix() {
    assert_eq!(
        extract_path_hint("failed to write /home/user/lorvex/sync.json: EACCES"),
        Some("/home/user/lorvex/sync.json".to_string()),
    );
}

#[test]
fn extract_path_handles_windows() {
    assert_eq!(
        extract_path_hint("failed to write C:\\Users\\a\\sync.json: Access is denied"),
        Some("C:\\Users\\a\\sync.json".to_string()),
    );
}

#[test]
fn envelope_is_valid_json() {
    let encoded = encode_sync_error("Permission denied".to_string());
    let parsed: serde_json::Value = serde_json::from_str(&encoded).expect("valid JSON");
    assert_eq!(parsed["kind"], "permissions");
    assert_eq!(parsed["retryable"], true);
    assert_eq!(parsed["message"], "Permission denied");
    assert!(parsed["path"].is_null());
}

#[test]
fn envelope_retryable_flag_matches_kind() {
    let encoded = encode_sync_error("Permission denied".to_string());
    let parsed: serde_json::Value = serde_json::from_str(&encoded).unwrap();
    assert_eq!(parsed["kind"], "permissions");
    assert_eq!(parsed["retryable"], true);
}

#[test]
fn envelope_captures_path_for_permissions() {
    let encoded = encode_sync_error("failed to write /Users/a/box/sync.json: EACCES".to_string());
    let parsed: serde_json::Value = serde_json::from_str(&encoded).unwrap();
    assert_eq!(parsed["kind"], "permissions");
    assert_eq!(parsed["path"], "/Users/a/box/sync.json");
}
