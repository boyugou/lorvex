import Foundation
import LorvexWidgetKitSupport
import WidgetKit

public struct LorvexTodayWidgetTimelineProvider: AppIntentTimelineProvider {
  public typealias Entry = LorvexSnapshotEntry
  public typealias Intent = LorvexTodayWidgetConfigurationIntent

  private let configuration: LorvexWidgetConfiguration

  public init(configuration: LorvexWidgetConfiguration = LorvexWidgetConfiguration()) {
    self.configuration = configuration
  }

  public func placeholder(in context: Context) -> LorvexSnapshotEntry {
    LorvexSnapshotTimelineAdapter.staticPlaceholder(viewMode: .today)
  }

  public func snapshot(
    for configuration: LorvexTodayWidgetConfigurationIntent,
    in context: Context
  ) async -> LorvexSnapshotEntry {
    makeSnapshotEntry(
      viewMode: configuration.viewMode ?? .today,
      listID: configuration.list?.id,
      isPreview: context.isPreview
    )
  }

  func makeSnapshotEntry(
    viewMode: LorvexTodayWidgetViewMode,
    listID: String? = nil,
    isPreview: Bool
  ) -> LorvexSnapshotEntry {
    if isPreview {
      return LorvexSnapshotTimelineAdapter.staticPreview(
        viewMode: viewMode,
        listID: listID
      )
    }
    return makeTimelineEntry(
      viewMode: viewMode,
      listID: listID
    ).entry
  }

  public func timeline(
    for configuration: LorvexTodayWidgetConfigurationIntent,
    in context: Context
  ) async -> Timeline<LorvexSnapshotEntry> {
    let result = makeTimelineEntry(
      viewMode: configuration.viewMode ?? .today,
      listID: configuration.list?.id
    )
    return Timeline(entries: [result.entry], policy: .after(result.refreshAfter))
  }

  func makeTimelineEntry(
    viewMode: LorvexTodayWidgetViewMode,
    listID: String? = nil
  ) -> (entry: LorvexSnapshotEntry, refreshAfter: Date) {
    guard let adapter = adapter(snapshotURL: configuration.resolvedSnapshotURL()) else {
      return LorvexSnapshotTimelineAdapter.staticMissingSnapshotURLResult(
        viewMode: viewMode,
        listID: listID
      )
    }
    return adapter.timelineResult(viewMode: viewMode, listID: listID)
  }

  private func adapter(snapshotURL: URL?) -> LorvexSnapshotTimelineAdapter? {
    guard let url = snapshotURL else { return nil }
    let support = WidgetTimelineProviderSupport(configuration: .init(snapshotURL: url))
    return LorvexSnapshotTimelineAdapter(support: support)
  }

}
