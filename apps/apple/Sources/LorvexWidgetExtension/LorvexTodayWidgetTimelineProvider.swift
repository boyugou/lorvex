import Foundation
import LorvexWidgetKitSupport
import WidgetKit

/// Timelines for the Today widget: one entry now and one at each instant the
/// lead, its ring, or its line changes before the reload point, narrowed to the
/// configured list.
public struct LorvexTodayWidgetTimelineProvider: AppIntentTimelineProvider {
  public typealias Entry = LorvexWidgetEntry
  public typealias Intent = LorvexTodayWidgetConfigurationIntent

  private let configuration: LorvexWidgetConfiguration
  private let refreshPolicy = WidgetTimelineRefreshPolicy()

  public init(configuration: LorvexWidgetConfiguration = LorvexWidgetConfiguration()) {
    self.configuration = configuration
  }

  public func placeholder(in context: Context) -> LorvexWidgetEntry {
    LorvexWidgetTimelineAdapter.staticPlaceholder(
      family: Self.familyKind(for: context.family),
      refreshPolicy: refreshPolicy
    )
  }

  public func snapshot(
    for configuration: LorvexTodayWidgetConfigurationIntent,
    in context: Context
  ) async -> LorvexWidgetEntry {
    makeSnapshotEntry(
      family: Self.familyKind(for: context.family),
      listID: configuration.list?.id,
      isPreview: context.isPreview)
  }

  func makeSnapshotEntry(
    family: WidgetFamilyKind,
    listID: String? = nil,
    isPreview: Bool
  ) -> LorvexWidgetEntry {
    if isPreview {
      return LorvexWidgetTimelineAdapter.staticPreview(family: family, listID: listID)
    }
    if let adapter = adapter(snapshotURL: self.configuration.resolvedSnapshotURL()) {
      return adapter.snapshot(family: family, listID: listID)
    }
    return LorvexWidgetTimelineAdapter.staticPlaceholder(
      family: family,
      refreshPolicy: refreshPolicy
    )
  }

  public func timeline(
    for configuration: LorvexTodayWidgetConfigurationIntent,
    in context: Context
  ) async -> Timeline<LorvexWidgetEntry> {
    let family = Self.familyKind(for: context.family)
    if let adapter = adapter(snapshotURL: self.configuration.resolvedSnapshotURL()) {
      return adapter.timeline(family: family, listID: configuration.list?.id)
    }
    let entry = placeholder(in: context)
    return Timeline(
      entries: [entry],
      policy: .after(
        entry.date.addingTimeInterval(
          TimeInterval(refreshPolicy.refreshIntervalSeconds(freshness: nil)))))
  }

  public static func familyKind(for family: WidgetFamily) -> WidgetFamilyKind {
    switch family {
    case .systemSmall:
      .systemSmall
    case .systemMedium:
      .systemMedium
    case .systemLarge, .systemExtraLarge, .systemExtraLargePortrait:
      .systemLarge
    case .accessoryInline:
      .accessoryInline
    case .accessoryRectangular:
      .accessoryRectangular
    case .accessoryCircular:
      .accessoryCircular
    @unknown default:
      .systemSmall
    }
  }

  private func adapter(snapshotURL: URL?) -> LorvexWidgetTimelineAdapter? {
    guard let url = snapshotURL else { return nil }
    let support = WidgetTimelineProviderSupport(configuration: .init(snapshotURL: url))
    return LorvexWidgetTimelineAdapter(support: support)
  }
}
