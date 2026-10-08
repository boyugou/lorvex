import Foundation
import LorvexCore

extension AppStore {
  func prepareListDraft(for list: LorvexList) {
    draftListName = list.displayName
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
      // Three-state description patch: a non-empty field sets the value; an empty
      // field clears it (blanking the description in the editor is an explicit
      // "no value", never a silent leave-as-is).
      _ = try await core.updateList(
        id: list.id,
        name: LorvexListNaming.nameToStore(
          id: list.id, storedName: list.name,
          editedName: draftListName.trimmingCharacters(in: .whitespacesAndNewlines)),
        description: description.isEmpty ? .clear : .set(description),
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
