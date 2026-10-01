import Foundation
import LorvexCore

extension MobileStore {
  /// On iPhone the Habits tab is hidden from the bar, and a hidden tab draws
  /// nothing when selected. Whatever selects it (a deep link, Handoff, a
  /// shortcut, a notification) is redirected here: the Tasks tab opens with the
  /// Habits workspace pushed on its stack, followed by any habit route that was
  /// queued for the Habits stack.
  func redirectHiddenHabitsTab() {
    guard selectedTab == .habits || !habitsRoutePath.isEmpty else { return }
    let queued = habitsRoutePath
    habitsRoutePath = []
    selectedTab = .tasks
    tasksRoutePath = [.workspace(.habits)] + queued
  }
}
