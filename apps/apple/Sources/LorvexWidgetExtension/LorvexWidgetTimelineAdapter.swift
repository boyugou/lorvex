import Foundation
import LorvexWidgetKitSupport
import WidgetKit

public struct LorvexWidgetTimelineAdapter {
  private let support: WidgetTimelineProviderSupport
  private let modelBuilder: WidgetRenderModelBuilder

  public init(
    support: WidgetTimelineProviderSupport,
    modelBuilder: WidgetRenderModelBuilder = WidgetRenderModelBuilder()
  ) {
    self.support = support
    self.modelBuilder = modelBuilder
  }

  public func placeholder(family: WidgetFamilyKind) -> LorvexWidgetEntry {
    entry(from: support.placeholderEntry(), family: family, isPlaceholder: true)
  }

  /// Returns a placeholder entry without requiring a snapshot file URL.
  /// Suitable for use in `TimelineProvider.placeholder(in:)` where no snapshot is loaded.
  public static func staticPlaceholder(
    family: WidgetFamilyKind,
    refreshPolicy: WidgetTimelineRefreshPolicy = WidgetTimelineRefreshPolicy(),
    now: Date = Date()
  ) -> LorvexWidgetEntry {
    let builder = WidgetRenderModelBuilder()
    let entry = staticPlaceholderTimelineEntry(refreshPolicy: refreshPolicy, now: now)
    let model = builder.model(
      entry: entry,
      family: family,
      statusText: String(
        localized: "widget.placeholder.ready",
        defaultValue: "Lorvex is ready.",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle)
    )
    return LorvexWidgetEntry(date: now, model: model, isPlaceholder: true)
  }

  /// Representative, unredacted content for the widget gallery. Unlike the
  /// loading placeholder, this must look like a configured Lorvex widget even
  /// when the app has never produced an App Group snapshot.
  public static func staticPreview(
    family: WidgetFamilyKind,
    now: Date = Date()
  ) -> LorvexWidgetEntry {
    let timelineEntry = WidgetTimelineEntry(
      date: now,
      state: .snapshot(WidgetPreviewSnapshot.make(now: now), freshness: .fresh(ageSeconds: 0)),
      refreshAfter: now
    )
    let model = WidgetRenderModelBuilder().model(
      entry: timelineEntry,
      family: family,
      statusText: String(
        localized: "widget.status.updated_now",
        defaultValue: "Updated now",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle)
    )
    return LorvexWidgetEntry(
      date: now,
      model: model,
      timezoneName: timelineEntry.state.snapshot?.timezone)
  }

  public static func staticPlaceholderTimelineEntry(
    refreshPolicy: WidgetTimelineRefreshPolicy = WidgetTimelineRefreshPolicy(),
    now: Date = Date()
  ) -> WidgetTimelineEntry {
    let placeholderSnapshot = WidgetSnapshot(
      generatedAt: "1970-01-01T00:00:00Z",
      timezone: nil,
      stats: .init(focusCount: 0, overdueCount: 0, dueTodayCount: 0),
      briefing: String(
        localized: "widget.placeholder.ready",
        defaultValue: "Lorvex is ready.",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle),
      focusTasks: []
    )
    return WidgetTimelineEntry(
      date: now,
      state: .snapshot(placeholderSnapshot, freshness: .unknownTimestamp),
      refreshAfter: now.addingTimeInterval(
        TimeInterval(refreshPolicy.refreshIntervalSeconds(freshness: nil))
      )
    )
  }

  public func snapshot(family: WidgetFamilyKind) -> LorvexWidgetEntry {
    entry(from: support.timelineEntry(), family: family)
  }

  public func timeline(family: WidgetFamilyKind) -> Timeline<LorvexWidgetEntry> {
    let timelineEntry = support.timelineEntry()
    return Timeline(
      entries: [entry(from: timelineEntry, family: family)],
      policy: .after(timelineEntry.refreshAfter)
    )
  }

  private func entry(
    from timelineEntry: WidgetTimelineEntry, family: WidgetFamilyKind, isPlaceholder: Bool = false
  ) -> LorvexWidgetEntry {
    let model = modelBuilder.model(
      entry: timelineEntry,
      family: family,
      statusText: support.compactStatusText(for: timelineEntry)
    )
    return LorvexWidgetEntry(
      date: timelineEntry.date,
      model: model,
      timezoneName: timelineEntry.state.snapshot?.timezone,
      isPlaceholder: isPlaceholder)
  }
}
