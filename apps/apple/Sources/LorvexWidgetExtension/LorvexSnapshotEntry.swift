import Foundation
import LorvexWidgetKitSupport
import WidgetKit

/// A timeline entry that carries the raw `WidgetSnapshot` (or nil on fallback) for widgets
/// that render directly from snapshot fields rather than through `WidgetRenderModel`.
public struct LorvexSnapshotEntry: TimelineEntry, Equatable {
  public let date: Date
  public let state: WidgetTimelineEntryState
  /// Age classification of `snapshot` so the Today/Habits/Progress widgets can
  /// flag stale data instead of rendering a day-old snapshot as if current.
  /// `.unknownTimestamp` when there is no snapshot.
  public let freshness: WidgetSnapshotFreshness
  public let statusText: String
  public let todayWidgetViewMode: LorvexTodayWidgetViewMode
  public let todayWidgetListID: String?

  /// `true` for the system-requested placeholder entry (before real data has
  /// loaded), so the entry view can apply `.redacted(reason: .placeholder)`
  /// and read as loading rather than as real (if coincidentally empty) content.
  public let isPlaceholder: Bool

  public init(
    date: Date,
    snapshot: WidgetSnapshot?,
    freshness: WidgetSnapshotFreshness = .unknownTimestamp,
    statusText: String = "",
    todayWidgetViewMode: LorvexTodayWidgetViewMode = .today,
    todayWidgetListID: String? = nil,
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
    self.todayWidgetViewMode = todayWidgetViewMode
    self.todayWidgetListID = todayWidgetListID
    self.isPlaceholder = isPlaceholder
  }

  public init(
    timelineEntry: WidgetTimelineEntry,
    statusText: String,
    todayWidgetViewMode: LorvexTodayWidgetViewMode = .today,
    todayWidgetListID: String? = nil,
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
    self.todayWidgetViewMode = todayWidgetViewMode
    self.todayWidgetListID = todayWidgetListID
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
    // De-dupe by id: a task that is both due today and in the actionable focus
    // queue must count once, or the Smart Stack relevance score is inflated.
    let dueTodayIDs = Set(snapshot.todayTasks.map(\.id))
    let actionableFocusIDs = Set(snapshot.actionableFocusTasks.map(\.id))
    let count = dueTodayIDs.union(actionableFocusIDs).count
    return WidgetSmartStackRelevancePolicy.relevance(
      taskCount: count,
      date: date,
      timezoneName: snapshot.timezone
    ).map(\.timelineEntryRelevance)
  }
}
