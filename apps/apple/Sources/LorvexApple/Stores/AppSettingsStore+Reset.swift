import Foundation

extension AppSettingsStore {
  /// Restore every persisted preference to its first-launch default and clear
  /// the auxiliary EventKit caches/latches. Used by the factory reset; does not
  /// touch the database — the caller wipes that separately. `setupCompleted` is
  /// reset to `false` so the first-run wizard reappears.
  func resetToDefaults() {
    cloudSyncMode = .off
    setupCompleted = false
    badgeEnabled = true
    eventKitEnabled = false
    eventKitCalendarFilterMode = .allExcept
    eventKitIncludedCalendarIDs = []
    eventKitExcludedCalendarIDs = []
    appearance = .system

    // Persisted keys without a backing property: the EventKit grant latch and
    // the cached Lorvex-calendar identifier.
    defaults.removeObject(forKey: EventKitAccessLatch.calendarKey)
    defaults.removeObject(forKey: "eventKit.lorvexCalendarID")
  }
}
