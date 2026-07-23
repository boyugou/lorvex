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

  public func loadListDetail(id: LorvexList.ID) async {
    listDetailLoadToken &+= 1
    let token = listDetailLoadToken
    isLoadingListDetail = true
    failedListDetailID = nil
    do {
      let detail = try await core.loadListDetail(id: id, limit: 50, offset: 0)
      // The user switched lists while this load was in flight; the newer load
      // owns the detail and the loading flag, so discard this stale result.
      guard token == listDetailLoadToken else { return }
      selectedListDetail = detail
      failedListDetailID = nil
      errorMessage = nil
      isLoadingListDetail = false
    } catch {
      guard token == listDetailLoadToken else { return }
      failedListDetailID = id
      await presentUserFacingError(error)
      isLoadingListDetail = false
    }
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

    selectedListID = created.id
    listDraft = MobileListDraft()
    openNavigationTarget(MobileNavigationTarget(selectedTab: .today, route: .list(created.id)))
    await reconcileAfterCommittedMutation(source: "ios.list.create.reconcile") {
      lists = try await core.loadLists()
      selectedListDetail = try await core.loadListDetail(id: created.id, limit: 50, offset: 0)
    }
    return true
  }

  @discardableResult
  public func updateList(_ list: LorvexList) async -> Bool {
    guard canUpdateListDraft else { return false }
    isUpdatingList = true
    defer { isUpdatingList = false }
    do {
      _ = try await core.updateList(
        id: list.id,
        name: listDraft.trimmedName,
        description: listDraft.trimmedDescription,
        color: listDraft.color,
        icon: listDraft.icon
      )
      lists = try await core.loadLists()
      selectedListDetail = try await core.loadListDetail(id: list.id, limit: 50, offset: 0)
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
      lists = try await core.loadLists()
      if selectedListDetail?.list.id == list.id {
        selectedListDetail = nil
      }
      if selectedListID == list.id {
        selectedListID = nil
      }
      routePath.removeAll { route in
        if case .list(let id) = route {
          return id == list.id
        }
        return false
      }
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  @discardableResult
  public func deleteLists(_ listsToDelete: some Sequence<LorvexList>) async -> Bool {
    guard !isDeletingList else { return false }
    let listsToDelete = Array(listsToDelete)
    guard !listsToDelete.isEmpty else { return false }

    isDeletingList = true
    defer { isDeletingList = false }

    // Each delete is its own transaction, so a mid-batch failure leaves the
    // earlier deletions committed. Stop on the first failure but ALWAYS reconcile
    // the displayed state against the store afterward — otherwise a partial batch
    // leaves the UI showing rows already gone from SQLite (and a selection/route
    // pointing at a deleted list).
    var caught: Error?
    for list in listsToDelete {
      do {
        try await core.deleteList(id: list.id)
      } catch {
        caught = error
        break
      }
    }

    lists = (try? await core.loadLists()) ?? lists
    let liveIDs = Set(lists?.lists.map(\.id) ?? [])
    if let detailID = selectedListDetail?.list.id, !liveIDs.contains(detailID) {
      selectedListDetail = nil
    }
    if let selectedListID, !liveIDs.contains(selectedListID) {
      self.selectedListID = nil
    }
    routePath.removeAll { route in
      if case .list(let id) = route {
        return !liveIDs.contains(id)
      }
      return false
    }

    if let caught {
      await presentUserFacingError(caught)
      return false
    }
    errorMessage = nil
    return true
  }

  public func completeTask(_ taskID: LorvexTask.ID, inList listID: LorvexList.ID) async {
    await completeTask(taskID)
    await reloadListDetailAfterSuccessfulTaskMutation(listID)
  }

  public func deferTaskToTomorrow(_ taskID: LorvexTask.ID, inList listID: LorvexList.ID) async {
    await deferTaskToTomorrow(taskID)
    await reloadListDetailAfterSuccessfulTaskMutation(listID)
  }

  public func toggleTaskFocus(_ taskID: LorvexTask.ID, inList listID: LorvexList.ID) async {
    await toggleTaskFocus(taskID)
    await reloadListDetailAfterSuccessfulTaskMutation(listID)
  }

  public func moveTask(_ taskID: LorvexTask.ID, toListID listID: LorvexList.ID) async {
    let moved = await mutateTaskReturningTask(id: taskID) {
      try await self.core.moveTask(id: taskID, toListID: listID)
    }
    guard moved else { return }
    do {
      lists = try await core.loadLists()
      if let selectedListID {
        selectedListDetail = try await core.loadListDetail(id: selectedListID, limit: 50, offset: 0)
      }
      errorMessage = nil
    } catch {
      await presentUserFacingError(error)
    }
  }

  private func reloadListDetailAfterSuccessfulTaskMutation(_ listID: LorvexList.ID) async {
    guard errorMessage == nil else { return }
    await loadListDetail(id: listID)
  }
}
