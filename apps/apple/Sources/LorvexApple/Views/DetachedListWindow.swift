import LorvexCore
import SwiftUI

/// A value-typed window scene body that detaches a single list into its own native window.
///
/// SwiftUI's `WindowGroup(for: LorvexList.ID.self)` dedupes by value, so opening the same
/// list ID twice focuses the existing window instead of creating duplicates.
struct DetachedListWindow: View {
  let store: AppStore
  let listID: LorvexList.ID?

  var body: some View {
    Group {
      if let listID {
        DetachedListWindowContent(store: store, listID: listID)
      } else {
        DetachedWindowPlaceholder(
          systemImage: "tray",
          title: String(
            localized: "detached_window.placeholder.no_list_title",
            defaultValue: "No List Selected",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          )
        )
      }
    }
    .lorvexMinimumWindowSize(.lists)
    .tint(.accentColor)
  }
}

private struct DetachedListWindowContent: View {
  let store: AppStore
  let listID: LorvexList.ID

  @State private var windowStore: AppStore?
  @Environment(\.controlActiveState) private var controlActiveState

  var body: some View {
    Group {
      if let windowStore {
        ListDetailPane(store: windowStore)
          .lorvexRecurringCancelDialog(windowStore)
          .lorvexPermanentDeleteDialog(windowStore)
          .lorvexErrorAlert(windowStore)
      } else {
        DetachedWindowLoadingView(
          systemImage: "tray",
          title: String(localized: "sidebar.item.lists", defaultValue: "Lists", table: "Localizable", bundle: LorvexL10n.bundle)
        )
      }
    }
    .task(id: listID) {
      let detachedStore = windowStore ?? store.makeDetachedWindowStore()
      windowStore = detachedStore
      // Converge on MCP-host / main-window writes without a second CloudKit
      // stack — the regain-key path below is only a backstop for signals missed
      // while unfocused. Registered before the load await so the observers are
      // always paired with the `.onDisappear` teardown even if the window closes
      // mid-load; a signal before the load merely no-ops (no entity selected yet).
      detachedStore.startDetachedWindowObserversIfNeeded()
      await detachedStore.loadDetachedListWindow(listID: listID)
    }
    .onDisappear { windowStore?.stopDetachedWindowObservers() }
    // Re-read the list when the window regains key, so changes made in the main
    // window or by the assistant are visible here even if a live signal was
    // missed while unfocused — the multi-store coherence backstop
    // (docs/architecture/MULTI_STORE_COHERENCE.md).
    .onChange(of: controlActiveState) { _, newState in
      guard newState == .key, let windowStore else { return }
      Task { await windowStore.loadDetachedListWindow(listID: listID) }
    }
    .focusedSceneValue(
      \.lorvexTaskCommandContext,
      windowStore.map {
        LorvexTaskCommandContext(store: $0, selectionSurface: .selectedList)
      }
    )
  }
}
