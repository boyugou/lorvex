use super::support::*;

#[test]
fn read_changelog_retention_days_surfaces_preference_lookup_failures() {
    let conn = setup_sync_test_conn();
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "preferences",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let error = crate::commands::diagnostics::read_changelog_retention_days(&conn)
        .expect_err("preferences read failure should surface");
    let message = error.to_string();
    assert!(
        message.contains("database error") || message.contains("access to preferences"),
        "unexpected error: {message}"
    );
}

#[test]
fn read_changelog_retention_days_rejects_invalid_preference() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        params![
            lorvex_domain::preference_keys::PREF_AI_CHANGELOG_RETENTION_POLICY,
            "\"definitely_invalid_policy\"",
            TEST_VERSION,
            "2026-03-29T00:00:00Z"
        ],
    )
    .expect("insert invalid retention policy");

    let error = crate::commands::diagnostics::read_changelog_retention_days(&conn)
        .expect_err("invalid preference should fail");
    assert!(
        error.to_string().contains("ai_changelog_retention_policy"),
        "unexpected error: {error}"
    );
}

/// Regression for the MCP AuditRetentionPolicy enum bug: the UI offers
/// 60/180/365-day retention options that the legacy enum rejected with
/// "unsupported day count". This test asserts every UI-selectable value
/// round-trips cleanly through the unified reader. Before the fix, the
/// MCP server's `read_changelog_retention_policy` would error out on
/// 60/180/365, which broke every MCP mutation that tried to log to
/// ai_changelog.
#[test]
fn read_changelog_retention_days_accepts_all_ui_offered_values() {
    for days in [7i64, 14, 30, 60, 90, 180, 365] {
        let conn = setup_sync_test_conn();
        conn.execute(
            "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
            params![
                lorvex_domain::preference_keys::PREF_AI_CHANGELOG_RETENTION_POLICY,
                days.to_string(),
                TEST_VERSION,
                "2026-03-29T00:00:00Z"
            ],
        )
        .expect("insert retention days preference");

        let parsed = crate::commands::diagnostics::read_changelog_retention_days(&conn)
            .expect("integer preference should parse");
        assert_eq!(
            parsed,
            Some(days),
            "UI-offered retention value {days} must parse without error"
        );
    }
}

#[test]
fn read_changelog_retention_days_returns_none_when_unset() {
    let conn = setup_sync_test_conn();
    let parsed = crate::commands::diagnostics::read_changelog_retention_days(&conn)
        .expect("missing preference should return Ok(None), not error");
    assert_eq!(
        parsed, None,
        "missing preference means 'Forever' (None), not a default day count"
    );
}

#[test]
fn read_retention_days_surfaces_preference_lookup_failures() {
    let conn = setup_sync_test_conn();
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "preferences",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let error = read_retention_days(
        &conn,
        lorvex_domain::preference_keys::PREF_AI_CHANGELOG_RETENTION_POLICY,
    )
    .expect_err("preferences read failure should surface");
    let message = error.to_string();
    assert!(
        message.contains("database error") || message.contains("access to preferences"),
        "unexpected error: {message}"
    );
}

#[test]
fn read_retention_days_rejects_invalid_preference() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        params![
            lorvex_domain::preference_keys::PREF_ERROR_LOG_RETENTION_DAYS,
            "\"definitely_invalid_days\"",
            TEST_VERSION,
            "2026-03-29T00:00:00Z"
        ],
    )
    .expect("insert invalid retention days");

    let error = read_retention_days(
        &conn,
        lorvex_domain::preference_keys::PREF_ERROR_LOG_RETENTION_DAYS,
    )
    .expect_err("invalid preference should fail");
    assert!(
        error.to_string().contains("error_log_retention_days"),
        "unexpected error: {error}"
    );
}

#[test]
fn read_retention_days_rejects_non_positive_preference() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        params![
            lorvex_domain::preference_keys::PREF_ERROR_LOG_RETENTION_DAYS,
            "0",
            TEST_VERSION,
            "2026-03-29T00:00:00Z"
        ],
    )
    .expect("insert non-positive retention days");

    let error = read_retention_days(
        &conn,
        lorvex_domain::preference_keys::PREF_ERROR_LOG_RETENTION_DAYS,
    )
    .expect_err("non-positive preference should fail");
    assert!(
        error.to_string().contains("positive integer"),
        "unexpected error: {error}"
    );
}

#[test]
fn read_retention_days_accepts_canonical_json_number() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        params![
            lorvex_domain::preference_keys::PREF_ERROR_LOG_RETENTION_DAYS,
            "45",
            TEST_VERSION,
            "2026-03-29T00:00:00Z"
        ],
    )
    .expect("insert numeric retention days");

    let days = read_retention_days(
        &conn,
        lorvex_domain::preference_keys::PREF_ERROR_LOG_RETENTION_DAYS,
    )
    .expect("numeric preference should parse");
    assert_eq!(days, Some(45));
}
