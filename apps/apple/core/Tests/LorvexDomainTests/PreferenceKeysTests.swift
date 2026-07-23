import XCTest

@testable import LorvexDomain

final class PreferenceKeysTests: XCTestCase {
  func testLocalOnlyIncludesPerDeviceUISettings() {
    // language + theme are per-device UI settings that must not sync; the
    // notification-notes exposure is a per-device lock-screen privacy choice.
    XCTAssertTrue(PreferenceKeys.isLocalOnlyPreference(PreferenceKeys.prefLanguage))
    XCTAssertTrue(PreferenceKeys.isLocalOnlyPreference(PreferenceKeys.prefTheme))
    XCTAssertTrue(PreferenceKeys.isLocalOnlyPreference(PreferenceKeys.prefNotificationShowTaskNotes))
  }

  func testOrdinaryPreferencesAreSyncable() {
    XCTAssertFalse(PreferenceKeys.isLocalOnlyPreference(PreferenceKeys.prefTimezone))
    XCTAssertFalse(PreferenceKeys.isLocalOnlyPreference(PreferenceKeys.prefWorkingHours))
    XCTAssertFalse(PreferenceKeys.isLocalOnlyPreference(PreferenceKeys.prefDefaultListId))
    XCTAssertFalse(PreferenceKeys.isLocalOnlyPreference("never_seen_before_key"))
  }

  func testAuditRetentionIsVirtualControlPlanePreference() {
    let key = PreferenceKeys.prefAiChangelogRetentionPolicy
    XCTAssertTrue(PreferenceKeys.isControlPlanePreference(key))
    XCTAssertFalse(PreferenceKeys.isLocalOnlyPreference(key))
    XCTAssertTrue(PreferenceKeys.isExcludedFromPreferenceEntitySync(key))
    XCTAssertFalse(
      PreferenceKeys.isExcludedFromPreferenceEntitySync(PreferenceKeys.prefWorkingHours))
  }

  func testPreferenceAllowlistContainsEveryPrefConstant() {
    let prefs = [
      PreferenceKeys.prefWorkingHours,
      PreferenceKeys.prefTimezone,
      PreferenceKeys.prefDefaultListId,
      PreferenceKeys.prefAiChangelogRetentionPolicy,
      PreferenceKeys.prefLanguage,
      PreferenceKeys.prefTheme,
      PreferenceKeys.prefSetupCompleted,
      PreferenceKeys.prefSetupSummary,
      PreferenceKeys.prefSetupState,
      PreferenceKeys.prefRecordRawInput,
      PreferenceKeys.prefNotificationShowTaskNotes,
    ]
    for k in prefs {
      XCTAssertTrue(
        PreferenceKeys.isKnownPreferenceKey(k),
        "PREF_* constant '\(k)' is not in allKnownPreferenceKeys")
    }
  }

  func testUnknownKeysAreRejectedByAllowlist() {
    XCTAssertFalse(PreferenceKeys.isKnownPreferenceKey(""))
    XCTAssertFalse(PreferenceKeys.isKnownPreferenceKey("theme../../etc/passwd"))
    XCTAssertFalse(PreferenceKeys.isKnownPreferenceKey("DROP TABLE preferences"))
    XCTAssertFalse(PreferenceKeys.isKnownPreferenceKey("never_seen_before_key"))
  }

  /// These keys were registry entries with no shipping consumer (no code
  /// outside `PreferenceKeys.swift` read or wrote them) and were removed from
  /// the write allowlist before schema freeze so `set_preference` cannot
  /// create permanent legacy data-contract inputs for features that were
  /// never implemented. Re-add a key here only alongside a real consumer and
  /// a typed validator.
  func testFormerRegistryOnlyKeysAreRejectedByAllowlist() {
    let removedKeys = [
      "weekly_review_day",
      "dashboard_layout",
      "ai_briefing_enabled",
      "appearance_profile",
      "font_scale",
      "error_log_retention_days",
      "hide_completed_older_than_days",
      "sidebar_visible_modules",
      "morning_briefing_time",
      "weekly_review_time",
      "memory_lock_enabled",
      "sync_enabled",
      "sync_backend_configs",
      "quiet_hours_start",
      "quiet_hours_end",
      "notification_sound_enabled",
      "notification_muted_lists",
      "week_starts_on",
      "calendar_view_mode",
      "sidebar_hide_empty_lists",
      "widget_app_group_id",
      "widget_hide_titles",
      "focus_window_opacity",
      "focus_confirm_skip_break",
      "focus_confirm_exit",
      "focus_break_end_alert",
      // Apple Lorvex has a single sync backend (CloudKit); the writable
      // sync_backend_kind preference had no consumer and was removed.
      "sync_backend_kind",
    ]
    XCTAssertEqual(removedKeys.count, 27)
    for key in removedKeys {
      XCTAssertFalse(
        PreferenceKeys.isKnownPreferenceKey(key),
        "'\(key)' should have been removed from allKnownPreferenceKeys")
    }
  }
}
