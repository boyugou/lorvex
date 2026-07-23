import CloudKit
import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexDomain
import Testing

@testable import LorvexApple

// P2 (dirty-domain reload gating): on macOS the inbound sync runs at the tail of a
// refresh fan-out; when it applies records attributable to a bounded set of
// domains it reloads ONLY those inline instead of requesting a full trailing
// rerun. These drive `AppStore.refresh()` end to end through a real coordinator +
// a counting `StubFocusCoreService`, asserting that a habits-only push re-reads
// habits without re-reading the calendar / list / diagnostics surfaces, while a
// task push re-reads the task-bearing surfaces but never habits.
//
// The unattributable case (records fetched but not cleanly attributed) still
// falls back to the full `refreshPending` rerun — covered by
// `AppStoreInboundSyncReloadTests` (concurrency-M3), whose fetcher applies via a
// side channel and returns a foreign marker, so its applied-kind set is empty.

@MainActor
private func makeSelectiveAppStore(
  core: any LorvexCoreServicing,
  records: [CKRecord],
  widget: RecordingWidgetSnapshotPublisher
) -> AppStore {
  let coordinator = CloudSyncEngineCoordinator(
    accountChecker: StubAccountStatusChecker(availability: .available),
    pusher: RecordingRecordPusher(),
    fetcher: StubRemoteChangeFetcher(records: records, serverChangeTokenData: Data([0x02])),
    accountIdentifier: StubAccountIdentifier(identifier: "sel-account"),
    accountIdentityStore: RecordingAccountIdentityStore(),
    accountPauseStore: RecordingCloudSyncPauseStore())
  return AppStore(
    core: core,
    widgetSnapshotPublisher: widget,
    cloudSyncMode: .live,
    cloudSyncCoordinator: coordinator)
}

@MainActor
@Test("an inbound habits-only sync reloads habits inline, not the calendar/list/diagnostics surfaces")
func appStoreInboundHabitsOnlyReloadsHabitsOnly() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let widget = RecordingWidgetSnapshotPublisher()
  let store = makeSelectiveAppStore(
    core: core,
    records: [inboundSelectiveRecord(.habit, "01966a3f-7c8b-7d4e-8f3a-0000000000a1", 1)],
    widget: widget)

  await store.refresh()

  #expect(store.lastCloudSyncCycleReport?.inbound.appliedEntityTypes == [.habit])
  // The fan-out loaded every surface once; the inline selective reload re-read
  // ONLY habits (`loadHabits` goes 1 → 2).
  #expect(core.loadHabitsCallCount == 2)
  // Untouched surfaces stayed at their fan-out baseline. Lists and diagnostics are
  // each read once per fan-out (clean baseline 1); the calendar timeline is read
  // twice per fan-out — once for the timeline surface, once for the Spotlight
  // content index — so its unchanged baseline is 2.
  #expect(core.loadListsCallCount == 1)
  #expect(core.loadRuntimeDiagnosticsCallCount == 1)
  #expect(core.loadCalendarTimelineCallCount == 2)
  // The widget was republished from the reloaded habits (habits feed the habits
  // widget): once in the fan-out, once in the selective reload.
  #expect(widget.publishedSnapshots().count == 2)
  // The selective path took the inline branch, not the full `refreshPending`
  // rerun — the single-flight loop settled without a queued full reload.
  #expect(store.refreshPending == false)
  #expect(store.isRefreshing == false)
}

@MainActor
@Test("an inbound task sync reloads the task-bearing surfaces inline but never habits")
func appStoreInboundTaskReloadsTaskSurfacesNotHabits() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let widget = RecordingWidgetSnapshotPublisher()
  let store = makeSelectiveAppStore(
    core: core,
    records: [inboundSelectiveRecord(.task, "01966a3f-7c8b-7d4e-8f3a-0000000000b2", 2)],
    widget: widget)

  await store.refresh()

  #expect(store.lastCloudSyncCycleReport?.inbound.appliedEntityTypes == [.task])
  // today / lists each go 1 → 2 (fan-out + selective); the calendar timeline goes
  // 2 → 3 (its fan-out baseline is 2: surface + Spotlight index).
  #expect(core.loadTodayCallCount == 2)
  #expect(core.loadListsCallCount == 2)
  #expect(core.loadCalendarTimelineCallCount == 3)
  // A task change never reloads the independent habits surface.
  #expect(core.loadHabitsCallCount == 1)
  #expect(store.refreshPending == false)
}

@MainActor
@Test("an inbound sync spanning multiple domains reloads all of them inline")
func appStoreInboundMultiDomainReloadsAll() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let widget = RecordingWidgetSnapshotPublisher()
  let store = makeSelectiveAppStore(
    core: core,
    records: [
      inboundSelectiveRecord(.habit, "01966a3f-7c8b-7d4e-8f3a-0000000000c1", 3),
      inboundSelectiveRecord(.calendarEvent, "01966a3f-7c8b-7d4e-8f3a-0000000000c2", 4),
    ],
    widget: widget)

  await store.refresh()

  #expect(store.lastCloudSyncCycleReport?.inbound.appliedEntityTypes == [.habit, .calendarEvent])
  // Both affected surfaces reload: habits 1 → 2, calendar timeline 2 → 3.
  #expect(core.loadHabitsCallCount == 2)
  #expect(core.loadCalendarTimelineCallCount == 3)
  // The list / diagnostics surfaces stayed at their single fan-out load.
  #expect(core.loadListsCallCount == 1)
  #expect(core.loadRuntimeDiagnosticsCallCount == 1)
  #expect(store.refreshPending == false)
}

@MainActor
@Test("a memory-only reload refreshes memory without discarding an unsaved draft")
func appStoreInboundMemoryReloadPreservesDraft() async throws {
  let preview = try await makeSeededInMemoryCore()
  _ = try await preview.upsertMemory(key: "remote-memory", content: "before")
  let core = StubFocusCoreService(preview: preview)
  let store = AppStore(core: core, cloudSyncMode: .off)

  await store.loadMemory()
  store.beginEditingMemory(try #require(store.memoryEntries.first { $0.key == "remote-memory" }))
  store.memoryContentDraft = "unsaved local edit"
  _ = try await preview.deleteMemory(key: "remote-memory")

  await store.performSelectiveInboundReload([.memory])

  #expect(core.loadMemoryCallCount == 2)
  #expect(store.memoryEntries.contains(where: { $0.key == "remote-memory" }) == false)
  #expect(store.memoryContentDraft == "unsaved local edit")
  #expect(store.memoryEditingKey == nil)
}

@MainActor
@Test("a selective task reload preserves a checklist draft when the task leaves its list")
func appStoreInboundTaskReloadPreservesChecklistDraftAcrossListMove() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, cloudSyncMode: .off)
  await store.refresh()

  store.selection = .lists
  store.selectedListID = LorvexPreviewSeedID.appleNativeList
  try await store.loadSelectedListDetail()
  let target: LorvexTask.ID = LorvexPreviewSeedID.agendaTask
  store.selectOnlySelectedListTask(target)
  store.taskDetailNewChecklistText = "half-typed checklist item"
  #expect(store.selectedTaskHasUnsavedEditorState)

  let peerList = try await core.createList(name: "Peer destination", description: nil)
  _ = try await core.moveTask(id: target, toListID: peerList.id)
  await store.performSelectiveInboundReload([.today, .tasks, .lists])

  // The list-detail reload no longer clears the inspector before the final
  // draft-aware reconciliation gets to decide. The peer move is visible in the
  // list while the user's uncommitted checklist composer survives.
  #expect(store.selectedListDetail?.tasks.contains(where: { $0.id == target }) == false)
  #expect(store.selectedTaskID == target)
  #expect(store.taskDetailDraftTaskID == target)
  #expect(store.taskDetailNewChecklistText == "half-typed checklist item")
}

@MainActor
@Test("a clean selected-task draft force-adopts peer fields after selective reload")
func appStoreInboundTaskReloadAdoptsCleanSelectedTaskDraft() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, cloudSyncMode: .off)
  await store.refresh()

  let target: LorvexTask.ID = LorvexPreviewSeedID.agendaTask
  // Bind the inspector through a surface that actually contains the fixed-date
  // seed task. Assigning the ID while the store remains on today's live date
  // creates no selected task/draft and correctly gets reconciled away.
  store.selection = .lists
  store.selectedListID = LorvexPreviewSeedID.appleNativeList
  try await store.loadSelectedListDetail()
  store.selectOnlySelectedListTask(target)
  store.syncSelectedTaskDraft(force: true)
  #expect(!store.selectedTaskHasUnsavedEditorState)

  _ = try await core.updateTask(TaskUpdateDraft(id: target, title: "Peer title"))
  await store.performSelectiveInboundReload([.today, .tasks, .lists])

  #expect(store.selectedTaskID == target)
  #expect(store.selectedTask?.title == "Peer title")
  #expect(store.taskDetailTitle == "Peer title")
  #expect(!store.selectedTaskHasUnsavedEditorState)
}

@MainActor
@Test("a task detail load preserves an in-progress recurrence-only draft")
func appStoreTaskDetailLoadPreservesRecurrenceOnlyDraft() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, cloudSyncMode: .off)
  await store.refresh()

  let target: LorvexTask.ID = LorvexPreviewSeedID.agendaTask
  store.selection = .lists
  store.selectedListID = LorvexPreviewSeedID.appleNativeList
  try await store.loadSelectedListDetail()
  store.selectOnlySelectedListTask(target)
  store.syncSelectedTaskDraft(force: true)
  #expect(store.selectedTask?.recurrence == nil)

  store.taskDetailHasRecurrence = true
  store.taskDetailRecurrenceFrequency = .daily
  store.taskDetailRecurrenceIntervalText = "3"
  #expect(store.selectedTaskHasUnsavedEditorState)

  await store.loadSelectedTaskDetail()

  #expect(store.taskDetailHasRecurrence)
  #expect(store.taskDetailRecurrenceFrequency == .daily)
  #expect(store.taskDetailRecurrenceIntervalText == "3")
  #expect(store.selectedTaskHasUnsavedEditorState)
}

@MainActor
@Test("a selective reload preserves a local recurrence draft while exposing the peer rule")
func appStoreInboundTaskReloadPreservesRecurrenceDraft() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, cloudSyncMode: .off)
  await store.refresh()

  let target: LorvexTask.ID = LorvexPreviewSeedID.agendaTask
  store.selection = .lists
  store.selectedListID = LorvexPreviewSeedID.appleNativeList
  try await store.loadSelectedListDetail()
  store.selectOnlySelectedListTask(target)
  store.syncSelectedTaskDraft(force: true)

  store.taskDetailHasRecurrence = true
  store.taskDetailRecurrenceFrequency = .daily
  store.taskDetailRecurrenceIntervalText = "3"
  _ = try await core.setTaskRecurrence(
    taskID: target, rule: TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO"]))

  await store.performSelectiveInboundReload([.today, .tasks, .lists])

  #expect(store.selectedTask?.recurrence?.freq == .weekly)
  #expect(store.taskDetailHasRecurrence)
  #expect(store.taskDetailRecurrenceFrequency == .daily)
  #expect(store.taskDetailRecurrenceIntervalText == "3")
  #expect(store.selectedTaskHasUnsavedEditorState)
}

@MainActor
@Test("a clean recurrence draft adopts a peer recurrence after selective reload")
func appStoreInboundTaskReloadAdoptsCleanRecurrenceDraft() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, cloudSyncMode: .off)
  await store.refresh()

  let target: LorvexTask.ID = LorvexPreviewSeedID.agendaTask
  store.selection = .lists
  store.selectedListID = LorvexPreviewSeedID.appleNativeList
  try await store.loadSelectedListDetail()
  store.selectOnlySelectedListTask(target)
  store.syncSelectedTaskDraft(force: true)
  #expect(!store.selectedTaskHasUnsavedEditorState)

  _ = try await core.setTaskRecurrence(
    taskID: target, rule: TaskRecurrenceRule(freq: .daily, interval: 4))
  await store.performSelectiveInboundReload([.today, .tasks, .lists])

  #expect(store.selectedTask?.recurrence?.freq == .daily)
  #expect(store.taskDetailRecurrenceDraft.originalRule?.freq == .daily)
  #expect(store.taskDetailRecurrenceIntervalText == "4")
  #expect(!store.selectedTaskHasUnsavedEditorState)
}
