import Foundation
import LorvexWidgetKitSupport
import WidgetKit

public struct LorvexFocusWidgetProvider: TimelineProvider {
  public typealias Entry = LorvexWidgetEntry

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

  public func getSnapshot(in context: Context, completion: @escaping (LorvexWidgetEntry) -> Void) {
    let family = Self.familyKind(for: context.family)
    completion(makeSnapshotEntry(family: family, isPreview: context.isPreview))
  }

  func makeSnapshotEntry(
    family: WidgetFamilyKind,
    isPreview: Bool
  ) -> LorvexWidgetEntry {
    if isPreview {
      return LorvexWidgetTimelineAdapter.staticPreview(family: family)
    }
    if let adapter = adapter(snapshotURL: configuration.resolvedSnapshotURL()) {
      return adapter.snapshot(family: family)
    }
    return LorvexWidgetTimelineAdapter.staticPlaceholder(
      family: family,
      refreshPolicy: refreshPolicy
    )
  }

  public func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<LorvexWidgetEntry>) -> Void
  ) {
    let family = Self.familyKind(for: context.family)
    if let adapter = adapter(snapshotURL: configuration.resolvedSnapshotURL()) {
      completion(adapter.timeline(family: family))
    } else {
      let entry = placeholder(in: context)
      completion(
        Timeline(
          entries: [entry],
          policy: .after(
            entry.date.addingTimeInterval(
              TimeInterval(refreshPolicy.refreshIntervalSeconds(freshness: nil))
            )
          )
        )
      )
    }
  }

  public static func familyKind(for family: WidgetFamily) -> WidgetFamilyKind {
    switch family {
    case .systemSmall:
      .systemSmall
    case .systemMedium:
      .systemMedium
    case .systemLarge, .systemExtraLarge:
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
    let support = WidgetTimelineProviderSupport(
      configuration: .init(snapshotURL: url)
    )
    return LorvexWidgetTimelineAdapter(support: support)
  }
}
