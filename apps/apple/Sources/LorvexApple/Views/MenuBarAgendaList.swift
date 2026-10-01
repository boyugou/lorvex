import LorvexCore
import SwiftUI

/// The menu bar panel's Next 7 Days body: each day ahead that has something
/// on it, under its name ("Tomorrow", then "Saturday, October 3"), with its
/// events (a bar in the calendar's color, the title, the time) and then its
/// tasks (the circle that completes it, the title that opens it, its time).
/// A free week reads one line saying so.
struct MenuBarAgendaList: View {
  let days: [LorvexAgendaDay]
  /// The logical today as `yyyy-MM-dd`, which names tomorrow.
  let todayKey: String
  let complete: (LorvexTask) -> Void
  let open: (LorvexTask) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
      if days.isEmpty {
        Text(MenuBarCopy.weekEmpty)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("menubar.agenda.empty")
      }
      ForEach(days) { day in
        VStack(alignment: .leading, spacing: 0) {
          Text(MenuBarCopy.dayTitle(day.key, todayKey: todayKey))
            .font(LorvexDesign.Typography.pageLabel)
            .foregroundStyle(.secondary)
            .padding(.bottom, LorvexDesign.Spacing.xxs)
            .accessibilityAddTraits(.isHeader)
          ForEach(day.events) { eventRow($0) }
          ForEach(day.tasks) { taskRow($0, dayKey: day.key) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menubar.agenda.day")
      }
    }
  }

  private func eventRow(_ event: CalendarTimelineEvent) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Capsule()
        .fill(Color(lorvexHex: event.color) ?? LorvexDesign.Palette.neutral)
        .frame(width: 3, height: 14)
        .frame(width: 18)
        .accessibilityHidden(true)
      Text(event.title)
        .font(LorvexDesign.Typography.primaryText)
        .lineLimit(1)
      Spacer(minLength: 0)
      Text(eventTime(event))
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
    }
    .frame(minHeight: 28)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("menubar.agenda.event")
  }

  private func taskRow(_ task: LorvexTask, dayKey: String) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Button {
        complete(task)
      } label: {
        LorvexTaskRing(progress: 0, isDone: false, diameter: 18, showsCheckHint: false)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .help(TodayCalmCopy.complete)
      .accessibilityLabel(MenuBarCopy.complete(task.title))
      Button {
        open(task)
      } label: {
        HStack(spacing: LorvexDesign.Spacing.s) {
          Text(task.title)
            .font(LorvexDesign.Typography.primaryText)
            .foregroundStyle(.primary)
            .lineLimit(1)
          Spacer(minLength: 0)
          if let time = task.time(on: dayKey) {
            Text(TodayCalmCopy.timeRange(start: time.lowerBound, end: time.upperBound))
              .font(LorvexDesign.Typography.secondaryText)
              .foregroundStyle(.secondary)
              .monospacedDigit()
              .lineLimit(1)
          }
        }
        .frame(minHeight: 28)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(TodayCalmCopy.openDetails)
    }
    .accessibilityIdentifier("menubar.agenda.task")
  }

  /// An event's time on the agenda: "All day", or its range.
  private func eventTime(_ event: CalendarTimelineEvent) -> String {
    guard !event.allDay, let start = CalendarGridModel.parseMinutes(event.startTime) else {
      return TodayCalmCopy.allDay
    }
    return TodayCalmCopy.timeRange(start: start, end: CalendarGridModel.parseMinutes(event.endTime))
  }
}

/// The menu bar panel's own words.
enum MenuBarCopy {
  static var overdue: String {
    String(localized: "menubar.section.overdue", defaultValue: "Overdue", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  static var today: String {
    String(localized: "menubar.section.today", defaultValue: "Today", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  static var habits: String {
    String(localized: "menubar.section.habits", defaultValue: "Habits", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  static var checkIn: String {
    String(localized: "menubar.habit.check_in", defaultValue: "Check In", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  static var weekEmpty: String {
    String(
      localized: "menubar.agenda.empty", defaultValue: "Nothing planned for the next 7 days.",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  static func complete(_ title: String) -> String {
    String(
      format: String(
        localized: "menubar.now.complete_a11y", defaultValue: "Complete %@", table: "Localizable",
        bundle: LorvexL10n.bundle),
      title)
  }

  /// "Tomorrow" for the day after `todayKey`, else the day spelled out
  /// ("Saturday, October 3").
  static func dayTitle(_ key: String, todayKey: String) -> String {
    if key == LorvexDateFormatters.ymdUTCAddingDays(todayKey, days: 1) {
      return String(
        localized: "menubar.agenda.tomorrow", defaultValue: "Tomorrow", table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    return lorvexDayLine(logicalDay: key)
  }
}
