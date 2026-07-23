import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import LorvexWidgetViews
import SwiftUI
import WidgetKit

/// Widget showing daily task completion progress as a ring/gauge.
/// Available in systemSmall, accessoryCircular, and accessoryInline.
public struct LorvexProgressWidget: Widget {
  public static let kind = LorvexProductMetadata.progressWidgetKind

  private let configuration: LorvexWidgetConfiguration

  public init() {
    configuration = LorvexWidgetConfiguration(kind: Self.kind)
  }

  public var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: configuration.kind,
      provider: LorvexSnapshotTimelineProvider(configuration: configuration)
    ) { entry in
      LorvexProgressWidgetEntryView(entry: entry)
    }
    .configurationDisplayName(
      LocalizedStringResource(
        "widget.progress.name",
        defaultValue: "Daily Progress",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle))
    .description(
      LocalizedStringResource(
        "widget.progress.desc",
        defaultValue: "Track today's task completion at a glance.",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle))
    .supportedFamilies(supportedFamilies)
  }

  private var supportedFamilies: [WidgetFamily] {
    #if os(iOS)
      [.systemSmall, .accessoryCircular, .accessoryInline]
    #else
      [.systemSmall]
    #endif
  }
}

struct LorvexProgressWidgetEntryView: View {
  let entry: LorvexSnapshotEntry

  @Environment(\.widgetFamily) private var family

  var body: some View {
    Group {
      if let snapshot = entry.snapshot {
        ProgressWidgetView(snapshot: snapshot, family: familyKind, staleAgeLabel: systemStaleAgeLabel)
      } else {
        ProgressFallbackView(family: familyKind, statusText: entry.statusText)
      }
    }
    .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    .containerBackground(.background, for: .widget)
    .widgetURL(LorvexDeepLinkContract.destinationURL(.today))
  }

  private var systemStaleAgeLabel: String? {
    familyKind == .systemSmall ? entry.staleAgeLabel : nil
  }

  private var familyKind: WidgetFamilyKind {
    switch family {
    case .accessoryCircular: .accessoryCircular
    case .accessoryInline: .accessoryInline
    default: .systemSmall
    }
  }
}

private struct ProgressFallbackView: View {
  let family: WidgetFamilyKind
  let statusText: String

  var body: some View {
    switch family {
    case .accessoryInline:
      Text(
        statusText.isEmpty
          ? String(
            localized: "widget.progress.unavailable",
            defaultValue: "Progress unavailable",
            table: "Localizable",
            bundle: WidgetSupportL10n.bundle)
          : statusText)
    case .accessoryCircular:
      Image(systemName: "chart.pie")
        .widgetAccentable()
        .accessibilityLabel(
          String(
            localized: "widget.progress.unavailable",
            defaultValue: "Progress unavailable",
            table: "Localizable",
            bundle: WidgetSupportL10n.bundle))
    default:
      VStack(alignment: .leading, spacing: 8) {
        Text("widget.progress.title", bundle: WidgetSupportL10n.bundle)
          .font(.headline)
        Text(
          statusText.isEmpty
            ? String(
              localized: "widget.progress.fallback",
              defaultValue: "Open Lorvex to load.",
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
}
