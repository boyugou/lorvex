import Foundation
import LorvexCore

/// Holds the calendar event form's draft fields: the title, timing, place,
/// notes, color, repeat rule, and target calendar of the event being created
/// or edited. The draft sits apart from ``AppStoreCalendarStorage`` because the
/// store hands a stored property to its readers as one unit: a keystroke in the
/// form changes only this value, so the grids that read the loaded timeline do
/// not draw again with it.
struct AppStoreCalendarDraftStorage {
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
    self = AppStoreCalendarDraftStorage()
  }
}
