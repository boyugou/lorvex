import Foundation
import LorvexCore

/// Holds runtime state for the calendar domain: the loaded timeline snapshot,
/// the tasks drawn in its window, and what the workspace has selected. The
/// event form's draft fields live in ``AppStoreCalendarDraftStorage``.
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

  mutating func reset() {
    calendarTimeline = nil
    calendarScheduledTasks = nil
    calendarUnplannedTasks = nil
    calendarUnplannedRailIsShown = false
    calendarUnplannedTotal = 0
    selectedCalendarEventID = nil
    calendarPendingDayKey = nil
  }
}
