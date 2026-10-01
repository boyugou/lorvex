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
    MobileCalendarAgendaPanel(
      days: agendaDays(dayCount: dayCount, from: start),
      todayKey: store.logicalTodayString,
      nowMinutes: store.nowMinutesInProductDay,
      calendar: calendar,
      isMutating: store.isMutatingCalendarEvent,
      editEvent: { event in
        store.prepareCalendarDraft(for: event)
        editingEvent = event
      },
      deleteEvent: { event in
        // Route a scoped (recurring) delete to the this/future/all dialog, the
        // same as the day column — not the edit sheet. (The agenda panel only
        // invokes this for non-scoped events today, but keep the two delete
        // paths consistent so a future scoped caller behaves correctly.)
        if event.supportsScopedMutation {
          eventAwaitingDeleteScope = event
          return false
        }
        return await store.deleteCalendarEvent(event)
      },
      deleteScopedEvent: { await store.deleteScopedCalendarEvent($0, scope: $1) },
      openTask: { task in
        store.cacheTasks([task])
        store.openTaskRouteOnCurrentStack(task.id)
      },
      taskActions: { store.rowActions(for: $0.id) },
      taskIsMutating: { store.taskIsMutating($0) }
    )
  }

  private func dates(dayCount: Int, from start: Date) -> [Date] {
    (0..<dayCount).map {
      calendar.date(byAdding: .day, value: $0, to: start) ?? start
    }
  }

  /// Events that belong on the agenda for `key` (`yyyy-MM-dd`), ordered for
  /// display. The day filter is a span test mirroring
  /// `CalendarGridModel.buildDays`: a multi-day event appears on every day its
  /// `[startDate, endDate]` range covers, not only its first/last day, so the
  /// agenda panel and the timeline grid never disagree about which day an event
  /// belongs to. `yyyy-MM-dd` keys compare lexicographically in date order; a
  /// missing `endDate` is a single-day event. Ordering puts events without a
  /// start time (all-day) first, then start-time ascending, then title.
  nonisolated static func agendaEvents(
    from events: [CalendarTimelineEvent],
    on key: String
  ) -> [CalendarTimelineEvent] {
    events
      .filter { event in
        let startKey = event.startDate
        let endKey = event.endDate ?? event.startDate
        guard key >= startKey, key <= endKey else { return false }
        // A timed event ending exactly at midnight occupies no time on its end
        // day (22:00→00:00-next-day is a start-day-only event), so don't list it
        // there — matching the day grid and Apple Calendar.
        if key == endKey, endKey != startKey, !event.allDay,
          CalendarGridModel.parseMinutes(event.endTime) == 0
        {
          return false
        }
        return true
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

  func agendaDays(dayCount: Int, from start: Date) -> [MobileCalendarAgendaDay] {
    dates(dayCount: dayCount, from: start).map { date in
      let key = Self.keyFormatter.string(from: date)
      // Keep the wide-layout agenda on the exact same event
      // projection as the time grid. Otherwise an active search empties the
      // grid while this adjacent panel continues to reveal nonmatching event
      // titles, locations, or notes.
      let events = Self.agendaEvents(from: filteredEvents, on: key)
      // Timed tasks read in clock order, ahead of the day's untimed ones.
      let tasks = store.calendarScheduledTasks
        .filter { task in
          CalendarGridModel.scheduledTaskDayKey(task) == key
        }
        .sorted { lhs, rhs in
          let lhsStart = lhs.time(on: key)?.lowerBound ?? Int.max
          let rhsStart = rhs.time(on: key)?.lowerBound ?? Int.max
          if lhsStart != rhsStart { return lhsStart < rhsStart }
          if lhs.priority != rhs.priority { return lhs.priority.rawValue < rhs.priority.rawValue }
          return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
      return MobileCalendarAgendaDay(date: date, key: key, events: events, tasks: tasks)
    }
  }
}
