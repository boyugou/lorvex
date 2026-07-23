import SwiftUI

/// iPad sidebar showing all primary tabs plus the full domain workspace set.
/// Tapping a primary tab clears `store.iPadDestination`; tapping a workspace destination
/// sets it, driving the detail column independently of `MobileStore.selectedTab`.
struct MobileStoreSidebarList: View {
  @Bindable var store: MobileStore
  let appDisplayName: String

  var body: some View {
    List(selection: $store.iPadDestination) {
      Section(
        String(
          localized: "sidebar.section.main", defaultValue: "Main", table: "Localizable",
          bundle: MobileL10n.bundle)
      ) {
        ForEach(MobileTab.allCases.filter { $0 != .more }) { tab in
          MobileSidebarTabRow(
            tab: tab,
            isSelected: store.selectedTab == tab && store.iPadDestination == nil
          ) {
            store.selectedTab = tab
            store.iPadDestination = nil
            store.moreNavigationPath = []
            store.pendingListRoute = nil
          }
        }
      }

      Section(
        String(
          localized: "more.section.workspaces", defaultValue: "Workspaces", table: "Localizable",
          bundle: MobileL10n.bundle)
      ) {
        ForEach(MobileDestination.secondaryWorkspaces) { destination in
          NavigationLink(value: destination) {
            Label(destination.title, systemImage: destination.systemImage)
          }
          .accessibilityIdentifier("mobileSidebar.\(destination.rawValue)")
        }
      }

      Section {
        NavigationLink(value: MobileDestination.settings) {
          Label(
            String(
              localized: "destination.settings", defaultValue: "Settings", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "gearshape")
        }
        .accessibilityIdentifier("mobileSidebar.settings")
      }
    }
    .navigationTitle(appDisplayName)
    .overlay {
      if store.isLoading {
        MobileInitialWorkspaceSkeleton()
      }
    }
  }
}

/// A primary-tab row in the iPad / visionOS sidebar. Extracted into its own view
/// so the modifier chain stays within the type-checker's complexity budget and
/// so the row can carry a `hoverEffect` for pointer (iPad) and gaze (visionOS).
private struct MobileSidebarTabRow: View {
  let tab: MobileTab
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      Label {
        Text(tab.title)
          .fontWeight(isSelected ? .semibold : .regular)
          .foregroundStyle(.primary)
      } icon: {
        Image(systemName: tab.systemImage)
          .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .lorvexRowHoverEffect()
    .listRowBackground(rowBackground)
    .accessibilityIdentifier("mobileSidebar.\(tab.rawValue)")
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  private var rowBackground: some View {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
  }
}
