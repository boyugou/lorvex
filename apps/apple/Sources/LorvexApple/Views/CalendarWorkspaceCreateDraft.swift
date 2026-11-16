import Foundation

extension CalendarWorkspaceView {
  /// Pre-fills the create-event draft for a click-or-drag on the week grid.
  /// `minutes` is the start minute-of-day; `durationMinutes` is the requested
  /// duration (callers pass 60 for tap, the dragged span for drag-to-create).
  func prepareCreateDraft(date: Date, minutes: Int, durationMinutes: Int = 60) {
    // Stash the live draft first: a grid tap/drag to create shares the same draft
    // fields as an open inline edit, which is restored when the create sheet
    // dismisses (see `AppStore.stashCalendarDraftForCreate()`).
    store.stashCalendarDraftForCreate()
    store.draftCalendarTitle = ""
    // A drag to the bottom of the grid ends the event at midnight, the start
    // of the next day.
    store.draftCalendarTiming = .timed(
      on: date, atMinute: minutes, minutes: max(15, durationMinutes),
      timeZone: store.logicalTimeZone, dayCalendar: calendar)
    store.draftCalendarLocation = ""
    store.draftCalendarNotes = ""
    store.draftCalendarColor = nil
    store.draftCalendarRecurrence = nil
    store.calendarDraftStorage.draftCalendarRecurrenceWasEdited = false
    store.calendarDraftStorage.draftCalendarRecurrenceBaseline = .known(nil)
    store.calendarDraftStorage.draftCalendarEditBaseline = nil
    store.draftCalendarTargetCalendarID = nil
  }
}
