import Foundation
import LorvexCore

/// Read/write surface for the `working_hours` preference — the working
/// window the schedule-proposal engine (app button and MCP tool alike) fits
/// focus blocks into.
extension AppStore {
  static let workingHoursDefault = WorkingHoursPreference.defaultWindow

  /// The stored window, falling back to the engine's defaults when the
  /// preference is absent or malformed.
  func loadWorkingHoursPreference() async -> (start: String, end: String) {
    let raw = try? await core.getPreference(key: "working_hours")
    return WorkingHoursPreference.parse(raw ?? nil) ?? Self.workingHoursDefault
  }

  /// Persist a new window. Returns false (with `errorMessage` set) for
  /// malformed times or an end at/before the start.
  @discardableResult
  func saveWorkingHoursPreference(start: String, end: String) async -> Bool {
    guard let encoded = WorkingHoursPreference.encode(start: start, end: end) else {
      errorMessage = String(
        localized: "settings.working_hours.invalid",
        defaultValue: "Working hours must be HH:MM with the end after the start.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
      return false
    }
    do {
      _ = try await core.setPreference(key: "working_hours", value: encoded)
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  static func minutesOfDay(_ value: String) -> Int? {
    WorkingHoursPreference.minutesOfDay(value)
  }
}
