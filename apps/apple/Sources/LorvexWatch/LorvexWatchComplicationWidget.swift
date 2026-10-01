import SwiftUI
import WidgetKit
import LorvexCore

/// The Lorvex Today complication for watchOS faces: how many tasks are left
/// today and the one at the top.
///
/// Supported families: `accessoryCircular`, `accessoryRectangular`,
/// `accessoryInline`, and `accessoryCorner` (watchOS only).
public struct LorvexWatchComplicationWidget: Widget {
  public static let kind = LorvexProductMetadata.watchComplicationKind

  public init() {}

  public var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: Self.kind,
      provider: LorvexWatchComplicationProvider()
    ) { entry in
      LorvexWatchComplicationView(entry: entry)
    }
    .configurationDisplayName(LocalizedStringResource(
      "watch.complication.name",
      defaultValue: "Lorvex Today",
      table: "Localizable",
      bundle: WatchL10n.bundle
    ))
    .description(LocalizedStringResource(
      "watch.complication.description",
      defaultValue: "Shows how many tasks are left today and the one at the top.",
      table: "Localizable",
      bundle: WatchL10n.bundle
    ))
    .supportedFamilies(Self.supportedFamilies)
  }

  private static var supportedFamilies: [WidgetFamily] {
    #if os(watchOS)
      [.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]
    #elseif os(iOS)
      [.accessoryCircular, .accessoryRectangular, .accessoryInline]
    #else
      []
    #endif
  }
}
