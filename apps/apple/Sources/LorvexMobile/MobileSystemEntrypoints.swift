import SwiftUI

public struct MobileSystemEntrypointsModifier: ViewModifier {
  let store: MobileStore

  public func body(content: Content) -> some View {
    content
      .onAppear {
        store.applyPendingIntentHandoff()
      }
      .onOpenURL { url in
        store.openDeepLink(url)
      }
      .onContinueUserActivity(MobileActivityType.openTask) { activity in
        store.continueOpenTaskActivity(activity)
      }
      .onContinueUserActivity(MobileActivityType.openDestination) { activity in
        store.continueOpenDestinationActivity(activity)
      }
      .onContinueUserActivity(MobileActivityType.openList) { activity in
        store.continueOpenListActivity(activity)
      }
  }
}

extension View {
  public func lorvexMobileSystemEntrypoints(store: MobileStore) -> some View {
    modifier(MobileSystemEntrypointsModifier(store: store))
  }
}
