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

  /// True when Today should show the standalone schedule agenda: there are
  /// events today and no focus timeline is displayed. When a focus schedule
  /// (proposed or saved) exists, those same events are woven into it as `event`
  /// blocks, so the standalone agenda steps aside to avoid listing them twice.
  var showsStandaloneTodaySchedule: Bool {
    proposedFocusSchedule == nil && focusSchedule == nil && !todayScheduleEvents.isEmpty
  }

  var draftCalendarTitle: String {
    get { calendarStorage.draftCalendarTitle }
    set { calendarStorage.draftCalendarTitle = newValue }
  }

  var draftCalendarDate: Date {
    get { calendarStorage.draftCalendarDate }
    set { calendarStorage.draftCalendarDate = newValue }
  }

  var draftCalendarStartTime: Date {
    get { calendarStorage.draftCalendarStartTime }
    set { calendarStorage.draftCalendarStartTime = newValue }
  }

  var draftCalendarEndTime: Date {
    get { calendarStorage.draftCalendarEndTime }
    set { calendarStorage.draftCalendarEndTime = newValue }
  }

  var draftCalendarAllDay: Bool {
    get { calendarStorage.draftCalendarAllDay }
    set { calendarStorage.draftCalendarAllDay = newValue }
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

  /// True when the draft's end time is after its start time. All-day events have
  /// no intra-day span, so they are always valid. Compares time-of-day only: the
  /// start/end pickers carry independent date components, and the create/edit
  /// sheet has no end-date field, so end ≤ start would persist a zero- or
  /// negative-duration event that the week grid can only render as a stub.
  var draftCalendarTimesValid: Bool {
    guard !draftCalendarAllDay else { return true }
    let calendar = Calendar.current
    let start = calendar.dateComponents([.hour, .minute], from: draftCalendarStartTime)
    let end = calendar.dateComponents([.hour, .minute], from: draftCalendarEndTime)
    let startMinutes = (start.hour ?? 0) * 60 + (start.minute ?? 0)
    let endMinutes = (end.hour ?? 0) * 60 + (end.minute ?? 0)
    return endMinutes > startMinutes
  }

  /// Capture the live event draft before the create sheet resets and rewrites the
  /// shared draft fields. The inline editor binds the same fields, so without this
  /// an in-progress edit would be left holding the create form's values and Save
  /// would write them onto the edited event. Restored by
  /// ``restoreStashedCalendarDraft()`` when the create sheet dismisses.
  func stashCalendarDraftForCreate() {
    calendarStorage.stashedDraft = AppStoreCalendarStorage.CalendarDraftSnapshot(
      title: draftCalendarTitle,
      date: draftCalendarDate,
      startTime: draftCalendarStartTime,
      endTime: draftCalendarEndTime,
      allDay: draftCalendarAllDay,
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
    draftCalendarDate = stashed.date
    draftCalendarStartTime = stashed.startTime
    draftCalendarEndTime = stashed.endTime
    draftCalendarAllDay = stashed.allDay
    draftCalendarLocation = stashed.location
    draftCalendarNotes = stashed.notes
    draftCalendarColor = stashed.color
    draftCalendarRecurrence = stashed.recurrence
    calendarStorage.draftCalendarRecurrenceWasEdited = stashed.recurrenceWasEdited
    calendarStorage.draftCalendarRecurrenceBaseline = stashed.recurrenceBaseline
    draftCalendarTargetCalendarID = stashed.targetCalendarID
  }
}
