import LorvexCore
import Testing

@Test
func previewCoreServiceSetsAndLoadsCurrentFocus() async throws {
  let service = try await makeSeededInMemoryCore()
  let today = try await service.loadToday()
  let ids = Array(today.tasks.prefix(2).map(\.id))

  let plan = try await service.setCurrentFocus(
    date: "2026-05-22",
    taskIDs: ids,
    briefing: "Preview focus",
    timezone: "America/Los_Angeles"
  )
  let loaded = try await service.loadCurrentFocus(date: "2026-05-22")

  #expect(plan.taskIDs == ids)
  #expect(loaded?.briefing == "Preview focus")
}

@Test
func previewCoreServiceRemovesCurrentFocusTask() async throws {
  let service = try await makeSeededInMemoryCore()
  let today = try await service.loadToday()
  let ids = Array(today.tasks.prefix(2).map(\.id))
  _ = try await service.setCurrentFocus(
    date: "2026-05-22",
    taskIDs: ids,
    briefing: "Preview focus",
    timezone: "America/Los_Angeles"
  )

  let remaining = try await service.removeFromCurrentFocus(date: "2026-05-22", taskID: ids[0])
  let cleared = try await service.removeFromCurrentFocus(date: "2026-05-22", taskID: ids[1])

  #expect(remaining?.taskIDs == [ids[1]])
  #expect(cleared == nil)
  #expect(try await service.loadCurrentFocus(date: "2026-05-22") == nil)
}

@Test
func previewCoreServiceAddsAndClearsCurrentFocus() async throws {
  let service = try await makeSeededInMemoryCore()
  let today = try await service.loadToday()
  let ids = Array(today.tasks.prefix(2).map(\.id))
  _ = try await service.setCurrentFocus(
    date: "2026-05-22",
    taskIDs: [ids[0]],
    briefing: "Preview focus",
    timezone: "America/Los_Angeles"
  )

  let added = try await service.addToCurrentFocus(
    date: "2026-05-22",
    taskIDs: [ids[0], ids[1]],
    briefing: nil,
    timezone: "America/Los_Angeles"
  )
  let cleared = try await service.clearCurrentFocus(date: "2026-05-22")

  #expect(added.taskIDs == ids)
  #expect(cleared == nil)
  #expect(try await service.loadCurrentFocus(date: "2026-05-22") == nil)
}

@Test
func previewCoreServiceProposesAndSavesFocusSchedule() async throws {
  let service = try await makeSeededInMemoryCore()
  let today = try await service.loadToday()
  let ids = Array(today.tasks.prefix(2).map(\.id))
  _ = try await service.setCurrentFocus(
    date: "2026-05-22",
    taskIDs: ids,
    briefing: "Preview focus",
    timezone: "America/Los_Angeles"
  )

  let proposed = try await service.proposeFocusSchedule(date: "2026-05-22")
  let saved = try await service.saveFocusSchedule(
    date: "2026-05-22",
    blocks: proposed.blocks,
    rationale: "Preview schedule"
  )
  let loaded = try await service.loadFocusSchedule(date: "2026-05-22")

  // The real proposal engine interleaves structure blocks (buffers) with the
  // work; the contract is one task block per focused task, in order.
  #expect(proposed.blocks.compactMap(\.taskID) == ids)
  #expect(saved.rationale == "Preview schedule")
  #expect(loaded?.blocks.compactMap(\.taskID) == ids)
}
