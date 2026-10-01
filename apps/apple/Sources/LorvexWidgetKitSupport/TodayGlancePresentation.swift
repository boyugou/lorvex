import Foundation

/// A truthful, surface-independent reading of the snapshot's Today list for the
/// compact glances: the lead task and how many tasks are left.
///
/// A failed or expired snapshot is not an empty day. Control Center and the
/// watch complications use this projection so every compact surface preserves
/// that distinction, and name the same lead the widgets do.
public struct TodayGlancePresentation: Equatable, Sendable {
  public enum Availability: Equatable, Sendable {
    case unavailable
    case empty
    case content
  }

  public let availability: Availability
  /// The ``TodayLead`` at the resolved clock; nil when no task leads, even
  /// with tasks left.
  public let lead: WidgetSnapshot.TodayTask?
  /// Tasks left on Today, the lead included. Read from the uncapped count, so
  /// a snapshot that carries only the top of a long list still counts it all.
  public let remainingCount: Int
  public let timezoneName: String?

  public static func resolve(
    from result: WidgetSnapshotLoadResult,
    now: Date,
    calendar: Calendar = .autoupdatingCurrent
  ) -> TodayGlancePresentation {
    let validated = WidgetSnapshotFreshnessPolicy().validatingCurrentDay(
      result, now: now, calendar: calendar)
    guard case .snapshot(let snapshot) = validated else {
      return TodayGlancePresentation(
        availability: .unavailable, lead: nil, remainingCount: 0, timezoneName: nil)
    }
    let glance = WidgetTodayGlance.build(
      tasks: snapshot.tasks,
      nowMinutes: WidgetTodayGlance.minutes(
        at: now, timezoneName: snapshot.timezone, calendar: calendar))
    let remaining = max(glance.remainingCount, snapshot.stats.todayCount)
    guard remaining > 0 else {
      return TodayGlancePresentation(
        availability: .empty, lead: nil, remainingCount: 0, timezoneName: snapshot.timezone)
    }
    return TodayGlancePresentation(
      availability: .content,
      lead: glance.lead?.task,
      remainingCount: remaining,
      timezoneName: snapshot.timezone)
  }
}
