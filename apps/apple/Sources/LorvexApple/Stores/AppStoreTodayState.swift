import LorvexCore

extension AppStore {
  var today: TodaySnapshot {
    get { todayStorage.today }
    set {
      let priorTimezone = todayStorage.today.timezone
      todayStorage.today = newValue
      if priorTimezone != newValue.timezone {
        resetTaskDetailReminderDate()
      }
    }
  }

  /// Suggested times under review in Today's schedule, or nil.
  var proposedDayTimes: DayTimesProposal? {
    get { todayStorage.proposedDayTimes }
    set { todayStorage.proposedDayTimes = newValue }
  }
}
