import LorvexCore
import SwiftUI

/// The "More" tab on iPhone — lists all domain destinations not shown in the
/// primary tab bar. Tapping a row pushes into the matching workspace view.
@MainActor
public struct MobileStoreMoreView: View {
  @Bindable var store: MobileStore

  public init(store: MobileStore) {
    self.store = store
  }

  public var body: some View {
    NavigationStack(path: $store.moreNavigationPath) {
      List {
        Section(
          String(
            localized: "more.section.workspaces", defaultValue: "Workspaces", table: "Localizable",
            bundle: MobileL10n.bundle)
        ) {
          ForEach(workspaceDestinations) { destination in
            NavigationLink(value: destination) {
              MobileNavigationRow(
                title: destination.title,
                systemImage: destination.systemImage,
                tint: destination.tileTint
              )
              .accessibilityIdentifier("mobileMore.\(destination.rawValue)")
            }
          }
        }

        Section {
          NavigationLink(value: MobileDestination.settings) {
            MobileNavigationRow(
              title: MobileDestination.settings.title,
              systemImage: MobileDestination.settings.systemImage,
              tint: MobileDestination.settings.tileTint
            )
            .accessibilityIdentifier("mobileMore.settings")
          }
        }
      }
      .navigationTitle(
        String(
          localized: "tab.more", defaultValue: "More", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .navigationDestination(for: MobileDestination.self) { destination in
        MobileDestinationView(destination: destination, store: store)
      }
      .navigationDestination(for: MobileRoute.self) { route in
        MobileStoreRouteView(route: route, store: store)
      }
      .navigationDestination(
        isPresented: Binding(
          get: { store.pendingListRoute != nil },
          set: { if !$0 { store.pendingListRoute = nil } }
        )
      ) {
        if let route = store.pendingListRoute {
          MobileStoreRouteView(route: route, store: store)
        }
      }
    }
  }

  private var workspaceDestinations: [MobileDestination] { MobileDestination.secondaryWorkspaces }
}

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
      MobileStoreListsView(store: store)
    case .memory:
      MobileStoreMemoryView(store: store)
    case .review:
      MobileStoreReviewView(store: store)
    case .settings:
      MobileStoreSettingsView(store: store)
    }
  }
}
