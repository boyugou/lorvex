import Foundation
import LorvexCore

/// Read/write surface for the `working_hours` preference on the mobile
/// settings screen; mirrors the macOS semantics through the shared
/// WorkingHoursPreference helper.
extension MobileStore {
  func loadWorkingHoursPreference() async -> (start: String, end: String) {
    let raw = try? await core.getPreference(key: "working_hours")
    return WorkingHoursPreference.parse(raw ?? nil) ?? WorkingHoursPreference.defaultWindow
  }

  /// Persist a new window. Returns false (with `errorMessage` set) for
  /// malformed times or an end at/before the start.
  @discardableResult
  func saveWorkingHoursPreference(start: String, end: String) async -> Bool {
    guard let encoded = WorkingHoursPreference.encode(start: start, end: end) else {
      errorMessage = String(
        localized: "settings.working_hours.invalid",
        defaultValue: "Working hours must be HH:MM with the end after the start.",
        table: "Localizable", bundle: MobileL10n.bundle)
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
}
