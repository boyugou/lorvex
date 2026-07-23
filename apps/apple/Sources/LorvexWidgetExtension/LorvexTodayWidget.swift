import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import LorvexWidgetViews
import SwiftUI
import WidgetKit

/// Widget showing today's open tasks (due today + overdue) with inline complete buttons.
public struct LorvexTodayWidget: Widget {
  public static let kind = LorvexProductMetadata.todayWidgetKind

  private let configuration: LorvexWidgetConfiguration

  public init() {
    configuration = LorvexWidgetConfiguration(kind: Self.kind)
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
        defaultValue: "Today Tasks",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle)
    )
    .description(
      LocalizedStringResource(
        "widget.today.desc",
        defaultValue: "See today's open tasks at a glance.",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle)
    )
    .supportedFamilies(Self.supportedFamilies)
  }

  private static var supportedFamilies: [WidgetFamily] {
    // No `.systemExtraLarge`: it has no dedicated layout (it collapsed to the
    // systemLarge layout floating in a much larger frame). Re-add it only with a
    // real two-column XL design.
    [.systemSmall, .systemMedium, .systemLarge]
  }
}

struct LorvexTodayWidgetEntryView: View {
  let entry: LorvexSnapshotEntry

  @Environment(\.widgetFamily) private var family

  var body: some View {
    Group {
      if let snapshot = entry.snapshot {
        configuredSnapshotView(snapshot)
      } else {
        TodayWidgetFallbackView(statusText: entry.statusText)
      }
    }
    .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    .containerBackground(.background, for: .widget)
    .widgetURL(widgetURL)
  }

  @ViewBuilder
  private func configuredSnapshotView(_ snapshot: WidgetSnapshot) -> some View {
    let filtered = TodayWidgetSnapshotFilter.applying(
      listID: entry.todayWidgetListID, to: snapshot)
    switch entry.todayWidgetViewMode {
    case .today:
      TodayWidgetView(snapshot: filtered, family: familyKind, staleAgeLabel: entry.staleAgeLabel)
    case .focus:
      LorvexWidgetView(
        model: WidgetRenderModelBuilder().model(
          entry: WidgetTimelineEntry(
            date: entry.date,
            state: .snapshot(filtered, freshness: entry.freshness),
            refreshAfter: entry.date
          ),
          family: familyKind,
          statusText: entry.statusText
        )
      )
    }
  }

  private var widgetURL: URL {
    // Both view modes open Today: it is the single planning home that renders the
    // focus plan alongside the rest of the day's tasks.
    LorvexDeepLinkContract.destinationURL(.today)
  }

  private var familyKind: WidgetFamilyKind {
    switch family {
    case .systemMedium: .systemMedium
    case .systemLarge, .systemExtraLarge: .systemLarge
    default: .systemSmall
    }
  }
}

/// Applies the configurable list scope without carrying prose generated for a
/// broader focus plan into the narrowed result.
enum TodayWidgetSnapshotFilter {
  static func applying(listID: String?, to snapshot: WidgetSnapshot) -> WidgetSnapshot {
    guard let listID else { return snapshot }
    let focusTasks = snapshot.focusTasks.filter { $0.listID == listID }
    let todayTasks = snapshot.todayTasks.filter { $0.listID == listID }
    return WidgetSnapshot(
      generatedAt: snapshot.generatedAt,
      storageGeneration: snapshot.storageGeneration,
      focusFilterRevision: snapshot.focusFilterRevision,
      workspaceInstanceID: snapshot.workspaceInstanceID,
      localChangeSequence: snapshot.localChangeSequence,
      timezone: snapshot.timezone,
      logicalDay: snapshot.logicalDay,
      stats: snapshot.listStats.first { $0.id == listID }?.stats
        ?? .init(
          focusCount: focusTasks.count,
          overdueCount: 0,
          dueTodayCount: todayTasks.count,
          completedTodayCount: 0),
      // There is no list-scoped briefing. Reusing the global prose can mention
      // tasks removed by this filter, so the focused view falls back to its
      // truthful generic subheadline.
      briefing: nil,
      focusTasks: focusTasks,
      habits: snapshot.habits,
      todayTasks: todayTasks,
      lists: snapshot.lists,
      listStats: snapshot.listStats
    )
  }
}

private struct TodayWidgetFallbackView: View {
  let statusText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("widget.title.today", bundle: WidgetSupportL10n.bundle)
        .font(.headline)
      Text(
        statusText.isEmpty
          ? String(
            localized: "widget.today.fallback",
            defaultValue: "Open Lorvex to load tasks.",
            table: "Localizable",
            bundle: WidgetSupportL10n.bundle)
          : statusText
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
