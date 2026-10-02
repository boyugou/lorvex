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
    case .completeTask(let id):
      if tasks.contains(where: { $0.id == id }) { completedTodayCount += 1 }
      tasks.removeAll { $0.id == id }
    case .cancelTask(let id), .deferTaskToTomorrow(let id, _):
      tasks.removeAll { $0.id == id }
    case .startTask(let id):
      setStatus(.inProgress, ofTask: id)
    case .pauseTask(let id):
      setStatus(.open, ofTask: id)
    case .completeHabit(let id, _):
      guard let index = habits.firstIndex(where: { $0.id == id }),
        !habits[index].isDoneToday
      else { break }
      let current = habits[index]
      habits[index] = WidgetSnapshot.HabitSummary(
        id: current.id, name: current.name, icon: current.icon,
        completedToday: current.completedToday + 1, target: current.target, color: current.color)
    case .captureTask:
      break
    }
  }

  /// Re-applies the task actions still waiting for the phone's ACK over a
  /// freshly read replica, so a task completed on the wrist does not reappear
  /// on the next refresh while the phone has yet to apply it. Every task action
  /// is idempotent over a replica that already includes it. Habit check-ins are
  /// left out: adding one again could count a check-in the replica already has.
  func reapplyPendingTaskCommands() {
    for command in deliveryStatus.pendingCommands {
      if case .completeHabit = command.mutation { continue }
      applyOptimisticUpdate(for: command.mutation)
    }
  }

  /// Sets a task's started state and keeps Today's rule that started tasks
  /// come first, each group in its current order. The phone's next snapshot
  /// settles the exact place within the group.
  private func setStatus(_ status: LorvexTask.Status, ofTask id: LorvexTask.ID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    tasks[index].status = status
    tasks = tasks.filter { $0.status == .inProgress } + tasks.filter { $0.status != .inProgress }
  }
}
