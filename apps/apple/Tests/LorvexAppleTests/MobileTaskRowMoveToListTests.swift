import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

@MainActor
@Test("A task row's actions carry the list catalog and file the task into another list")
func mobileRowActionsFileATaskIntoAnotherList() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let id = LorvexPreviewSeedID.venueTask
  #expect(try await core.loadTask(id: id).listID == LorvexPreviewSeedID.inboxList)
  var reloads = 0

  let actions = store.rowActions(for: id, afterSuccess: { reloads += 1 })
  #expect(actions.lists.contains { $0.id == LorvexPreviewSeedID.appleNativeList })
  await actions.moveToList(LorvexPreviewSeedID.appleNativeList)

  #expect(try await core.loadTask(id: id).listID == LorvexPreviewSeedID.appleNativeList)
  #expect(reloads == 1)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test("A refused move leaves the task where it was and does not reload the host page")
func mobileRowActionsDoNotReloadAfterARefusedMove() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let id = LorvexPreviewSeedID.venueTask
  var reloads = 0

  await store.rowActions(for: id, afterSuccess: { reloads += 1 }).moveToList("no-such-list")

  #expect(try await core.loadTask(id: id).listID == LorvexPreviewSeedID.inboxList)
  #expect(reloads == 0)
}

@Test("Only an open task's context menu offers Move to List, without the task's own list")
func mobileRowMenuOffersMoveToListForOpenTasksOnly() throws {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources/LorvexMobile/MobileTaskRowActions.swift")
  let text = try String(contentsOf: url, encoding: .utf8)

  let menu = try #require(text.range(of: ".contextMenu {"))
  let definition = try #require(text.range(of: "private var moveToListMenu"))
  let body = text[menu.upperBound..<definition.lowerBound]
  let resolvedBranch = try #require(body.range(of: "if isResolved {"))
  let openBranch = try #require(body.range(of: "} else {", range: resolvedBranch.upperBound..<body.endIndex))
  let deferMenu = try #require(body.range(of: "MobileDeferMenu("))
  let moveMenu = try #require(body.range(of: "moveToListMenu"))
  #expect(openBranch.upperBound < deferMenu.lowerBound)
  #expect(deferMenu.upperBound < moveMenu.lowerBound)
  #expect(!body[..<openBranch.lowerBound].contains("moveToListMenu"))

  let menuText = text[definition.lowerBound...]
  #expect(menuText.contains("task.listID ?? LorvexListNaming.inboxID"))
  #expect(menuText.contains("$0.id != current"))
  #expect(menuText.contains("MobileListMenuLabel(list: list)"))
}
