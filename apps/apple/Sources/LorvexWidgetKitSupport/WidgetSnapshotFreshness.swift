import Foundation

public enum WidgetSnapshotFreshness: Equatable, Sendable {
  case fresh(ageSeconds: Int)
  case warning(ageSeconds: Int)
  case stale(ageSeconds: Int)
  case unknownTimestamp

  /// Seconds since the snapshot was generated, or `nil` when the timestamp
  /// could not be parsed (``unknownTimestamp``). Every dated case carries an
  /// age; used by "synced N ago" status text regardless of threshold.
  public var ageSeconds: Int? {
    switch self {
    case .fresh(let age), .warning(let age), .stale(let age): age
    case .unknownTimestamp: nil
    }
  }

  /// The compact staleness label ("5m ago" / "2h ago" …) once the snapshot has
  /// aged past the warning threshold (``warning`` or ``stale``), else `nil`.
  /// The single derivation the widget surfaces use to show a staleness badge,
  /// so the warning/stale gate lives in one place.
  public func staleAgeLabel(
    policy: WidgetSnapshotFreshnessPolicy = WidgetSnapshotFreshnessPolicy()
  ) -> String? {
    switch self {
    case .warning(let age), .stale(let age): policy.compactAgeLabel(ageSeconds: age)
    case .fresh, .unknownTimestamp: nil
    }
  }
}

public struct WidgetSnapshotFreshnessPolicy: Equatable, Sendable {
  public let warningAfterSeconds: Int
  public let staleAfterSeconds: Int

  public init(
    warningAfterSeconds: Int = 2 * 60 * 60,
    staleAfterSeconds: Int = 24 * 60 * 60
  ) {
    self.warningAfterSeconds = warningAfterSeconds
    self.staleAfterSeconds = staleAfterSeconds
  }

  public func classify(snapshot: WidgetSnapshot, now: Date = Date()) -> WidgetSnapshotFreshness {
    guard let generatedAt = WidgetSnapshotOrdering.parse(snapshot.generatedAt) else {
      return .unknownTimestamp
    }

    let age = max(0, Int(now.timeIntervalSince(generatedAt)))
    if age >= staleAfterSeconds {
      return .stale(ageSeconds: age)
    }
    if age >= warningAfterSeconds {
      return .warning(ageSeconds: age)
    }
    return .fresh(ageSeconds: age)
  }

  public func compactAgeLabel(ageSeconds: Int) -> String {
    if ageSeconds >= 24 * 60 * 60 {
      let days = ageSeconds / (24 * 60 * 60)
      return String(
        localized: "widget.age.days", defaultValue: "\(days)d ago",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    }
    if ageSeconds >= 60 * 60 {
      let hours = ageSeconds / (60 * 60)
      return String(
        localized: "widget.age.hours", defaultValue: "\(hours)h ago",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    }
    let minutes = max(1, ageSeconds / 60)
    return String(
      localized: "widget.age.minutes", defaultValue: "\(minutes)m ago",
      table: "Localizable", bundle: WidgetSupportL10n.bundle)
  }

  /// Product calendar carried by the snapshot. It owns both the materialized
  /// logical day and its next boundary; falling back to the injected device
  /// calendar is only for malformed/legacy preview data without a valid zone.
  public func logicalCalendar(
    for snapshot: WidgetSnapshot,
    fallback: Calendar
  ) -> Calendar {
    var calendar = fallback
    if let identifier = snapshot.timezone,
      let timeZone = TimeZone(identifier: identifier)
    {
      calendar.timeZone = timeZone
    }
    return calendar
  }

  /// True when a materialized day-relative snapshot belongs to a different
  /// current product day. `logicalDay` and `timezone` are one atomic projection
  /// frame: comparing it to the device's unrelated local day would expire a
  /// correct snapshot while the product timezone still considers it current.
  public func isForDifferentLogicalDay(
    _ snapshot: WidgetSnapshot,
    now: Date,
    calendar fallback: Calendar
  ) -> Bool {
    let productCalendar = logicalCalendar(for: snapshot, fallback: fallback)
    let currentDay = Self.dayIdentifier(for: now, calendar: productCalendar)
    if let logicalDay = snapshot.logicalDay {
      return logicalDay != currentDay
    }
    guard let generatedAt = WidgetSnapshotOrdering.parse(snapshot.generatedAt) else {
      return false
    }
    return Self.dayIdentifier(for: generatedAt, calendar: productCalendar) != currentDay
  }

  /// Converts a decoded prior-day snapshot into the canonical fallback shared
  /// by widgets, controls, complications, and the watch app. Keeping this
  /// transformation in one place prevents a secondary snapshot consumer from
  /// accidentally presenting yesterday's materialized Today data as current.
  public func validatingCurrentDay(
    _ result: WidgetSnapshotLoadResult,
    now: Date,
    calendar: Calendar
  ) -> WidgetSnapshotLoadResult {
    guard case .snapshot(let snapshot) = result,
      isForDifferentLogicalDay(snapshot, now: now, calendar: calendar)
    else {
      return result
    }
    return .fallback(
      .init(
        reason: .expiredDay,
        detail: "Snapshot was generated on an earlier logical day"
      )
    )
  }

  private static func dayIdentifier(for date: Date, calendar: Calendar) -> String {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    let components = gregorian.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year, let month = components.month, let day = components.day else {
      return ""
    }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }
}
