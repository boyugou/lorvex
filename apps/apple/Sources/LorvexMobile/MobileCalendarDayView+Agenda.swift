import LorvexCore
import SwiftUI

extension MobileCalendarDayView {
  var weekAgenda: some View {
    let days = agendaDays(dayCount: 7, from: visibleDate)
    let focus = Self.keyFormatter.string(from: modeSwitchDay)
    let loaded = store.calendarTimeline.map { window in
      days.first.map { $0.key >= window.from } == true
        && days.last.map { $0.key <= window.to } == true
    } ?? false
    return ScrollViewReader { reader in
      MobileStoreCalendarAgenda(
        store: store, days: days, calendar: calendar, pinnedDayKey: focus, placement: .under,
        selectDay: { day in weekDayIndex = Self.dayIndexInWeek(of: day, calendar: calendar) },
        editEvent: { editingEvent = $0 })
        .onChange(of: loaded, initial: true) { _, ready in
          // Open the current week at its focused day. Earlier sections stay
          // within reach. A different week opens at its first listed day.
          if ready, dayOffset == 0 { reader.scrollTo(focus, anchor: .top) }
        }
    }
    .id(visibleDate)
  }

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
      editEvent: { editingEvent = $0 })
  }

  private func dates(dayCount: Int, from start: Date) -> [Date] {
    (0..<dayCount).map {
      calendar.date(byAdding: .day, value: $0, to: start) ?? start
    }
  }

  /// The agenda days of the `dayCount` days from `start`.
  func agendaDays(dayCount: Int, from start: Date) -> [MobileCalendarAgendaDay] {
    MobileCalendarAgendaDay.days(
      for: dates(dayCount: dayCount, from: start), events: loadedEvents,
      tasks: store.calendarScheduledTasks, keyFor: { Self.keyFormatter.string(from: $0) })
  }
}
