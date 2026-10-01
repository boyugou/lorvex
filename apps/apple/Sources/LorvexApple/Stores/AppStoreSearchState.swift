import Foundation
import LorvexCore

extension AppStore {
  /// The workspaces whose content a toolbar search field narrows: the task
  /// backlog and the assistant's memory, the two collections long enough to
  /// need filtering. Every other workspace shows its whole content.
  static let searchableSelections: Set<SidebarSelection> = [.tasks, .memory]

  /// Find (⌘F): focus the current workspace's search field, or, from a
  /// workspace without one, open All Tasks across every list and focus its
  /// field there.
  func beginSearch() {
    if !Self.searchableSelections.contains(selection) {
      setTaskWorkspaceListScope(nil)
      selection = .tasks
    }
    isSearchFocusRequested = true
  }

  var hasActiveSearch: Bool {
    !trimmedSearchText.isEmpty
  }

  var trimmedSearchText: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Memory entries narrowed by the search field through the shared
  /// ``LorvexCatalogSearch`` projection, so the Memory workspace filters exactly
  /// like the same surface on iOS. Preserves the core's returned order and is a
  /// pure client-side filter over the loaded snapshot; it never re-queries the
  /// core.
  var filteredMemoryEntries: [MemoryEntry] {
    LorvexCatalogSearch.memory(memoryEntries, query: trimmedSearchText)
  }
}
