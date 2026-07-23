import Foundation
import LorvexCore
import LorvexMobile
import Testing

@Test
func mobileTaskEditDraftParsesCompactFields() {
  let task = LorvexTask(
    id: "task-edit",
    title: "Edit task",
    notes: "Original notes",
    priority: .p2,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: [],
    dependsOn: []
  )
  var draft = MobileTaskEditDraft(task: task)
  draft.title = "  Updated title  "
  draft.estimatedMinutesText = "45"
  draft.tagsText = "mobile, review\nmobile"
  draft.dependsOnText = "dep-1, dep-2\tdep-1"

  #expect(draft.trimmedTitle == "Updated title")
  #expect(draft.parsedEstimatedMinutes == 45)
  #expect(draft.parsedTags == ["mobile", "review"])
  #expect(draft.parsedDependencies == ["dep-1", "dep-2"])
  #expect(draft.canSave)
}

@Test
func mobileTaskEditDraftTokenAccessorsRoundTripToCommaContract() {
  let task = LorvexTask(
    id: "task-edit",
    title: "Edit task",
    notes: "",
    priority: .p2,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: ["alpha", "beta"],
    dependsOn: ["dep-1"]
  )
  var draft = MobileTaskEditDraft(task: task)

  #expect(draft.tags == ["alpha", "beta"])
  #expect(draft.dependencyIDs == ["dep-1"])

  // Structured edits must serialize back to the comma string the save path reads.
  draft.tags = ["alpha", "gamma"]
  draft.dependencyIDs = ["dep-1", "dep-2"]

  #expect(draft.tagsText == "alpha, gamma")
  #expect(draft.dependsOnText == "dep-1, dep-2")
  #expect(draft.parsedTags == ["alpha", "gamma"])
  #expect(draft.parsedDependencies == ["dep-1", "dep-2"])
}

@Test
func mobileTaskEditDraftRejectsBlankTitleAndInvalidEstimate() {
  let task = LorvexTask(
    id: "task-edit",
    title: "Edit task",
    notes: "",
    priority: .p3,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: [],
    dependsOn: []
  )
  var draft = MobileTaskEditDraft(task: task)

  draft.title = " "
  #expect(!draft.canSave)

  draft.title = "Valid title"
  for invalid in ["-5", "0", "1441"] {
    draft.estimatedMinutesText = invalid
    #expect(!draft.estimateIsValid)
    #expect(!draft.canSave)
  }
}

@MainActor
@Test
func mobileStoreSavesTaskEditDraftThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let task = try #require(store.snapshot.openTasks.first)
  var draft = MobileTaskEditDraft(task: task)
  draft.title = " Updated from mobile "
  draft.notes = "Edited on iPhone."
  draft.priority = .p1
  draft.estimatedMinutesText = "35"
  draft.hasPlannedDate = true
  // The draft holds picker-frame (local) dates; the save bridges them to the
  // storage frame, so feed what the picker would show for the stored day.
  let storagePlannedDate = Date(timeIntervalSince1970: 1_779_494_400)
  draft.plannedDate = PlannedDayBridge.displayDate(forStorageDate: storagePlannedDate)
  draft.tagsText = "mobile, native"
  // depends_on must reference an existing task (validated UUID).
  let dependency = try await core.createTask(title: "Mobile dependency", notes: "")
  draft.dependsOnText = dependency.id

  let saved = await store.saveTaskEditDraft(draft)

  #expect(saved)
  let updated = try await core.loadTask(id: task.id)
  #expect(updated.title == "Updated from mobile")
  #expect(updated.notes == "Edited on iPhone.")
  #expect(updated.priority == .p1)
  #expect(updated.estimatedMinutes == 35)
  #expect(updated.plannedDate == storagePlannedDate)
  #expect(updated.tags == ["mobile", "native"])
  #expect(updated.dependsOn == [dependency.id])
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileTaskEditPatchesOnlyUserChangedFields() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let original = try #require(store.snapshot.openTasks.first)
  var draft = MobileTaskEditDraft(task: original)
  draft.title = "User title"

  // A peer/MCP edit lands after the sheet captured its baseline. Saving the
  // title must not write the draft's stale copy of every untouched field back
  // over that newer change.
  _ = try await core.updateTask(TaskUpdateDraft(id: original.id, notes: "Peer notes"))

  #expect(await store.saveTaskEditDraft(draft))
  let updated = try await core.loadTask(id: original.id)
  #expect(updated.title == "User title")
  #expect(updated.notes == "Peer notes")
}

@MainActor
@Test
func mobileStoreTaskEditDoesNotReloadPlanningSnapshots() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let listLoads = core.loadListsCallCount
  let habitLoads = core.loadHabitsCallCount
  let calendarLoads = core.loadCalendarTimelineCallCount
  let task = try #require(store.snapshot.openTasks.first)
  var draft = MobileTaskEditDraft(task: task)
  draft.title = "Targeted mobile edit"

  let saved = await store.saveTaskEditDraft(draft)

  #expect(saved)
  #expect(core.loadListsCallCount == listLoads)
  #expect(core.loadHabitsCallCount == habitLoads)
  #expect(core.loadCalendarTimelineCallCount == calendarLoads)
  #expect(store.selectedTask?.title == "Targeted mobile edit")
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreSavesDueDateAndAvailableFromThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let task = try #require(store.snapshot.openTasks.first)
  var draft = MobileTaskEditDraft(task: task)
  // Pickers hold local-frame days; the save bridges to UTC-midnight storage.
  let storageDueDate = Date(timeIntervalSince1970: 1_779_494_400)
  let storageAvailableFrom = Date(timeIntervalSince1970: 1_779_580_800)
  draft.hasDueDate = true
  draft.dueDate = PlannedDayBridge.displayDate(forStorageDate: storageDueDate)
  draft.hasAvailableFrom = true
  draft.availableFrom = PlannedDayBridge.displayDate(forStorageDate: storageAvailableFrom)

  let saved = await store.saveTaskEditDraft(draft)

  let updated = try await core.loadTask(id: task.id)
  #expect(saved)
  #expect(updated.dueDate == storageDueDate)
  #expect(updated.availableFrom == storageAvailableFrom)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreClearsDueDateAndAvailableFromWhenTogglesOff() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let task = try #require(store.snapshot.openTasks.first)
  var seed = MobileTaskEditDraft(task: task)
  seed.hasDueDate = true
  seed.dueDate = PlannedDayBridge.displayDate(
    forStorageDate: Date(timeIntervalSince1970: 1_779_494_400))
  seed.hasAvailableFrom = true
  seed.availableFrom = PlannedDayBridge.displayDate(
    forStorageDate: Date(timeIntervalSince1970: 1_779_580_800))
  _ = await store.saveTaskEditDraft(seed)

  let withDates = try await core.loadTask(id: task.id)
  #expect(withDates.dueDate != nil)
  #expect(withDates.availableFrom != nil)

  // The reload draft pre-fills the toggles from the stored values.
  var clearDraft = MobileTaskEditDraft(task: withDates)
  #expect(clearDraft.hasDueDate)
  #expect(clearDraft.hasAvailableFrom)
  clearDraft.hasDueDate = false
  clearDraft.hasAvailableFrom = false

  let saved = await store.saveTaskEditDraft(clearDraft)
  let cleared = try await core.loadTask(id: task.id)
  #expect(saved)
  #expect(cleared.dueDate == nil)
  #expect(cleared.availableFrom == nil)
}

@MainActor
@Test
func mobileStoreMarksTaskSomedayAndMovesBackToOpen() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let task = try #require(
    store.snapshot.today.tasks.first { $0.status == .open && $0.recurrence == nil })

  let parked = await store.markTaskSomeday(task.id)
  #expect(parked)
  #expect((try await core.loadTask(id: task.id)).status == .someday)

  // "Move to Open" reuses the reopen transition.
  let reopened = await store.reopenTask(task.id)
  #expect(reopened)
  #expect((try await core.loadTask(id: task.id)).status == .open)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreTaskEditPublishesWidgetSnapshot() async throws {
  let core = try await makeSeededInMemoryCore()
  let publisher = RecordingMobileWidgetSnapshotPublisher()
  let store = MobileStore(
    core: core,
    widgetSnapshotPublisher: publisher,
    todayString: { "2026-05-23" }
  )

  await store.refresh()
  let task = try #require(store.snapshot.openTasks.first)
  var draft = MobileTaskEditDraft(task: task)
  draft.title = "Widget-visible mobile edit"

  let saved = await store.saveTaskEditDraft(draft)

  let publications = await publisher.publications
  let latestTask = try #require(publications.last?.today.tasks.first { $0.id == task.id })
  #expect(saved)
  #expect(publications.count == 2)
  #expect(latestTask.title == "Widget-visible mobile edit")
}
