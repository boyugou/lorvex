import Foundation
import LorvexCore

extension AppStore {
  func prepareListDraft(for list: LorvexList) {
    draftListName = list.displayName
    draftListDescription = list.description ?? ""
    draftListIcon = list.icon
    draftListColor = list.color
    listsStorage.draftListBaseline = AppStoreListsStorage.ListDraftBaseline(
      storedName: list.name,
      name: draftListName.trimmingCharacters(in: .whitespacesAndNewlines),
      description: draftListDescription.trimmingCharacters(in: .whitespacesAndNewlines),
      icon: draftListIcon,
      color: draftListColor)
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
      let baseline = listsStorage.draftListBaseline
      let name = draftListName.trimmingCharacters(in: .whitespacesAndNewlines)
      let description = draftListDescription.trimmingCharacters(in: .whitespacesAndNewlines)
      // Only the fields the user changed from the baseline are sent; nil and
      // `.unset` leave the others as stored, including a change another writer
      // made while the sheet was open. A description the user emptied clears it.
      _ = try await core.updateList(
        id: list.id,
        name: name == baseline?.name
          ? nil
          : LorvexListNaming.nameToStore(
            id: list.id, storedName: baseline?.storedName ?? list.name, editedName: name),
        description: description == baseline?.description
          ? .unset : description.isEmpty ? .clear : .set(description),
        color: draftListColor == baseline?.color ? nil : draftListColor,
        icon: draftListIcon == baseline?.icon ? nil : draftListIcon
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
    listsStorage.draftListBaseline = nil
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

  /// Returns an archived list to the active set. An archived list can stay
  /// selected, so when it is the one shown its detail is re-read to drop the
  /// archived header.
  func unarchiveList(_ list: LorvexList) async {
    await perform {
      _ = try await core.unarchiveList(id: list.id)
      lists = try await core.loadLists()
      archivedLists = try await core.loadArchivedLists()
      if selectedListID == list.id {
        try await loadSelectedListDetail()
      }
    }
  }

  /// Moves the currently-selected task (in the detail inspector) into `listID`.
  /// Routes through `afterSelectedTaskMutation()` so every pool the inspector
  /// might have loaded the task from (today, list detail, the Tasks workspace)
  /// picks up the new `listID`. Dragging tasks onto a list and the Move to List
  /// menu go through ``moveTasks(ids:toListID:undoManager:)`` instead, which
  /// also confirms the move and registers its undo.
  func moveSelectedTaskToList(_ listID: LorvexList.ID) async {
    guard let taskID = selectedTask?.id, selectedTask?.listID != listID else { return }
    await perform {
      _ = try await core.moveTask(id: taskID, toListID: listID)
      try await afterSelectedTaskMutation()
    }
  }
}
