import LorvexCore
import SwiftUI

/// How a month-grid day cell shows the day's entries: as marks under the day
/// number where the cell is small (a phone), or as titled chips where it is
/// tall and wide enough (an iPad), as many as fit, with "+N" for the rest.
enum MobileCalendarMonthCellStyle: Equatable {
  case marks
  case titled(maxChips: Int)
}

/// One month of the month grid: its weeks as rows of seven day cells
/// (``MobileCalendarMonthDayCell``), with a hairline over each row and,
/// where the cells name their entries, between the days. Every cell takes
/// one style, chosen from the cell size
/// (``cellStyle(rowHeight:cellWidth:dayNumberSize:chipHeight:)``).
struct MobileCalendarMonthGrid: View {
  /// The grid's days, whole weeks in order.
  let days: [CalendarMonthGridDay]
  /// The logical today as `yyyy-MM-dd`.
  let todayKey: String
  /// The chosen day as `yyyy-MM-dd`.
  let selectedKey: String
  let calendar: Calendar
  let choose: (CalendarMonthGridDay) -> Void
  let openEvent: (CalendarTimelineEvent) -> Void
  let openTask: (LorvexTask) -> Void
  /// Creates an event on the day.
  let createEvent: (Date) -> Void
  /// Plans the dropped tasks on the day.
  let dropTasks: ([LorvexTaskRef], Date) -> Void
  @ScaledMetric(relativeTo: .subheadline) private var dayNumberSize: CGFloat = 28
  @ScaledMetric(relativeTo: .caption2) private var chipHeight: CGFloat = 17
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    GeometryReader { geo in
      let weeks = max(1, days.count / 7)
      let rowHeight = geo.size.height / CGFloat(weeks)
      let style = Self.cellStyle(
        rowHeight: rowHeight, cellWidth: geo.size.width / 7, dayNumberSize: dayNumberSize,
        chipHeight: chipHeight)
      // A short row (a phone on its side) shrinks the circle to keep the
      // marks under it in the row.
      let numberSize = min(dayNumberSize, max(20, rowHeight - 14))
      VStack(spacing: 0) {
        ForEach(0..<weeks, id: \.self) { week in
          HStack(spacing: 0) {
            ForEach(week * 7..<min(week * 7 + 7, days.count), id: \.self) { index in
              cell(days[index], style: style, numberSize: numberSize)
                .overlay(alignment: .leading) {
                  if case .titled = style, index % 7 != 0 {
                    Rectangle().fill(.separator).frame(width: 1 / displayScale)
                  }
                }
            }
          }
          .frame(maxHeight: .infinity)
          .overlay(alignment: .top) {
            Rectangle().fill(.separator).frame(height: 1 / displayScale)
          }
        }
      }
    }
  }

  private func cell(
    _ day: CalendarMonthGridDay, style: MobileCalendarMonthCellStyle, numberSize: CGFloat
  ) -> some View {
    MobileCalendarMonthDayCell(
      day: day,
      isToday: day.dayKey == todayKey,
      isSelected: day.dayKey == selectedKey,
      style: style,
      dayNumberSize: numberSize,
      chipHeight: chipHeight,
      calendar: calendar,
      choose: { choose(day) },
      openEvent: openEvent,
      openTask: openTask,
      createEvent: { createEvent(day.date) },
      dropTasks: { dropTasks($0, day.date) })
  }

  /// The style every cell of a grid takes: `.titled` where a cell is at least
  /// 72 points wide and holds its day number and two chips, with as many
  /// chips as its height holds; `.marks` otherwise.
  nonisolated static func cellStyle(
    rowHeight: CGFloat, cellWidth: CGFloat, dayNumberSize: CGFloat, chipHeight: CGFloat
  ) -> MobileCalendarMonthCellStyle {
    let room = rowHeight - MobileCalendarMonthDayCell.titledInsets - dayNumberSize
    let chips = Int((room / (chipHeight + MobileCalendarMonthDayCell.chipSpacing)).rounded(.down))
    guard cellWidth >= 72, chips >= 2 else { return .marks }
    return .titled(maxChips: chips)
  }
}
