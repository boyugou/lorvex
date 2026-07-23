import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import LorvexWidgetViews
import SwiftUI
import WidgetKit

/// Widget showing today's habit completion status in systemSmall, systemMedium, and accessoryCircular.
public struct LorvexHabitsWidget: Widget {
  public static let kind = LorvexProductMetadata.habitsWidgetKind

  private let configuration: LorvexWidgetConfiguration

  public init() {
    configuration = LorvexWidgetConfiguration(kind: Self.kind)
  }

  public var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: configuration.kind,
      provider: LorvexSnapshotTimelineProvider(configuration: configuration)
    ) { entry in
      LorvexHabitsWidgetEntryView(entry: entry)
    }
    .configurationDisplayName(
      LocalizedStringResource(
        "widget.habits.name",
        defaultValue: "Habits",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle))
    .description(
      LocalizedStringResource(
        "widget.habits.desc",
        defaultValue: "See today's habit progress at a glance.",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle))
    .supportedFamilies(supportedFamilies)
  }

  private var supportedFamilies: [WidgetFamily] {
    #if os(iOS)
      [.systemSmall, .systemMedium, .accessoryCircular]
    #else
      [.systemSmall, .systemMedium]
    #endif
  }
}

struct LorvexHabitsWidgetEntryView: View {
  let entry: LorvexSnapshotEntry

  @Environment(\.widgetFamily) private var family

  /// Isolates the `.accessoryCircular` case reference, which is unavailable on
  /// the macOS host SwiftPM compiles against.
  private var isAccessoryCircular: Bool {
    #if os(iOS)
      family == .accessoryCircular
    #else
      false
    #endif
  }

  var body: some View {
    Group {
      if let snapshot = entry.snapshot {
        if isAccessoryCircular {
          HabitsAccessoryCircularView(habits: snapshot.habits)
        } else {
          HabitsWidgetView(
            habits: snapshot.habits,
            family: family == .systemMedium ? .systemMedium : .systemSmall,
            staleAgeLabel: entry.staleAgeLabel
          )
        }
      } else {
        HabitsFallbackView(statusText: entry.statusText)
      }
    }
    .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    .containerBackground(.background, for: .widget)
    .widgetURL(LorvexDeepLinkContract.destinationURL(.habits))
  }
}

private struct HabitsFallbackView: View {
  let statusText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("widget.habits.title", bundle: WidgetSupportL10n.bundle)
        .font(.headline)
      Text(
        statusText.isEmpty
          ? String(
            localized: "widget.habits.fallback",
            defaultValue: "Open Lorvex to load habits.",
            table: "Localizable",
            bundle: WidgetSupportL10n.bundle)
          : statusText)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
