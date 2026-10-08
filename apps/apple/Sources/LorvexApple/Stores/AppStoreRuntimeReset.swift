import Foundation
import LorvexCore

extension AppStore {
  func resetRuntimeState() {
    todayStorage.reset()
    dailyReviewStorage.reset()
    listsStorage.reset()
    calendarStorage.reset()
    calendarDraftStorage.reset()
    taskDetailStorage.reset()
    habitsStorage.reset()
    memoryStorage.reset()
    syncReportsStorage.reset()
    runtimeDiagnostics = nil
    selectedTaskID = nil
    selectedHabitID = nil
  }
}
