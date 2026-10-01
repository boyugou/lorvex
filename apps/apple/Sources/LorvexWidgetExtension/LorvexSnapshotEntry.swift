import Foundation
import LorvexWidgetKitSupport
import WidgetKit

/// A timeline entry that carries the raw `WidgetSnapshot` (or nil on fallback) for widgets
/// that render directly from snapshot fields rather than through `WidgetRenderModel`
/// (Habits, Progress).
public struct LorvexSnapshotEntry: TimelineEntry, Equatable {
  public let date: Date
  public let state: WidgetTimelineEntryState
  /// Age classification of `snapshot` so the Habits and Progress widgets can
  /// flag stale data instead of rendering a day-old snapshot as if current.
  /// `.unknownTimestamp` when there is no snapshot.
  public let freshness: WidgetSnapshotFreshness
  public let statusText: String

  /// `true` for the system-requested placeholder entry (before real data has
  /// loaded), so the entry view can apply `.redacted(reason: .placeholder)`
  /// and read as loading rather than as real (if coincidentally empty) content.
  public let isPlaceholder: Bool

  public init(
    date: Date,
    snapshot: WidgetSnapshot?,
    freshness: WidgetSnapshotFreshness = .unknownTimestamp,
    statusText: String = "",
    isPlaceholder: Bool = false
  ) {
    self.date = date
    state = snapshot.map { .snapshot($0, freshness: freshness) }
      ?? .fallback(
        .init(
          reason: .missingFile,
          detail: String(
            localized: "widget.status.snapshot_unavailable",
            defaultValue: "Snapshot unavailable",
            table: "Localizable",
            bundle: WidgetSupportL10n.bundle)
        )
      )
    self.freshness = freshness
    self.statusText = statusText
    self.isPlaceholder = isPlaceholder
  }

  public init(
    timelineEntry: WidgetTimelineEntry,
    statusText: String,
    isPlaceholder: Bool = false
  ) {
    date = timelineEntry.date
    state = timelineEntry.state
    switch timelineEntry.state {
    case .snapshot(_, let freshness):
      self.freshness = freshness
    case .fallback:
      self.freshness = .unknownTimestamp
    }
    self.statusText = statusText
    self.isPlaceholder = isPlaceholder
  }

  public var snapshot: WidgetSnapshot? {
    state.snapshot
  }

  /// A short age label ("5m ago" / "2h ago" …) once the snapshot is past the
  /// warning threshold, else `nil`. Localized via `WidgetSupportL10n`.
  public var staleAgeLabel: String? {
    freshness.staleAgeLabel()
  }

  public var relevance: TimelineEntryRelevance? {
    guard let snapshot else { return nil }
    return WidgetSmartStackRelevancePolicy.relevance(
      taskCount: snapshot.stats.todayCount,
      date: date,
      timezoneName: snapshot.timezone
    ).map(\.timelineEntryRelevance)
  }
}
