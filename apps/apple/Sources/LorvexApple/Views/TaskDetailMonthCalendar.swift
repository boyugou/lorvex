import LorvexCore
import SwiftUI

private enum TaskDetailMonthCalendarMetrics {
  static let cellSize: CGFloat = 32
  static let weeks = 6
}

/// A month of days for picking one date: the month's name with arrows to page
/// between months, the weekday initials, and six weeks of round day cells.
/// The chosen day is a filled accent circle, today's number is accent-colored,
/// and days of the neighbouring months are dimmed but still pickable. It
/// opens on the month of `selection` (today's month when nil) and follows
/// `selection` to its month when it changes from outside, such as a preset.
/// `onPick` receives the clicked day's local midnight.
struct TaskDetailMonthCalendar: View {
  let selection: Date?
  let onPick: (Date) -> Void

  @State private var month: Date?

  private var calendar: Calendar { .autoupdatingCurrent }

  private var shownMonth: Date { month ?? monthStart(of: selection ?? .now) }

  var body: some View {
    VStack(spacing: LorvexDesign.Spacing.xs) {
      header
      Grid(horizontalSpacing: 2, verticalSpacing: 2) {
        GridRow {
          ForEach(weekdayInitials.indices, id: \.self) { index in
            Text(weekdayInitials[index])
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
              .frame(width: TaskDetailMonthCalendarMetrics.cellSize)
              .accessibilityHidden(true)
          }
        }
        ForEach(0..<TaskDetailMonthCalendarMetrics.weeks, id: \.self) { week in
          GridRow {
            ForEach(days(inWeek: week), id: \.self) { day in
              TaskDetailMonthDayCell(
                day: day,
                isSelected: selection.map { calendar.isDate($0, inSameDayAs: day) } ?? false,
                isToday: calendar.isDateInToday(day),
                isInMonth: calendar.isDate(day, equalTo: shownMonth, toGranularity: .month)
              ) { onPick(day) }
            }
          }
        }
      }
    }
    .onChange(of: selection) { _, newValue in
      guard let newValue else { return }
      month = monthStart(of: newValue)
    }
  }

  private var header: some View {
    HStack(spacing: 0) {
      Text(shownMonth.formatted(.dateTime.month(.wide).year()))
        .font(LorvexDesign.Typography.primaryEmphasis)
        .padding(.leading, LorvexDesign.Spacing.xs)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: LorvexDesign.Spacing.s)
      LorvexIconButton(
        systemImage: "chevron.left",
        label: String(
          localized: "task_detail.picker.previous_month_a11y", defaultValue: "Previous Month",
          table: "Localizable", bundle: LorvexL10n.bundle),
        accessibilityIdentifier: "task.detail.calendar.previous"
      ) { page(by: -1) }
      LorvexIconButton(
        systemImage: "chevron.right",
        label: String(
          localized: "task_detail.picker.following_month_a11y", defaultValue: "Following Month",
          table: "Localizable", bundle: LorvexL10n.bundle),
        accessibilityIdentifier: "task.detail.calendar.next"
      ) { page(by: 1) }
    }
  }

  /// The very short weekday names, starting from the calendar's first weekday.
  private var weekdayInitials: [String] {
    let symbols = calendar.veryShortStandaloneWeekdaySymbols
    let first = calendar.firstWeekday - 1
    return Array(symbols[first...] + symbols[..<first])
  }

  /// The seven days of the `week`th row: rows start on the first weekday on
  /// or before the first of the shown month.
  private func days(inWeek week: Int) -> [Date] {
    let start = shownMonth
    let lead = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
    return (0..<7).compactMap { column in
      calendar.date(byAdding: .day, value: week * 7 + column - lead, to: start)
    }
  }

  private func monthStart(of date: Date) -> Date {
    calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
  }

  private func page(by months: Int) {
    withAnimation(.snappy(duration: 0.2)) {
      month = calendar.date(byAdding: .month, value: months, to: shownMonth)
    }
  }
}

/// One day of ``TaskDetailMonthCalendar``: its number in a circle that fills
/// with the accent when chosen and faintly under the pointer.
private struct TaskDetailMonthDayCell: View {
  let day: Date
  let isSelected: Bool
  let isToday: Bool
  let isInMonth: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      // The bare day number: `.dateTime.day()` reads "1日" in Chinese, which a
      // month grid never shows.
      Text(Calendar.autoupdatingCurrent.component(.day, from: day), format: .number.grouping(.never))
        .font(
          LorvexDesign.Typography.secondaryText.monospacedDigit()
            .weight(isSelected || isToday ? .semibold : .regular)
        )
        .foregroundStyle(numberStyle)
        .frame(width: TaskDetailMonthCalendarMetrics.cellSize, height: TaskDetailMonthCalendarMetrics.cellSize)
        .background(Circle().fill(fillStyle))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var numberStyle: AnyShapeStyle {
    if isSelected { return AnyShapeStyle(.white) }
    if isToday { return AnyShapeStyle(LorvexDesign.Palette.accent) }
    return isInMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
  }

  private var fillStyle: AnyShapeStyle {
    if isSelected { return AnyShapeStyle(LorvexDesign.Palette.accent) }
    return AnyShapeStyle(.quaternary.opacity(isHovering ? 1 : 0))
  }
}
