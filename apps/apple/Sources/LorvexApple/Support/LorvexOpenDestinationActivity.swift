import LorvexCore
import SwiftUI

extension View {
  /// Advertises an `openDestination` `NSUserActivity` for Handoff and Spotlight
  /// while `isActive` holds, named the way the sidebar names `selection` in the
  /// current language.
  func lorvexOpenDestinationActivity(
    selection: SidebarSelection,
    isActive: Bool
  ) -> some View {
    self.userActivity(LorvexActivityType.openDestination, isActive: isActive) { activity in
      configureOpenDestinationActivity(
        activity, selection: selection, title: String(localized: selection.macOSLocalizedTitle))
    }
  }
}
