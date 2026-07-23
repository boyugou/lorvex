import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

@MainActor
@Test
func mobileListDetailContentStateTreatsMissingOrStaleDetailAsLoading() async throws {
  let core = try await makeSeededInMemoryCore()
  let matchingDetail = try await core.loadListDetail(id: LorvexPreviewSeedID.appleNativeList, limit: 50, offset: 0)
  let staleDetail = try await core.loadListDetail(id: "inbox", limit: 50, offset: 0)

  #expect(
    MobileListDetailContentState.resolve(
      listID: LorvexPreviewSeedID.appleNativeList,
      isLoading: false,
      selectedDetail: nil,
      failedListDetailID: nil
    ) == .loading
  )
  #expect(
    MobileListDetailContentState.resolve(
      listID: LorvexPreviewSeedID.appleNativeList,
      isLoading: false,
      selectedDetail: staleDetail,
      failedListDetailID: nil
    ) == .loading
  )
  #expect(
    MobileListDetailContentState.resolve(
      listID: LorvexPreviewSeedID.appleNativeList,
      isLoading: true,
      selectedDetail: staleDetail,
      failedListDetailID: LorvexPreviewSeedID.appleNativeList
    ) == .loading
  )
  #expect(
    MobileListDetailContentState.resolve(
      listID: LorvexPreviewSeedID.appleNativeList,
      isLoading: false,
      selectedDetail: staleDetail,
      failedListDetailID: "inbox"
    ) == .loading
  )
  #expect(
    MobileListDetailContentState.resolve(
      listID: LorvexPreviewSeedID.appleNativeList,
      isLoading: false,
      selectedDetail: staleDetail,
      failedListDetailID: LorvexPreviewSeedID.appleNativeList
    ) == .unavailable
  )
  #expect(
    MobileListDetailContentState.resolve(
      listID: LorvexPreviewSeedID.appleNativeList,
      isLoading: false,
      selectedDetail: matchingDetail,
      failedListDetailID: LorvexPreviewSeedID.appleNativeList
    ) == .detail(matchingDetail)
  )
}

@MainActor
@Test
func mobileStoreLoadsListDetailThroughCore() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })

  await store.refresh()
  await store.loadListDetail(id: LorvexPreviewSeedID.appleNativeList)

  let detail = try #require(store.selectedListDetail)
  #expect(detail.list.name == "Apple Native")
  #expect(detail.tasks.map(\.id) == [LorvexPreviewSeedID.agendaTask, LorvexPreviewSeedID.statusUpdateTask])
  #expect(store.errorMessage == nil)
  #expect(store.isLoadingListDetail == false)
}

@MainActor
@Test
func mobileStoreListScopedTaskActionsReloadListDetail() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })

  await store.refresh()
  await store.loadListDetail(id: LorvexPreviewSeedID.appleNativeList)
  let task = try #require(
    store.selectedListDetail?.tasks.first { $0.id == LorvexPreviewSeedID.agendaTask }
  )
  #expect(task.status == .open)

  await store.completeTask(task.id, inList: LorvexPreviewSeedID.appleNativeList)

  // The list detail lists open tasks, so the completed row leaves it; the
  // detail's counts carry the evidence.
  #expect(
    store.selectedListDetail?.tasks.contains { $0.id == LorvexPreviewSeedID.agendaTask } == false)
  #expect(store.selectedListDetail?.list.id == LorvexPreviewSeedID.appleNativeList)
  #expect(store.selectedListDetail?.list.openCount == 1)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreMovesDroppedTaskToListAndReloadsCatalog() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  store.selectList(LorvexPreviewSeedID.appleNativeList)
  await store.loadListDetail(id: LorvexPreviewSeedID.appleNativeList)
  #expect(
    store.selectedListDetail?.tasks.map(\.id) == [LorvexPreviewSeedID.agendaTask, LorvexPreviewSeedID.statusUpdateTask])

  await store.moveTask(LorvexPreviewSeedID.venueTask, toListID: LorvexPreviewSeedID.appleNativeList)

  #expect(store.errorMessage == nil)
  #expect(store.isMutatingTask == false)
  #expect(store.lists?.lists.first { $0.id == LorvexPreviewSeedID.appleNativeList }?.openCount == 3)
  #expect(store.selectedListDetail?.list.id == LorvexPreviewSeedID.appleNativeList)
  #expect(store.selectedListDetail?.tasks.map(\.id).contains(LorvexPreviewSeedID.venueTask) == true)
  let movedPage = try await core.listTasks(
    status: "open", listID: LorvexPreviewSeedID.appleNativeList, priority: nil, text: "venue", limit: 10, offset: 0)
  #expect(movedPage.tasks.map(\.id).contains(LorvexPreviewSeedID.venueTask))
}

@MainActor
@Test
func mobileStoreCreatesListThroughCore() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
  await store.refresh()

  store.listDraft = MobileListDraft(
    name: "  Mobile Writing  ",
    description: "  Drafting from iPad  "
  )

  let created = await store.createDraftList()
  let detail = try #require(store.selectedListDetail)

  #expect(created)
  #expect(detail.list.name == "Mobile Writing")
  #expect(detail.list.description == "Drafting from iPad")
  #expect(store.lists?.lists.contains { $0.id == detail.list.id } == true)
  #expect(store.routePath == [.list(detail.list.id)])
  #expect(store.listDraft == MobileListDraft())
  #expect(store.errorMessage == nil)
  #expect(store.isCreatingList == false)
}

@MainActor
@Test
func mobileStoreUpdatesListThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  await store.loadListDetail(id: LorvexPreviewSeedID.appleNativeList)
  let list = try #require(store.selectedListDetail?.list)
  store.prepareListDraft(for: list)
  store.listDraft.name = "  Native Apple Work  "
  store.listDraft.description = "  Focused Swift surfaces  "

  let updated = await store.updateList(list)
  let detail = try #require(store.selectedListDetail)

  #expect(updated)
  #expect(detail.list.id == list.id)
  #expect(detail.list.name == "Native Apple Work")
  #expect(detail.list.description == "Focused Swift surfaces")
  #expect(
    store.lists?.lists.contains { $0.id == list.id && $0.name == "Native Apple Work" } == true)
  #expect(store.listDraft == MobileListDraft())
  #expect(store.errorMessage == nil)
  #expect(store.isUpdatingList == false)
}

@MainActor
@Test
func mobileStoreDeletesEmptyListThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  store.listDraft = MobileListDraft(name: "Empty Mobile List")
  let created = await store.createDraftList()
  let list = try #require(store.selectedListDetail?.list)

  let deleted = await store.deleteList(list)

  #expect(created)
  #expect(deleted)
  #expect(store.selectedListDetail == nil)
  #expect(store.lists?.lists.contains { $0.id == list.id } == false)
  #expect(store.routePath.contains(.list(list.id)) == false)
  #expect(store.errorMessage == nil)
  #expect(store.isDeletingList == false)
}

@MainActor
@Test
func mobileStoreBatchDeletesEmptyListsThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  store.listDraft = MobileListDraft(name: "First Empty Mobile List")
  let createdFirst = await store.createDraftList()
  let first = try #require(store.selectedListDetail?.list)
  store.listDraft = MobileListDraft(name: "Second Empty Mobile List")
  let createdSecond = await store.createDraftList()
  let second = try #require(store.selectedListDetail?.list)
  store.routePath = [.list(first.id), .list(second.id)]
  store.selectList(first.id)

  let deleted = await store.deleteLists([first, second])

  #expect(createdFirst)
  #expect(createdSecond)
  #expect(deleted)
  #expect(store.selectedListDetail == nil)
  #expect(store.selectedListID == nil)
  #expect(store.lists?.lists.contains { $0.id == first.id || $0.id == second.id } == false)
  #expect(store.routePath.contains(.list(first.id)) == false)
  #expect(store.routePath.contains(.list(second.id)) == false)
  #expect(store.errorMessage == nil)
  #expect(store.isDeletingList == false)
}

@MainActor
@Test
func mobileStoreBatchDeleteReconcilesUIAfterPartialFailure() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()

  // An empty, deletable list...
  store.listDraft = MobileListDraft(name: "Deletable Empty List")
  _ = await store.createDraftList()
  let deletable = try #require(store.selectedListDetail?.list)

  // ...plus the seeded list that holds tasks, whose delete the core refuses —
  // so the batch commits the first deletion and then fails on the second.
  await store.loadListDetail(id: LorvexPreviewSeedID.appleNativeList)
  let withTasks = try #require(store.selectedListDetail?.list)

  store.selectList(deletable.id)
  store.routePath = [.list(deletable.id), .list(withTasks.id)]

  let ok = await store.deleteLists([deletable, withTasks])

  #expect(ok == false, "a batch that fails on one item reports failure")
  // The UI reconciled from the store despite the failure: the committed deletion
  // is gone, the refused list remains, and nothing points at a deleted list.
  #expect(store.lists?.lists.contains { $0.id == deletable.id } == false)
  #expect(store.lists?.lists.contains { $0.id == withTasks.id } == true)
  #expect(store.selectedListID == nil, "the selection on the now-deleted list was cleared")
  #expect(store.routePath.contains(.list(deletable.id)) == false)
  #expect(store.routePath.contains(.list(withTasks.id)) == true)
  #expect(store.isDeletingList == false)
}

@MainActor
@Test
func mobileStoreRejectsDeletingListWithTasks() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })

  await store.refresh()
  await store.loadListDetail(id: LorvexPreviewSeedID.appleNativeList)
  let list = try #require(store.selectedListDetail?.list)

  let deleted = await store.deleteList(list)

  #expect(deleted == false)
  #expect(store.selectedListDetail?.list.id == list.id)
  #expect(store.lists?.lists.contains { $0.id == list.id } == true)
  #expect(store.errorMessage?.contains("Cannot delete list while") == true)
  #expect(store.isDeletingList == false)
}

@MainActor
@Test
func mobileStoreContinuesOpenListActivityIntoListRoute() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), selectedTab: .today)
  let activity = NSUserActivity(activityType: MobileActivityType.openList)
  activity.addUserInfoEntries(from: ["listID": LorvexPreviewSeedID.appleNativeList])

  store.continueOpenListActivity(activity)

  #expect(store.selectedTab == .more)
  #expect(store.moreNavigationPath == [.lists])
  #expect(store.pendingListRoute == .list(LorvexPreviewSeedID.appleNativeList))
}
