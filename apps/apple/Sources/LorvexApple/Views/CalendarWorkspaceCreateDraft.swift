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
    let safeDuration = max(15, durationMinutes)
    store.draftCalendarTitle = ""
    store.draftCalendarDate = date
    store.draftCalendarStartTime = start
    store.draftCalendarEndTime = start.addingTimeInterval(TimeInterval(safeDuration * 60))
    store.draftCalendarAllDay = false
    store.draftCalendarLocation = ""
    store.draftCalendarNotes = ""
    store.draftCalendarColor = nil
    store.draftCalendarRecurrence = nil
    store.calendarStorage.draftCalendarRecurrenceWasEdited = false
    store.calendarStorage.draftCalendarRecurrenceBaseline = .known(nil)
    store.draftCalendarTargetCalendarID = nil
  }
}
