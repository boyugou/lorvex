import AppIntents
import LorvexCore

public enum LorvexIntentHandoff {
  public static func storeDestination(_ destination: SidebarSelection) {
    LorvexIntentHandoffStore().storeDestination(destination.rawValue)
  }

  public static func storeTask(_ taskID: LorvexTask.ID) {
    LorvexIntentHandoffStore().storeTask(taskID)
  }

  public static func consumeDestination() -> SidebarSelection? {
    guard let rawValue = LorvexIntentHandoffStore().consumeDestination(),
      let destination = SidebarSelection.matching(rawValue)
    else { return nil }
    return destination
  }

  public static func consumeTaskID() -> LorvexTask.ID? {
    LorvexIntentHandoffStore().consumeTaskID()
  }
}
