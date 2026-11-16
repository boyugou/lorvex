import Foundation

/// Scope for editing or deleting a single occurrence of a recurring calendar
/// event, matching the `scope` argument of `editScopedCalendarEvent` /
/// `deleteScopedCalendarEvent`. Raw values are the wire strings the core
/// expects; `allEvents` updates/deletes the addressed series segment.
///
/// Occurrence scopes keep the original source slot as their identity even
/// when an edit moves the event to another day. Use the event's original
/// `occurrenceDate`, never its projected display day or the edited start day.
public enum CalendarEventEditScope: String, Sendable, CaseIterable {
  case thisEvent = "this_only"
  case thisAndFollowing = "this_and_following"
  case allEvents = "all_in_series"
}
