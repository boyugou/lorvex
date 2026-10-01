import Foundation
import LorvexCore

/// Representative, localized content for WidgetKit's gallery snapshots.
///
/// Gallery previews must not depend on an App Group file already existing: a
/// person often sees the gallery before launching Lorvex for the first time.
/// This sample exercises the Today, progress, and habit layouts while remaining
/// visibly separate from the redacted loading placeholder. The lead task's
/// saved time is placed around `now` — it started twenty minutes ago and has
/// twenty-five to go — so the gallery shows its ring mid-fill; the rows after
/// it show a started task, an estimate, and an overdue task.
public enum WidgetPreviewSnapshot {
  public static func make(
    now: Date = Date(),
    listID: String? = nil
  ) -> WidgetSnapshot {
    let calendar = Calendar.autoupdatingCurrent
    let nowMinutes = WidgetTodayGlance.minutes(at: now, timezoneName: nil, calendar: calendar)
    let today = LorvexDateFormatters.ymd.string(from: now)
    let yesterday = LorvexDateFormatters.ymd.string(
      from: calendar.date(byAdding: .day, value: -1, to: now) ?? now)

    func task(
      _ id: String, _ title: String, status: LorvexTask.Status = .open, due: String? = nil,
      priority: Int? = nil, minutes: Int? = nil, start: String? = nil, end: String? = nil
    ) -> WidgetSnapshot.TodayTask {
      WidgetSnapshot.TodayTask(
        id: id, title: title, status: status.rawValue, dueDate: due, priority: priority,
        listID: listID, estimatedMinutes: minutes, scheduledStart: start, scheduledEnd: end)
    }

    let tasks = [
      task(
        "widget-preview-spec",
        String(
          localized: "widget.control.preview.task_title", defaultValue: "Review spec",
          table: "Localizable", bundle: WidgetSupportL10n.bundle),
        status: .inProgress, due: today, priority: 1, minutes: 45,
        start: clockString(nowMinutes - 20), end: clockString(nowMinutes + 25)),
      task(
        "widget-preview-feedback",
        String(
          localized: "widget.preview.task.feedback", defaultValue: "Answer design feedback",
          table: "Localizable", bundle: WidgetSupportL10n.bundle),
        status: .inProgress, priority: 2),
      task(
        "widget-preview-passport",
        String(
          localized: "widget.preview.task.passport", defaultValue: "Renew passport",
          table: "Localizable", bundle: WidgetSupportL10n.bundle),
        due: yesterday, priority: 2),
      task(
        "widget-preview-flights",
        String(
          localized: "widget.preview.task.flights", defaultValue: "Book flights",
          table: "Localizable", bundle: WidgetSupportL10n.bundle),
        priority: 3, minutes: 30),
    ]
    let stats = WidgetSnapshot.Stats(
      todayCount: tasks.count, overdueCount: 1, dueTodayCount: 1, completedTodayCount: 2)

    return WidgetSnapshot(
      generatedAt: LorvexDateFormatters.iso8601.string(from: now),
      timezone: TimeZone.current.identifier,
      logicalDay: WidgetSnapshotProjector.localDateOnlyString(from: now, calendar: calendar),
      stats: stats,
      briefing: String(
        localized: "widget.preview.briefing",
        defaultValue: "The spec review matters most today; the flights can wait until Thursday.",
        table: "Localizable", bundle: WidgetSupportL10n.bundle),
      tasks: tasks,
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
      listStats: listID.map { [.init(id: $0, stats: stats)] } ?? []
    )
  }

  /// `HH:mm` for minutes since midnight, clamped to the day.
  static func clockString(_ minutes: Int) -> String {
    let clamped = min(max(minutes, 0), 24 * 60 - 1)
    return String(format: "%02d:%02d", clamped / 60, clamped % 60)
  }
}
