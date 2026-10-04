import LorvexCore
import SwiftUI

extension View {
  /// Adds the window-toolbar search field for the workspace `selection`, or
  /// nothing for a workspace without search (``AppStore/workspaceSearchPrompt(for:)``).
  ///
  /// A window applies it once, above whichever workspace it shows, never
  /// inside each workspace: the window then keeps one search item while the
  /// user moves between two searchable workspaces and only its prompt
  /// changes. Two workspace-owned fields would be two toolbar items, and
  /// AppKit raises when SwiftUI inserts the next one before removing the
  /// last.
  func lorvexWorkspaceSearchField(store: AppStore, selection: SidebarSelection) -> some View {
    modifier(WorkspaceSearchHost(store: store, selection: selection))
  }

  /// The search field itself, with a fixed prompt. The field edits the store's
  /// ``AppStore/searchText``, and takes keyboard focus when Find (⌘F) asks for
  /// it — including a request made just before the workspace appeared.
  ///
  /// The field holds the toolbar's trailing edge behind a flexible space the
  /// system inserts, so a workspace that adds it keeps its own toolbar actions
  /// at the leading edge: a spacer pushing them toward the field would leave
  /// them floating mid-toolbar.
  func lorvexWorkspaceSearchField(store: AppStore, prompt: String) -> some View {
    modifier(WorkspaceSearchField(store: store, prompt: prompt))
  }
}

private struct WorkspaceSearchHost: ViewModifier {
  @Bindable var store: AppStore
  let selection: SidebarSelection

  func body(content: Content) -> some View {
    if let prompt = store.workspaceSearchPrompt(for: selection) {
      content.lorvexWorkspaceSearchField(store: store, prompt: prompt)
    } else {
      content
    }
  }
}

extension AppStore {
  /// The search field's placeholder for a workspace that has search, naming
  /// what it narrows: every task, the scoped list's tasks, or the memory
  /// notes. Nil for the workspaces without search.
  func workspaceSearchPrompt(for selection: SidebarSelection) -> String? {
    switch selection {
    case .tasks:
      if let listID = taskWorkspaceListScopeID, let list = lists?.lists.first(where: { $0.id == listID }) {
        return String(
          format: String(
            localized: "tasks.search.prompt_list", defaultValue: "Search “%@”", table: "Localizable",
            bundle: LorvexL10n.bundle),
          Self.promptListName(list.displayName, limit: Self.searchPromptListNameLimit))
      }
      return String(localized: "tasks.search.prompt", defaultValue: "Search All Tasks", table: "Localizable", bundle: LorvexL10n.bundle)
    case .memory:
      return String(localized: "memory.search.prompt", defaultValue: "Search Memory", table: "Localizable", bundle: LorvexL10n.bundle)
    case .today, .lists, .calendar, .habits, .reviews:
      return nil
    }
  }
}

private struct WorkspaceSearchField: ViewModifier {
  @Bindable var store: AppStore
  let prompt: String
  @FocusState private var isFocused: Bool

  func body(content: Content) -> some View {
    content
      .searchable(text: $store.searchText, placement: .toolbar, prompt: Text(prompt))
      .searchFocused($isFocused)
      .onChange(of: store.isSearchFocusRequested, initial: true) { _, requested in
        guard requested else { return }
        store.isSearchFocusRequested = false
        // The toolbar installs the field after the workspace's first layout,
        // so focus waits a turn for a workspace that just appeared.
        Task { @MainActor in
          await Task.yield()
          isFocused = true
        }
      }
  }
}
