import SwiftUI

struct MobileStoreDetailView: View {
  @Bindable var store: MobileStore
  /// Non-nil when the iPad sidebar has selected an extended domain destination.
  let iPadDestination: MobileDestination?

  var body: some View {
    if let destination = iPadDestination {
      NavigationStack {
        MobileDestinationView(destination: destination, store: store)
      }
    } else {
      switch store.selectedTab {
      case .today:
        NavigationStack(path: $store.routePath) {
          MobileStoreTodayView(store: store)
            .navigationTitle(MobileTab.today.title)
            // First-load skeleton on iPad regular width too, matching the compact
            // tab path; refreshes keep existing content visible.
            .overlay {
              if store.isLoading, store.snapshot.today == .empty {
                MobileInitialWorkspaceSkeleton()
              }
            }
            .navigationDestination(for: MobileRoute.self) { route in
              MobileStoreRouteView(route: route, store: store)
            }
        }
      case .tasks:
        NavigationStack(path: $store.tasksRoutePath) {
          MobileStoreTasksHomeView(store: store)
        }
      case .calendar:
        NavigationStack {
          MobileStoreCalendarView(store: store)
            .navigationDestination(for: MobileRoute.self) { route in
              MobileStoreRouteView(route: route, store: store)
            }
        }
      case .habits:
        NavigationStack {
          MobileStoreHabitsView(store: store)
            .navigationDestination(for: MobileRoute.self) { route in
              MobileStoreRouteView(route: route, store: store)
            }
        }
      case .more:
        NavigationStack {
          MobileStoreMoreView(store: store)
        }
      }
    }
  }
}
