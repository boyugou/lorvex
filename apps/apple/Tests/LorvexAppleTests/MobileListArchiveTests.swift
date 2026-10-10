import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

@MainActor
@Test("Archiving a list keeps its tasks, moves it to the archived lists, and closes its screen")
func mobileArchivingAListMovesItToTheArchivedLists() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), selectedTab: .tasks, todayString: { "2026-05-23" })
  await store.refresh()
  let list = try #require(store.lists?.lists.first { $0.id == LorvexPreviewSeedID.appleNativeList })
  let route = MobileRoute.tasksScope(.list(list.id))
  store.tasksRoutePath = [route]

  let archived = await store.setListArchived(list, archived: true)

  #expect(archived)
  #expect(store.lists?.lists.contains { $0.id == list.id } == false)
  #expect(store.archivedLists.map(\.id) == [list.id])
  #expect(store.archivedLists.first?.isArchived == true)
  #expect(store.archivedLists.first?.totalCount == list.totalCount, "an archived list keeps its tasks")
  #expect(store.tasksRoutePath.isEmpty, "the archived list's screen closes")
  #expect(store.errorMessage == nil)
  #expect(store.isArchivingList == false)
}

@MainActor
@Test("Restoring an archived list returns it to the active lists")
func mobileRestoringAListReturnsItToTheActiveLists() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
  await store.refresh()
  let list = try #require(store.lists?.lists.first { $0.id == LorvexPreviewSeedID.appleNativeList })
  _ = await store.setListArchived(list, archived: true)
  let archivedRow = try #require(store.archivedLists.first)

  let restored = await store.setListArchived(archivedRow, archived: false)

  #expect(restored)
  #expect(store.archivedLists.isEmpty)
  #expect(store.lists?.lists.contains { $0.id == list.id } == true)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test("The Inbox cannot be archived and a refused archive leaves the lists unchanged")
func mobileArchivingTheInboxIsRefused() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
  await store.refresh()
  let inbox = try #require(store.lists?.lists.first { $0.isInbox })
  let before = store.lists?.lists.map(\.id)

  let archived = await store.setListArchived(inbox, archived: true)

  #expect(archived == false)
  #expect(store.lists?.lists.map(\.id) == before)
  #expect(store.archivedLists.isEmpty)
  #expect(store.errorMessage != nil)
  #expect(store.isArchivingList == false)
}

@MainActor
@Test("Deleting an empty archived list removes it from the archived lists")
func mobileDeletingAnArchivedListRemovesItFromTheSection() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
  await store.refresh()
  store.listDraft = MobileListDraft(name: "Finished Project")
  _ = await store.createDraftList()
  let list = try #require(store.lists?.lists.first { $0.name == "Finished Project" })
  _ = await store.setListArchived(list, archived: true)
  let archivedRow = try #require(store.archivedLists.first)
  #expect(archivedRow.totalCount == 0)

  let deleted = await store.deleteList(archivedRow)

  #expect(deleted)
  #expect(store.archivedLists.isEmpty)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test("Archived lists are read once the Lists screen asks, then follow every reload")
func mobileArchivedListsReloadOnlyAfterTheFirstLoad() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let list = try #require(store.lists?.lists.first { $0.id == LorvexPreviewSeedID.appleNativeList })
  _ = try await core.archiveList(id: list.id)

  // Nothing reads them before the Lists screen does.
  await store.refresh()
  #expect(store.archivedLists.isEmpty)
  #expect(store.archivedListsAreLoaded == false)

  await store.loadArchivedLists()
  #expect(store.archivedLists.map(\.id) == [list.id])

  // A change made elsewhere reaches the section on the next refresh.
  _ = try await core.unarchiveList(id: list.id)
  await store.refresh()
  #expect(store.archivedLists.isEmpty)
  #expect(store.archivedListsAreLoaded)
}

@Test("The archive words resolve from the catalog instead of falling back to their keys")
func mobileListArchiveCopyReadsTheCatalog() {
  let words = [
    MobileListArchiveCopy.archive, MobileListArchiveCopy.archiveList,
    MobileListArchiveCopy.restore, MobileListArchiveCopy.sectionTitle,
  ]

  for word in words {
    #expect(!word.isEmpty)
    #expect(!word.contains("lists.") && !word.contains("list_detail."))
  }
}
