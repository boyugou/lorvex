import Foundation

extension AppStore {
  /// Pre-fills the create-event draft for a click or a drag on a time grid:
  /// the Calendar workspace's and Today's day rail. `minutes` is the start
  /// minute of the day; `durationMinutes` is the requested length (60 for a
  /// click, the dragged span for a drag). `dayCalendar` is the calendar the
  /// grid lays its days out in.
  func prepareCalendarCreateDraft(
    date: Date, minutes: Int, durationMinutes: Int = 60, dayCalendar: Calendar
  ) {
    // Stash the live draft first: a grid tap/drag to create shares the same draft
    // fields as an open inline edit, which is restored when the create sheet
    // dismisses (see `AppStore.stashCalendarDraftForCreate()`).
    stashCalendarDraftForCreate()
    draftCalendarTitle = ""
    // A drag to the bottom of the grid ends the event at midnight, the start
    // of the next day.
    draftCalendarTiming = .timed(
      on: date, atMinute: minutes, minutes: max(15, durationMinutes),
      timeZone: logicalTimeZone, dayCalendar: dayCalendar)
    draftCalendarLocation = ""
    draftCalendarNotes = ""
    draftCalendarColor = nil
    draftCalendarRecurrence = nil
    calendarDraftStorage.draftCalendarRecurrenceWasEdited = false
    calendarDraftStorage.draftCalendarRecurrenceBaseline = .known(nil)
    calendarDraftStorage.draftCalendarEditBaseline = nil
    draftCalendarTargetCalendarID = nil
  }
}

extension CalendarWorkspaceView {
  /// Pre-fills the create-event draft for a click-or-drag on the week grid
  /// (``AppStore/prepareCalendarCreateDraft(date:minutes:durationMinutes:dayCalendar:)``).
  func prepareCreateDraft(date: Date, minutes: Int, durationMinutes: Int = 60) {
    store.prepareCalendarCreateDraft(
      date: date, minutes: minutes, durationMinutes: durationMinutes, dayCalendar: calendar)
  }
}
