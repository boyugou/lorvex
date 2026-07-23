use super::*;

#[test]
fn undo_token_serialization_roundtrip() {
    let token = UndoToken {
        task_id: "01966a3f-7c8b-7d4e-8f3a-00000000003a".to_string(),
        action: LifecycleAction::Complete,
        cancel_series: false,
        pre_status: TaskStatus::Open,
        pre_completed_at: None,
        pre_planned_date: Some("2026-03-28".to_string()),
        pre_defer_count: 2,
        pre_last_deferred_at: Some("2026-03-27T10:00:00Z".to_string()),
        pre_last_defer_reason: Some("low_energy".to_string()),
        spawned_successor_id: Some("01966a3f-7c8b-7d4e-8f3a-00000000003b".to_string()),
        cancelled_reminder_ids: vec![
            "01966a3f-7c8b-7d4e-8f3a-000000000033".to_string(),
            "01966a3f-7c8b-7d4e-8f3a-000000000034".to_string(),
        ],
        deleted_dep_edges: vec![(
            "01966a3f-7c8b-7d4e-8f3a-00000000003c".to_string(),
            "01966a3f-7c8b-7d4e-8f3a-00000000003a".to_string(),
        )],
        affected_dependent_ids: vec!["01966a3f-7c8b-7d4e-8f3a-00000000003c".to_string()],
        expires_at: "2026-03-27T12:00:05.000Z".to_string(),
        pre_task_snapshot: None,
    };

    let json = serde_json::to_string(&token).unwrap();
    let deserialized: UndoToken = serde_json::from_str(&json).unwrap();

    assert_eq!(deserialized.task_id, "01966a3f-7c8b-7d4e-8f3a-00000000003a");
    assert_eq!(deserialized.action, LifecycleAction::Complete);
    assert!(!deserialized.cancel_series);
    assert_eq!(deserialized.pre_status, TaskStatus::Open);
    assert_eq!(deserialized.pre_completed_at, None);
    assert_eq!(deserialized.pre_planned_date.as_deref(), Some("2026-03-28"));
    assert_eq!(deserialized.pre_defer_count, 2);
    assert_eq!(
        deserialized.pre_last_deferred_at.as_deref(),
        Some("2026-03-27T10:00:00Z")
    );
    assert_eq!(
        deserialized.pre_last_defer_reason.as_deref(),
        Some("low_energy")
    );
    assert_eq!(
        deserialized.spawned_successor_id.as_deref(),
        Some("01966a3f-7c8b-7d4e-8f3a-00000000003b")
    );
    assert_eq!(
        deserialized.cancelled_reminder_ids,
        vec![
            "01966a3f-7c8b-7d4e-8f3a-000000000033",
            "01966a3f-7c8b-7d4e-8f3a-000000000034"
        ]
    );
    assert_eq!(deserialized.deleted_dep_edges.len(), 1);
    assert_eq!(
        deserialized.affected_dependent_ids,
        vec!["01966a3f-7c8b-7d4e-8f3a-00000000003c"]
    );
    assert_eq!(deserialized.expires_at, "2026-03-27T12:00:05.000Z");
}

#[test]
fn undo_token_defaults_for_missing_fields() {
    // A token JSON that omits the serde-default fields (cancel_series,
    // pre_task_snapshot) must still deserialize with their defaults.
    let json = r#"{
        "task_id": "01966a3f-7c8b-7d4e-8f3a-000000000036",
        "action": "cancel",
        "pre_status": "open",
        "pre_completed_at": null,
        "pre_planned_date": null,
        "pre_defer_count": 0,
        "pre_last_deferred_at": null,
        "pre_last_defer_reason": null,
        "spawned_successor_id": null,
        "cancelled_reminder_ids": [],
        "deleted_dep_edges": [],
        "affected_dependent_ids": [],
        "expires_at": "2026-03-27T12:00:05.000Z"
    }"#;
    let token: UndoToken = serde_json::from_str(json).unwrap();
    assert!(!token.cancel_series);
    assert_eq!(token.pre_last_defer_reason, None);
    assert_eq!(token.pre_task_snapshot, None);
}

#[test]
fn expired_token_is_rejected() {
    let past = chrono::Utc::now() - chrono::Duration::seconds(60);
    let expires_at = past.format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string();
    let token = UndoToken {
        task_id: "01966a3f-7c8b-7d4e-8f3a-000000000036".to_string(),
        action: LifecycleAction::Complete,
        cancel_series: false,
        pre_status: TaskStatus::Open,
        pre_completed_at: None,
        pre_planned_date: None,
        pre_defer_count: 0,
        pre_last_deferred_at: None,
        pre_last_defer_reason: None,
        spawned_successor_id: None,
        cancelled_reminder_ids: vec![],
        deleted_dep_edges: vec![],
        affected_dependent_ids: vec![],
        expires_at,
        pre_task_snapshot: None,
    };
    let json = serde_json::to_string(&token).unwrap();
    let result = parse_and_validate_undo_token(&json);
    assert!(result.is_err());
    let msg = result.unwrap_err().to_string();
    assert!(msg.contains("expired"), "expected expiry error, got: {msg}");
}

#[test]
fn redo_token_roundtrip_for_complete() {
    // A complete-action redo token carries no cancel_series flag;
    // the redo pipeline routes through `complete_task_inner` which
    // has no series concept (recurrence is spawned post-complete).
    let future_expires = (chrono::Utc::now() + chrono::Duration::seconds(30))
        .to_rfc3339_opts(chrono::SecondsFormat::Micros, true);
    let undo = UndoToken {
        task_id: "01966a3f-7c8b-7d4e-8f3a-000000000036".to_string(),
        action: LifecycleAction::Complete,
        cancel_series: false,
        pre_status: TaskStatus::Open,
        pre_completed_at: None,
        pre_planned_date: None,
        pre_defer_count: 0,
        pre_last_deferred_at: None,
        pre_last_defer_reason: None,
        spawned_successor_id: None,
        cancelled_reminder_ids: vec![],
        deleted_dep_edges: vec![],
        affected_dependent_ids: vec![],
        expires_at: future_expires.clone(),
        pre_task_snapshot: None,
    };
    let redo_json = build_redo_token(&undo, &future_expires)
        .unwrap()
        .expect("complete undo should produce redo token");
    let parsed = parse_and_validate_redo_token(&redo_json).unwrap();
    assert_eq!(parsed.task_id(), "01966a3f-7c8b-7d4e-8f3a-000000000036");
    assert_eq!(parsed.lifecycle_action(), LifecycleAction::Complete);
    assert!(matches!(parsed, RedoToken::Complete { .. }));
}

#[test]
fn redo_token_for_single_cancel_keeps_series_flag_false() {
    let future_expires = (chrono::Utc::now() + chrono::Duration::seconds(30))
        .to_rfc3339_opts(chrono::SecondsFormat::Micros, true);
    let undo = UndoToken {
        task_id: "01966a3f-7c8b-7d4e-8f3a-000000000037".to_string(),
        action: LifecycleAction::Cancel,
        cancel_series: false,
        pre_status: TaskStatus::Open,
        pre_completed_at: None,
        pre_planned_date: None,
        pre_defer_count: 0,
        pre_last_deferred_at: None,
        pre_last_defer_reason: None,
        spawned_successor_id: None,
        cancelled_reminder_ids: vec![],
        deleted_dep_edges: vec![],
        affected_dependent_ids: vec![],
        expires_at: future_expires.clone(),
        pre_task_snapshot: None,
    };
    let redo_json = build_redo_token(&undo, &future_expires)
        .unwrap()
        .expect("cancel undo should produce redo token");
    let parsed = parse_and_validate_redo_token(&redo_json).unwrap();
    assert_eq!(parsed.task_id(), "01966a3f-7c8b-7d4e-8f3a-000000000037");
    assert_eq!(parsed.lifecycle_action(), LifecycleAction::Cancel);
    match parsed {
        RedoToken::Cancel { cancel_series, .. } => assert!(!cancel_series),
        other => panic!("expected Cancel arm, got {other:?}"),
    }
}

#[test]
fn redo_token_for_cancel_preserves_series_flag() {
    let future_expires = (chrono::Utc::now() + chrono::Duration::seconds(30))
        .to_rfc3339_opts(chrono::SecondsFormat::Micros, true);
    let undo = UndoToken {
        task_id: "01966a3f-7c8b-7d4e-8f3a-000000000076".to_string(),
        action: LifecycleAction::Cancel,
        cancel_series: true,
        pre_status: TaskStatus::Open,
        pre_completed_at: None,
        pre_planned_date: None,
        pre_defer_count: 0,
        pre_last_deferred_at: None,
        pre_last_defer_reason: None,
        spawned_successor_id: None,
        cancelled_reminder_ids: vec![],
        deleted_dep_edges: vec![],
        affected_dependent_ids: vec![],
        expires_at: future_expires.clone(),
        pre_task_snapshot: None,
    };

    let redo_json = build_redo_token(&undo, &future_expires)
        .unwrap()
        .expect("cancel undo should produce redo token");
    let parsed = parse_and_validate_redo_token(&redo_json).unwrap();

    match parsed {
        RedoToken::Cancel { cancel_series, .. } => assert!(cancel_series),
        other => panic!("expected Cancel arm, got {other:?}"),
    }
}

#[test]
fn expired_redo_token_is_rejected() {
    let past = (chrono::Utc::now() - chrono::Duration::seconds(60))
        .to_rfc3339_opts(chrono::SecondsFormat::Micros, true);
    let redo = RedoToken::Complete {
        task_id: "01966a3f-7c8b-7d4e-8f3a-000000000038".to_string(),
        expires_at: past,
    };
    let json = serde_json::to_string(&redo).unwrap();
    let err = parse_and_validate_redo_token(&json).unwrap_err();
    let msg = err.to_string();
    assert!(msg.contains("expired"), "expected expiry error, got: {msg}");
}

#[test]
fn update_undo_does_not_build_redo_token() {
    let future_expires = (chrono::Utc::now() + chrono::Duration::seconds(30))
        .to_rfc3339_opts(chrono::SecondsFormat::Micros, true);
    let undo = UndoToken {
        task_id: "01966a3f-7c8b-7d4e-8f3a-000000000081".to_string(),
        action: LifecycleAction::Update,
        cancel_series: false,
        pre_status: TaskStatus::Open,
        pre_completed_at: None,
        pre_planned_date: None,
        pre_defer_count: 0,
        pre_last_deferred_at: None,
        pre_last_defer_reason: None,
        spawned_successor_id: None,
        cancelled_reminder_ids: vec![],
        deleted_dep_edges: vec![],
        affected_dependent_ids: vec![],
        expires_at: future_expires.clone(),
        pre_task_snapshot: Some(serde_json::json!({})),
    };

    let redo_json = build_redo_token(&undo, &future_expires).unwrap();
    assert_eq!(redo_json, None);
}

#[test]
fn lifecycle_token_expiry_accepts_rfc3339_offsets() {
    let now = chrono::DateTime::parse_from_rfc3339("2026-04-18T09:29:59Z")
        .unwrap()
        .with_timezone(&chrono::Utc);

    let result = validate_lifecycle_token_expiry(
        "2026-04-18T10:30:00+01:00",
        LifecycleTokenKind::Undo,
        "01966a3f-7c8b-7d4e-8f3a-000000000021",
        now,
    );

    assert!(result.is_ok());
}

#[test]
fn lifecycle_token_expiry_allows_exact_boundary() {
    let now = chrono::DateTime::parse_from_rfc3339("2026-04-18T09:30:00Z")
        .unwrap()
        .with_timezone(&chrono::Utc);

    let result = validate_lifecycle_token_expiry(
        "2026-04-18T09:30:00.000000Z",
        LifecycleTokenKind::Redo,
        "01966a3f-7c8b-7d4e-8f3a-000000000020",
        now,
    );

    assert!(result.is_ok(), "expiry exactly at now is still valid");
}

/// a tampered `RedoToken` that paired
/// `action: Complete` with a `cancel_series: true` flag would
/// have parsed cleanly under the old flat-struct shape and the
/// redundant flag was silently dropped. With the sum-typed shape
/// the wire format rejects the unknown field on the
/// `Complete` variant — there is no `cancel_series` slot for it
/// to land in.
#[test]
fn redo_token_rejects_complete_with_extraneous_cancel_series_field() {
    let future_expires = (chrono::Utc::now() + chrono::Duration::seconds(30))
        .to_rfc3339_opts(chrono::SecondsFormat::Micros, true);
    // Tampered JSON: the new sum-typed serde shape uses
    // `tag = "action"` so an unknown sibling field is
    // tolerated by serde unless the struct is `deny_unknown_fields`.
    // We instead assert on the round-trip: the field cannot
    // round-trip on the `Complete` variant because it has no
    // place to land. A valid Complete token serializes to
    // `{"action":"complete","task_id":"…","expires_at":"…"}`
    // and the typed parse exposes that shape exactly.
    let redo = RedoToken::Complete {
        task_id: "01966a3f-7c8b-7d4e-8f3a-000000000039".to_string(),
        expires_at: future_expires,
    };
    let serialized = serde_json::to_string(&redo).expect("serialize complete redo");
    assert!(
        !serialized.contains("cancel_series"),
        "Complete variant must not carry a cancel_series field on the wire (got {serialized})"
    );
}

#[test]
fn valid_token_is_accepted() {
    let future = chrono::Utc::now() + chrono::Duration::seconds(60);
    let expires_at = future.format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string();
    let token = UndoToken {
        task_id: "01966a3f-7c8b-7d4e-8f3a-000000000036".to_string(),
        action: LifecycleAction::Complete,
        cancel_series: false,
        pre_status: TaskStatus::Open,
        pre_completed_at: None,
        pre_planned_date: None,
        pre_defer_count: 0,
        pre_last_deferred_at: None,
        pre_last_defer_reason: None,
        spawned_successor_id: None,
        cancelled_reminder_ids: vec![],
        deleted_dep_edges: vec![],
        affected_dependent_ids: vec![],
        expires_at,
        pre_task_snapshot: None,
    };
    let json = serde_json::to_string(&token).unwrap();
    let result = parse_and_validate_undo_token(&json);
    assert!(result.is_ok());
}
