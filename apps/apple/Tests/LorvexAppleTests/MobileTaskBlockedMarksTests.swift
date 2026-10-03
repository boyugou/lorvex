import LorvexCore
import Testing

@testable import LorvexMobile

// The iOS task lists mark a task that waits on an unfinished task Blocked, and
// its row offers no Start, from the ids each page reads with its tasks.

@MainActor
@Test
func mobileTaskPagesMarkATaskThatWaitsOnAnUnfinishedOne() async throws {
  // The seeded "Book the offsite venue" waits on "Draft the team offsite agenda".
  let store = MobileStore(core: try await makeSeededInMemoryCore())
  let page = await store.taskWorkspacePage(scope: .all, query: "")
  #expect(page.tasks.contains { $0.id == LorvexPreviewSeedID.venueTask })
  #expect(page.blockedTaskIDs == [LorvexPreviewSeedID.venueTask])
  let search = await store.taskWorkspacePage(scope: .all, query: "venue")
  #expect(search.blockedTaskIDs == [LorvexPreviewSeedID.venueTask])

  _ = await store.completeTask(LorvexPreviewSeedID.agendaTask)
  let reloaded = await store.taskWorkspacePage(scope: .all, query: "")
  #expect(reloaded.blockedTaskIDs.isEmpty)
}

@Test
func appendedTaskPagesKeepEveryPagesMarks() {
  let first = MobileTaskWorkspacePage(
    tasks: [], totalMatching: 2, nextOffset: 1, blockedTaskIDs: ["a"])
  let second = MobileTaskWorkspacePage(
    tasks: [], totalMatching: 2, nextOffset: nil, blockedTaskIDs: ["b"])
  #expect(first.appending(second).blockedTaskIDs == ["a", "b"])
}
