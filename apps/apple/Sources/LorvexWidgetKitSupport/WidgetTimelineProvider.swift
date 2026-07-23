import Foundation

public enum WidgetTimelineEntryState: Equatable, Sendable {
  case snapshot(WidgetSnapshot, freshness: WidgetSnapshotFreshness)
  case fallback(WidgetSnapshotFallback)

  public var snapshot: WidgetSnapshot? {
    if case .snapshot(let snapshot, _) = self {
      return snapshot
    }
    return nil
  }
}

public struct WidgetTimelineEntry: Equatable, Sendable {
  public let date: Date
  public let state: WidgetTimelineEntryState
  public let refreshAfter: Date

  public init(date: Date, state: WidgetTimelineEntryState, refreshAfter: Date) {
    self.date = date
    self.state = state
    self.refreshAfter = refreshAfter
  }
}

public struct WidgetTimelineProviderConfiguration: Equatable, Sendable {
  public var snapshotURL: URL
  public var freshnessPolicy: WidgetSnapshotFreshnessPolicy
  public var refreshPolicy: WidgetTimelineRefreshPolicy
  /// The user's calendar, used to schedule a reload at the next local midnight so
  /// the widget's day-relative stats refresh at the day boundary. Defaults to
  /// `.autoupdatingCurrent` (the device's live zone); injected in tests for a
  /// deterministic clock.
  public var calendar: Calendar

  public init(
    snapshotURL: URL,
    freshnessPolicy: WidgetSnapshotFreshnessPolicy = WidgetSnapshotFreshnessPolicy(),
    refreshPolicy: WidgetTimelineRefreshPolicy = WidgetTimelineRefreshPolicy(),
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.snapshotURL = snapshotURL
    self.freshnessPolicy = freshnessPolicy
    self.refreshPolicy = refreshPolicy
    self.calendar = calendar
  }
}

public struct WidgetTimelineProviderSupport {
  private let configuration: WidgetTimelineProviderConfiguration
  private let loader: WidgetSnapshotLoader
  private let now: () -> Date

  public init(
    configuration: WidgetTimelineProviderConfiguration,
    loader: WidgetSnapshotLoader = WidgetSnapshotLoader(),
    now: @escaping () -> Date = Date.init
  ) {
    self.configuration = configuration
    self.loader = loader
    self.now = now
  }

  public func placeholderEntry() -> WidgetTimelineEntry {
    let date = now()
    let snapshot = WidgetSnapshot(
      generatedAt: Self.placeholderGeneratedAt,
      timezone: nil,
      stats: .init(focusCount: 0, overdueCount: 0, dueTodayCount: 0),
      briefing: String(
        localized: "widget.placeholder.ready", defaultValue: "Lorvex is ready.",
        table: "Localizable", bundle: WidgetSupportL10n.bundle),
      focusTasks: []
    )
    return WidgetTimelineEntry(
      date: date,
      state: .snapshot(snapshot, freshness: .unknownTimestamp),
      refreshAfter: refreshAfter(from: date, freshness: nil)
    )
  }

  public func timelineEntry() -> WidgetTimelineEntry {
    let date = now()
    let unvalidatedResult = loader.loadSnapshot(at: configuration.snapshotURL)
    let result = configuration.freshnessPolicy.validatingCurrentDay(
      unvalidatedResult,
      now: date,
      calendar: configuration.calendar
    )
    switch result {
    case .snapshot(let snapshot):
      let freshness = configuration.freshnessPolicy.classify(snapshot: snapshot, now: date)
      return WidgetTimelineEntry(
        date: date,
        state: .snapshot(snapshot, freshness: freshness),
        refreshAfter: refreshAfter(
          from: date,
          freshness: freshness,
          calendar: configuration.freshnessPolicy.logicalCalendar(
            for: snapshot, fallback: configuration.calendar))
      )
    case .fallback(let fallback):
      return WidgetTimelineEntry(
        date: date,
        state: .fallback(fallback),
        refreshAfter: refreshAfter(
          from: date, freshness: nil, calendar: configuration.calendar)
      )
    }
  }

  /// The reload point for a timeline built at `date`: the sooner of the
  /// freshness-based age interval and the next local midnight, so day-relative
  /// stats get a scheduled refresh at the day boundary.
  private func refreshAfter(
    from date: Date,
    freshness: WidgetSnapshotFreshness?,
    calendar: Calendar? = nil
  ) -> Date {
    return configuration.refreshPolicy.nextRefreshDate(
      after: date,
      freshness: freshness,
      freshnessPolicy: configuration.freshnessPolicy,
      calendar: calendar ?? configuration.calendar)
  }

  public func compactStatusText(for entry: WidgetTimelineEntry) -> String {
    switch entry.state {
    case .snapshot(_, .fresh):
      return String(
        localized: "widget.status.updated_now", defaultValue: "Updated now",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    case .snapshot(_, .warning(let ageSeconds)), .snapshot(_, .stale(let ageSeconds)):
      return String(
        format: String(
          localized: "widget.status.updated_ago", defaultValue: "Updated %@",
          table: "Localizable", bundle: WidgetSupportL10n.bundle),
        configuration.freshnessPolicy.compactAgeLabel(ageSeconds: ageSeconds))
    case .snapshot(_, .unknownTimestamp):
      return String(
        localized: "widget.status.time_unavailable", defaultValue: "Update time unavailable",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    case .fallback(let fallback):
      switch fallback.reason {
      case .missingFile, .expiredDay:
        return String(
          localized: "widget.status.open_to_refresh", defaultValue: "Open Lorvex to refresh",
          table: "Localizable", bundle: WidgetSupportL10n.bundle)
      case .unreadableFile:
        return String(
          localized: "widget.status.snapshot_unavailable", defaultValue: "Snapshot unavailable",
          table: "Localizable", bundle: WidgetSupportL10n.bundle)
      case .invalidJSON:
        return String(
          localized: "widget.status.snapshot_damaged", defaultValue: "Snapshot data damaged",
          table: "Localizable", bundle: WidgetSupportL10n.bundle)
      case .unsupportedVersion:
        return String(
          localized: "widget.status.update_to_refresh", defaultValue: "Update Lorvex to refresh",
          table: "Localizable", bundle: WidgetSupportL10n.bundle)
      }
    }
  }

  private static let placeholderGeneratedAt = "1970-01-01T00:00:00Z"
}
