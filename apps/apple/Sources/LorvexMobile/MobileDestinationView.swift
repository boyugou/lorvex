import SwiftUI

/// Routes a `MobileDestination` to its corresponding full workspace view.
@MainActor
struct MobileDestinationView: View {
  let destination: MobileDestination
  @Bindable var store: MobileStore

  var body: some View {
    switch destination {
    case .tasks:
      MobileStoreTasksView(store: store)
    case .calendar:
      MobileStoreCalendarView(store: store)
    case .habits:
      MobileStoreHabitsView(store: store)
    case .lists:
      // Lists live on the Tasks home, below the smart collections.
      MobileStoreTasksHomeView(store: store)
    case .memory:
      MobileStoreMemoryView(store: store)
    case .review:
      MobileStoreReviewView(store: store)
    case .settings:
      MobileStoreSettingsView(store: store)
    }
  }
}
