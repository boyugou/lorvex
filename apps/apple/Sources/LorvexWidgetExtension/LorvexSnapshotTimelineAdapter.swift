import Foundation
import LorvexWidgetKitSupport
import WidgetKit

public struct LorvexSnapshotTimelineAdapter {
  private let support: WidgetTimelineProviderSupport

  public init(support: WidgetTimelineProviderSupport) {
    self.support = support
  }

  public func placeholder() -> LorvexSnapshotEntry {
    entry(from: support.placeholderEntry(), isPlaceholder: true)
  }

  public static func staticPlaceholder(
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
      isPlaceholder: true
    )
  }

  /// Representative, unredacted content for WidgetKit's gallery snapshot.
  /// This intentionally bypasses the live App Group file, which may not exist
  /// before the first app launch.
  public static func staticPreview(
    now: Date = Date()
  ) -> LorvexSnapshotEntry {
    let timelineEntry = WidgetTimelineEntry(
      date: now,
      state: .snapshot(
        WidgetPreviewSnapshot.make(now: now),
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
        bundle: WidgetSupportL10n.bundle)
    )
  }

  public static func staticMissingSnapshotURLResult(
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
          bundle: WidgetSupportL10n.bundle)
      ),
      refreshAfter
    )
  }

  public func snapshot() -> LorvexSnapshotEntry {
    entry(from: support.timelineEntry())
  }

  public func timeline() -> Timeline<LorvexSnapshotEntry> {
    let result = timelineResult()
    return Timeline(
      entries: [result.entry],
      policy: .after(result.refreshAfter)
    )
  }

  public func timelineResult() -> (entry: LorvexSnapshotEntry, refreshAfter: Date) {
    let timelineEntry = support.timelineEntry()
    return (
      entry(from: timelineEntry),
      timelineEntry.refreshAfter
    )
  }

  private func entry(
    from timelineEntry: WidgetTimelineEntry,
    isPlaceholder: Bool = false
  ) -> LorvexSnapshotEntry {
    Self.entry(
      from: timelineEntry,
      statusText: support.compactStatusText(for: timelineEntry),
      isPlaceholder: isPlaceholder
    )
  }

  private static func entry(
    from timelineEntry: WidgetTimelineEntry,
    statusText: String,
    isPlaceholder: Bool = false
  ) -> LorvexSnapshotEntry {
    LorvexSnapshotEntry(
      timelineEntry: timelineEntry,
      statusText: statusText,
      isPlaceholder: isPlaceholder
    )
  }
}
