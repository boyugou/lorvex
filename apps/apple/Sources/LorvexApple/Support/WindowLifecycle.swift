@preconcurrency import CoreSpotlight
import LorvexCore
import SwiftUI

extension View {
  func lorvexMainWindowLifecycle(
    _ store: AppStore,
    openMainWindow: @escaping () -> Void = {}
  ) -> some View {
    task {
      await store.refresh()
      store.applyPendingIntentHandoff()
    }
    .onAppear {
      store.applyPendingIntentHandoff()
    }
    .onOpenURL { url in
      Task { await store.openDeepLink(url) }
    }
    .onContinueUserActivity(LorvexActivityType.openTask) { activity in
      store.continueActivity(activity)
      openMainWindow()
    }
    .onContinueUserActivity(LorvexActivityType.openDestination) { activity in
      store.continueActivity(activity)
      openMainWindow()
    }
    .onContinueUserActivity(LorvexActivityType.openList) { activity in
      store.continueActivity(activity)
      openMainWindow()
    }
    .onContinueUserActivity(CSSearchableItemActionType) { activity in
      store.continueActivity(activity)
      openMainWindow()
    }
  }

  func lorvexRefreshOnOpen(_ store: AppStore) -> some View {
    task {
      await store.refresh()
    }
  }

  func lorvexRefreshableWindow(_ windowID: LorvexWindowID, store: AppStore) -> some View {
    lorvexMinimumWindowSize(windowID)
      .lorvexRefreshOnOpen(store)
  }
}
