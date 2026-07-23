import LorvexCore
import SwiftUI

extension View {
  /// Advertises an `openDestination` `NSUserActivity` for Handoff and Spotlight,
  /// active only while `selection` matches `destination`.
  ///
  /// Equivalent to the repeated `.userActivity(LorvexActivityType.openDestination, …)`
  /// blocks that appear in each workspace view. Consolidating here ensures the
  /// activity keys stay in sync across every destination.
  func lorvexOpenDestinationActivity(
    selection: SidebarSelection,
    isActive: Bool
  ) -> some View {
    self.userActivity(LorvexActivityType.openDestination, isActive: isActive) { activity in
      let built = makeOpenDestinationActivity(selection: selection)
      activity.title = built.title
      activity.isEligibleForHandoff = built.isEligibleForHandoff
      activity.isEligibleForSearch = built.isEligibleForSearch
      activity.requiredUserInfoKeys = built.requiredUserInfoKeys
      activity.addUserInfoEntries(from: built.userInfo ?? [:])
    }
  }
}
