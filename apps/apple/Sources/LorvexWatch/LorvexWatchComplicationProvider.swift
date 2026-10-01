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

  /// The sample day, redacted by the view, so the placeholder has the shape
  /// of a real day without showing one.
  public static func placeholderEntry(at date: Date = Date()) -> LorvexWatchComplicationEntry {
    LorvexWatchComplicationEntryMapper.entry(
      from: .snapshot(WidgetPreviewSnapshot.make(now: date)), at: date, isPlaceholder: true)
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
    let timeline = LorvexWatchComplicationEntryMapper.timeline(from: loadResult(at: now), at: now)
    completion(Timeline(entries: timeline.entries, policy: .after(timeline.refreshAfter)))
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
