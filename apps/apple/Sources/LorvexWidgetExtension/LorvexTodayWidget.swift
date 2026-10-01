import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// The Today widget: the day's list led by the task at its top, optionally
/// scoped to one list.
///
/// Small shows the lead task alone; medium and large add the tasks after it,
/// each with a circle that completes it; large opens with the day's briefing.
/// The Lock Screen families show the lead with its line, or, in the circle,
/// the minutes left in a running time or the tasks left today.
public struct LorvexTodayWidget: Widget {
  /// `LorvexProductMetadata.widgetKind`, the kind release manifests and reload
  /// calls name.
  public static let kind = LorvexProductMetadata.widgetKind

  private let configuration: LorvexWidgetConfiguration

  public init() {
    configuration = LorvexWidgetConfiguration(kind: Self.kind)
  }

  init(configuration: LorvexWidgetConfiguration) {
    self.configuration = configuration
  }

  public var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: configuration.kind,
      intent: LorvexTodayWidgetConfigurationIntent.self,
      provider: LorvexTodayWidgetTimelineProvider(configuration: configuration)
    ) { entry in
      LorvexTodayWidgetEntryView(entry: entry)
    }
    .configurationDisplayName(
      LocalizedStringResource(
        "widget.today.name",
        defaultValue: "Today",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle)
    )
    .description(
      LocalizedStringResource(
        "widget.today.desc",
        defaultValue: "See today’s tasks at a glance.",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle)
    )
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
