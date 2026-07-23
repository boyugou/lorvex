import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import WidgetKit

/// Supplies timeline entries for the Lorvex watch face complication.
///
/// Reads the shared App Group snapshot via `LorvexWatchSnapshotReader` and
/// maps it through `LorvexWatchComplicationEntryMapper`. New snapshot
/// publications explicitly invalidate WidgetKit; scheduled reloads are reserved
/// for freshness/day transitions instead of polling the same file.
public struct LorvexWatchComplicationProvider: TimelineProvider {
  public typealias Entry = LorvexWatchComplicationEntry

  private let appGroupID: String

  public init(appGroupID: String = LorvexProductMetadata.appGroupIdentifier) {
    self.appGroupID = appGroupID
  }

  public func placeholder(in context: Context) -> LorvexWatchComplicationEntry {
    Self.placeholderEntry(at: Date())
  }

  public static func placeholderEntry(at date: Date = Date()) -> LorvexWatchComplicationEntry {
    LorvexWatchComplicationEntry(
      date: date,
      taskTitle: String(
        localized: "watch.complication.placeholder.task_title", defaultValue: "Review pull request",
        table: "Localizable", bundle: WatchL10n.bundle),
      statusText: String(
        localized: "watch.complication.placeholder.status", defaultValue: "1 focus task",
        table: "Localizable", bundle: WatchL10n.bundle),
      openFocusCount: 1,
      availability: .content,
      primaryPriorityTier: 1,
      isPlaceholder: true
    )
  }

  /// Representative, unredacted entry for the watch-face gallery. It must not
  /// depend on the App Group snapshot existing before first launch.
  public static func previewEntry(at date: Date = Date()) -> LorvexWatchComplicationEntry {
    LorvexWatchComplicationEntryMapper.entry(
      from: .snapshot(WidgetPreviewSnapshot.make(now: date)),
      at: date
    )
  }

  public func getSnapshot(
    in context: Context,
    completion: @escaping (LorvexWatchComplicationEntry) -> Void
  ) {
    let date = Date()
    completion(makeSnapshotEntry(isPreview: context.isPreview, at: date))
  }

  public func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<LorvexWatchComplicationEntry>) -> Void
  ) {
    let now = Date()
    let result = makeTimelineResult(from: loadResult(at: now), at: now)
    completion(Timeline(entries: [result.entry], policy: .after(result.refreshAfter)))
  }

  func makeSnapshotEntry(
    isPreview: Bool,
    at date: Date
  ) -> LorvexWatchComplicationEntry {
    if isPreview {
      return Self.previewEntry(at: date)
    }
    return LorvexWatchComplicationEntryMapper.entry(from: loadResult(at: date), at: date)
  }

  func makeTimelineResult(
    from unvalidatedResult: WidgetSnapshotLoadResult,
    at date: Date,
    calendar fallbackCalendar: Calendar = .autoupdatingCurrent
  ) -> (entry: LorvexWatchComplicationEntry, refreshAfter: Date) {
    let freshnessPolicy = WidgetSnapshotFreshnessPolicy()
    let result = freshnessPolicy.validatingCurrentDay(
      unvalidatedResult,
      now: date,
      calendar: fallbackCalendar
    )
    let freshness = result.snapshot.map {
      freshnessPolicy.classify(snapshot: $0, now: date)
    }

    let refreshAfter = WidgetTimelineRefreshPolicy().nextRefreshDate(
      after: date,
      freshness: freshness,
      freshnessPolicy: freshnessPolicy,
      calendar: fallbackCalendar
    )
    return (
      LorvexWatchComplicationEntryMapper.entry(from: result, at: date),
      refreshAfter
    )
  }

  private func loadResult(at date: Date) -> WidgetSnapshotLoadResult {
    guard
      let reader = LorvexWatchSnapshotReader.appGroupReader(
        appGroupID: appGroupID
      )
    else {
      return .fallback(
        .init(reason: .missingFile, detail: "app_group_unavailable")
      )
    }
    return reader.read(at: date).result
  }
}
