import LorvexCore
import LorvexDomain

extension AppSettingsStore {
  enum Key {
    static let cloudSyncMode = "cloudSyncMode"
    static let badgeEnabled = "badgeEnabled"
    static let setupCompleted = "setupCompleted"
    static let eventKitEnabled = "eventKitEnabled"
    static let eventKitCalendarFilterMode = "eventKitCalendarFilterMode"
    static let eventKitIncludedCalendarIDs = "eventKitIncludedCalendarIDs"
    static let eventKitExcludedCalendarIDs = "eventKitExcludedCalendarIDs"
    static let appearance = AppAppearance.preferenceKey
  }
}
