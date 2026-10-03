import LorvexCore
import SwiftUI

extension MobileCalendarDayView {
  func regularBody(dayCount: Int) -> some View {
    HStack(spacing: 0) {
      dayGrid(dayCount: dayCount)
      Divider()
      agendaPanel(dayCount: dayCount, start: visibleDate)
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
    }
  }

  private func agendaPanel(dayCount: Int, start: Date) -> some View {
    MobileStoreCalendarAgenda(
      store: store,
      days: agendaDays(dayCount: dayCount, from: start),
      calendar: calendar,
      editEvent: { editingEvent = $0 },
      requestScopedDelete: { eventAwaitingDeleteScope = $0 })
  }

  private func dates(dayCount: Int, from start: Date) -> [Date] {
    (0..<dayCount).map {
      calendar.date(byAdding: .day, value: $0, to: start) ?? start
    }
  }

  /// The agenda days of the `dayCount` days from `start`. Their events are
  /// the grid's own search-filtered ones, so an active search never leaves
  /// the agenda showing the titles, locations, or notes of events the grid
  /// beside it has filtered out.
  func agendaDays(dayCount: Int, from start: Date) -> [MobileCalendarAgendaDay] {
    MobileCalendarAgendaDay.days(
      for: dates(dayCount: dayCount, from: start), events: filteredEvents,
      tasks: store.calendarScheduledTasks, keyFor: { Self.keyFormatter.string(from: $0) })
  }
}
