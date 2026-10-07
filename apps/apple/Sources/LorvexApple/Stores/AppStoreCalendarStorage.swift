import Foundation
import LorvexCore

/// Holds runtime state for the calendar domain: the loaded timeline snapshot
/// and all draft fields for creating a new calendar event.
struct AppStoreCalendarStorage {
  var calendarTimeline: CalendarTimelineSnapshot?
  /// The loaded window's tasks, planned (or, unplanned, due) in it; a task
  /// with a time is drawn on the time axis of its planned day.
  var calendarScheduledTasks: [LorvexTask]?
  /// The open tasks with no planned day that the Calendar's "Unplanned Tasks" rail lists
  /// (the first ``AppStore/calendarUnplannedLimit``, in the canonical task
  /// order). Nil while the rail is hidden and until its first load succeeds.
  var calendarUnplannedTasks: [LorvexTask]?
  /// The rail is on screen, so task changes reload its tasks.
  var calendarUnplannedRailIsShown = false
  /// How many open tasks have no planned day in all, which can exceed what the
  /// rail lists.
  var calendarUnplannedTotal = 0
  /// Monotonic generation stamp for in-flight timeline loads. A load captures it
  /// at entry and only commits its results if it is still the latest, so two
  /// overlapping loads (week navigation, the EventKit observer, the today
  /// refetch) can't pair one window's events with another window's tasks.
  var timelineLoadToken = 0
  /// The calendar event whose detail inspector is open in the workspace's right
  /// panel. Nil hides the panel. Cleared when the event leaves the visible
  /// timeline (navigation, deletion, or a filter change).
  var selectedCalendarEventID: String?
  /// The day the Calendar workspace shows next (``AppStore/calendarPendingDayKey``).
  var calendarPendingDayKey: String?
  var draftCalendarTitle = ""
  /// When the draft event starts and ends, including whether it is all-day.
  var draftCalendarTiming = CalendarEventTiming.timed(startingAt: Date())
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

  /// Snapshot of the event-draft fields, used to stash/restore the draft
  /// around the create sheet so create and edit don't corrupt each other's
  /// in-progress values.
  struct CalendarDraftSnapshot {
    var title: String
    var timing: CalendarEventTiming
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
    calendarUnplannedTasks = nil
    calendarUnplannedRailIsShown = false
    calendarUnplannedTotal = 0
    selectedCalendarEventID = nil
    calendarPendingDayKey = nil
    draftCalendarTitle = ""
    draftCalendarTiming = CalendarEventTiming.timed(startingAt: Date())
    draftCalendarLocation = ""
    draftCalendarNotes = ""
    draftCalendarColor = nil
    draftCalendarRecurrence = nil
    draftCalendarRecurrenceWasEdited = false
    draftCalendarRecurrenceBaseline = .known(nil)
    draftCalendarTargetCalendarID = nil
  }
}
