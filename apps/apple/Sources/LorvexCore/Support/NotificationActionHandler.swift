import Foundation
import UserNotifications

/// Handles a UNNotificationResponse for Lorvex task reminder actions.
///
/// Extracts the task ID from userInfo and dispatches to the appropriate closure
/// based on the action identifier. Returns without effect when the action identifier
/// is not a Lorvex action or when the task ID is missing — callers should handle
/// default taps (UNNotificationDefaultActionIdentifier) via existing deep-link routing.
///
/// - Parameters:
///   - response: The notification response received from the system.
///   - completeTask: Called with the task ID when the complete action fires.
///   - deferTask: Called with the task ID when the defer action fires.
///   - snoozeTask: Called with the task ID when the snooze action fires.
public func handleLorvexNotificationAction(
  response: UNNotificationResponse,
  completeTask: (LorvexTask.ID) async -> Void,
  deferTask: (LorvexTask.ID) async -> Void,
  snoozeTask: (LorvexTask.ID) async -> Void
) async {
  let actionID = response.actionIdentifier
  guard
    actionID == LorvexNotificationActionID.completeTask
      || actionID == LorvexNotificationActionID.deferTask
      || actionID == LorvexNotificationActionID.snoozeTask
  else { return }

  guard
    let taskID = response.notification.request.content.userInfo[
      LorvexNotificationRoute.taskIDUserInfoKey
    ] as? String, !taskID.isEmpty
  else { return }

  switch actionID {
  case LorvexNotificationActionID.completeTask:
    await completeTask(taskID)
  case LorvexNotificationActionID.deferTask:
    await deferTask(taskID)
  case LorvexNotificationActionID.snoozeTask:
    await snoozeTask(taskID)
  default:
    break
  }
}
