import LorvexCore
import SwiftUI

/// Native month grid: weeks × 7 day cells honoring the user's calendar (first
/// weekday, current locale), each cell showing a bounded number of event/task
/// chips with a "+N" overflow, leading/trailing days from adjacent months
/// dimmed, and today highlighted.
///
/// Follows the same data-flow and design-token conventions as
/// ``CalendarWeekGridView``: the visible month (`monthAnchor`) drives the
/// data fetch through the caller (`CalendarWorkspaceView`, which loads the
/// grid's exact leading/trailing-day span so a busy month's boundary weeks
/// aren't clipped), the grid renders from `store.filteredCalendarEvents` /
/// `store.filteredScheduledTasks`, and list/event colors resolve the same way
/// the week grid's all-day strip does. Clicking a day cell opens that day (the
/// workspace's existing day/week navigation) — clicking a chip opens that
/// event/task instead.
struct CalendarMonthGridView: View {
  @Bindable var store: AppStore
  let monthAnchor: Date
  let selectEvent: (CalendarTimelineEvent) -> Void
  let openTask: (LorvexTask) -> Void
  /// Navigates the workspace to Day mode anchored at the clicked date.
  let openDay: (Date) -> Void

  /// Reads `@Environment(\.calendar)`, matching `CalendarWeekGridView`, so a
  /// first-weekday / locale change (including mid-session) flows into the
  /// grid layout rather than freezing whatever `Calendar.current` was at the
  /// workspace's init.
  @Environment(\.calendar) private var calendar
  /// Day cell whose overflow "+N" popover is open, threaded into
  /// `CalendarMonthGridDayCell` via `isOverflowPresented` / `onShowOverflow`.
  @State private var overflowDayID: CalendarMonthGridDay.ID? = nil

  static let maxChipsPerDay = CalendarMonthGridModel.defaultMaxChipsPerDay

  private var weeks: [[CalendarMonthGridDay]] {
    let days = CalendarMonthGridModel.buildDays(
      monthAnchor: monthAnchor,
      calendar: calendar,
      events: store.filteredCalendarEvents,
      tasks: store.filteredScheduledTasks,
      dayKeyFor: { AppStore.ymdFormatter.string(from: $0) }
    )
    guard !days.isEmpty else { return [] }
    return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
  }

  var body: some View {
    let weeks = self.weeks
    VStack(spacing: 0) {
      weekdayHeader
      Divider()
      GeometryReader { geo in
        let rowHeight = weeks.isEmpty ? 0 : geo.size.height / CGFloat(weeks.count)
        VStack(spacing: 0) {
          ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
            weekRow(week)
              .frame(height: rowHeight)
          }
        }
      }
    }
    .frame(minHeight: 320)
    .accessibilityIdentifier("calendar.month.grid")
  }

  private var weekdayHeader: some View {
    HStack(spacing: 0) {
      ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
        Text(symbol)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
      }
    }
    .padding(.vertical, CalendarWeekGridMetrics.headerVerticalPadding)
    .accessibilityHidden(true)
  }

  /// Localized weekday abbreviations, rotated to start at
  /// `calendar.firstWeekday` and uppercased to match the week grid's
  /// day-of-week header labels.
  private var weekdaySymbols: [String] {
    let symbols = calendar.shortWeekdaySymbols
    guard symbols.count == 7 else { return symbols.map { $0.uppercased() } }
    let firstIndex = max(0, min(6, calendar.firstWeekday - 1))
    return (Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])).map { $0.uppercased() }
  }

  private func weekRow(_ week: [CalendarMonthGridDay]) -> some View {
    HStack(spacing: 0) {
      ForEach(Array(week.enumerated()), id: \.element.id) { index, day in
        CalendarMonthGridDayCell(
          day: day,
          isToday: calendar.isDateInToday(day.date),
          maxVisibleChips: Self.maxChipsPerDay,
          eventColor: eventColor,
          taskColor: taskColor,
          onSelectEvent: selectEvent,
          onOpenTask: openTask,
          onOpenDay: { openDay(day.date) },
          isOverflowPresented: Binding(
            get: { overflowDayID == day.id },
            set: { if !$0 { overflowDayID = nil } }
          ),
          onShowOverflow: { overflowDayID = day.id }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) {
          if index < week.count - 1 {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
          }
        }
      }
    }
    .overlay(alignment: .bottom) {
      Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
    }
  }

  private func eventColor(_ event: CalendarTimelineEvent) -> Color {
    Color(lorvexHex: event.color) ?? .accentColor
  }

  /// A scheduled-task chip's tint: its owning list's color, resolved live from
  /// the loaded list catalog — the same recipe the week grid's all-day strip
  /// uses. Falls back to secondary for a task with no list or an unloaded
  /// catalog.
  private func taskColor(_ task: LorvexTask) -> Color {
    guard let listID = task.listID,
      let list = store.lists?.lists.first(where: { $0.id == listID }),
      let color = Color(lorvexHex: list.color)
    else { return .secondary }
    return color
  }
}
