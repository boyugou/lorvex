import Foundation
import LorvexCore

/// Holds runtime state for the calendar domain: the loaded timeline snapshot
/// and all draft fields for creating a new calendar event.
struct AppStoreCalendarStorage {
  var calendarTimeline: CalendarTimelineSnapshot?
  var calendarScheduledTasks: [LorvexTask]?
  /// Monotonic generation stamp for in-flight timeline loads. A load captures it
  /// at entry and only commits its results if it is still the latest, so two
  /// overlapping loads (week navigation, the EventKit observer, the today
  /// refetch) can't pair one window's events with another window's tasks.
  var timelineLoadToken = 0
  /// The calendar event whose detail inspector is open in the workspace's right
  /// panel. Nil hides the panel. Cleared when the event leaves the visible
  /// timeline (navigation, deletion, or a filter change).
  var selectedCalendarEventID: String?
  var draftCalendarTitle = ""
  var draftCalendarDate = Date()
  var draftCalendarStartTime = Date()
  var draftCalendarEndTime = Date()
  var draftCalendarAllDay = false
  var draftCalendarLocation = ""
  var draftCalendarNotes = ""
  var draftCalendarColor: String?
  /// Typed repeat rule for the draft event, or nil for a one-off event. The
  /// create/edit form's Repeat row edits this; the service serializes it to
  /// canonical recurrence JSON at the boundary.
  var draftCalendarRecurrence: TaskRecurrenceRule?
  /// True after the form binding changes recurrence. Needed only for an opaque
  /// future rule: untouched nil preserves it, while choosing None explicitly
  /// must clear it.
  var draftCalendarRecurrenceWasEdited = false
  /// The rule present when the edit form opened. `.opaque` protects a future
  /// recurrence shape this client cannot decode from being cleared by an
  /// otherwise unrelated edit.
  var draftCalendarRecurrenceBaseline: CalendarRecurrenceBaseline = .known(nil)
  /// The writable EventKit calendar the draft event's mirror is filed into, by
  /// `calendarIdentifier`. Nil selects the dedicated Lorvex calendar (the
  /// picker's default). The calendar lives only in the EventKit mirror, so the
  /// edit form resolves it live from the coordinator on open.
  var draftCalendarTargetCalendarID: String?
  /// A copy of the live event draft captured before the create sheet overwrites
  /// the shared draft fields, so an in-progress inline edit (which binds the same
  /// fields) can be restored when the create sheet dismisses. `nil` when nothing
  /// is stashed.
  var stashedDraft: CalendarDraftSnapshot?

  /// Snapshot of the eight event-draft fields, used to stash/restore the draft
  /// around the create sheet so create and edit don't corrupt each other's
  /// in-progress values.
  struct CalendarDraftSnapshot {
    var title: String
    var date: Date
    var startTime: Date
    var endTime: Date
    var allDay: Bool
    var location: String
    var notes: String
    var color: String?
    var recurrence: TaskRecurrenceRule?
    var recurrenceWasEdited: Bool
    var recurrenceBaseline: CalendarRecurrenceBaseline
    var targetCalendarID: String?
  }

  enum CalendarRecurrenceBaseline: Equatable {
    case known(TaskRecurrenceRule?)
    case opaque
  }

  mutating func reset() {
    stashedDraft = nil
    calendarTimeline = nil
    calendarScheduledTasks = nil
    selectedCalendarEventID = nil
    draftCalendarTitle = ""
    draftCalendarDate = Date()
    draftCalendarStartTime = Date()
    draftCalendarEndTime = Date()
    draftCalendarAllDay = false
    draftCalendarLocation = ""
    draftCalendarNotes = ""
    draftCalendarColor = nil
    draftCalendarRecurrence = nil
    draftCalendarRecurrenceWasEdited = false
    draftCalendarRecurrenceBaseline = .known(nil)
    draftCalendarTargetCalendarID = nil
  }
}
