import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

@MainActor
@Test
func mobileListScopePageLoadsTheListsOpenTasksThroughCore() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
  await store.refresh()

  let page = await store.taskWorkspacePage(
    scope: .list(LorvexPreviewSeedID.appleNativeList), query: "")

  #expect(page.tasks.map(\.id) == [LorvexPreviewSeedID.agendaTask, LorvexPreviewSeedID.statusUpdateTask])
  #expect(page.totalMatching == 2)
  // The page fills the task cache, so a task opened from the list resolves.
  #expect(store.resolveTask(LorvexPreviewSeedID.statusUpdateTask) != nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreMovesDroppedTaskToListAndReloadsCatalog() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let revision = store.taskWorkspaceRevision

  await store.moveTask(LorvexPreviewSeedID.venueTask, toListID: LorvexPreviewSeedID.appleNativeList)

  #expect(store.errorMessage == nil)
  #expect(store.isMutatingTask == false)
  #expect(store.lists?.lists.first { $0.id == LorvexPreviewSeedID.appleNativeList }?.openCount == 3)
  // The open list screen re-queries on the revision bump.
  #expect(store.taskWorkspaceRevision != revision)
  let movedPage = try await core.listTasks(
    status: "open", listID: LorvexPreviewSeedID.appleNativeList, priority: nil, text: "venue", limit: 10, offset: 0)
  #expect(movedPage.tasks.map(\.id).contains(LorvexPreviewSeedID.venueTask))
}

@MainActor
@Test
func mobileStoreCreatesListAndOpensItsScreen() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(), selectedTab: .tasks, todayString: { "2026-05-23" })
  await store.refresh()

  store.listDraft = MobileListDraft(
    name: "  Mobile Writing  ",
    description: "  Drafting from iPad  "
  )

  let created = await store.createDraftList()
  let list = try #require(store.lists?.lists.first { $0.name == "Mobile Writing" })

  #expect(created)
  #expect(list.description == "Drafting from iPad")
  // The catalog already holds the list when its screen opens, so the route
  // never reads it as missing.
  #expect(store.tasksRoutePath == [.tasksScope(.list(list.id))])
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
  let list = try #require(store.lists?.lists.first { $0.id == LorvexPreviewSeedID.appleNativeList })
  store.prepareListDraft(for: list)
  store.listDraft.name = "  Native Apple Work  "
  store.listDraft.description = "  Focused Swift surfaces  "

  let updated = await store.updateList(list)
  let reloaded = try #require(store.lists?.lists.first { $0.id == list.id })

  #expect(updated)
  #expect(reloaded.name == "Native Apple Work")
  #expect(reloaded.description == "Focused Swift surfaces")
  #expect(store.listDraft == MobileListDraft())
  #expect(store.errorMessage == nil)
  #expect(store.isUpdatingList == false)
}

@MainActor
@Test
func mobileStoreClearsListDescriptionThroughEditSheet() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let list = try #require(store.lists?.lists.first { $0.id == LorvexPreviewSeedID.appleNativeList })

  // Give the list a description through the edit sheet.
  store.prepareListDraft(for: list)
  store.listDraft.description = "Focused Swift surfaces"
  #expect(await store.updateList(list))
  let withDescription = try #require(store.lists?.lists.first { $0.id == list.id })
  #expect(withDescription.description == "Focused Swift surfaces")

  // Emptying the description field and saving must NULL the column, not leave the
  // old value — the three-state edit-sheet clear path.
  store.prepareListDraft(for: withDescription)
  store.listDraft.description = ""
  #expect(await store.updateList(withDescription))
  let cleared = try #require(store.lists?.lists.first { $0.id == list.id })
  #expect(cleared.description == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreDeletingAListClosesItsScreenOnEveryStack() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, selectedTab: .tasks, todayString: { "2026-05-23" })

  await store.refresh()
  store.listDraft = MobileListDraft(name: "Empty Mobile List")
  let created = await store.createDraftList()
  let list = try #require(store.lists?.lists.first { $0.name == "Empty Mobile List" })
  let listRoute = MobileRoute.tasksScope(.list(list.id))
  // The list's screen is open on the Tasks stack (from creation) and on Today.
  store.routePath = [listRoute]
  #expect(store.tasksRoutePath == [listRoute])

  let deleted = await store.deleteList(list)

  #expect(created)
  #expect(deleted)
  #expect(store.lists?.lists.contains { $0.id == list.id } == false)
  #expect(store.tasksRoutePath.isEmpty)
  #expect(store.routePath.isEmpty)
  #expect(store.errorMessage == nil)
  #expect(store.isDeletingList == false)
}

@MainActor
@Test
func mobileStoreRejectsDeletingListWithTasks() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })

  await store.refresh()
  let list = try #require(store.lists?.lists.first { $0.id == LorvexPreviewSeedID.appleNativeList })
  let listRoute = MobileRoute.tasksScope(.list(list.id))
  store.tasksRoutePath = [listRoute]

  let deleted = await store.deleteList(list)

  #expect(deleted == false)
  #expect(store.tasksRoutePath == [listRoute], "a refused delete leaves the list's screen open")
  #expect(store.lists?.lists.contains { $0.id == list.id } == true)
  #expect(store.errorMessage?.contains("Cannot delete list while") == true)
  #expect(store.isDeletingList == false)
}

@MainActor
@Test
func mobileListInboxIsTheSeededFallbackList() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
  await store.refresh()

  let lists = try #require(store.lists?.lists)
  #expect(lists.filter(\.isInbox).map(\.id) == [LorvexListNaming.inboxID])
  #expect(lists.first { $0.id == LorvexPreviewSeedID.appleNativeList }?.isInbox == false)
}

@MainActor
@Test
func mobileStoreContinuesOpenListActivityIntoListRoute() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), selectedTab: .today)
  let activity = NSUserActivity(activityType: MobileActivityType.openList)
  activity.addUserInfoEntries(from: ["listID": LorvexPreviewSeedID.appleNativeList])

  store.continueOpenListActivity(activity)

  #expect(store.selectedTab == .tasks)
  #expect(store.tasksRoutePath == [.tasksScope(.list(LorvexPreviewSeedID.appleNativeList))])
}
