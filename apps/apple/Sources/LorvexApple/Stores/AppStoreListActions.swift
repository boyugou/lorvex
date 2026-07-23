import Foundation
import LorvexCore

extension AppStore {
  func prepareListDraft(for list: LorvexList) {
    draftListName = list.name
    draftListDescription = list.description ?? ""
    draftListIcon = list.icon
    draftListColor = list.color
  }

  /// Reset the shared list draft to empty before presenting the create sheet.
  /// The draft fields are reused by the edit flow (``prepareListDraft(for:)``),
  /// so a create sheet opened after an edit would otherwise inherit the edited
  /// list's name and description.
  func beginCreateListDraft() {
    resetListDraft()
  }

  func createDraftList() async {
    // Guard against a double Return/click during the create round-trip (write +
    // reload), which would otherwise create duplicate lists.
    guard !isCreating else { return }
    isCreating = true
    defer { isCreating = false }
    guard
      let list = await performCanonicalMutation({
        try await core.createList(
          name: draftListName.trimmingCharacters(in: .whitespacesAndNewlines),
          description: draftListDescription.trimmedNilIfEmpty,
          color: draftListColor,
          icon: draftListIcon
        )
      })
    else { return }

    // The create is durable at this point. Close the draft and preserve the new
    // identity even if a derived list/detail reload fails afterward.
    selectedListID = list.id
    resetListDraft()
    await reconcileAfterCommittedMutation(source: "macos.list.create.reconcile") {
      lists = try await core.loadLists()
      try await loadSelectedListDetail()
    }
  }

  func updateList(_ list: LorvexList) async {
    // Guard against a double Return/click during the save round-trip.
    guard !isCreating else { return }
    isCreating = true
    defer { isCreating = false }
    await perform {
      let description = draftListDescription.trimmingCharacters(in: .whitespacesAndNewlines)
      _ = try await core.updateList(
        id: list.id,
        name: draftListName.trimmingCharacters(in: .whitespacesAndNewlines),
        description: description,
        color: draftListColor,
        icon: draftListIcon
      )
      lists = try await core.loadLists()
      selectedListID = list.id
      try await loadSelectedListDetail()
      resetListDraft()
    }
  }

  private func resetListDraft() {
    draftListName = ""
    draftListDescription = ""
    draftListIcon = nil
    draftListColor = nil
  }

  func deleteList(_ list: LorvexList) async {
    await perform {
      try await core.deleteList(id: list.id)
      lists = try await core.loadLists()
      archivedLists = try await core.loadArchivedLists()
      if selectedListID == list.id {
        selectedListID = lists?.lists.first?.id
        try await loadSelectedListDetail()
      }
      // The Tasks workspace scope drives the sidebar selection and quick-add
      // routing; left pointing at a deleted list it shows a stale empty scope
      // and silently creates tasks into a list the core no longer has.
      if taskWorkspaceListScopeID == list.id {
        setTaskWorkspaceListScope(nil)
        await loadTaskWorkspace()
      }
    }
  }

  /// Retires a list from the active set while keeping it and all its tasks.
  /// Mirrors ``deleteList(_:)``'s selection/scope cleanup since an archived list
  /// also drops out of the active Lists section, but the list itself survives in
  /// the Archived section and can be restored via ``unarchiveList(_:)``.
  func archiveList(_ list: LorvexList) async {
    await perform {
      _ = try await core.archiveList(id: list.id)
      lists = try await core.loadLists()
      archivedLists = try await core.loadArchivedLists()
      if selectedListID == list.id {
        selectedListID = lists?.lists.first?.id
        try await loadSelectedListDetail()
      }
      if taskWorkspaceListScopeID == list.id {
        setTaskWorkspaceListScope(nil)
        await loadTaskWorkspace()
      }
    }
  }

  func unarchiveList(_ list: LorvexList) async {
    await perform {
      _ = try await core.unarchiveList(id: list.id)
      lists = try await core.loadLists()
      archivedLists = try await core.loadArchivedLists()
    }
  }

  func moveSelectedTaskToSelectedList() async {
    guard let taskID = selectedTask?.id, let selectedListID else { return }
    await perform {
      _ = try await core.moveTask(id: taskID, toListID: selectedListID)
      today = try await core.loadToday()
      lists = try await core.loadLists()
      try await loadSelectedListDetail()
      selectedTaskID = taskID
      selection = .lists
      await republishSurfacesAfterLocalMutation()
    }
  }

  /// Moves the task identified by `taskID` into the list identified by `listID`.
  ///
  /// Refreshes today snapshot and list catalog after the move. Intended for
  /// drag-and-drop drop handlers where the task and list IDs come from transferred data.
  /// No-ops when the task is already in `listID` (prevents redundant core writes
  /// and surface republishing on self-drops).
  func moveTask(id taskID: LorvexTask.ID, toListID listID: LorvexList.ID) async {
    let alreadyInList =
      today.tasks.first(where: { $0.id == taskID })?.listID == listID
      || selectedListDetail?.tasks.first(where: { $0.id == taskID })?.listID == listID
    guard !alreadyInList else { return }
    await perform {
      _ = try await core.moveTask(id: taskID, toListID: listID)
      today = try await core.loadToday()
      lists = try await core.loadLists()
      if selectedListID == listID {
        try await loadSelectedListDetail()
      }
      await republishSurfacesAfterLocalMutation()
    }
  }

  /// Moves the currently-selected task (in the detail inspector) into `listID`.
  /// Unlike ``moveTask(id:toListID:)`` (scoped to the today/list-detail pools
  /// for drag-and-drop), this routes through `afterSelectedTaskMutation()` so
  /// every pool the inspector might have loaded the task from (today, list
  /// detail, the Tasks workspace) picks up the new `listID`,
  /// not just the two `moveTask` refreshes.
  func moveSelectedTaskToList(_ listID: LorvexList.ID) async {
    guard let taskID = selectedTask?.id, selectedTask?.listID != listID else { return }
    await perform {
      _ = try await core.moveTask(id: taskID, toListID: listID)
      try await afterSelectedTaskMutation()
    }
  }
}
