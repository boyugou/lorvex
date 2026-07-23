import SwiftUI
import WidgetKit
import LorvexCore

/// The Lorvex focus complication for watchOS faces.
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
      defaultValue: "Lorvex Focus",
      table: "Localizable",
      bundle: WatchL10n.bundle
    ))
    .description(LocalizedStringResource(
      "watch.complication.description",
      defaultValue: "Shows your current focus task.",
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
