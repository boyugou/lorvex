import Foundation
import LorvexWidgetKitSupport
import WidgetKit

/// A `TimelineProvider` that vends `LorvexSnapshotEntry` for widgets that render
/// directly from the raw snapshot fields (Today, Progress, Habits).
public struct LorvexSnapshotTimelineProvider: TimelineProvider, Sendable {
  public typealias Entry = LorvexSnapshotEntry

  private let configuration: LorvexWidgetConfiguration
  private let dayRollover: WidgetSnapshotDayRollover

  public init(configuration: LorvexWidgetConfiguration = LorvexWidgetConfiguration()) {
    self.init(configuration: configuration, dayRollover: .live)
  }

  init(configuration: LorvexWidgetConfiguration, dayRollover: WidgetSnapshotDayRollover) {
    self.configuration = configuration
    self.dayRollover = dayRollover
  }

  public func placeholder(in context: Context) -> LorvexSnapshotEntry {
    LorvexSnapshotTimelineAdapter.staticPlaceholder()
  }

  public func getSnapshot(in context: Context, completion: @escaping (LorvexSnapshotEntry) -> Void) {
    completion(makeSnapshotEntry(isPreview: context.isPreview))
  }

  func makeSnapshotEntry(isPreview: Bool) -> LorvexSnapshotEntry {
    if isPreview {
      return LorvexSnapshotTimelineAdapter.staticPreview()
    }
    if let adapter = adapter(snapshotURL: configuration.resolvedSnapshotURL()) {
      return adapter.snapshot()
    }
    return LorvexSnapshotTimelineAdapter.staticMissingSnapshotURLResult().entry
  }

  public func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<LorvexSnapshotEntry>) -> Void
  ) {
    let snapshotURL = configuration.resolvedSnapshotURL()
    // WidgetKit's completion is not declared Sendable but may be called from
    // any thread; the task calls it exactly once.
    nonisolated(unsafe) let completion = completion
    Task {
      completion(await timeline(snapshotURL: snapshotURL))
    }
  }

  /// The timeline for the snapshot at `snapshotURL`, rebuilt for the current
  /// day first when the file on disk belongs to an earlier one.
  func timeline(snapshotURL: URL?) async -> Timeline<LorvexSnapshotEntry> {
    await dayRollover.rollOverIfExpired(snapshotURL: snapshotURL)
    if let adapter = adapter(snapshotURL: snapshotURL) {
      return adapter.timeline()
    }
    let result = LorvexSnapshotTimelineAdapter.staticMissingSnapshotURLResult()
    return Timeline(entries: [result.entry], policy: .after(result.refreshAfter))
  }

  private func adapter(snapshotURL: URL?) -> LorvexSnapshotTimelineAdapter? {
    guard let url = snapshotURL else { return nil }
    let support = WidgetTimelineProviderSupport(configuration: .init(snapshotURL: url))
    return LorvexSnapshotTimelineAdapter(support: support)
  }
}
