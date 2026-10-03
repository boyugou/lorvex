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
    let start = calendar.date(
      bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date) ?? date
    store.draftCalendarTitle = ""
    // A drag to the bottom of the grid ends the event at midnight, the start
    // of the next day.
    store.draftCalendarTiming = .timed(startingAt: start, minutes: max(15, durationMinutes))
    store.draftCalendarLocation = ""
    store.draftCalendarNotes = ""
    store.draftCalendarColor = nil
    store.draftCalendarRecurrence = nil
    store.calendarStorage.draftCalendarRecurrenceWasEdited = false
    store.calendarStorage.draftCalendarRecurrenceBaseline = .known(nil)
    store.draftCalendarTargetCalendarID = nil
  }
}
