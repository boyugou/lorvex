import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// A task that waits on an unfinished task cannot start: the core refuses with
// `TaskLifecycleError.startBlockedByDependencies`. The task detail on every
// platform keeps Start unavailable while that is so, judged by
// `LorvexTask.isHeldUp(by:)` or by the core's own test, and the task lists
// mark such a task Blocked from the ids the core reports
// (`LorvexTaskServicing.blockedTaskIDs`). These pin the predicate, its
// agreement with the core for every state a blocker can be in, the reported
// ids, and the Mac store's re-read whenever task data changes.

private func task(
  _ id: String, status: LorvexTask.Status = .open, dependsOn: [String] = [],
  archivedAt: String? = nil
) -> LorvexTask {
  LorvexTask(
    id: id, title: "Task \(id)", notes: "", priority: .p2, status: status,
    dueDate: nil, estimatedMinutes: nil, tags: [], dependsOn: dependsOn,
    archivedAt: archivedAt)
}

@Test
func unfinishedTasksHoldUpTheTasksThatWaitOnThem() {
  #expect(task("a", status: .open).holdsUpDependents)
  #expect(task("a", status: .inProgress).holdsUpDependents)
  #expect(task("a", status: .someday).holdsUpDependents)
  #expect(!task("a", status: .completed).holdsUpDependents)
  #expect(!task("a", status: .cancelled).holdsUpDependents)
  #expect(!task("a", status: .open, archivedAt: "2026-10-03T00:00:00Z").holdsUpDependents)
}

@Test
func onlyListedUnfinishedDependenciesHoldATaskUp() {
  let waiting = task("w", dependsOn: ["a", "b"])
  #expect(waiting.isHeldUp(by: [task("a", status: .completed), task("b", status: .open)]))
  #expect(!waiting.isHeldUp(by: [task("a", status: .completed), task("b", status: .cancelled)]))
  // An unfinished task the task does not list does not count.
  #expect(!waiting.isHeldUp(by: [task("c", status: .open)]))
  // Nor does a dependency that is not loaded or no longer exists.
  #expect(!waiting.isHeldUp(by: []))
  #expect(!task("free").isHeldUp(by: [task("a", status: .open)]))
}

/// Each state the task a task waits on can be in, reached through the core.
enum BlockerState: String, CaseIterable, Sendable {
  case open, started, someday, completed, cancelled, trashed

  func apply(to id: LorvexTask.ID, in core: SwiftLorvexCoreService) async throws {
    switch self {
    case .open: break
    case .started: _ = try await core.startTask(id: id)
    case .someday: _ = try await core.markTaskSomeday(id: id)
    case .completed: _ = try await core.completeTask(id: id)
    case .cancelled: _ = try await core.cancelTask(id: id)
    case .trashed: _ = try await core.archiveTask(id: id)
    }
  }
}

@Test(arguments: BlockerState.allCases)
func startGateAgreesWithTheCore(_ state: BlockerState) async throws {
  // The seeded "Book the offsite venue" waits on "Draft the team offsite agenda".
  let core = try await makeSeededInMemoryCore()
  try await state.apply(to: LorvexPreviewSeedID.agendaTask, in: core)
  let venue = try await core.loadTask(id: LorvexPreviewSeedID.venueTask)
  let agenda = try? await core.loadTask(id: LorvexPreviewSeedID.agendaTask)
  let isHeldUp = venue.isHeldUp(by: agenda.map { [$0] } ?? [])

  do {
    _ = try await core.startTask(id: venue.id)
    #expect(!isHeldUp, "the core started a task the gate holds up (blocker \(state.rawValue))")
  } catch {
    #expect(isHeldUp, "the core refused a start the gate allows (blocker \(state.rawValue))")
    #expect(UserFacingError.Reason(error) == .taskStartBlocked)
  }
}

@MainActor
@Test
func macStoreHoldsUpStartWhileATaskItWaitsOnIsUnfinished() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, cloudSyncMode: .off)
  await store.refresh()
  let venue = try await core.loadTask(id: LorvexPreviewSeedID.venueTask)
  #expect(await store.blockedTaskIDs(in: [venue]) == [venue.id])

  // The selected task's own read (heldUpTaskID) gates Start and the command
  // too, whatever the loaded lists say.
  if let load = store.applyRouteNavigation(.task(venue.id)) { await load() }
  #expect(store.selectedTaskID == venue.id)
  await store.refreshSelectedTaskStartGate()
  #expect(store.heldUpTaskID == venue.id)
  #expect(store.startIsHeldUp(for: venue))
  let context = LorvexTaskCommandContext(store: store, selectionSurface: nil)
  #expect(!TaskCommand.toggleStarted.isEnabled(in: context))

  let agenda = try await core.loadTask(id: LorvexPreviewSeedID.agendaTask)
  await store.toggleTaskCompletion(agenda)
  #expect(await store.blockedTaskIDs(in: [venue]).isEmpty)
  await store.refreshSelectedTaskStartGate()
  #expect(store.heldUpTaskID == nil)
  #expect(!store.startIsHeldUp(for: try await core.loadTask(id: venue.id)))
  #expect(TaskCommand.toggleStarted.isEnabled(in: context))
}

@Test
func theCoreReportsTheTasksThatWaitOnUnfinishedOnes() async throws {
  let core = try await makeSeededInMemoryCore()
  let venue = try await core.loadTask(id: LorvexPreviewSeedID.venueTask)
  let agenda = try await core.loadTask(id: LorvexPreviewSeedID.agendaTask)
  #expect(venue.mayBeBlocked)
  #expect(!task("a", status: .completed, dependsOn: ["b"]).mayBeBlocked)
  #expect(!task("a", status: .someday, dependsOn: ["b"]).mayBeBlocked)
  #expect(!task("a").mayBeBlocked)
  #expect(try await core.blockedTaskIDs(in: [venue, agenda]) == [venue.id])
  #expect(try await core.blockedTaskIDs(among: []).isEmpty)
  let listID = try #require(venue.listID)
  let detail = try await core.loadListDetail(id: listID, limit: 100, offset: 0)
  #expect(detail.blockedTaskIDs.contains(venue.id))

  _ = try await core.completeTask(id: agenda.id)
  #expect(try await core.blockedTaskIDs(among: [venue.id]).isEmpty)
  let reloaded = try await core.loadListDetail(id: listID, limit: 100, offset: 0)
  #expect(!reloaded.blockedTaskIDs.contains(venue.id))
}

@MainActor
@Test
func macTaskListsMarkATaskThatWaitsOnAnUnfinishedOne() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, cloudSyncMode: .off)
  await store.refresh()
  await store.loadTaskWorkspace()
  let venue = try await core.loadTask(id: LorvexPreviewSeedID.venueTask)
  // The Tasks workspace's own pages mark it.
  #expect(store.taskWorkspaceStorage.blockedTaskIDs.contains(venue.id))
  #expect(store.isBlocked(venue))

  // Finishing the blocker reloads the workspace, which drops the mark.
  let agenda = try await core.loadTask(id: LorvexPreviewSeedID.agendaTask)
  await store.toggleTaskCompletion(agenda)
  #expect(!store.taskWorkspaceStorage.blockedTaskIDs.contains(venue.id))
  #expect(!store.isBlocked(venue))
}

@MainActor
@Test
func macTaskDataGenerationAdvancesWhenTaskDataIsReRead() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, cloudSyncMode: .off)

  let initial = store.taskDataGeneration
  await store.refresh()
  let afterRefresh = store.taskDataGeneration
  #expect(afterRefresh > initial)

  // An inbound reload that touches no task-bearing surface leaves it alone.
  await store.performSelectiveInboundReload([.memory])
  #expect(store.taskDataGeneration == afterRefresh)
  await store.performSelectiveInboundReload([.tasks])
  let afterInbound = store.taskDataGeneration
  #expect(afterInbound > afterRefresh)

  let agenda = try await core.loadTask(id: LorvexPreviewSeedID.agendaTask)
  await store.toggleTaskCompletion(agenda)
  #expect(store.taskDataGeneration > afterInbound)
}
