@preconcurrency import EventKit
import Foundation

/// Checks the current EventKit calendar authorization state and reports
/// whether the user must open System Settings to grant access.
///
/// `needsSettingsRecovery` is true when the status is `.denied` or
/// `.restricted` — states that cannot be resolved with an in-app prompt.
struct EventKitAuthorizationHelper: Sendable {
  let statusProvider: @Sendable (EKEntityType) -> EKAuthorizationStatus

  init(
    statusProvider: @escaping @Sendable (EKEntityType) -> EKAuthorizationStatus =
      EKEventStore.authorizationStatus(for:)
  ) {
    self.statusProvider = statusProvider
  }

  /// Returns true when calendar access has been explicitly denied, restricted
  /// by policy, or granted as "Add Only" — states the in-app prompt cannot
  /// upgrade, recoverable only through System Settings. Add Only blocks every
  /// read (the calendar import path), so leaving it unflagged shows a broken
  /// import beside a green permission row.
  var needsSettingsRecovery: Bool {
    switch statusProvider(.event) {
    case .denied, .restricted, .writeOnly:
      return true
    default:
      return false
    }
  }

  /// Returns true when calendar access has been fully granted (reads and
  /// writes). "Add Only" is deliberately excluded: it cannot serve the import
  /// path.
  var isAuthorized: Bool {
    switch statusProvider(.event) {
    case .fullAccess:
      return true
    default:
      return false
    }
  }
}
