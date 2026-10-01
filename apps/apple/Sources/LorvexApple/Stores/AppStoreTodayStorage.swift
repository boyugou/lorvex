import Foundation
import LorvexCore

/// Holds runtime state for Today: the day's list, suggested times under review,
/// the row selection, what is done today, and the working hours.
struct AppStoreTodayStorage {
  var today: TodaySnapshot = .empty
  /// Suggested times the user is reviewing, until they accept or dismiss them.
  var proposedDayTimes: DayTimesProposal?
  var selectedTaskIDs = Set<LorvexTask.ID>()
  /// Tasks completed on the product day, for Today's facts line.
  var doneTodayCount = 0
  /// The tasks behind ``doneTodayCount``, newest completion first, for Today's
  /// Done section and the finished times on the schedule.
  var doneTodayTasks: [LorvexTask] = []
  /// The working-hours window in minutes since midnight, for Today's overbooked
  /// decision and the Plan week's per-day load. Both are `nil` until the
  /// preference loads.
  var workdayStartMinutes: Int?
  var workdayEndMinutes: Int?

  mutating func reset() {
    today = .empty
    proposedDayTimes = nil
    selectedTaskIDs.removeAll()
    doneTodayCount = 0
    doneTodayTasks = []
    workdayStartMinutes = nil
    workdayEndMinutes = nil
  }
}
