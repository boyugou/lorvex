import Foundation

/// UserDefaults keys for the "Lorvex has been granted system access" latches.
///
/// macOS keeps returning a process-cached `notDetermined` from EventKit's static
/// `authorizationStatus` for the rest of a session after an in-app grant (it
/// only refreshes on the next launch). These persisted flags record that a grant
/// succeeded so reads and the Permissions UI don't regress to "Not Set"
/// mid-session. They are overridden only by a real `denied`/`restricted`, never
/// by a stale `notDetermined`.
enum EventKitAccessLatch {
  static let calendarKey = "eventKit.confirmedCalendarReadAccess"
}
