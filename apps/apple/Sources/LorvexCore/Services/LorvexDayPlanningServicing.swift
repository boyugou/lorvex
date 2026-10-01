import Foundation

/// A day's tasks' times.
///
/// Which tasks a day holds is set through the task services (a planned date,
/// deferral). A task's time is part of the task (``LorvexTask/plannedTime``),
/// so a day's times arrive with its tasks; the calls here suggest times, or
/// replace the times of a whole day at once.
public protocol LorvexDayPlanningServicing: Sendable {
  /// Every task with a time on a day from `start` through `end` (inclusive
  /// `yyyy-MM-dd` keys), finished ones included and cancelled or trashed ones
  /// left out, ordered by day, then start.
  func loadTimedTasks(from start: String, through end: String) async throws -> [LorvexTask]

  /// Suggested times for the tasks on `date` (``DayTimesProposal``), with the
  /// stored working hours and the day's calendar. Nothing is stored.
  func proposeDayTimes(date: String) async throws -> DayTimesProposal

  /// A suggestion with per-call options: `workingHoursStart` and
  /// `workingHoursEnd` (`HH:MM`) override the stored working hours for this
  /// suggestion only, each falling back to the stored value independently, and
  /// `includeCalendarEvents: false` suggests as if the calendar were empty.
  func proposeDayTimes(
    date: String,
    workingHoursStart: String?,
    workingHoursEnd: String?,
    includeCalendarEvents: Bool?
  ) async throws -> DayTimesProposal

  /// Replace the times of `date`'s unfinished tasks with `times`: each listed
  /// task is planned for `date` and takes its time, and every other unfinished
  /// task timed on `date` loses its time and keeps its planned date. Finished
  /// tasks keep their times as the day's record. Every listed task must be
  /// unfinished and appear once. Returns the day's timed tasks in start order.
  func saveDayTimes(date: String, times: [LorvexTaskTime]) async throws -> [LorvexTask]
}
