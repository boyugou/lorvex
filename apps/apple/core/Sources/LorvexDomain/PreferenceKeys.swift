/// Canonical preference and device-state key registry.
///
/// Every preference key exposed by the product API, persisted in the SQLite
/// `preferences` table, or stored in the `device_state` table is declared as a
/// constant on this namespace. A virtual control-plane preference may be
/// exposed without occupying an ordinary `preferences` row.
/// The `set_preference` path (the MCP host and platform surfaces) and the
/// sync apply path validate against ``isKnownPreferenceKey(_:)`` before any
/// DB work so malformed input cannot insert arbitrary keys.
///
/// Product-facing key strings are stable. Ordinary synced preferences ride the
/// `.preference` protocol; virtual control-plane preferences use their own
/// metadata contract. Adding a new preference requires both adding the constant
/// here and appending it to ``allKnownPreferenceKeys``.
public enum PreferenceKeys {
  // ── synced global preferences ──────────────────────────────────────

  public static let prefWorkingHours = "working_hours"
  public static let prefTimezone = "timezone"
  public static let prefDefaultListId = "default_list_id"
  /// How long the `ai_changelog` audit trail is retained. This is a virtual
  /// control-plane preference whose JSON value is a three-state
  /// ``ChangelogRetentionPolicy``:
  /// the string `"maximum"` (keep up to the absolute row-count
  /// safeguard), a positive integer number of days, or the string `"off"` (never
  /// store — suppress new local audit writes and purge all existing rows). See
  /// ``ChangelogRetentionPolicy/parse(_:)`` for the tolerant decoding. It is
  /// exposed through the normal preference product API, but is never stored as
  /// a `preferences` row or transported as a `.preference` entity. The
  /// account-scoped audit-retention metadata is its sole durable sync authority.
  public static let prefAiChangelogRetentionPolicy = "ai_changelog_retention_policy"
  public static let prefLanguage = "language"
  public static let prefTheme = "theme"
  /// Whether a task's freeform notes may appear as the body of its reminder
  /// notification (lock screen / banner). Local-only (see
  /// ``localOnlyPreferenceKeys``): the reminder body renders on THIS device's
  /// lock screen, so whether notes are exposed there is a per-device privacy
  /// choice, not a value that should follow the user to a device with a
  /// different exposure model. Absent or any value other than the literal
  /// string `"true"` means hidden — the default is to withhold notes, showing
  /// only non-sensitive fallback copy instead.
  public static let prefNotificationShowTaskNotes = "notification_show_task_notes"
  public static let prefSetupCompleted = "setup_completed"
  public static let prefSetupSummary = "setup_summary"
  public static let prefSetupState = "setup_state"
  public static let prefRecordRawInput = "record_raw_input"

  // ── device-local state ─────────────────────────────────────────────

  public static let devCalendarAiAccessMode = "calendar_ai_access_mode"

  // ── classification predicates ──────────────────────────────────────

  /// Preferences whose value is only meaningful on the device that wrote it.
  /// These must never cross the sync boundary in either direction: `language` and
  /// `theme` are UI settings each device picks for itself (a user may want dark
  /// mode or a different language on one device, and shouldn't have it follow them
  /// across devices), and `notification_show_task_notes` is a per-device
  /// lock-screen exposure choice.
  public static let localOnlyPreferenceKeys: [String] = [
    prefLanguage,
    prefTheme,
    prefNotificationShowTaskNotes,
  ]

  /// Returns `true` if `key` is device-local and must NOT be enqueued to the
  /// sync outbox or accepted from a peer.
  public static func isLocalOnlyPreference(_ key: String) -> Bool {
    localOnlyPreferenceKeys.contains(key)
  }

  /// Returns `true` for a preference-shaped product setting whose durable
  /// authority lives in a dedicated sync control plane rather than the ordinary
  /// `preferences` entity stream.
  public static func isControlPlanePreference(_ key: String) -> Bool {
    key == prefAiChangelogRetentionPolicy
  }

  /// Returns `true` when a preference key must never be represented as a
  /// `.preference` envelope. Device-local preferences stay on one device;
  /// control-plane preferences use their dedicated account-scoped metadata.
  public static func isExcludedFromPreferenceEntitySync(_ key: String) -> Bool {
    isLocalOnlyPreference(key) || isControlPlanePreference(key)
  }

  /// Canonical allowlist of every preference key the app or MCP server may
  /// write through `set_preference`. The list is the union of every synced
  /// `pref*` constant plus the device-local subset stored in the preferences
  /// table and the virtual control-plane preference exposed through the same
  /// API; see ``localOnlyPreferenceKeys`` and ``isControlPlanePreference(_:)``.
  public static let allKnownPreferenceKeys: [String] = [
    prefWorkingHours,
    prefTimezone,
    prefDefaultListId,
    prefAiChangelogRetentionPolicy,
    prefLanguage,
    prefTheme,
    prefSetupCompleted,
    prefSetupSummary,
    prefSetupState,
    prefRecordRawInput,
    prefNotificationShowTaskNotes,
  ]

  /// Returns `true` if `key` is in the canonical allowlist and may be written
  /// via the `set_preference` IPC.
  public static func isKnownPreferenceKey(_ key: String) -> Bool {
    allKnownPreferenceKeys.contains(key)
  }
}
