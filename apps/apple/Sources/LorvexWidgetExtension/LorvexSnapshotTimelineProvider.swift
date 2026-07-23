import Foundation
import LorvexWidgetKitSupport
import WidgetKit

/// A `TimelineProvider` that vends `LorvexSnapshotEntry` for widgets that render
/// directly from the raw snapshot fields (Today, Progress, Habits).
public struct LorvexSnapshotTimelineProvider: TimelineProvider {
  public typealias Entry = LorvexSnapshotEntry

  private let configuration: LorvexWidgetConfiguration

  public init(configuration: LorvexWidgetConfiguration = LorvexWidgetConfiguration()) {
    self.configuration = configuration
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
    if let adapter = adapter(snapshotURL: configuration.resolvedSnapshotURL()) {
      completion(adapter.timeline())
    } else {
      let result = LorvexSnapshotTimelineAdapter.staticMissingSnapshotURLResult()
      completion(
        Timeline(
          entries: [result.entry],
          policy: .after(result.refreshAfter)
        )
      )
    }
  }

  private func adapter(snapshotURL: URL?) -> LorvexSnapshotTimelineAdapter? {
    guard let url = snapshotURL else { return nil }
    let support = WidgetTimelineProviderSupport(configuration: .init(snapshotURL: url))
    return LorvexSnapshotTimelineAdapter(support: support)
  }
}
