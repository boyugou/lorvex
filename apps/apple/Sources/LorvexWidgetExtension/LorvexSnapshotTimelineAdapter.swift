import Foundation
import LorvexWidgetKitSupport
import WidgetKit

public struct LorvexSnapshotTimelineAdapter {
  private let support: WidgetTimelineProviderSupport

  public init(support: WidgetTimelineProviderSupport) {
    self.support = support
  }

  public func placeholder(
    viewMode: LorvexTodayWidgetViewMode = .today,
    listID: String? = nil
  ) -> LorvexSnapshotEntry {
    entry(from: support.placeholderEntry(), viewMode: viewMode, listID: listID, isPlaceholder: true)
  }

  public static func staticPlaceholder(
    viewMode: LorvexTodayWidgetViewMode = .today,
    listID: String? = nil,
    refreshPolicy: WidgetTimelineRefreshPolicy = WidgetTimelineRefreshPolicy(),
    now: Date = Date()
  ) -> LorvexSnapshotEntry {
    entry(
      from: LorvexWidgetTimelineAdapter.staticPlaceholderTimelineEntry(
        refreshPolicy: refreshPolicy,
        now: now
      ),
      statusText: String(
        localized: "widget.status.open_to_refresh",
        defaultValue: "Open Lorvex to refresh",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle),
      viewMode: viewMode,
      listID: listID,
      isPlaceholder: true
    )
  }

  /// Representative, unredacted content for WidgetKit's gallery snapshot.
  /// This intentionally bypasses the live App Group file, which may not exist
  /// before the first app launch.
  public static func staticPreview(
    viewMode: LorvexTodayWidgetViewMode = .today,
    listID: String? = nil,
    now: Date = Date()
  ) -> LorvexSnapshotEntry {
    let timelineEntry = WidgetTimelineEntry(
      date: now,
      state: .snapshot(
        WidgetPreviewSnapshot.make(now: now, listID: listID),
        freshness: .fresh(ageSeconds: 0)
      ),
      refreshAfter: now
    )
    return entry(
      from: timelineEntry,
      statusText: String(
        localized: "widget.status.updated_now",
        defaultValue: "Updated now",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle),
      viewMode: viewMode,
      listID: listID
    )
  }

  public static func staticMissingSnapshotURLResult(
    viewMode: LorvexTodayWidgetViewMode = .today,
    listID: String? = nil,
    refreshPolicy: WidgetTimelineRefreshPolicy = WidgetTimelineRefreshPolicy(),
    now: Date = Date()
  ) -> (entry: LorvexSnapshotEntry, refreshAfter: Date) {
    let refreshAfter = now.addingTimeInterval(
      TimeInterval(refreshPolicy.refreshIntervalSeconds(freshness: nil))
    )
    let timelineEntry = WidgetTimelineEntry(
      date: now,
      state: .fallback(.init(
        reason: .missingFile,
        detail: String(
          localized: "widget.status.open_to_refresh",
          defaultValue: "Open Lorvex to refresh",
          table: "Localizable",
          bundle: WidgetSupportL10n.bundle)
      )),
      refreshAfter: refreshAfter
    )
    return (
      entry(
        from: timelineEntry,
        statusText: String(
          localized: "widget.status.open_to_refresh",
          defaultValue: "Open Lorvex to refresh",
          table: "Localizable",
          bundle: WidgetSupportL10n.bundle),
        viewMode: viewMode,
        listID: listID
      ),
      refreshAfter
    )
  }

  public func snapshot(
    viewMode: LorvexTodayWidgetViewMode = .today,
    listID: String? = nil
  ) -> LorvexSnapshotEntry {
    entry(from: support.timelineEntry(), viewMode: viewMode, listID: listID)
  }

  public func timeline(
    viewMode: LorvexTodayWidgetViewMode = .today,
    listID: String? = nil
  ) -> Timeline<LorvexSnapshotEntry> {
    let result = timelineResult(viewMode: viewMode, listID: listID)
    return Timeline(
      entries: [result.entry],
      policy: .after(result.refreshAfter)
    )
  }

  public func timelineResult(
    viewMode: LorvexTodayWidgetViewMode = .today,
    listID: String? = nil
  ) -> (entry: LorvexSnapshotEntry, refreshAfter: Date) {
    let timelineEntry = support.timelineEntry()
    return (
      entry(from: timelineEntry, viewMode: viewMode, listID: listID),
      timelineEntry.refreshAfter
    )
  }

  private func entry(
    from timelineEntry: WidgetTimelineEntry,
    viewMode: LorvexTodayWidgetViewMode,
    listID: String?,
    isPlaceholder: Bool = false
  ) -> LorvexSnapshotEntry {
    Self.entry(
      from: timelineEntry,
      statusText: support.compactStatusText(for: timelineEntry),
      viewMode: viewMode,
      listID: listID,
      isPlaceholder: isPlaceholder
    )
  }

  private static func entry(
    from timelineEntry: WidgetTimelineEntry,
    statusText: String,
    viewMode: LorvexTodayWidgetViewMode,
    listID: String?,
    isPlaceholder: Bool = false
  ) -> LorvexSnapshotEntry {
    LorvexSnapshotEntry(
      timelineEntry: timelineEntry,
      statusText: statusText,
      todayWidgetViewMode: viewMode,
      todayWidgetListID: listID,
      isPlaceholder: isPlaceholder
    )
  }
}
