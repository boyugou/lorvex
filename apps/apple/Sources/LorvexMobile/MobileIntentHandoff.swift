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

  public static func consumeNavigationTarget() -> MobileNavigationTarget? {
    if let taskID = consumeTaskID() {
      return MobileDeepLinkRoute.task(taskID).navigationTarget
    }
    guard let rawDestination = consumeRawDestination() else { return nil }
    guard let destination = SidebarSelection.matching(rawDestination),
      let url = URL(string: LorvexDeepLinkContract.destinationURLString(destination))
    else { return nil }
    return MobileDeepLinkRoute(url: url)?.navigationTarget(resolvedFrom: url)
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
