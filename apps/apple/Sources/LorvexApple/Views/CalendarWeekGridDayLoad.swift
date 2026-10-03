import LorvexCore
import SwiftUI

/// The week's load behind the grid header: under each day number, how much of
/// the working window that day's meetings and tasks already take (a timed
/// task counts its time, any other task its estimate), or the overrun in the
/// overdue tint when the day holds more than the window; and in the week that
/// holds today, which days are already past. It is the same arithmetic as the
/// iPhone Plan strip and Today's overrun headline, so the three surfaces agree
/// on which day is full.
extension CalendarWeekGridView {
  /// The load of the visible columns, one day per column in column order,
  /// measured against the stored working hours.
  func weekLoad(_ columns: [CalendarGridDay]) -> LorvexWeekLoad {
    let workStart =
      store.workdayStartMinutes
      ?? WorkingHoursPreference.minutesOfDay(WorkingHoursPreference.defaultWindow.start) ?? 8 * 60
    let workEnd =
      store.workdayEndMinutes
      ?? WorkingHoursPreference.minutesOfDay(WorkingHoursPreference.defaultWindow.end) ?? 18 * 60
    return LorvexWeekLoad.build(
      days: columns.map { day in
        LorvexWeekLoad.DayInput(
          key: day.dayKey,
          // A timed event of a day or more sits in the all-day strip but still
          // takes the day's hours, as Today counts it.
          events: day.timedBlocks.map(\.event) + day.allDayEvents.filter { !$0.allDay },
          tasks: day.scheduledTasks + day.taskBlocks.map(\.task))
      },
      todayKey: store.logicalTodayDateString,
      workStart: workStart,
      workEnd: max(workEnd, workStart + 60),
      nowMinutes: store.nowMinutesInProductDay)
  }
}

/// A day's load under its number in the week header. A day that fits its day
/// hours shows a short bar filled by the share of them its meetings and tasks
/// take (for today, the share of the hours still ahead); a day that runs past
/// them says by how much, in the overdue tint. Either way the full sentence
/// ("4 hr 35 min planned, 10 hr 25 min free") is the column's tooltip and
/// what VoiceOver reads. A day with nothing on it has no caption, since its
/// empty column already says so.
enum CalendarWeekDayLoadCaption: Equatable {
  case busy(minutes: Int, freeMinutes: Int)
  case over(minutes: Int)

  /// The caption for one day of the week's load, or nil for a day with
  /// nothing on it.
  init?(_ day: LorvexWeekLoad.Day) {
    if day.overMinutes > 0 {
      self = .over(minutes: day.overMinutes)
    } else {
      let total = day.meetingMinutes + day.taskMinutes
      guard total > 0 else { return nil }
      self = .busy(minutes: total, freeMinutes: day.freeMinutes)
    }
  }

  /// How much of the bar fills, 0...1: the planned share of planned plus free
  /// time, and all of it for a day that runs over.
  var fill: Double {
    switch self {
    case .busy(let minutes, let free):
      return minutes + free > 0 ? Double(minutes) / Double(minutes + free) : 1
    case .over:
      return 1
    }
  }

  /// The words shown under the day number: only the overrun, which the bar
  /// alone could not size.
  var visibleText: String? {
    guard case .over(let minutes) = self else { return nil }
    return String(
      localized: "calendar.week.load.over",
      defaultValue: "\(LorvexDurationFormat.hoursAndMinutes(minutes)) over",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// The full sentence for the tooltip and VoiceOver.
  var sentence: String {
    switch self {
    case .busy(let minutes, let free):
      return String(
        localized: "calendar.week.load.sentence",
        defaultValue: "\(LorvexDurationFormat.hoursAndMinutes(minutes)) planned, \(LorvexDurationFormat.hoursAndMinutes(free)) free",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .over(let minutes):
      return String(
        localized: "calendar.week.load.over_sentence",
        defaultValue: "\(LorvexDurationFormat.hoursAndMinutes(minutes)) more than your day hours hold",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  var isOver: Bool {
    if case .over = self { return true }
    return false
  }

  /// What VoiceOver says for a day without a caption, whose empty column is
  /// not read aloud.
  static var nothingPlanned: String {
    String(
      localized: "calendar.week.load.nothing_planned", defaultValue: "Nothing planned",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }
}

/// The line under a day number in the week header: the overrun in words, or
/// the load bar, on a line as tall as a caption so every column's number
/// stays level whether or not its day has anything planned. A past day's bar
/// takes the secondary style, as its number does.
struct CalendarWeekDayLoadLine: View {
  let caption: CalendarWeekDayLoadCaption?
  let isPast: Bool

  @ScaledMetric(relativeTo: .caption) private var barWidth: CGFloat = 36
  @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 4

  var body: some View {
    // A blank caption holds the line's height for every column.
    Text(caption?.visibleText ?? " ")
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(LorvexDesign.Palette.overdue)
      .lineLimit(1)
      .overlay {
        if let caption, caption.visibleText == nil {
          Capsule()
            .fill(.quaternary)
            .frame(width: barWidth, height: barHeight)
            .overlay(alignment: .leading) {
              Capsule()
                .fill(isPast ? AnyShapeStyle(.secondary) : AnyShapeStyle(LorvexDesign.Palette.accent))
                .frame(width: max(barHeight, barWidth * caption.fill), height: barHeight)
            }
        }
      }
      .help(caption?.sentence ?? "")
  }
}
