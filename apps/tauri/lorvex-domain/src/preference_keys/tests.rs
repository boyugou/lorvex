use super::*;

#[test]
fn local_only_includes_sync_backend_configs() {
    assert!(is_local_only_preference(PREF_SYNC_BACKEND_CONFIGS));
    assert!(is_local_only_preference(PREF_SYNC_BACKEND_KIND));
    assert!(is_local_only_preference(PREF_SYNC_ENABLED));
}

#[test]
fn ordinary_preferences_are_syncable() {
    assert!(!is_local_only_preference(PREF_LANGUAGE));
    assert!(!is_local_only_preference(PREF_THEME));
    assert!(!is_local_only_preference(PREF_TIMEZONE));
    assert!(!is_local_only_preference(PREF_WORKING_HOURS));
    assert!(!is_local_only_preference("never_seen_before_key"));
}

/// every preference constant defined in this
/// module must appear in `ALL_KNOWN_PREFERENCE_KEYS`. The Tauri
/// `set_preference` IPC uses the allowlist as the security
/// boundary; a constant that ships without being added here would
/// be silently rejected by the writer (looks like a regression to
/// the user). This test catches the drift at CI time.
#[test]
fn preference_allowlist_contains_every_pref_constant() {
    // Every PREF_* constant declared above. Keep in sync; the
    // surrounding ALL_KNOWN_PREFERENCE_KEYS list is the canonical
    // source — this assertion is the drift guard.
    for key in [
        PREF_WORKING_HOURS,
        PREF_TIMEZONE,
        PREF_WEEKLY_REVIEW_DAY,
        PREF_DASHBOARD_LAYOUT,
        PREF_DEFAULT_LIST_ID,
        PREF_AI_BRIEFING_ENABLED,
        PREF_AI_CHANGELOG_RETENTION_POLICY,
        PREF_LANGUAGE,
        PREF_THEME,
        PREF_APPEARANCE_PROFILE,
        PREF_FONT_SCALE,
        PREF_ERROR_LOG_RETENTION_DAYS,
        PREF_HIDE_COMPLETED_OLDER_THAN_DAYS,
        PREF_SIDEBAR_VISIBLE_MODULES,
        PREF_MORNING_BRIEFING_TIME,
        PREF_WEEKLY_REVIEW_TIME,
        PREF_MEMORY_LOCK_ENABLED,
        PREF_SYNC_ENABLED,
        PREF_SYNC_BACKEND_KIND,
        PREF_SYNC_BACKEND_CONFIGS,
        PREF_QUIET_HOURS_START,
        PREF_QUIET_HOURS_END,
        PREF_NOTIFICATION_SOUND_ENABLED,
        PREF_NOTIFICATION_MUTED_LISTS,
        PREF_WEEK_STARTS_ON,
        PREF_CALENDAR_VIEW_MODE,
        PREF_SIDEBAR_HIDE_EMPTY_LISTS,
        PREF_SETUP_COMPLETED,
        PREF_SETUP_SUMMARY,
        PREF_SETUP_STATE,
        PREF_RECORD_RAW_INPUT,
        PREF_FOCUS_WINDOW_OPACITY,
        PREF_FOCUS_CONFIRM_SKIP_BREAK,
        PREF_FOCUS_CONFIRM_EXIT,
        PREF_FOCUS_BREAK_END_ALERT,
    ] {
        assert!(
            is_known_preference_key(key),
            "PREF_* constant '{key}' is not in ALL_KNOWN_PREFERENCE_KEYS — \
             add it to the allowlist or remove the constant"
        );
    }
}

#[test]
fn unknown_keys_are_rejected_by_allowlist() {
    assert!(!is_known_preference_key(""));
    assert!(!is_known_preference_key("sync_enabled../../etc/passwd"));
    assert!(!is_known_preference_key("DROP TABLE preferences"));
    assert!(!is_known_preference_key("never_seen_before_key"));
}

#[test]
fn path_shaped_keys_are_classified() {
    // Tauri currently has no scalar path-shaped preferences. If one is added,
    // it must be explicitly classified here.
    assert!(!is_path_shaped_preference_key(PREF_LANGUAGE));
    assert!(!is_path_shaped_preference_key(PREF_THEME));
}
