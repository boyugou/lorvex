import Foundation

public struct WidgetTimelineRefreshPolicy: Equatable, Sendable {
  /// Upper bounds for scheduled reloads while the snapshot is in each age band.
  /// The actual interval can be shorter when the next visible age-label or
  /// freshness transition occurs first.
  public let freshIntervalSeconds: Int
  public let warningIntervalSeconds: Int
  public let staleIntervalSeconds: Int

  /// WidgetKit asks timeline entries to be at least about five minutes apart.
  /// Keeping the floor here prevents a near-boundary age transition from
  /// spending the widget's daily reload budget on a sub-five-minute request.
  public static let minimumIntervalSeconds = 5 * 60

  public init(
    freshIntervalSeconds: Int = 2 * 60 * 60,
    warningIntervalSeconds: Int = 60 * 60,
    staleIntervalSeconds: Int = 24 * 60 * 60
  ) {
    self.freshIntervalSeconds = max(Self.minimumIntervalSeconds, freshIntervalSeconds)
    self.warningIntervalSeconds = max(Self.minimumIntervalSeconds, warningIntervalSeconds)
    self.staleIntervalSeconds = max(Self.minimumIntervalSeconds, staleIntervalSeconds)
  }

  /// Returns the next interval at which re-rendering can change visible widget
  /// state. The app calls `WidgetCenter` whenever it publishes new data, so a
  /// timeline reload cannot make a stale or missing snapshot fresher by itself.
  /// Scheduled reloads therefore track only age-band/label changes, with a long
  /// fallback safety interval, instead of polling fastest when no data exists.
  public func refreshIntervalSeconds(
    freshness: WidgetSnapshotFreshness?,
    freshnessPolicy: WidgetSnapshotFreshnessPolicy = WidgetSnapshotFreshnessPolicy()
  ) -> Int {
    let interval: Int
    switch freshness {
    case .fresh(let ageSeconds):
      interval = min(
        freshIntervalSeconds,
        max(0, freshnessPolicy.warningAfterSeconds - ageSeconds)
      )
    case .warning(let ageSeconds):
      let nextAgeLabel = Self.secondsUntilNextAgeLabelChange(after: ageSeconds)
      let untilStale = max(0, freshnessPolicy.staleAfterSeconds - ageSeconds)
      interval = min(warningIntervalSeconds, nextAgeLabel, untilStale)
    case .stale(let ageSeconds):
      interval = min(staleIntervalSeconds, Self.secondsUntilNextAgeLabelChange(after: ageSeconds))
    case .unknownTimestamp, nil:
      interval = staleIntervalSeconds
    }
    return max(Self.minimumIntervalSeconds, interval)
  }

  /// The next local-calendar midnight strictly after `date`.
  ///
  /// The widget snapshot bakes day-relative stats (due-today / overdue /
  /// completed-today) at the host's publish instant, so those numbers silently
  /// go stale the moment the local day rolls over. Scheduling a reload at the day
  /// boundary lets the widget pick up a freshly republished snapshot promptly
  /// instead of drifting until the next age-based refresh. `calendar` carries the
  /// user's time zone, so this is DST- and time-zone-correct (00:00 is resolved on
  /// the wall clock, not by adding a fixed 86 400 s).
  public func nextLocalMidnight(after date: Date, calendar: Calendar) -> Date {
    calendar.nextDate(
      after: date,
      matching: DateComponents(hour: 0, minute: 0, second: 0),
      matchingPolicy: .nextTime,
      direction: .forward
    ) ?? calendar.startOfDay(for: date.addingTimeInterval(24 * 60 * 60))
  }

  /// When WidgetKit should be asked to reload: whichever comes first, the
  /// freshness-based age interval or the next local midnight. The clock is passed
  /// in (never `Date.now`) so the schedule is deterministic and testable.
  public func nextRefreshDate(
    after date: Date,
    freshness: WidgetSnapshotFreshness?,
    freshnessPolicy: WidgetSnapshotFreshnessPolicy = WidgetSnapshotFreshnessPolicy(),
    calendar: Calendar
  ) -> Date {
    let ageBased = date.addingTimeInterval(
      TimeInterval(
        refreshIntervalSeconds(
          freshness: freshness,
          freshnessPolicy: freshnessPolicy
        )
      )
    )
    return min(ageBased, nextLocalMidnight(after: date, calendar: calendar))
  }

  private static func secondsUntilNextMultiple(of unit: Int, after value: Int) -> Int {
    let nonnegativeValue = max(0, value)
    return unit - (nonnegativeValue % unit)
  }

  private static func secondsUntilNextAgeLabelChange(after ageSeconds: Int) -> Int {
    let unit: Int
    if ageSeconds >= 24 * 60 * 60 {
      unit = 24 * 60 * 60
    } else if ageSeconds >= 60 * 60 {
      unit = 60 * 60
    } else {
      unit = 60
    }
    return secondsUntilNextMultiple(of: unit, after: ageSeconds)
  }
}
