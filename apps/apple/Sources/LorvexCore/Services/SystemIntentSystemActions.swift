import Foundation
import LorvexDomain

extension LorvexSystemIntentRunner {
  public static func readRuntimeDiagnostics(
    core: any LorvexCoreServicing
  ) async throws -> RuntimeDiagnosticsSnapshot {
    try await core.loadRuntimeDiagnostics()
  }

  public static func readPreferences(
    core: any LorvexCoreServicing
  ) async throws -> PreferencesSnapshot {
    try await core.getAllPreferences()
  }

  public static func readPreference(
    key: String,
    core: any LorvexCoreServicing
  ) async throws -> String? {
    try await core.getPreference(key: validatedPreferenceKey(key))
  }

  public static func setPreference(
    key: String,
    value: String,
    core: any LorvexCoreServicing
  ) async throws -> String {
    let validatedKey = try validatedWritablePreferenceKey(key)
    let validatedValue = try validatedPreferenceValue(value)
    return try await core.setPreference(key: validatedKey, value: validatedValue)
  }

  public static func deletePreference(
    key: String,
    core: any LorvexCoreServicing
  ) async throws {
    try await core.deletePreference(key: validatedWritablePreferenceKey(key))
  }

  public static func completeSetup(
    workingHours: String?,
    defaultListID: String?,
    timezone: String?,
    core: any LorvexCoreServicing
  ) async throws -> PreferencesSnapshot {
    try await core.completeSetup(
      workingHours: workingHours.trimmedNilIfEmpty,
      defaultListID: defaultListID.trimmedNilIfEmpty,
      timezone: timezone.trimmedNilIfEmpty
    )
  }

  public static func readOverview(core: any LorvexCoreServicing) async throws
    -> OverviewCompactSnapshot
  {
    try await core.getOverviewCompact()
  }

  public static func readSessionContext(core: any LorvexCoreServicing) async throws
    -> SessionContextSnapshot
  {
    try await core.getSessionContext()
  }

  private static func validatedPreferenceKey(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(field: "key", message: "A preference key is required.")
    }
    return trimmed
  }

  /// Validate a preference key for a WRITE (set / delete). Trims and requires
  /// non-empty like ``validatedPreferenceKey(_:)``, then enforces the MCP host's
  /// `set_preference` allowlist (a known configuration key) plus one
  /// App-Intents-only addition: the device-local calendar AI-access tier
  /// (``PreferenceKeys/devCalendarAiAccessMode``). The MCP surface deliberately
  /// rejects that key so the assistant cannot set its own calendar-visibility
  /// tier; the user-driven Shortcuts path may, so a user can downgrade it.
  ///
  /// An arbitrary key is rejected because it would both persist a `preferences`
  /// row AND enqueue a sync envelope that every peer rejects
  /// (`SyncEntityId.validatePreference`), permanently diverging devices. Reads
  /// stay unrestricted (they use ``validatedPreferenceKey(_:)``), matching the
  /// MCP host's read/write asymmetry.
  private static func validatedWritablePreferenceKey(_ value: String) throws -> String {
    let trimmed = try validatedPreferenceKey(value)
    guard PreferenceKeys.isKnownPreferenceKey(trimmed)
      || trimmed == PreferenceKeys.devCalendarAiAccessMode
    else {
      throw LorvexCoreError.validation(
        field: "key",
        message: "Unknown preference key '\(trimmed)'. Only known configuration keys can be set or deleted.")
    }
    return trimmed
  }

  private static func validatedPreferenceValue(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(field: "value", message: "A preference value is required.")
    }
    return trimmed
  }
}
