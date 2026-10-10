import LorvexCore
import SwiftUI

/// The calendar's agenda bound to the store: ``MobileCalendarAgendaPanel``
/// over `days` with the store's event and task actions, and the Blocked marks
/// it reads for the loaded window's scheduled tasks. The view hosting it owns
/// the event edit sheet, which `editEvent` raises, so an event opened from the
/// agenda and one opened from the grid beside it share it. Each agenda row asks
/// before it deletes its event.
struct MobileStoreCalendarAgenda: View {
  @Bindable var store: MobileStore
  let days: [MobileCalendarAgendaDay]
  let calendar: Calendar
  /// A day as `yyyy-MM-dd` listed even when it is free (see
  /// ``MobileCalendarAgendaPanel/pinnedDayKey``).
  var pinnedDayKey: String? = nil
  var placement: MobileCalendarAgendaPanel.Placement = .beside
  /// Opens `event` in the host's edit sheet.
  let editEvent: (CalendarTimelineEvent) -> Void
  @State private var blockedTaskIDs: Set<LorvexTask.ID> = []

  var body: some View {
    MobileCalendarAgendaPanel(
      days: days,
      todayKey: store.logicalTodayString,
      pinnedDayKey: pinnedDayKey,
      placement: placement,
      nowMinutes: store.nowMinutesInProductDay,
      calendar: calendar,
      isMutating: store.isMutatingCalendarEvent,
      editEvent: { event in
        store.prepareCalendarDraft(for: event)
        editEvent(event)
      },
      deleteEvent: { await store.deleteCalendarEvent($0) },
      deleteScopedEvent: { await store.deleteScopedCalendarEvent($0, scope: $1) },
      openTask: { task in
        store.cacheTasks([task])
        store.openTaskRouteOnCurrentStack(task.id)
      },
      taskActions: { store.rowActions(for: $0.id) },
      taskIsMutating: { store.taskIsMutating($0) },
      taskIsBlocked: { blockedTaskIDs.contains($0) }
    )
    // Re-read whenever a task changes (the revision advances on every local
    // change and inbound task sync) or the window's tasks do, so a task whose
    // blocker was just finished loses its mark at once.
    .task(
      id: MobileAgendaBlockedKey(
        revision: store.taskWorkspaceRevision, taskIDs: store.calendarScheduledTasks.map(\.id))
    ) {
      blockedTaskIDs = await store.blockedTaskIDs(in: store.calendarScheduledTasks)
    }
  }
}

/// What the agenda's Blocked marks are read against: the task data's revision
/// and the scheduled tasks in the loaded window.
private struct MobileAgendaBlockedKey: Equatable {
  let revision: UInt64
  let taskIDs: [LorvexTask.ID]
}
