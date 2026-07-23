import LorvexCore
import LorvexSystemIntents
import SwiftUI
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func intentHandoffStoreUsesSharedKeysAndSinglePendingTarget() {
  let suiteName = "LorvexIntentHandoffStoreTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = LorvexIntentHandoffStore(defaults: defaults)

  store.storeDestination(SidebarSelection.calendar.rawValue)

  #expect(defaults.string(forKey: LorvexIntentHandoffKeys.destination) == "calendar")
  #expect(store.consumeDestination() == "calendar")
  #expect(store.consumeDestination() == nil)

  store.storeDestination(SidebarSelection.today.rawValue)
  store.storeTask("task-from-system")

  #expect(defaults.string(forKey: LorvexIntentHandoffKeys.destination) == nil)
  #expect(store.consumeTaskID() == "task-from-system")
  #expect(store.consumeTaskID() == nil)
}
