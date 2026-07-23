import LorvexCore
import SwiftUI

extension MobileCalendarDayView {
  var weekAgendaBody: some View {
    VStack(spacing: 0) {
      weekNavigationHeader
      Divider()
      agendaPanel(dayCount: 7)
    }
  }

  func regularBody(dayCount: Int) -> some View {
    HStack(spacing: 0) {
      dayGrid(dayCount: dayCount)
      Divider()
      agendaPanel(dayCount: dayCount)
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
    }
  }

  private func agendaPanel(dayCount: Int) -> some View {
    MobileCalendarAgendaPanel(
      days: visibleAgendaDays(dayCount: dayCount),
      calendar: calendar,
      isMutating: store.isMutatingCalendarEvent,
      createEvent: {
        let date = defaultCreateDate
        prepareCreate(at: date, minutes: defaultCreateMinutes(on: date))
      },
      editEvent: { event in
        store.prepareCalendarDraft(for: event)
        editingEvent = event
      },
      deleteEvent: { event in
        if event.supportsScopedMutation {
          store.prepareCalendarDraft(for: event)
          editingEvent = event
          return false
        }
        return await store.deleteCalendarEvent(event)
      },
      deleteScopedEvent: { await store.deleteScopedCalendarEvent($0, scope: $1) },
      openTask: { task in
        store.cacheTasks([task])
        store.openNavigationTarget(
          MobileNavigationTarget(selectedTab: .today, route: .task(task.id))
        )
      }
    )
  }

  private func visibleDates(dayCount: Int) -> [Date] {
    (0..<dayCount).map {
      calendar.date(byAdding: .day, value: $0, to: visibleDate) ?? visibleDate
    }
  }

  /// Events that belong on the agenda for `key` (`yyyy-MM-dd`), ordered for
  /// display. The day filter is a span test mirroring
  /// `CalendarGridModel.buildDays`: a multi-day event appears on every day its
  /// `[startDate, endDate]` range covers, not only its first/last day, so the
  /// agenda panel and the timeline grid never disagree about which day an event
  /// belongs to. `yyyy-MM-dd` keys compare lexicographically in date order; a
  /// missing `endDate` is a single-day event. Ordering is start-time ascending
  /// (timed before untimed), then title.
  nonisolated static func agendaEvents(
    from events: [CalendarTimelineEvent],
    on key: String
  ) -> [CalendarTimelineEvent] {
    events
      .filter { event in
        let startKey = event.startDate
        let endKey = event.endDate ?? event.startDate
        return key >= startKey && key <= endKey
      }
      .sorted { lhs, rhs in
        switch (lhs.startTime, rhs.startTime) {
        case (let left?, let right?) where left != right:
          left < right
        case (nil, _?):
          true
        case (_?, nil):
          false
        default:
          lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
      }
  }

  func visibleAgendaDays(dayCount: Int) -> [MobileCalendarAgendaDay] {
    visibleDates(dayCount: dayCount).map { date in
      let key = Self.keyFormatter.string(from: date)
      // Keep the grouped week / wide-layout agenda on the exact same event
      // projection as the time grid. Otherwise an active search empties the
      // grid while this adjacent panel continues to reveal nonmatching event
      // titles, locations, or notes.
      let events = Self.agendaEvents(from: filteredEvents, on: key)
      let tasks = store.calendarScheduledTasks
        .filter { task in
          CalendarGridModel.scheduledTaskDayKey(task) == key
        }
        .sorted { lhs, rhs in
          if lhs.priority != rhs.priority { return lhs.priority.rawValue < rhs.priority.rawValue }
          return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
      return MobileCalendarAgendaDay(date: date, events: events, tasks: tasks)
    }
  }
}
