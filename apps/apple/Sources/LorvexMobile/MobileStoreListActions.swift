import LorvexCore

extension MobileStore {
  public var canCreateListDraft: Bool {
    listDraft.canSubmit && !isCreatingList
  }

  public var canUpdateListDraft: Bool {
    listDraft.canSubmit && !isUpdatingList
  }

  public func prepareListDraft(for list: LorvexList) {
    listDraft = MobileListDraft(list: list)
  }

  /// Reset the shared list draft to empty before presenting the create sheet.
  /// `listDraft` is reused by the edit flow (``prepareListDraft(for:)``), so a
  /// create sheet opened after an edit would otherwise inherit the edited
  /// list's name and description.
  public func beginCreateListDraft() {
    listDraft = MobileListDraft()
  }

  @discardableResult
  public func createDraftList() async -> Bool {
    guard canCreateListDraft else { return false }
    isCreatingList = true
    defer { isCreatingList = false }
    guard
      let created = await performCanonicalMutation({
        try await core.createList(
          name: listDraft.trimmedName,
          description: listDraft.trimmedDescription.isEmpty ? nil : listDraft.trimmedDescription,
          color: listDraft.color,
          icon: listDraft.icon
        )
      })
    else { return false }

    listDraft = MobileListDraft()
    // The catalog must hold the new list before its screen opens, or the route
    // would read it as missing. A failed reload still adds the created row.
    await reconcileAfterCommittedMutation(source: "ios.list.create.reconcile") {
      lists = try await core.loadLists()
    }
    if lists?.lists.contains(where: { $0.id == created.id }) == false {
      lists?.lists.append(created)
    }
    openListRouteOnCurrentStack(created.id)
    return true
  }

  @discardableResult
  public func updateList(_ list: LorvexList) async -> Bool {
    guard canUpdateListDraft else { return false }
    isUpdatingList = true
    defer { isUpdatingList = false }
    do {
      // Three-state description patch: a non-empty field sets the value; an empty
      // field clears it (blanking the description in the editor is an explicit
      // "no value", never a silent leave-as-is).
      _ = try await core.updateList(
        id: list.id,
        name: LorvexListNaming.nameToStore(
          id: list.id, storedName: list.name, editedName: listDraft.trimmedName),
        description: listDraft.trimmedDescription.isEmpty
          ? .clear : .set(listDraft.trimmedDescription),
        color: listDraft.color,
        icon: listDraft.icon
      )
      lists = try await core.loadLists()
      listDraft = MobileListDraft()
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  @discardableResult
  public func deleteList(_ list: LorvexList) async -> Bool {
    guard !isDeletingList else { return false }
    isDeletingList = true
    defer { isDeletingList = false }
    do {
      try await core.deleteList(id: list.id)
      // Close the list's screen as soon as the delete commits, before the
      // catalog reload, so a failed reload cannot strand it.
      removeRoutes(toList: list.id)
      lists = try await core.loadLists()
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  /// Pops every screen of list `id` from every tab's stack, so a deleted
  /// list's screen closes wherever it was open.
  private func removeRoutes(toList id: LorvexList.ID) {
    let route = MobileRoute.tasksScope(.list(id))
    routePath.removeAll { $0 == route }
    tasksRoutePath.removeAll { $0 == route }
    calendarRoutePath.removeAll { $0 == route }
    habitsRoutePath.removeAll { $0 == route }
    reviewRoutePath.removeAll { $0 == route }
  }

  public func moveTask(_ taskID: LorvexTask.ID, toListID listID: LorvexList.ID) async {
    let moved = await mutateTaskReturningTask(id: taskID) {
      try await self.core.moveTask(id: taskID, toListID: listID)
    }
    guard moved else { return }
    do {
      lists = try await core.loadLists()
      errorMessage = nil
    } catch {
      await presentUserFacingError(error)
    }
  }
}
