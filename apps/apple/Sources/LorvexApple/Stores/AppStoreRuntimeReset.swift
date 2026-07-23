import Foundation
import LorvexCore

extension AppStore {
  func resetRuntimeState() {
    focusStorage.reset()
    dailyReviewStorage.reset()
    listsStorage.reset()
    calendarStorage.reset()
    taskDetailStorage.reset()
    habitsStorage.reset()
    memoryStorage.reset()
    syncReportsStorage.reset()
    runtimeDiagnostics = nil
    selectedTaskID = nil
    selectedHabitID = nil
  }
}
