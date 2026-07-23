import Foundation
import LorvexWidgetKitSupport

/// Maps a `WidgetSnapshotLoadResult` to a `LorvexWatchComplicationEntry`.
///
/// Pure function — the testable core of the complication provider. The entry
/// carries the next actionable-focus task title plus the actionable-task count for
/// per-family layouts.
public enum LorvexWatchComplicationEntryMapper {

  public static func entry(
    from result: WidgetSnapshotLoadResult,
    at date: Date = Date()
  ) -> LorvexWatchComplicationEntry {
    let presentation = FocusGlancePresentation.resolve(from: result, now: date)
    switch presentation.availability {
    case .content:
      let count = presentation.actionableCount
      return LorvexWatchComplicationEntry(
        date: date,
        taskTitle: presentation.primaryTask?.title,
        statusText: statusText(taskCount: count),
        openFocusCount: count,
        availability: .content,
        primaryPriorityTier: presentation.primaryTask?.priority,
        timezoneName: presentation.timezoneName
      )
    case .empty:
      return LorvexWatchComplicationEntry(
        date: date,
        taskTitle: nil,
        statusText: String(
          localized: "watch.complication.no_focus", defaultValue: "No focus",
          table: "Localizable", bundle: WatchL10n.bundle),
        openFocusCount: 0,
        availability: .empty,
        timezoneName: presentation.timezoneName
      )
    case .unavailable:
      return LorvexWatchComplicationEntry(
        date: date,
        taskTitle: nil,
        statusText: String(
          localized: "watch.status.unavailable", defaultValue: "Snapshot unavailable",
          table: "Localizable", bundle: WatchL10n.bundle),
        openFocusCount: 0,
        availability: .unavailable
      )
    }
  }

  // MARK: - Helpers

  private static func statusText(taskCount: Int) -> String {
    switch taskCount {
    case 0:
      String(
        localized: "watch.complication.no_focus", defaultValue: "No focus",
        table: "Localizable", bundle: WatchL10n.bundle)
    case 1:
      String(
        localized: "watch.complication.one_task", defaultValue: "1 focus task",
        table: "Localizable", bundle: WatchL10n.bundle)
    default:
      String(
        localized: "watch.complication.tasks", defaultValue: "\(taskCount) tasks",
        table: "Localizable", bundle: WatchL10n.bundle)
    }
  }
}
