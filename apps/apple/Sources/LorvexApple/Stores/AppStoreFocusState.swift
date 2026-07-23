import LorvexCore

extension AppStore {
  var today: TodaySnapshot {
    get { focusStorage.today }
    set {
      let priorTimezone = focusStorage.today.timezone
      focusStorage.today = newValue
      if priorTimezone != newValue.timezone {
        resetTaskDetailReminderDate()
      }
    }
  }

  var currentFocus: CurrentFocusPlan? {
    get { focusStorage.currentFocus }
    set { focusStorage.currentFocus = newValue }
  }

  var focusSchedule: FocusSchedule? {
    get { focusStorage.focusSchedule }
    set { focusStorage.focusSchedule = newValue }
  }

  var proposedFocusSchedule: FocusSchedule? {
    get { focusStorage.proposedFocusSchedule }
    set { focusStorage.proposedFocusSchedule = newValue }
  }
}
