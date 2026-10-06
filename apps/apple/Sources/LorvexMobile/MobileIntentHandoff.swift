import Foundation
import LorvexCore

public enum MobileIntentHandoff {
  public static let destinationKey = LorvexIntentHandoffKeys.destination
  public static let taskIDKey = LorvexIntentHandoffKeys.taskID

  public static func storeDestination(_ rawDestination: String) {
    LorvexIntentHandoffStore().storeDestination(rawDestination)
  }

  public static func storeTask(_ taskID: LorvexTask.ID) {
    LorvexIntentHandoffStore().storeTask(taskID)
  }

  /// The place a system intent asked the app to open, consumed once: a task's
  /// detail, or a workspace destination matched case-insensitively. Lands
  /// where the same `lorvex://` link would (`MobileNavigationTarget`).
  public static func consumeNavigationTarget() -> MobileNavigationTarget? {
    if let taskID = consumeTaskID() {
      return MobileNavigationTarget(route: .task(taskID))
    }
    guard let rawDestination = consumeRawDestination(),
      let destination = SidebarSelection.matching(rawDestination)
    else { return nil }
    return MobileNavigationTarget(destination: destination)
  }

  /// The quick action a control asked for, consumed once.
  public static func consumeQuickAction() -> LorvexQuickAction? {
    LorvexIntentHandoffStore().consumeQuickAction()
  }

  public static func clear() {
    LorvexIntentHandoffStore().clear()
  }

  private static func consumeTaskID() -> LorvexTask.ID? {
    LorvexIntentHandoffStore().consumeTaskID()
  }

  private static func consumeRawDestination() -> String? {
    LorvexIntentHandoffStore().consumeDestination()
  }
}
