import CloudKit
import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexDomain
import Synchronization
import Testing

@testable import LorvexMobile

// P2 (dirty-domain reload gating): an inbound sync reloads ONLY the mobile
// surfaces whose entity kinds it applied. These drive `MobileStore.refresh()` end
// to end through a real coordinator + `StubFocusCoreService` (a delegating,
// call-counting core), so a habits-only push must re-read habits without touching
// the calendar / list surfaces, while a multi-domain push re-reads each. The
// counting core delegates the atomic traversal page to its real in-memory core,
// so the applied-kind report is produced by the production apply path.

@MainActor
private func makeSelectiveLiveStore(
  core: any LorvexCoreServicing,
  records: [CKRecord]
) -> MobileStore {
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(availability: .available),
    pusher: RecordingRecordPusher(),
    fetcher: StubRemoteChangeFetcher(records: records, serverChangeTokenData: Data([0x02])),
    accountIdentifier: StubAccountIdentifier(identifier: "account-A"),
    accountIdentityStore: RecordingAccountIdentityStore(initial: "account-A"))
  return MobileStore(
    core: core,
    todayString: { "2026-05-23" },
    cloudSyncMode: .live,
    cloudSyncCoordinator: coordinator)
}

@MainActor
@Test("an inbound habits-only sync reloads habits but not the calendar/list surfaces")
func mobileInboundHabitsOnlyReloadsHabitsOnly() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = makeSelectiveLiveStore(
    core: core,
    records: [inboundSelectiveRecord(.habit, "01966a3f-7c8b-7d4e-8f3a-000000000021", 1)])

  let result = await store.refresh()

  #expect(result == .newData)
  #expect(store.lastCloudSyncCycleReport?.inbound.appliedEntityTypes == [.habit])
  // Phase 1 loaded every surface once from the pre-apply state; the selective
  // phase-2 reload re-read ONLY habits.
  #expect(core.loadHabitsCallCount == 2)
  // The unrelated surfaces stayed at their single phase-1 load — the win. (These
  // surfaces are each read exactly once per full refresh, so an unchanged count
  // proves the selective reload skipped them.)
  #expect(core.loadCalendarTimelineCallCount == 1)
  #expect(core.loadListsCallCount == 1)
}

@MainActor
@Test("an inbound calendar-only sync reloads the calendar but not habits/lists")
func mobileInboundCalendarOnlyReloadsCalendarOnly() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = makeSelectiveLiveStore(
    core: core,
    records: [inboundSelectiveRecord(.calendarEvent, "01966a3f-7c8b-7d4e-8f3a-000000000031", 2)])

  let result = await store.refresh()

  #expect(result == .newData)
  #expect(store.lastCloudSyncCycleReport?.inbound.appliedEntityTypes == [.calendarEvent])
  #expect(core.loadCalendarTimelineCallCount == 2)
  #expect(core.loadHabitsCallCount == 1)
  #expect(core.loadListsCallCount == 1)
}

@MainActor
@Test("an inbound sync spanning multiple domains reloads all of them")
func mobileInboundMultiDomainReloadsAll() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = makeSelectiveLiveStore(
    core: core,
    records: [
      inboundSelectiveRecord(.habit, "01966a3f-7c8b-7d4e-8f3a-000000000041", 3),
      inboundSelectiveRecord(.calendarEvent, "01966a3f-7c8b-7d4e-8f3a-000000000042", 4),
    ])

  let result = await store.refresh()

  #expect(result == .newData)
  #expect(store.lastCloudSyncCycleReport?.inbound.appliedEntityTypes == [.habit, .calendarEvent])
  // Both affected surfaces reload; the list surface (untouched) does not.
  #expect(core.loadHabitsCallCount == 2)
  #expect(core.loadCalendarTimelineCallCount == 2)
  #expect(core.loadListsCallCount == 1)
}

@MainActor
@Test("an inbound task sync reloads task-bearing surfaces but not habits")
func mobileInboundTaskReloadsTaskSurfacesNotHabits() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = makeSelectiveLiveStore(
    core: core,
    records: [inboundSelectiveRecord(.task, "01966a3f-7c8b-7d4e-8f3a-000000000051", 5)])

  let result = await store.refresh()

  #expect(result == .newData)
  #expect(store.lastCloudSyncCycleReport?.inbound.appliedEntityTypes == [.task])
  // A task fans out across today + lists + calendar/scheduled, but never habits.
  #expect(core.loadTodayCallCount == 2)
  #expect(core.loadListsCallCount == 2)
  #expect(core.loadCalendarTimelineCallCount == 2)
  #expect(core.loadHabitsCallCount == 1)
}

@MainActor
@Test("selective domains invalidate view-owned task/list/habit query state")
func mobileInboundDomainsBumpViewInvalidationRevisions() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" },
    cloudSyncMode: .off)

  let taskBefore = store.taskWorkspaceRevision
  let listBefore = store.listDetailRevision
  let habitBefore = store.habitDetailRevision
  await store.reloadInboundDomains([.tasks])
  #expect(store.taskWorkspaceRevision == taskBefore + 1)
  #expect(store.listDetailRevision == listBefore + 1)
  #expect(store.habitDetailRevision == habitBefore)

  await store.reloadInboundDomains([.habits])
  #expect(store.taskWorkspaceRevision == taskBefore + 1)
  #expect(store.listDetailRevision == listBefore + 1)
  #expect(store.habitDetailRevision == habitBefore + 1)
}

@MainActor
@Test("post-mutation report adoption reloads a concurrent peer write into primary UI")
func mobilePostMutationReportReloadsInboundPrimarySurface() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(
    core: core, todayString: { "2026-05-23" }, cloudSyncMode: .off)
  let deliveries = Mutex(0)
  let token = NotificationCenter.default.addObserver(
    forName: DatabaseChangeSignal.didChangeNotification,
    object: store,
    queue: nil
  ) { _ in
    deliveries.withLock { $0 += 1 }
  }
  defer { NotificationCenter.default.removeObserver(token) }
  store.lastCloudSyncCycleReport = CloudSyncCycleReport(
    pushedRecordCount: 1, failedPushCount: 0, fetchedRecordCount: 0,
    moreInboundComing: false,
    inbound: InboundApplyReport(applied: 1, appliedEntityTypes: [.habit]))

  // `publishMobileSyncSurfaces` calls this seam after its post-mutation cycle.
  // It must not run MobileStore.refresh() or another sync cycle.
  await store.reloadInboundSurfacesIfNeeded(after: .newData)

  #expect(store.lastCloudSyncCycleReport?.inbound.appliedEntityTypes == [.habit])
  #expect(core.loadHabitsCallCount == 1)
  #expect(core.loadTodayCallCount == 0)
  #expect(core.loadListsCallCount == 0)
  #expect(core.loadCalendarTimelineCallCount == 0)
  #expect(deliveries.withLock { $0 } == 1)
}

@MainActor
@Test("an ordinary confirmed push does not reload unchanged local surfaces")
func mobileOrdinaryOutboundConfirmationSkipsLocalReload() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(
    core: core, todayString: { "2026-05-23" }, cloudSyncMode: .off)
  store.lastCloudSyncCycleReport = CloudSyncCycleReport(
    pushedRecordCount: 1, failedPushCount: 0, fetchedRecordCount: 0,
    moreInboundComing: false, inbound: InboundApplyReport())

  await store.reloadInboundSurfacesIfNeeded(after: .newData)

  #expect(core.loadHabitsCallCount == 0)
  #expect(core.loadTodayCallCount == 0)
  #expect(core.loadListsCallCount == 0)
  #expect(core.loadCalendarTimelineCallCount == 0)
}

@MainActor
@Test("a memory-only reload reconciles selection while preserving the draft")
func mobileInboundMemoryReloadPreservesDraft() async throws {
  let preview = try await makeSeededInMemoryCore()
  let entry = try await preview.upsertMemory(key: "remote-memory", content: "before")
  let core = StubFocusCoreService(preview: preview)
  let store = MobileStore(
    core: core, todayString: { "2026-05-23" }, cloudSyncMode: .off)

  await store.loadMemorySnapshot()
  store.selectMemoryEntry(entry.id)
  store.beginEditingMemory(entry)
  store.memoryContentDraft = "unsaved local edit"
  _ = try await preview.deleteMemory(key: entry.key)

  await store.reloadInboundDomains([.memory])

  #expect(core.loadMemoryCallCount == 2)
  #expect(store.memory?.entries.contains(where: { $0.id == entry.id }) == false)
  #expect(store.selectedMemoryKey == nil)
  #expect(store.memoryContentDraft == "unsaved local edit")
  #expect(store.memoryEditingKey == nil)
}
