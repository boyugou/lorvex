import Foundation
import LorvexWidgetKitSupport

/// Maps the watch replica to complication timeline entries.
///
/// Pure functions — the testable core of the complication provider. A
/// snapshot yields an entry for now and one at each instant the Today glance
/// changes before the reload point (a saved time's start or end, and a tick
/// inside a running time), so the lead and its ring advance without spending
/// the complication's refresh budget.
public enum LorvexWatchComplicationEntryMapper {
  /// The entries for a load result read at `date`, and when to reload.
  public static func timeline(
    from unvalidatedResult: WidgetSnapshotLoadResult,
    at date: Date,
    calendar fallbackCalendar: Calendar = .autoupdatingCurrent
  ) -> (entries: [LorvexWatchComplicationEntry], refreshAfter: Date) {
    let freshnessPolicy = WidgetSnapshotFreshnessPolicy()
    let refreshPolicy = WidgetTimelineRefreshPolicy()
    let result = freshnessPolicy.validatingCurrentDay(
      unvalidatedResult, now: date, calendar: fallbackCalendar)
    switch result {
    case .snapshot(let snapshot):
      let freshness = freshnessPolicy.classify(snapshot: snapshot, now: date)
      let calendar = freshnessPolicy.logicalCalendar(for: snapshot, fallback: fallbackCalendar)
      let refreshAfter = refreshPolicy.nextRefreshDate(
        after: date, freshness: freshness, freshnessPolicy: freshnessPolicy, calendar: calendar)
      let dates =
        [date]
        + WidgetTodayGlance.changeDates(
          tasks: snapshot.tasks, from: date, until: refreshAfter,
          timezoneName: snapshot.timezone, calendar: calendar)
      let entries = dates.map { entryDate in
        entry(
          from: WidgetTimelineEntry(
            date: entryDate, state: .snapshot(snapshot, freshness: freshness),
            refreshAfter: refreshAfter))
      }
      return (entries, refreshAfter)
    case .fallback(let fallback):
      let refreshAfter = refreshPolicy.nextRefreshDate(
        after: date, freshness: nil, freshnessPolicy: freshnessPolicy, calendar: fallbackCalendar)
      return (
        [entry(from: WidgetTimelineEntry(date: date, state: .fallback(fallback), refreshAfter: refreshAfter))],
        refreshAfter
      )
    }
  }

  /// The entry for a load result read at `date`: the first entry of
  /// ``timeline(from:at:calendar:)``.
  public static func entry(
    from result: WidgetSnapshotLoadResult,
    at date: Date = Date(),
    calendar: Calendar = .autoupdatingCurrent,
    isPlaceholder: Bool = false
  ) -> LorvexWatchComplicationEntry {
    let first = timeline(from: result, at: date, calendar: calendar).entries[0]
    return LorvexWatchComplicationEntry(
      date: first.date, model: first.model, timezoneName: first.timezoneName,
      isPlaceholder: isPlaceholder)
  }

  /// The entry for one timeline instant. The rectangular family's model is
  /// the richest (the lead and the task after it); every family reads from it.
  static func entry(from timelineEntry: WidgetTimelineEntry) -> LorvexWatchComplicationEntry {
    let statusText: String
    switch timelineEntry.state {
    case .snapshot:
      statusText = ""
    case .fallback(let fallback):
      statusText = LorvexWatchStore.snapshotUnavailableStatusText(fallback)
    }
    return LorvexWatchComplicationEntry(
      date: timelineEntry.date,
      model: WidgetRenderModelBuilder().model(
        entry: timelineEntry, family: .accessoryRectangular, statusText: statusText),
      timezoneName: timelineEntry.state.snapshot?.timezone)
  }
}
