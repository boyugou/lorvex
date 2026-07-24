import Foundation
import GRDB
import LorvexDomain

/// Typed reader for the device-local `calendar_ai_access_mode` row.
///
/// `device_state` is intentionally local-only, but several runtimes read the
/// same key. The per-key parsing lives here so every surface agrees on the
/// value contract. Missing rows fall back to the domain default
/// (``CalendarAiAccessMode/defaultMode``); malformed rows surface as a
/// ``StoreError/validation(_:)`` rather than silently falling back, because a
/// bad privacy setting should be fixed at the writer boundary instead of
/// being ignored by planning readers.
public enum DeviceStateRepo {
  /// Validate an already-decoded JSON value as a `calendar_ai_access_mode`.
  ///
  /// A non-string value yields the canonical "must contain a JSON string"
  /// message; an unrecognized mode yields the "contains invalid value '…'"
  /// message.
  static func validateCalendarAiAccessModeJSONValue(
    _ value: JSONValue
  ) throws -> CalendarAiAccessMode {
    guard case .string(let mode) = value else {
      throw StoreError.validation(
        "device_state '\(PreferenceKeys.devCalendarAiAccessMode)' must contain a JSON string")
    }
    guard let parsed = CalendarAiAccessMode.parseStrict(mode) else {
      throw StoreError.validation(
        "device_state '\(PreferenceKeys.devCalendarAiAccessMode)' contains invalid value '\(mode)'")
    }
    return parsed
  }

  /// Parse a raw `device_state.value` cell (JSON-encoded string) into a mode.
  ///
  /// Invalid JSON surfaces the "must contain valid JSON string" message with no
  /// parser-error suffix, since ``JSONValue/parse(_:)`` returns `nil` without
  /// surfacing a parser message.
  static func parseCalendarAiAccessModeState(
    _ raw: String
  ) throws -> CalendarAiAccessMode {
    guard let parsed = JSONValue.parse(raw) else {
      throw StoreError.validation(
        "device_state '\(PreferenceKeys.devCalendarAiAccessMode)' must contain valid JSON string")
    }
    return try validateCalendarAiAccessModeJSONValue(parsed)
  }

  /// Read the local `calendar_ai_access_mode` row.
  ///
  /// Missing rows return ``CalendarAiAccessMode/defaultMode``
  /// (`full_details`). Malformed rows throw a ``StoreError/validation(_:)``.
  public static func readCalendarAiAccessMode(
    _ db: Database
  ) throws -> CalendarAiAccessMode {
    try readCalendarAiAccessModeIfSet(db) ?? CalendarAiAccessMode.defaultMode
  }

  /// Read the local `calendar_ai_access_mode` row, preserving the unset state.
  ///
  /// Returns `nil` when the row is genuinely absent (the device has never chosen
  /// a tier), so a caller can tell "never chosen" apart from an explicit
  /// selection — unlike ``readCalendarAiAccessMode(_:)``, which substitutes the
  /// domain default (`full_details`) for a missing row. Malformed rows throw a
  /// ``StoreError/validation(_:)``.
  public static func readCalendarAiAccessModeIfSet(
    _ db: Database
  ) throws -> CalendarAiAccessMode? {
    let raw = try String.fetchOne(
      db,
      sql: "SELECT value FROM device_state WHERE key = ?1",
      arguments: [PreferenceKeys.devCalendarAiAccessMode])
    guard let raw else {
      return nil
    }
    return try parseCalendarAiAccessModeState(raw)
  }

  /// Write the local `calendar_ai_access_mode` row after validating the mode.
  ///
  /// This deliberately targets `device_state`, not `preferences` or
  /// UserDefaults: the selected calendar detail tier is local runtime state
  /// because each device has its own EventKit permissions and mirrored cache.
  public static func writeCalendarAiAccessMode(
    _ db: Database,
    mode: CalendarAiAccessMode
  ) throws {
    let data = try JSONSerialization.data(
      withJSONObject: mode.asString, options: [.fragmentsAllowed])
    guard let encoded = String(data: data, encoding: .utf8) else {
      throw StoreError.validation(
        "device_state '\(PreferenceKeys.devCalendarAiAccessMode)' must contain valid JSON string")
    }
    try db.execute(
      sql: """
        INSERT INTO device_state (key, value) VALUES (?1, ?2) \
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """,
      arguments: [PreferenceKeys.devCalendarAiAccessMode, encoded])
  }

  /// Clear the local calendar detail tier so readers fall back to the domain
  /// default.
  public static func clearCalendarAiAccessMode(_ db: Database) throws {
    try db.execute(
      sql: "DELETE FROM device_state WHERE key = ?1",
      arguments: [PreferenceKeys.devCalendarAiAccessMode])
  }
}
