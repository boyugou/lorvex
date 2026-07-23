import Foundation
import LorvexCore

extension AppStore {
  enum Key {
    static let selection = "navigation.selection"
    static let selectedTaskID = "navigation.selectedTaskID"
  }

  /// User-initiated workspace navigation from the sidebar, the Navigate menu, or
  /// the command palette. Dismisses any selected task first so the detail
  /// inspector never carries a selection from the previous workspace into one
  /// where it doesn't belong — a task opened in Tasks must not linger over the
  /// Lists catalog. Programmatic "reveal this task" flows set `selection`
  /// directly, pairing it with a fresh `selectedTaskID`, and deliberately skip
  /// this path.
  func navigateToWorkspace(_ destination: SidebarSelection) {
    selectedTaskID = nil
    if destination == .tasks || destination == .lists {
      setTaskWorkspaceListScope(nil)
    }
    selection = destination
  }

  /// Sidebar destinations whose UI actually consumes `selectedTaskID`. Other
  /// destinations clear it on switch so the detail pane and toolbar actions
  /// don't show stale state.
  static func selectionUsesSelectedTaskID(_ selection: SidebarSelection) -> Bool {
    switch selection {
    case .today, .tasks, .lists: true
    // These surfaces don't consume `selectedTaskID`, so a stray selection
    // clears the task rather than carrying an inspector into them.
    case .calendar, .habits, .reviews, .memory:
      false
    }
  }

  func persistSelectedTaskID() {
    if let selectedTaskID {
      defaults.set(selectedTaskID, forKey: AppStore.Key.selectedTaskID)
    } else {
      defaults.removeObject(forKey: AppStore.Key.selectedTaskID)
    }
  }

  /// Restores the sidebar selection and selected-task id persisted in
  /// `defaults` on the previous launch. Called once at the end of `init`;
  /// missing entries leave the in-memory defaults intact.
  func restorePersistedLaunchState() {
    if let rawSelection = defaults.string(forKey: Key.selection),
      let restoredSelection = SidebarSelection.matching(rawSelection),
      // Don't restore a selection that no longer has a Mac human surface (Matrix,
      // Dependencies, Memory) — fall through to the in-memory default.
      SidebarSelection.mainNavigationItems.contains(restoredSelection)
    {
      selection = restoredSelection
    }
    if Self.selectionUsesSelectedTaskID(selection) {
      selectedTaskID = defaults.string(forKey: Key.selectedTaskID)
    } else {
      selectedTaskID = nil
      defaults.removeObject(forKey: Key.selectedTaskID)
    }
  }
}
