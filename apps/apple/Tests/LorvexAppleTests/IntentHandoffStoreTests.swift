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

@Test
func intentHandoffStoreKeepsOnePendingQuickAction() {
  let suiteName = "LorvexIntentHandoffQuickActionTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = LorvexIntentHandoffStore(defaults: defaults)

  store.storeQuickAction(.quickCapture)

  #expect(
    defaults.string(forKey: LorvexIntentHandoffKeys.quickAction)
      == LorvexQuickAction.quickCapture.rawValue)
  #expect(store.consumeQuickAction() == .quickCapture)
  #expect(store.consumeQuickAction() == nil)

  // The newest request replaces an older one of any other kind, so the app
  // never applies two requests for one tap.
  store.storeTask("task-from-system")
  store.storeQuickAction(.openToday)
  #expect(store.consumeTaskID() == nil)
  #expect(store.consumeQuickAction() == .openToday)

  store.storeQuickAction(.quickCapture)
  store.storeDestination(SidebarSelection.calendar.rawValue)
  #expect(store.consumeQuickAction() == nil)
  #expect(store.consumeDestination() == "calendar")

  store.storeQuickAction(.quickCapture)
  store.clear()
  #expect(store.consumeQuickAction() == nil)
}

@Test
func intentHandoffStoreDropsAQuickActionThatNamesNothing() {
  let suiteName = "LorvexIntentHandoffUnknownActionTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = LorvexIntentHandoffStore(defaults: defaults)

  defaults.set("com.lorvex.apple.notAnAction", forKey: LorvexIntentHandoffKeys.quickAction)

  #expect(store.consumeQuickAction() == nil)
  #expect(defaults.string(forKey: LorvexIntentHandoffKeys.quickAction) == nil)
}
