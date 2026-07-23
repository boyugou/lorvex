import Foundation
import LorvexCore

/// Representative, localized content for WidgetKit's gallery snapshots.
///
/// Gallery previews must not depend on an App Group file already existing: a
/// person often sees the gallery before launching Lorvex for the first time.
/// This sample exercises the focus, Today, progress, and habit layouts while
/// remaining visibly separate from the redacted loading placeholder.
public enum WidgetPreviewSnapshot {
  public static func make(
    now: Date = Date(),
    listID: String? = nil
  ) -> WidgetSnapshot {
    let taskID = "widget-preview-focus"
    let taskTitle = String(
      localized: "widget.control.preview.task_title",
      defaultValue: "Review spec",
      table: "Localizable",
      bundle: WidgetSupportL10n.bundle
    )

    return WidgetSnapshot(
      generatedAt: LorvexDateFormatters.iso8601.string(from: now),
      timezone: TimeZone.current.identifier,
      logicalDay: WidgetSnapshotProjector.localDateOnlyString(
        from: now,
        calendar: .autoupdatingCurrent
      ),
      stats: .init(
        focusCount: 1,
        overdueCount: 0,
        dueTodayCount: 1,
        completedTodayCount: 2
      ),
      briefing: String(
        localized: "widget.placeholder.ready",
        defaultValue: "Lorvex is ready.",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle
      ),
      focusTasks: [
        .init(
          id: taskID,
          title: taskTitle,
          status: LorvexTask.Status.inProgress.rawValue,
          dueDate: LorvexDateFormatters.ymd.string(from: now),
          priority: 1,
          listID: listID,
          estimatedMinutes: 30
        )
      ],
      habits: [
        .init(
          id: "widget-preview-habit",
          name: String(
            localized: "widget.habits.name",
            defaultValue: "Habits",
            table: "Localizable",
            bundle: WidgetSupportL10n.bundle
          ),
          icon: "checkmark.circle",
          completedToday: 1,
          target: 2
        )
      ],
      todayTasks: [
        .init(
          id: taskID,
          title: taskTitle,
          dueDate: LorvexDateFormatters.ymd.string(from: now),
          priority: 1,
          estimatedMinutes: 30,
          listID: listID
        )
      ],
      listStats: listID.map {
        [.init(id: $0, stats: .init(
          focusCount: 1,
          overdueCount: 0,
          dueTodayCount: 1,
          completedTodayCount: 2
        ))]
      } ?? []
    )
  }
}
