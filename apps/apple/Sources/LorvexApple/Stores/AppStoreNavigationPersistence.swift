import Foundation
import LorvexCore

extension AppStore {
  enum Key {
    static let selection = "navigation.selection"
    static let selectedTaskID = "navigation.selectedTaskID"
    static let todayDoneCollapsed = "today.done.collapsed"
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

  /// Opens the Tasks workspace scoped to the list `id`, from the sidebar's list
  /// rows, the Lists catalog, or the command palette. Dismisses any selected
  /// task first, since the list it belonged to may not be the one opening.
  func openTaskListScope(_ id: LorvexList.ID) {
    selectedTaskID = nil
    setTaskWorkspaceListScope(id)
    selection = .tasks
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
  /// `defaults` on the previous launch; missing entries leave the in-memory
  /// defaults intact. The app bootstrap calls this once on the store it builds
  /// for the main window. Every other store (a preview, a detached window, a
  /// snapshot dump, a test) starts on Today with no selection: it still
  /// persists its own navigation into whichever defaults it was given, and a
  /// store restoring from the standard defaults would take over the selection
  /// another store in the same process last wrote there.
  func restorePersistedLaunchState() {
    if let rawSelection = defaults.string(forKey: Key.selection),
      let restoredSelection = SidebarSelection.matching(rawSelection),
      // Don't restore a selection the Mac has no surface for — fall through to
      // the in-memory default.
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
