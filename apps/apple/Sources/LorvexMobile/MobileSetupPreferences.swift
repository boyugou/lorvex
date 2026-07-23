import Foundation
import LorvexCloudSync
import LorvexCore

public struct MobileSetupPreferences {
  public static let completedKey = "setupCompleted"
  public static let badgeEnabledKey = "badgeEnabled"
  public static let cloudSyncModeKey = "cloudSyncMode"
  public static let eventKitEnabledKey = "eventKitEnabled"
  public static let eventKitCalendarFilterModeKey = "eventKitCalendarFilterMode"
  public static let eventKitIncludedCalendarIDsKey = "eventKitIncludedCalendarIDs"
  public static let eventKitExcludedCalendarIDsKey = "eventKitExcludedCalendarIDs"

  let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var setupCompleted: Bool {
    defaults.bool(forKey: Self.completedKey)
  }

  /// The persisted iCloud sync mode for this device. Defaults to `.off` until a
  /// settings toggle writes it; the `LORVEX_CLOUDKIT_EXPORT` env var overrides it
  /// at resolution time (see `CloudSyncFactory.resolveMode`).
  public var cloudSyncMode: CloudSyncMode {
    defaults.string(forKey: Self.cloudSyncModeKey)
      .flatMap(CloudSyncMode.init(rawValue:)) ?? .off
  }

  public var eventKitEnabled: Bool {
    defaults.bool(forKey: Self.eventKitEnabledKey)
  }

  public var eventKitCalendarFilterMode: EventKitCalendarFilterMode {
    defaults.string(forKey: Self.eventKitCalendarFilterModeKey)
      .flatMap(EventKitCalendarFilterMode.init(rawValue:)) ?? .allExcept
  }

  public var eventKitIncludedCalendarIDs: Set<String> {
    Self.loadedCalendarIDs(defaults.stringArray(forKey: Self.eventKitIncludedCalendarIDsKey))
  }

  public var eventKitExcludedCalendarIDs: Set<String> {
    Self.loadedCalendarIDs(defaults.stringArray(forKey: Self.eventKitExcludedCalendarIDsKey))
  }

  public var eventKitCalendarFilter: EventKitCalendarFilter {
    EventKitCalendarFilter(
      mode: eventKitCalendarFilterMode,
      selectedCalendarIDs: eventKitIncludedCalendarIDs,
      excludedCalendarIDs: eventKitExcludedCalendarIDs)
  }

  /// Whether the app-icon badge should reflect due/overdue task count.
  /// Defaults to true when the key has not been explicitly set.
  public var badgeEnabled: Bool {
    defaults.object(forKey: Self.badgeEnabledKey) == nil
      ? true
      : defaults.bool(forKey: Self.badgeEnabledKey)
  }

  public func complete() {
    defaults.set(true, forKey: Self.completedKey)
  }

  public func setCloudSyncMode(_ mode: CloudSyncMode) {
    defaults.set(mode.rawValue, forKey: Self.cloudSyncModeKey)
  }

  public func setBadgeEnabled(_ enabled: Bool) {
    defaults.set(enabled, forKey: Self.badgeEnabledKey)
  }

  public func setEventKitEnabled(_ enabled: Bool) {
    defaults.set(enabled, forKey: Self.eventKitEnabledKey)
  }

  public func setEventKitCalendarFilterMode(_ mode: EventKitCalendarFilterMode) {
    defaults.set(mode.rawValue, forKey: Self.eventKitCalendarFilterModeKey)
  }

  public func setEventKitIncludedCalendarIDs(_ ids: Set<String>) {
    defaults.set(Self.persistedCalendarIDs(ids), forKey: Self.eventKitIncludedCalendarIDsKey)
  }

  public func setEventKitExcludedCalendarIDs(_ ids: Set<String>) {
    defaults.set(Self.persistedCalendarIDs(ids), forKey: Self.eventKitExcludedCalendarIDsKey)
  }

  private static func loadedCalendarIDs(_ stored: [String]?) -> Set<String> {
    Set((stored ?? []).filter { !$0.isEmpty })
  }

  private static func persistedCalendarIDs(_ ids: Set<String>) -> [String] {
    ids.filter { !$0.isEmpty }.sorted()
  }
}
