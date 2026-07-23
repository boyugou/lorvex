import Foundation
import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

public struct LorvexFocusWidget: Widget {
  private var configuration = LorvexWidgetConfiguration()

  public init() {}

  init(configuration: LorvexWidgetConfiguration) {
    self.configuration = configuration
  }

  public var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: configuration.kind,
      provider: LorvexFocusWidgetProvider(configuration: configuration)
    ) { entry in
      LorvexFocusWidgetEntryView(entry: entry)
    }
    .configurationDisplayName(
      LocalizedStringResource(
        "widget.focus.name",
        defaultValue: "Lorvex Focus",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle))
    .description(
      LocalizedStringResource(
        "widget.focus.desc",
        defaultValue: "Shows today's focus plan from Lorvex.",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle))
    .supportedFamilies(Self.supportedFamilies)
  }

  private static var supportedFamilies: [WidgetFamily] {
    #if os(iOS)
      // No `.systemExtraLarge` — it has no dedicated layout (it collapsed to the
      // systemLarge design in a much larger frame). `familyKind` still maps it to
      // systemLarge defensively.
      [
        .systemSmall,
        .systemMedium,
        .systemLarge,
        .accessoryInline,
        .accessoryRectangular,
        .accessoryCircular,
      ]
    #else
      [
        .systemSmall,
        .systemMedium,
        .systemLarge,
      ]
    #endif
  }
}
