import Foundation
import LorvexCore

/// When the event "Add to Calendar" makes for a task happens, in the
/// `YYYY-MM-DD` and `HH:MM` fields a canonical calendar event stores.
///
/// Every value is a wall-clock reading in the configured Lorvex timezone, the
/// zone a task's planned time and a new event's times are both read in, so
/// nothing passes through the device timezone. The day is the task's planned
/// day as stored (a UTC-midnight anchor), never re-read in a local calendar.
///
/// The event starts at the task's planned time or, for a task without one,
/// when the working day starts. It ends where the planned time ends, or after
/// the task's estimate: an hour when there is none, never less than 15
/// minutes. An event that runs past midnight carries the day it ends on in
/// ``endDate``, because a same-day event cannot end before it starts.
struct TaskCalendarEventSpan: Equatable {
  let startDate: String
  let startTime: String
  /// The day the event ends, or nil when it ends on ``startDate``.
  let endDate: String?
  let endTime: String

  private static let minutesPerDay = 24 * 60
  private static let secondsPerDay: TimeInterval = 24 * 60 * 60

  /// The span for `task` on `plannedDay`, the task's stored planned date.
  /// `workdayStartMinutes` (minutes since midnight) starts a task that has
  /// no planned time.
  init(task: LorvexTask, plannedDay: Date, workdayStartMinutes: Int) {
    let start = task.plannedTime?.lowerBound ?? workdayStartMinutes
    let end: Int
    if let planned = task.plannedTime, planned.upperBound > planned.lowerBound {
      end = planned.upperBound
    } else {
      end = start + max(15, task.estimatedMinutes ?? 60)
    }
    let endDayOffset = end / Self.minutesPerDay
    startDate = LorvexDateFormatters.ymdUTC.string(from: plannedDay)
    startTime = lorvexStoredClockTime(minutes: start)
    endDate =
      endDayOffset == 0
      ? nil
      : LorvexDateFormatters.ymdUTC.string(
        from: plannedDay.addingTimeInterval(TimeInterval(endDayOffset) * Self.secondsPerDay))
    endTime = lorvexStoredClockTime(minutes: end % Self.minutesPerDay)
  }
}
