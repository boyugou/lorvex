import Foundation

/// Scope for editing or deleting a single occurrence of a recurring calendar
/// event, matching the `scope` argument of `editScopedCalendarEvent` /
/// `deleteScopedCalendarEvent`. Raw values are the wire strings the core
/// expects; `allEvents` is equivalent to a whole-series update/delete.
///
/// `thisEvent` and `thisAndFollowing` pin the affected occurrence(s) to the
/// tapped date — the core ignores a start-date change for those scopes — so a
/// move to a different day only takes effect under `allEvents`.
public enum CalendarEventEditScope: String, Sendable, CaseIterable {
  case thisEvent = "this_only"
  case thisAndFollowing = "this_and_following"
  case allEvents = "all_in_series"
}
