use super::*;
use serde_json::json;

#[test]
#[serial_test::serial(hlc)]
fn token_roundtrips_delete_list_shape() {
    let token = McpUndoToken::delete_entity(
        McpUndoKind::DeleteList,
        "delete_list",
        "list-1".to_string(),
        json!({ "id": "list-1", "name": "Work" }),
        "2026-04-19T10:00:05.000000Z".to_string(),
    );
    let json_str = token.to_json_string().unwrap();
    let decoded: McpUndoToken = serde_json::from_str(&json_str).unwrap();
    assert_eq!(decoded.kind, McpUndoKind::DeleteList);
    assert_eq!(decoded.entity_id.as_deref(), Some("list-1"));
    assert_eq!(decoded.expires_at, "2026-04-19T10:00:05.000000Z");
    assert_eq!(
        decoded.pre_entity_json.as_ref().and_then(|v| v.get("name")),
        Some(&json!("Work"))
    );
}

#[test]
#[serial_test::serial(hlc)]
fn token_roundtrips_batch_create_with_ids_only() {
    let token = McpUndoToken::batch_create(
        vec!["t-1".to_string(), "t-2".to_string()],
        "2026-04-19T10:00:05.000000Z".to_string(),
    );
    let json_str = token.to_json_string().unwrap();
    let decoded: McpUndoToken = serde_json::from_str(&json_str).unwrap();
    assert_eq!(decoded.kind, McpUndoKind::BatchCreateTasks);
    assert_eq!(decoded.created_ids, vec!["t-1", "t-2"]);
    assert!(decoded.pre_entity_json.is_none());
    assert!(decoded.pre_entities_json.is_empty());
}

#[test]
#[serial_test::serial(hlc)]
fn token_roundtrips_set_preference_without_prior_value() {
    let token = McpUndoToken::set_preference(
        "theme_mode".to_string(),
        None,
        "2026-04-19T10:00:05.000000Z".to_string(),
    );
    let json_str = token.to_json_string().unwrap();
    let decoded: McpUndoToken = serde_json::from_str(&json_str).unwrap();
    assert_eq!(decoded.kind, McpUndoKind::SetPreference);
    assert_eq!(decoded.entity_id.as_deref(), Some("theme_mode"));
    assert!(!decoded.had_prior_value);
    assert!(decoded.prior_value_json.is_none());
}

#[test]
#[serial_test::serial(hlc)]
fn token_roundtrips_set_preference_with_prior_value() {
    let token = McpUndoToken::set_preference(
        "dashboard_layout".to_string(),
        Some(json!({"cols": 2})),
        "2026-04-19T10:00:05.000000Z".to_string(),
    );
    let json_str = token.to_json_string().unwrap();
    let decoded: McpUndoToken = serde_json::from_str(&json_str).unwrap();
    assert!(decoded.had_prior_value);
    assert_eq!(
        decoded
            .prior_value_json
            .as_ref()
            .and_then(|v| v.get("cols")),
        Some(&json!(2))
    );
}

#[test]
#[serial_test::serial(hlc)]
fn compute_undo_expiry_yields_future_rfc3339() {
    let now = Utc::now();
    let expiry_str = compute_undo_expiry();
    let expiry =
        chrono::DateTime::parse_from_rfc3339(&expiry_str).expect("expiry must be valid RFC3339");
    let delta = (expiry.with_timezone(&Utc) - now).num_seconds();
    assert!((UNDO_WINDOW_SECONDS - 1..=UNDO_WINDOW_SECONDS + 1).contains(&delta));
}
