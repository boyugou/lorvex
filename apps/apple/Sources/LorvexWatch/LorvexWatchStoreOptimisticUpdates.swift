import Foundation
import LorvexCore
import LorvexWidgetKitSupport

extension LorvexWatchStore {
  /// Applies a task-list mutation locally so the watch UI responds without
  /// waiting for the phone-pushed snapshot. Called only after the command is
  /// durably journaled on the watch. A later phone rejection is surfaced and
  /// retained in the delivery section until the user dismisses it.
  func applyOptimisticUpdate(for mutation: LorvexWatchMutation) {
    switch mutation {
    case .completeTask(let id), .cancelTask(let id),
         .deferTaskToTomorrow(let id, _), .removeFromFocus(let id, _):
      focusTasks.removeAll { $0.id == id }
      primaryTask = focusTasks.first
    case .completeHabit(let id, _):
      guard let index = habits.firstIndex(where: { $0.id == id }),
        !habits[index].isDoneToday
      else { break }
      let current = habits[index]
      habits[index] = WidgetSnapshot.HabitSummary(
        id: current.id, name: current.name, icon: current.icon,
        completedToday: current.completedToday + 1, target: current.target)
    case .captureTask:
      break
    }
  }
}
