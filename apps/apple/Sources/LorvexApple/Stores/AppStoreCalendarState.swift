import Foundation
import LorvexCore

extension AppStore {
  var calendarTimeline: CalendarTimelineSnapshot? {
    get { calendarStorage.calendarTimeline }
    set { calendarStorage.calendarTimeline = newValue }
  }

  /// The id of the calendar event shown in the detail inspector, or nil when the
  /// panel is closed. Setting it directly is fine; reads of the event itself go
  /// through ``selectedCalendarEvent``.
  var selectedCalendarEventID: String? {
    get { calendarStorage.selectedCalendarEventID }
    set { calendarStorage.selectedCalendarEventID = newValue }
  }

  /// The selected calendar event resolved against the live timeline, or nil if
  /// nothing is selected or the selected event has scrolled out of the loaded
  /// window. Resolving by id (rather than caching the value) keeps the inspector
  /// in step with edits and refreshes.
  var selectedCalendarEvent: CalendarTimelineEvent? {
    guard let id = calendarStorage.selectedCalendarEventID else { return nil }
    return calendarTimeline?.events.first { $0.id == id }
  }

  /// Open the inspector for `event` (any event — imported events show read-only).
  func selectCalendarEvent(_ event: CalendarTimelineEvent) {
    calendarStorage.selectedCalendarEventID = event.id
  }

  /// Toggle the inspector for `event`: re-tapping the open event collapses it,
  /// matching the inspector's ✕. Backs the event-block tap.
  func toggleCalendarEventSelection(_ event: CalendarTimelineEvent) {
    if calendarStorage.selectedCalendarEventID == event.id {
      clearSelectedCalendarEvent()
    } else {
      selectCalendarEvent(event)
    }
  }

  /// Close the calendar detail inspector.
  func clearSelectedCalendarEvent() {
    calendarStorage.selectedCalendarEventID = nil
  }

  /// The event shown in the main window's trailing inspector: the selected
  /// event while Today is showing, where its schedule rows open it. Nil on
  /// every other workspace; Calendar shows its selected event in its own
  /// panel beside the grid.
  var todayInspectorEvent: CalendarTimelineEvent? {
    selection == .today ? selectedCalendarEvent : nil
  }

  /// Opens `event` in Today's inspector, or closes it when it is already
  /// open, as re-clicking an open task row does. The inspector shows one
  /// subject, so an open task closes first.
  func toggleTodayEventSelection(_ event: CalendarTimelineEvent) {
    if calendarStorage.selectedCalendarEventID == event.id {
      clearSelectedCalendarEvent()
      return
    }
    selectedTaskID = nil
    selectCalendarEvent(event)
  }

  /// Shows the main window's Today with `event`'s detail open in the
  /// inspector, in place of whatever the inspector showed. Backs a click on an
  /// event in the menu bar panel's Today.
  func showEventInToday(_ event: CalendarTimelineEvent) {
    selection = .today
    selectedTaskID = nil
    selectCalendarEvent(event)
  }

  /// Shows the Calendar workspace on `dayKey` (`yyyy-MM-dd`) with `event`'s
  /// detail open beside the grid (``calendarPendingDayKey``). Backs a click on
  /// an event in the menu bar panel's Next 7 Days.
  func showEventInCalendar(_ event: CalendarTimelineEvent, onDayKey dayKey: String) {
    selection = .calendar
    calendarPendingDayKey = dayKey
    selectCalendarEvent(event)
  }

  /// The day (`yyyy-MM-dd`) the Calendar workspace shows next, set by a
  /// surface that opens the calendar on a given day. The workspace opens on
  /// it when it is created, or moves to it when it is already on screen, and
  /// clears it; nil leaves the workspace where it is (on today when it opens).
  var calendarPendingDayKey: String? {
    get { calendarStorage.calendarPendingDayKey }
    set { calendarStorage.calendarPendingDayKey = newValue }
  }

  var calendarScheduledTasks: [LorvexTask]? {
    get { calendarStorage.calendarScheduledTasks }
    set { calendarStorage.calendarScheduledTasks = newValue }
  }

  /// Today's calendar events — the day's fixed commitments (Lorvex-owned events
  /// plus the mirrored EventKit external calendar) filtered out of the loaded
  /// timeline window and agenda-ordered. Backs the Today "Schedule" section.
  /// Empty when the timeline has not loaded or the day is clear.
  var todayScheduleEvents: [CalendarTimelineEvent] {
    calendarTimeline?.eventsOccurring(on: logicalTodayDateString) ?? []
  }

  var draftCalendarTitle: String {
    get { calendarStorage.draftCalendarTitle }
    set { calendarStorage.draftCalendarTitle = newValue }
  }

  /// When the draft event starts and ends. The create and edit form's Start
  /// and End rows edit it, so an event can run overnight or across days.
  var draftCalendarTiming: CalendarEventTiming {
    get { calendarStorage.draftCalendarTiming }
    set { calendarStorage.draftCalendarTiming = newValue }
  }

  var draftCalendarLocation: String {
    get { calendarStorage.draftCalendarLocation }
    set { calendarStorage.draftCalendarLocation = newValue }
  }

  var draftCalendarNotes: String {
    get { calendarStorage.draftCalendarNotes }
    set { calendarStorage.draftCalendarNotes = newValue }
  }

  var draftCalendarColor: String? {
    get { calendarStorage.draftCalendarColor }
    set { calendarStorage.draftCalendarColor = newValue }
  }

  /// The draft event's typed repeat rule, or nil for a one-off event. Edited by
  /// the create/edit form's Repeat row and serialized to canonical recurrence
  /// JSON at the service boundary on create / update / scoped save.
  var draftCalendarRecurrence: TaskRecurrenceRule? {
    get { calendarStorage.draftCalendarRecurrence }
    set {
      calendarStorage.draftCalendarRecurrence = newValue
      calendarStorage.draftCalendarRecurrenceWasEdited = true
    }
  }

  var draftCalendarRecurrenceIsOpaque: Bool {
    if case .opaque = calendarStorage.draftCalendarRecurrenceBaseline { return true }
    return false
  }

  var draftCalendarRecurrencePatch: CalendarEventRecurrencePatch {
    switch calendarStorage.draftCalendarRecurrenceBaseline {
    case .opaque:
      if let draftCalendarRecurrence { return .set(draftCalendarRecurrence) }
      return calendarStorage.draftCalendarRecurrenceWasEdited ? .clear : .unset
    case .known(nil):
      return draftCalendarRecurrence.map(CalendarEventRecurrencePatch.set) ?? .unset
    case .known(let original?):
      guard let draftCalendarRecurrence else { return .clear }
      return draftCalendarRecurrence.isSemanticallyEquivalent(to: original)
        ? .unset : .set(draftCalendarRecurrence)
    }
  }

  var draftCalendarRecurrenceCanApplyToSingleOccurrence: Bool {
    if case .set = draftCalendarRecurrencePatch { return false }
    return true
  }

  /// Capture the live event draft before the create sheet resets and rewrites the
  /// shared draft fields. The inline editor binds the same fields, so without this
  /// an in-progress edit would be left holding the create form's values and Save
  /// would write them onto the edited event. Restored by
  /// ``restoreStashedCalendarDraft()`` when the create sheet dismisses.
  func stashCalendarDraftForCreate() {
    calendarStorage.stashedDraft = AppStoreCalendarStorage.CalendarDraftSnapshot(
      title: draftCalendarTitle,
      timing: draftCalendarTiming,
      location: draftCalendarLocation,
      notes: draftCalendarNotes,
      color: draftCalendarColor,
      recurrence: draftCalendarRecurrence,
      recurrenceWasEdited: calendarStorage.draftCalendarRecurrenceWasEdited,
      recurrenceBaseline: calendarStorage.draftCalendarRecurrenceBaseline,
      targetCalendarID: draftCalendarTargetCalendarID)
  }

  /// Restore the draft stashed by ``stashCalendarDraftForCreate()`` (a no-op when
  /// nothing was stashed). Called when the create sheet dismisses so the inline
  /// editor's draft is the edited event's again, not the create form's leftovers.
  func restoreStashedCalendarDraft() {
    guard let stashed = calendarStorage.stashedDraft else { return }
    calendarStorage.stashedDraft = nil
    draftCalendarTitle = stashed.title
    draftCalendarTiming = stashed.timing
    draftCalendarLocation = stashed.location
    draftCalendarNotes = stashed.notes
    draftCalendarColor = stashed.color
    draftCalendarRecurrence = stashed.recurrence
    calendarStorage.draftCalendarRecurrenceWasEdited = stashed.recurrenceWasEdited
    calendarStorage.draftCalendarRecurrenceBaseline = stashed.recurrenceBaseline
    draftCalendarTargetCalendarID = stashed.targetCalendarID
  }
}
