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

/// How a failed notification action reaches the app's alert layer.
///
/// The host app delegate runs Complete / Defer / Snooze from a reminder's own
/// buttons. When one fails, the delegate classifies the failure with
/// ``UserFacingError/classify(_:)`` while the error still has its type, and
/// posts the ``UserFacingError/Classification`` under ``classificationKey`` in
/// the `userInfo` of its failure notification. The store then shows that
/// classification's message, so a failure the app words itself (a
/// ``UserFacingError/Reason``, such as completing a canceled task) reads in the
/// interface language rather than as the core's English sentence, and the
/// technical detail of an unexpected failure still reaches `error_logs`. A post
/// without a classification is a failure with no detail; the store shows its
/// generic "Couldn't perform that action." line.
public enum LorvexNotificationActionFailure {
  /// The `userInfo` key whose value is a ``UserFacingError/Classification``.
  public static let classificationKey = "classification"
}
