import LorvexCore
import SwiftUI

/// Today on a time grid, in the rail beside the column
/// (``TodayPageLayout``): the day's calendar events and its timed tasks drawn
/// to scale, with a line where the clock sits, so free time shows as room
/// between the blocks.
///
/// It is the Calendar workspace's day grid for today
/// (``CalendarWeekGridView``), so everything a block does there it does here:
/// a block moves and resizes by dragging, a task dragged from the column
/// takes the time it is dropped on, and a click or a drag on free time starts
/// a new event. A click on an event or a task opens it in the window's
/// inspector, as its row in the column does. In a window that fits the
/// column, the rail and the inspector side by side, a second click on the
/// block closes it; in a narrower one the inspector stands in the rail's
/// place until it closes (``TodayPageLayout``).
///
/// The column lists every task, so the rail draws only what has a time:
/// all-day events stand in a strip above the grid, and the strip is left out
/// on a day without one.
struct TodayDayRail: View {
  @Bindable var store: AppStore
  @Environment(\.calendar) private var calendar
  @Environment(\.todayEventActions) private var eventActions

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      LorvexPageLabel(TodayCalmCopy.scheduleTitle)
        .padding(.horizontal, LorvexDesign.Spacing.m)
        .padding(.top, LorvexDesign.Spacing.m)
        .padding(.bottom, LorvexDesign.Spacing.s)
      Divider()
      CalendarWeekGridView(
        store: store,
        weekStart: today,
        visibleDayCount: 1,
        selectEvent: { store.toggleTodayEventSelection($0) },
        editEvent: { event in
          guard let eventActions else { return }
          // The inspector shows one subject, so an open task closes first.
          store.selectedTaskID = nil
          eventActions.beginEditing(event, store: store)
        },
        requestDeleteEvent: { eventActions?.requestDelete($0) },
        openTask: { task in
          if store.selectedTaskID == task.id {
            store.selectedTaskID = nil
          } else {
            store.selectOnlyTodayTask(task.id)
          }
        },
        createAt: { date, minutes, duration in
          // The event sheet belongs to the main window, the only place the
          // rail is drawn; without it there is nothing to open.
          guard let eventActions else { return }
          store.prepareCalendarCreateDraft(
            date: date, minutes: minutes, durationMinutes: duration, dayCalendar: calendar)
          eventActions.activeSheet = .create
        },
        showsDayHeader: false,
        hidesEmptyAllDayStrip: true,
        tasks: store.todayTimedTasks
      )
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("today.rail")
  }

  /// The product day as a date in the calendar the grid lays its days out in.
  private var today: Date {
    let anchor =
      PlannedDayBridge.displayDate(
        forLogicalDay: store.logicalTodayDateString, timeZone: calendar.timeZone) ?? Date()
    return calendar.startOfDay(for: anchor)
  }
}
