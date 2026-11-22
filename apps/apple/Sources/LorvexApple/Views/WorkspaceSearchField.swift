import LorvexCore
import SwiftUI

extension View {
  /// Mount search beside the split view. Switching workspace can then remove the
  /// native toolbar item without replacing the content that owns the toolbar.
  func lorvexWorkspaceSearchField(store: AppStore, selection: SidebarSelection) -> some View {
    background {
      if let prompt = store.workspaceSearchPrompt(for: selection) {
        Color.clear
          .frame(width: 0, height: 0)
          .modifier(WorkspaceSearchField(store: store, prompt: prompt))
      }
    }
  }
}

extension AppStore {
  /// The search field's placeholder for a workspace that has search, naming
  /// what it searches: every task, the scoped list's tasks, the memory notes,
  /// or the calendar's events. Nil for the workspaces without search.
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
    case .calendar:
      return String(
        localized: "calendar.search.prompt", defaultValue: "Search Events", table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .reviews:
      return ReviewJournalBrowser.searchPrompt
    case .today, .lists, .habits:
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
