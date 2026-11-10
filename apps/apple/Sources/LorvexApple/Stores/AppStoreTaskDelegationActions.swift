import Foundation
import LorvexCore

extension AppStore {
  /// Hands the task `id` to the person's assistant, or takes it back, from a
  /// row's context menu or the inspector's More menu, without changing
  /// `selectedTaskID`. The task's own title and notes are what the assistant
  /// is asked to do. A refused write shows its error and leaves every loaded
  /// copy of the task as it was.
  func performDelegationAction(_ action: LorvexTaskDelegationAction, taskID id: LorvexTask.ID) async {
    guard
      let updated = await performCanonicalMutation({
        switch action {
        case .handToAssistant: try await core.delegateTask(id: id, request: nil)
        case .takeBack: try await core.clearTaskDelegation(id: id)
        }
      })
    else { return }
    replaceTask(updated)
    await reconcileAfterCommittedMutation(source: "macos.task.delegation.reconcile") {
      try await afterSelectedTaskMutation()
    }
  }
}
