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
      archivedLists.removeAll { $0.id == list.id }
      lists = try await core.loadLists()
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  /// Archives `list`, or restores an archived one. An archived list keeps every
  /// task and its history but leaves the active Lists screen and the list
  /// pickers; restoring brings it back. Archiving closes the list's own screen,
  /// wherever it is open, once the write commits. Returns whether the write
  /// committed.
  @discardableResult
  public func setListArchived(_ list: LorvexList, archived: Bool) async -> Bool {
    guard !isArchivingList else { return false }
    isArchivingList = true
    defer { isArchivingList = false }
    do {
      if archived {
        _ = try await core.archiveList(id: list.id)
        removeRoutes(toList: list.id)
      } else {
        _ = try await core.unarchiveList(id: list.id)
      }
      lists = try await core.loadLists()
      await loadArchivedLists()
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  /// Loads the archived lists for the Lists screen's restore section. A failed
  /// read keeps the last list rather than raising an error: the section is
  /// secondary to the active lists above it.
  public func loadArchivedLists() async {
    guard let loaded = try? await core.loadArchivedLists() else { return }
    archivedLists = loaded.lists
    archivedListsAreLoaded = true
  }

  /// Re-reads the archived lists once the Lists screen has loaded them, so an
  /// archive, restore, rename, or deletion made elsewhere (the assistant, the
  /// Mac) shows in the restore section while the screen is open. Before the
  /// first load the list stays unread.
  func reloadArchivedListsIfLoaded() async {
    guard archivedListsAreLoaded else { return }
    await loadArchivedLists()
  }

  /// Pops every screen of list `id` from every tab's stack, so a deleted
  /// list's screen closes wherever it was open.
  private func removeRoutes(toList id: LorvexList.ID) {
    let route = MobileRoute.tasksScope(.list(id))
    routePath.removeAll { $0 == route }
    tasksRoutePath.removeAll { $0 == route }
    calendarRoutePath.removeAll { $0 == route }
    reviewRoutePath.removeAll { $0 == route }
  }

  /// Moves task `taskID` to list `listID`; the lists' counts follow, since a
  /// task mutation reloads them.
  public func moveTask(_ taskID: LorvexTask.ID, toListID listID: LorvexList.ID) async {
    await mutateTaskReturningTask(id: taskID) {
      try await self.core.moveTask(id: taskID, toListID: listID)
    }
  }

  /// Moves every task in `ids` to list `listID` in one core call; the lists'
  /// counts follow, since a task mutation reloads them. A task already in the
  /// list stays where it is. Returns whether the move committed. A move that
  /// changed a task offers its undo, which files each task back into the list
  /// it came from.
  @discardableResult
  public func moveTasks(_ ids: [LorvexTask.ID], toListID listID: LorvexList.ID) async -> Bool {
    let uniqueIDs = stableUniqueTaskIDs(ids)
    guard !uniqueIDs.isEmpty else { return false }
    var origin: [LorvexTask.ID: LorvexList.ID] = [:]
    for id in uniqueIDs {
      if let task = try? await core.loadTask(id: id) {
        origin[id] = task.listID ?? LorvexListNaming.inboxID
      }
    }
    guard let movedIDs = await fileTasks(uniqueIDs, toListID: listID) else { return false }
    let changedIDs = movedIDs.filter { (origin[$0] ?? LorvexListNaming.inboxID) != listID }
    if !changedIDs.isEmpty {
      let back = Dictionary(grouping: changedIDs) { origin[$0] ?? LorvexListNaming.inboxID }
        .map { TaskListMoveStep(ids: $0.value, listID: $0.key) }
        .sorted { $0.listID < $1.listID }
      offerListMoveUndo(
        back: back, movedCount: changedIDs.count, toListID: listID)
    }
    return true
  }

  /// Files `ids` into list `listID` without offering an undo, which is what
  /// undoing a move runs. Returns the ids the core moved (those already in the
  /// list stay put), or nil when the move did not commit.
  @discardableResult
  func fileTasks(_ ids: [LorvexTask.ID], toListID listID: LorvexList.ID) async -> [LorvexTask.ID]? {
    var movedIDs: [LorvexTask.ID] = []
    let committed = await mutateTaskReturningToday(affectedIDs: ids) {
      movedIDs = try await self.core.batchMoveTasks(ids: ids, toListID: listID).moved.map(\.id)
      return try await self.core.loadToday()
    }
    guard committed else { return nil }
    feedbackProvider.playFeedback(.taskMoved)
    return movedIDs
  }
}
