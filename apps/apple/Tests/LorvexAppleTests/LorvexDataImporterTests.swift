import Foundation
import GRDB
import LorvexDomain
import Testing

@testable import LorvexCore

// MARK: - Fixtures

/// Fixed canonical-UUID ids for the import fixtures — the real store's sync
/// outbox validates every entity id it enqueues, so restore payload ids must
/// be UUIDs exactly as real exports carry.
private enum ImportID {
  static let task1 = "bc554764-3d47-4af8-afed-77c694540105"
  static let task2 = "74d61be9-8ea2-4230-9a35-eabd0f5237f6"
  static let list1 = "2efda2e5-67b8-42b7-957e-4716cf92b91c"
  static let archivedList = "52789af8-c866-4d6f-84e5-7cac461a626a"
  static let habit1 = "8e71df49-054b-4109-ad74-ad361c6b518d"
  static let archivedHabit = "9494a631-2cda-4a79-98da-9e5eb2c5bab8"
  static let event1 = "c307ee6b-31da-4ba7-98a9-fa5dab093b79"
  static let event2 = "5a7e1c5d-8745-493b-b890-faae9baf84bd"
  static let goodTask = "cc685ff6-e9b6-4434-a22a-4a1c95a3ca37"
  static let badTask = "d89774d2-b383-48fb-949f-d1dd6b70551c"
  static let badDueDateTask = "c373fdd4-238b-45ee-9b6b-09c20327eee8"
  static let check1 = "6bffa9bd-66ee-4c2a-a7bf-f88d30f0fedc"
  static let check2 = "27cfc6b8-3f27-4de5-98a3-b64c07be9636"
  static let reminder1 = "e3c1a2fb-5f39-4a37-9f6f-1f2f4b1f2ab1"
  static let reminder2 = "9b6a2f0e-7d51-4b3c-8b53-6f6d1f0a2c44"
  static let policy1 = "4f2b7a63-0d3e-4c6a-9a1e-2b7c8d9e0f13"
  static let memory1 = "8c0b3f2e-1398-40e4-8e33-34a2191d913f"
}

/// A payload covering every supported category, using IDs/keys that do not
/// collide with the in-memory seed data.
private func makeImportPayload() -> LorvexDataExportPayload {
  LorvexDataExportPayload(
    tasks: [
      ExportTask(
        id: ImportID.task1,
        title: "Restored task",
        notes: "Restored body",
        priority: "P1",
        status: "open",
        dueDate: "2026-06-01T09:00:00Z",
        plannedDate: "2026-06-02T00:00:00Z",
        availableFrom: "2026-05-31T00:00:00Z",
        estimatedMinutes: 45,
        tags: ["alpha", "beta"],
        rawInput: "raw captured text",
        aiNotes: "AI synthesis for restore",
        checklist: [
          ExportChecklistItem(
            id: ImportID.check1, position: 0, text: "step one", completed: true,
            completedAt: "2026-06-01T09:00:00Z",
            createdAt: "2026-05-31T09:00:00Z",
            updatedAt: "2026-06-01T09:00:00Z"),
          ExportChecklistItem(
            id: ImportID.check2, position: 1, text: "step two", completed: false,
            createdAt: "2026-05-31T09:05:00Z",
            updatedAt: "2026-05-31T09:05:00Z"),
        ],
        reminders: [
          ExportTaskReminder(
            id: ImportID.reminder1,
            reminderAt: "2026-06-01T08:00:00Z",
            createdAt: "2026-05-31T08:00:00Z",
            originalLocalTime: "08:00",
            originalTz: "America/Los_Angeles"),
          ExportTaskReminder(
            id: ImportID.reminder2,
            reminderAt: "2026-06-01T08:30:00Z",
            dismissedAt: "2026-06-01T08:35:00Z",
            cancelledAt: "2026-06-01T08:40:00Z",
            createdAt: "2026-05-31T08:30:00Z",
            originalLocalTime: "08:30",
            originalTz: "America/Los_Angeles"),
        ],
        recurrence: ExportRecurrenceRule(
          from: TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO", "TH"])),
        recurrenceExceptions: ["2026-06-08"]),
      ExportTask(
        id: ImportID.task2,
        title: "Restored completed",
        notes: "",
        priority: "P3",
        status: "completed",
        dueDate: nil,
        estimatedMinutes: nil,
        tags: [],
        dependsOn: [ImportID.task1],
        listID: ImportID.list1,
        deferCount: 3,
        lastDeferReason: "low_energy",
        lastDeferredAt: "2026-06-01T07:00:00Z",
        completedAt: "2026-06-01T12:00:00Z",
        createdAt: "2026-05-30T09:00:00Z",
        updatedAt: "2026-06-02T10:00:00Z",
        archivedAt: "2026-06-03T12:00:00Z"),
    ],
    lists: [
      ExportList(
        id: ImportID.list1, name: "Restored list", description: "List desc",
        color: "#22C55E", icon: "briefcase")
    ],
    habits: [
      ExportHabit(
        id: ImportID.habit1, name: "Restored habit", cue: "After coffee",
        icon: "cup.and.saucer", color: "#F97316",
        frequencyType: "daily", targetCount: 2, milestoneTarget: 21,
        archived: false, position: 5,
        completions: [
          ExportHabitCompletion(
            completedDate: "2026-06-01",
            value: 2,
            note: "restore note",
            createdAt: "2026-06-01T08:00:00Z",
            updatedAt: "2026-06-01T08:30:00Z")
        ],
        reminderPolicies: [
          ExportHabitReminderPolicy(
            id: ImportID.policy1,
            reminderTime: "07:30",
            enabled: false,
            createdAt: "2026-05-31T07:00:00Z",
            updatedAt: "2026-06-01T07:00:00Z")
        ]),
      ExportHabit(
        id: ImportID.archivedHabit, name: "Archived habit", cue: "",
        icon: "archivebox", color: "#64748B",
        frequencyType: "daily", targetCount: 1, archived: true, position: 9)
    ],
    calendarEvents: [
      ExportCalendarEvent(
        id: ImportID.event1, title: "Restored event", startDate: "2026-06-03",
        startTime: "09:00", endDate: "2026-06-03", endTime: "10:00",
        allDay: false, location: "HQ",
        notes: "Restored notes",
        url: "https://example.com/restored",
        color: "#2563EB",
        eventType: "event",
        personName: "Ava",
        attendees: [
          CalendarEventAttendee(email: "ava@example.com", name: "Ava")
        ],
        timezone: "America/Los_Angeles",
        recurrence: ExportCalendarRecurrenceRule(freq: "WEEKLY", interval: 1, byDay: ["WE"]),
        recurrenceGeneration: "1780502400000_0000_1111111111111111"),
      ExportCalendarEvent(
        id: ImportID.event2, title: "Restored all-day", startDate: "2026-06-04",
        startTime: "", endDate: "", endTime: "", allDay: true, location: ""),
    ],
    dailyReviews: [
      ExportDailyReview(
        date: "2026-06-02",
        summary: "Restored review",
        mood: 4,
        energyLevel: 3,
        wins: "shipped import",
        blockers: "",
        learnings: "",
        timezone: "America/New_York",
        updatedAt: "2026-06-02T23:00:00Z",
        linkedTaskIDs: [ImportID.task1],
        linkedListIDs: [ImportID.list1])
    ],
    memory: [
      ExportMemoryEntry(
        id: ImportID.memory1, key: "import-mem-1", content: "Restored memory",
        updatedAt: "2026-06-02T00:00:00Z")
    ],
    preferences: [
      // Preference entity ids must be known SYNCED preference keys (the outbox
      // rejects arbitrary keys, and device-local prefs like language/theme are
      // excluded from import), so restore a real portable one.
      ExportPreference(key: "working_hours", value: #"{"start":"09:00","end":"17:00"}"#),
      // Exports carry the stored JSON form of string preferences (quoted). The
      // default-list validation must decode that form before checking list
      // existence, or a restored custom default list is silently dropped.
      ExportPreference(key: "default_list_id", value: "\"\(ImportID.list1)\""),
    ]
  )
}

// MARK: - Decode / dry-run guardrails

@Test
func importRejectsEmptyFile() {
  #expect(throws: LorvexDataImporter.ImportError.emptyFile) {
    try LorvexDataImporter.decode(Data())
  }
}

@Test
func importRejectsMalformedJSON() {
  #expect(throws: (any Error).self) {
    try LorvexDataImporter.decode(Data("not json".utf8))
  }
}

@Test
func dryRunPlanBucketsSupportedVsDeferred() {
  let plan = LorvexDataImporter.plan(for: makeImportPayload())
  let supported = Set(plan.entries.filter(\.isSupported).map(\.category))
  let deferred = Set(plan.entries.filter { !$0.isSupported }.map(\.category))

  #expect(
    supported == [
      .tasks, .lists, .habits, .calendarEvents, .dailyReviews, .memory, .preferences,
    ])
  // Every category in the payload now has an idempotent restore primitive.
  #expect(deferred.isEmpty)
  // tasks(2) + lists(1) + habits(2) + calendar(2) + reviews(1) + memory(1) + prefs(1)
  #expect(plan.supportedRecordCount == 2 + 1 + 2 + 2 + 1 + 1 + 2)
  #expect(plan.deferredRecordCount == 0)
  #expect(plan.hasSupportedRecords)
}

@Test
func dryRunOmitsAbsentCategories() {
  let plan = LorvexDataImporter.plan(for: LorvexDataExportPayload(tasks: []))
  // A present-but-empty array still appears (count 0); absent categories don't.
  #expect(plan.entries.map(\.category) == [.tasks])
  #expect(plan.entries.first?.recordCount == 0)
  #expect(!plan.hasSupportedRecords)
}

@Test
func dryRunEnablesNativeTaskSyncStateWithoutLiveTasks() throws {
  let version = try Hlc.parseCanonical("1700000000000_0000_1111111111111111")
  let deletedTaskID = "dc14d67f-26b9-43cb-9ce1-caf00c0ab41e"
  let linkedTaskID = "1934328e-e2f2-4cb4-850c-f027a66ae6f9"
  let linkedEventID = "d40064e3-662d-4592-a8d3-af9abc9a3291"

  let tombstoneOnly = NativeTaskGraphSnapshot(
    tasks: [], recurrenceExceptions: [], tagEdges: [], dependencyEdges: [],
    checklistItems: [], reminders: [],
    tombstones: [
      NativeTaskTombstoneSnapshot(
        entityType: .task, entityID: deletedTaskID, version: version,
        deletedAt: "2026-01-01T00:00:00.000Z")
    ])
  let shadowOnly = NativeTaskGraphSnapshot(
    tasks: [], recurrenceExceptions: [], tagEdges: [], dependencyEdges: [],
    checklistItems: [], reminders: [],
    payloadShadows: [
      NativeTaskPayloadShadowSnapshot(
        entityType: .taskCalendarEventLink,
        entityID: "\(linkedTaskID):\(linkedEventID)", baseVersion: version,
        payloadSchemaVersion: 2,
        rawPayloadJSON: "{\"future_user_field\":\"preserve me\"}",
        sourceDeviceID: "future-peer", updatedAt: "2026-01-01T00:00:00.000Z")
    ])

  for graph in [tombstoneOnly, shadowOnly] {
    let plan = LorvexDataImporter.plan(
      for: LorvexDataExportPayload(tasks: [], nativeTaskGraph: graph))
    #expect(plan.entries.map(\.category) == [.tasks])
    #expect(plan.entries.first?.recordCount == 0)
    #expect(plan.entries.first?.hasInternalDependencyData == true)
    #expect(plan.hasSupportedRecords)
  }
}

@Test
func dryRunPlanSupportsTags() {
  let plan = LorvexDataImporter.plan(
    for: LorvexDataExportPayload(
      tags: [
        ExportTag(id: "tag-1", displayName: "Focus", color: "#0EA5E9")
      ]))
  #expect(plan.entries.map(\.category) == [.tags])
  #expect(plan.entries.first?.isSupported == true)
  #expect(plan.supportedRecordCount == 1)
}

@Test
func dryRunPlanSupportsFocusAggregates() {
  let plan = LorvexDataImporter.plan(
    for: LorvexDataExportPayload(
      currentFocus: [ExportCurrentFocus(date: "2026-06-02", taskIDs: ["task-1"])],
      focusSchedules: [
        ExportFocusSchedule(
          date: "2026-06-02",
          blocks: [
            ExportFocusScheduleBlock(
              position: 0, blockType: "buffer", startMinutes: 600, endMinutes: 630)
          ])
      ]))
  #expect(plan.entries.map(\.category) == [.currentFocus, .focusSchedules])
  #expect(plan.entries.map(\.isSupported) == [true, true])
  #expect(plan.supportedRecordCount == 2)
}

@Test
func dryRunPlanSupportsTaskCalendarEventLinks() {
  let plan = LorvexDataImporter.plan(
    for: LorvexDataExportPayload(
      taskCalendarEventLinks: [
        ExportTaskCalendarEventLink(taskID: "task-1", calendarEventID: "event-1")
      ]))
  #expect(plan.entries.map(\.category) == [.taskCalendarEventLinks])
  #expect(plan.entries.first?.isSupported == true)
  #expect(plan.supportedRecordCount == 1)
}

// MARK: - Dry run performs no writes

@Test
func dryRunDoesNotWrite() async throws {
  let core = try await makeSeededInMemoryCore()
  var payload = makeImportPayload()
  payload.manifest = ExportPayloadManifest(
    formatVersion: LorvexDataExportPayload.currentFormatVersion,
    schemaVersion: ExportManifest.currentSchemaVersion,
    source: ExportSource(),
    entityCounts: [
      LorvexDataExportCategory.tasks.rawValue: 2,
      LorvexDataExportCategory.lists.rawValue: 1,
      LorvexDataExportCategory.habits.rawValue: 2,
      LorvexDataExportCategory.calendarEvents.rawValue: 2,
      LorvexDataExportCategory.dailyReviews.rawValue: 1,
      LorvexDataExportCategory.memory.rawValue: 1,
      LorvexDataExportCategory.preferences.rawValue: 2,
    ])
  let data = Data(try LorvexDataExporter.render(payload: payload, format: .json).utf8)

  let memoryBefore = try await core.loadMemory().entries.count

  // Building a plan is pure: decode + count only, no service calls.
  let (plan, _) = try LorvexDataImporter.plan(from: data)
  #expect(plan.hasSupportedRecords)

  // None of the imported records exist after a dry run.
  await #expect(throws: LorvexCoreError.taskNotFound) {
    _ = try await core.loadTask(id: ImportID.task1)
  }
  let memoryAfter = try await core.loadMemory().entries.count
  #expect(memoryAfter == memoryBefore)
  // The in-memory backend falls back to a seeded review for an unknown date, so
  // assert the imported review's summary was not written rather than nil.
  let review = try await core.loadDailyReview(date: "2026-06-02")
  #expect(review?.summary != "Restored review")
}

// MARK: - Round trip: apply restores supported entities

@Test
func applyRestoresSupportedEntities() async throws {
  let core = try await makeSeededInMemoryCore()
  let payload = makeImportPayload()
  let plan = LorvexDataImporter.plan(for: payload)

  let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: core)
  #expect(summary.errors.isEmpty)
  // tasks(2) + lists(1) + habits(2) + calendar(2) + reviews(1) + memory(1) + prefs(2)
  #expect(summary.totalImported == 2 + 1 + 2 + 2 + 1 + 1 + 2)

  // Tasks present with survivable fields. open/someday/completed restore via
  // `importRemoteTask`; cancelled restores via a follow-up `cancelTask`; any
  // derived lane such as deferred is rejected as an unstorable status. This payload
  // covers open + completed; the status-restore edges are asserted directly in
  // SwiftLorvexCoreServiceImportTests against the real SQL backend.
  let task1 = try await core.loadTask(id: ImportID.task1)
  #expect(task1.title == "Restored task")
  #expect(task1.priority == .p1)
  #expect(task1.rawInput == "raw captured text")
  // Due dates are day-granular in storage: the exported instant's day.
  #expect(task1.dueDate.map { LorvexDateFormatters.iso8601.string(from: $0) }
    == "2026-06-01T00:00:00Z")
  #expect(task1.plannedDate.map { LorvexDateFormatters.iso8601.string(from: $0) }
    == "2026-06-02T00:00:00Z")
  #expect(task1.availableFrom.map { LorvexDateFormatters.iso8601.string(from: $0) }
    == "2026-05-31T00:00:00Z")
  #expect(Set(task1.tags) == ["alpha", "beta"])
  // Checklist restored in export order with completion state; reminders set.
  let restoredChecklist = task1.checklistItems.sorted { $0.position < $1.position }
  #expect(restoredChecklist.map(\.id) == [ImportID.check1, ImportID.check2])
  #expect(restoredChecklist.map(\.text) == ["step one", "step two"])
  #expect(restoredChecklist.map { $0.completedAt != nil } == [true, false])
  #expect(restoredChecklist.first?.completedAt == "2026-06-01T09:00:00.000Z")
  #expect(restoredChecklist.first?.createdAt == "2026-05-31T09:00:00.000Z")
  #expect(restoredChecklist.first?.updatedAt == "2026-06-01T09:00:00.000Z")
  // Task reads surface only active reminders; the dismissed/cancelled row is
  // restored to storage but filtered from the read.
  #expect(task1.reminders.map(\.id) == [ImportID.reminder1])
  let storedDismissed = try core.read { db in
    try Row.fetchOne(
      db,
      sql: """
        SELECT dismissed_at, cancelled_at, created_at, original_local_time, original_tz \
        FROM task_reminders WHERE id = ?
        """,
      arguments: [ImportID.reminder2])
  }
  let dismissedRow = try #require(storedDismissed)
  #expect(dismissedRow["dismissed_at"] == "2026-06-01T08:35:00.000Z")
  #expect(dismissedRow["cancelled_at"] == "2026-06-01T08:40:00.000Z")
  #expect(dismissedRow["created_at"] == "2026-05-31T08:30:00.000Z")
  #expect(dismissedRow["original_local_time"] == "08:30")
  #expect(dismissedRow["original_tz"] == "America/Los_Angeles")
  #expect(task1.aiNotes == "AI synthesis for restore")
  // Recurrence rule and skipped occurrences survive the restore.
  #expect(task1.recurrence?.freq == .weekly)
  #expect(task1.recurrence?.interval == 2)
  #expect(task1.recurrence?.byDay == ["MO", "TH"])
  #expect(task1.recurrenceExceptions == ["2026-06-08"])
  let task2 = try await core.loadTask(id: ImportID.task2)
  #expect(task2.status == .completed)
  #expect(task2.deferCount == 3)
  #expect(task2.lastDeferReason == "low_energy")
  #expect(task2.lastDeferredAt == "2026-06-01T07:00:00.000Z")
  #expect(task2.completedAt == "2026-06-01T12:00:00.000Z")
  #expect(task2.createdAt == "2026-05-30T09:00:00.000Z")
  #expect(task2.updatedAt == "2026-06-02T10:00:00.000Z")
  #expect(task2.archivedAt == "2026-06-03T12:00:00.000Z")
  // Dependencies and list membership survive the restore (second-pass link-up).
  #expect(task2.dependsOn == [ImportID.task1])
  #expect(task2.listID == ImportID.list1)

  // List upserted by id present, with its visual identity preserved across the
  // export→import round-trip.
  let lists = try await core.loadLists()
  let restoredList = lists.lists.first { $0.id == ImportID.list1 }
  #expect(restoredList?.name == "Restored list")
  #expect(restoredList?.color == "#22C55E", "list color must survive export→import")
  #expect(restoredList?.icon == "briefcase", "list icon must survive export→import")

  // Habit upserted by id present.
  let habits = try await core.loadHabits(date: "2026-06-03")
  let restoredHabit = habits.habits.first { $0.id == ImportID.habit1 }
  #expect(restoredHabit?.name == "Restored habit")
  #expect(restoredHabit?.icon == "cup.and.saucer")
  #expect(restoredHabit?.color == "#F97316")
  #expect(restoredHabit?.milestoneTarget == 21)
  #expect(restoredHabit?.position == 5)
  let restoredCompletions = try await core.getHabitCompletions(
    id: ImportID.habit1, from: nil, to: nil, limit: 10)
  #expect(restoredCompletions.completions.count == 1)
  #expect(restoredCompletions.completions.first?.completedDate == "2026-06-01")
  #expect(restoredCompletions.completions.first?.value == 2)
  #expect(restoredCompletions.completions.first?.note == "restore note")
  #expect(restoredCompletions.completions.first?.createdAt == "2026-06-01T08:00:00.000Z")
  #expect(restoredCompletions.completions.first?.updatedAt == "2026-06-01T08:30:00.000Z")
  let restoredPolicies = try await core.getHabitReminderPolicies(id: ImportID.habit1)
  #expect(restoredPolicies.count == 1)
  #expect(restoredPolicies.first?.id == ImportID.policy1)
  #expect(restoredPolicies.first?.reminderTime == "07:30")
  #expect(restoredPolicies.first?.enabled == false)
  #expect(restoredPolicies.first?.createdAt == "2026-05-31T07:00:00.000Z")
  #expect(restoredPolicies.first?.updatedAt == "2026-06-01T07:00:00.000Z")
  let archivedHabits = try await core.loadArchivedHabits(date: "2026-06-03")
  #expect(archivedHabits.habits.contains { $0.id == ImportID.archivedHabit && $0.position == 9 })

  // Calendar events upserted by id present; the all-day event has no times.
  let timeline = try await core.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-30")
  // Recurring masters expand to deterministic occurrence ids. `eventID`
  // remains the stable master identity carried by every expanded occurrence.
  let restoredEvent = timeline.events.first { $0.eventID == ImportID.event1 }
  #expect(restoredEvent?.title == "Restored event")
  #expect(restoredEvent?.notes == "Restored notes")
  #expect(restoredEvent?.url == "https://example.com/restored")
  #expect(restoredEvent?.color == "#2563EB")
  #expect(restoredEvent?.personName == "Ava")
  #expect(restoredEvent?.attendees?.first?.email == "ava@example.com")
  #expect(restoredEvent?.timezone == "America/Los_Angeles")
  // The structured recurrence round-trips through import to the stored canonical
  // JSON string (uppercase keys, INTERVAL default applied, byte-sorted).
  #expect(restoredEvent?.recurrenceRule == #"{"BYDAY":["WE"],"FREQ":"WEEKLY","INTERVAL":1}"#)
  let allDay = timeline.events.first { $0.id == ImportID.event2 }
  #expect(allDay?.allDay == true)
  #expect(allDay?.startTime == nil)

  // Memory keyed entry present.
  let memory = try await core.loadMemory()
  let restoredMemory = memory.entries.first { $0.key == "import-mem-1" }
  #expect(restoredMemory?.content == "Restored memory")
  // Stored sync timestamps canonicalize to millisecond precision.
  #expect(restoredMemory?.updatedAt == "2026-06-02T00:00:00.000Z")

  // Daily review keyed by date present.
  let review = try await core.loadDailyReview(date: "2026-06-02")
  #expect(review?.summary == "Restored review")
  #expect(review?.timezone == "America/New_York")
  #expect(review?.updatedAt == "2026-06-02T23:00:00.000Z")
  #expect(review?.linkedTaskIDs == [ImportID.task1])
  #expect(review?.linkedListIDs == [ImportID.list1])

  // Preference keyed entry present.
  let preference = try await core.getPreference(key: "working_hours")
  #expect(preference == #"{"end":"17:00","start":"09:00"}"#)

  // The restored default list points at the imported custom list — the
  // stored-JSON form must survive the default-list existence validation.
  let defaultList = try await core.getPreference(key: "default_list_id")
  #expect(defaultList == "\"\(ImportID.list1)\"")
}

@Test
func applyRestoresArchivedListAndPosition() async throws {
  let core = try await makeSeededInMemoryCore()
  let payload = LorvexDataExportPayload(
    lists: [
      ExportList(
        id: ImportID.archivedList,
        name: "Archived project",
        description: "History kept",
        archivedAt: "2026-06-10T00:00:00.000Z",
        position: 9)
    ])
  let plan = LorvexDataImporter.plan(for: payload)

  let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: core)

  #expect(summary.errors.isEmpty)
  let archived = try await core.loadArchivedLists()
  let restored = archived.lists.first { $0.id == ImportID.archivedList }
  #expect(restored?.archivedAt == "2026-06-10T00:00:00.000Z")
  #expect(restored?.position == 9)
}

// MARK: - Idempotency: re-import does not duplicate

@Test
func reimportIsIdempotent() async throws {
  let core = try await makeSeededInMemoryCore()
  let payload = makeImportPayload()
  let plan = LorvexDataImporter.plan(for: payload)

  let first = await LorvexDataImporter.apply(plan: plan, payload: payload, using: core)
  #expect(first.totalImported == 2 + 1 + 2 + 2 + 1 + 1 + 2)

  // Counts of the import fixture's IDs/keys after the first import — none of
  // these may grow on re-import.
  func countMatching<T>(_ items: [T], _ matches: (T) -> Bool) -> Int {
    items.filter(matches).count
  }
  let tasksAfterFirst = try await taskCount(core)
  let memoryAfterFirst = countMatching(try await core.loadMemory().entries) {
    $0.key == "import-mem-1"
  }
  let listsAfterFirst = countMatching(try await core.loadLists().lists) {
    $0.id == ImportID.list1
  }
  let habitsAfterFirst = countMatching(try await core.loadHabits(date: "2026-06-03").habits) {
    $0.id == ImportID.habit1
  }
  // The weekly-recurring event expands to one occurrence per week in the
  // window; distinct ids are the duplication signal.
  func distinctImportedSourceEventIds() async throws -> Int {
    Set(
      try await core.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-30").events
        .map(\.eventID)
        .filter { $0 == ImportID.event1 || $0 == ImportID.event2 }
    ).count
  }
  let eventsAfterFirst = try await distinctImportedSourceEventIds()
  // Second import of the same file.
  let second = await LorvexDataImporter.apply(plan: plan, payload: payload, using: core)
  #expect(second.errors.isEmpty)

  // Tasks: skipped because already present (the loadTask precheck), not errored.
  let taskResult = try #require(second.results.first { $0.category == .tasks })
  #expect(taskResult.imported == 0)
  #expect(taskResult.skipped == 2)
  // Non-destructive skip-if-exists: a re-import of an id already present is
  // skipped in place, not overwritten (consistent with the task importer above).
  let listResult = try #require(second.results.first { $0.category == .lists })
  #expect(listResult.imported == 0)
  #expect(listResult.skipped == 1)
  let memoryResult = try #require(second.results.first { $0.category == .memory })
  #expect(memoryResult.imported == 0)
  #expect(memoryResult.skipped == 1)
  let habitResult = try #require(second.results.first { $0.category == .habits })
  #expect(habitResult.imported == 0)
  #expect(habitResult.skipped == 2)

  // No duplication anywhere — every category skips an already-present id.
  #expect(try await taskCount(core) == tasksAfterFirst)
  #expect(
    countMatching(try await core.loadMemory().entries) { $0.key == "import-mem-1" }
      == memoryAfterFirst)
  #expect(memoryAfterFirst == 1)
  #expect(
    countMatching(try await core.loadLists().lists) { $0.id == ImportID.list1 }
      == listsAfterFirst)
  #expect(listsAfterFirst == 1)
  #expect(
    countMatching(try await core.loadHabits(date: "2026-06-03").habits) {
      $0.id == ImportID.habit1
    } == habitsAfterFirst)
  #expect(habitsAfterFirst == 1)
  #expect(try await distinctImportedSourceEventIds() == eventsAfterFirst)
  #expect(eventsAfterFirst == 2)
}

// MARK: - One bad record does not abort

@Test
func badRecordIsCollectedNotThrown() async throws {
  let core = try await makeSeededInMemoryCore()
  let payload = LorvexDataExportPayload(
    tasks: [
      ExportTask(
        id: ImportID.goodTask, title: "Good", notes: "", priority: "P2", status: "open",
        dueDate: nil, estimatedMinutes: nil, tags: []),
      ExportTask(
        id: ImportID.badTask, title: "Bad", notes: "", priority: "NOPE", status: "open",
        dueDate: nil, estimatedMinutes: nil, tags: []),
    ]
  )
  let plan = LorvexDataImporter.plan(for: payload)
  let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: core)

  let taskResult = try #require(summary.results.first { $0.category == .tasks })
  #expect(taskResult.imported == 1)
  #expect(summary.errors.count == 1)
  #expect(summary.errors.first?.recordRef == ImportID.badTask)
  _ = try await core.loadTask(id: ImportID.goodTask)
}

@Test
func taskImportRejectsInvalidDueDateInsteadOfDroppingIt() async throws {
  let core = try await makeSeededInMemoryCore()
  let payload = LorvexDataExportPayload(
    tasks: [
      ExportTask(
        id: ImportID.badDueDateTask,
        title: "Bad due date",
        notes: "",
        priority: "P2",
        status: "open",
        dueDate: "not-a-date",
        estimatedMinutes: nil,
        tags: []),
    ]
  )
  let plan = LorvexDataImporter.plan(for: payload)
  let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: core)

  let result = try #require(summary.results.first { $0.category == .tasks })
  #expect(result.imported == 0)
  #expect(summary.errors.count == 1)
  #expect(summary.errors.first?.recordRef == ImportID.badDueDateTask)
  #expect(summary.errors.first?.message.contains("dueDate") == true)
  await #expect(throws: LorvexCoreError.taskNotFound) {
    _ = try await core.loadTask(id: ImportID.badDueDateTask)
  }
}

// MARK: - Helpers

/// Count how many of the import fixture's task IDs are present.
private func taskCount(_ core: SwiftLorvexCoreService) async throws -> Int {
  var count = 0
  for id in [ImportID.task1, ImportID.task2] {
    if let _ = try? await core.loadTask(id: id) { count += 1 }
  }
  return count
}

// MARK: - I4: native ZIP manifest is an enforced compatibility contract

private func nativeManifestData(schemaVersion: String, fileCounts: [String: Int]) throws -> Data {
  let manifest = ExportManifest(
    schemaVersion: schemaVersion, generatedAt: nil, appVersion: nil, fileCounts: fileCounts)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  return try encoder.encode(manifest)
}

private func oneTaskJSON() throws -> Data {
  let task = ExportTask(
    id: "11111111-1111-4111-8111-111111111111", title: "Restore me", notes: "",
    priority: "P2", status: "open", dueDate: nil, estimatedMinutes: nil, tags: [])
  return try JSONEncoder().encode([task])
}

@Test
func decodeRejectsANativeZipWithNoManifest() throws {
  let zip = try LorvexZipArchive.archive(entries: [
    .init(path: "tasks.json", data: try oneTaskJSON())
  ])
  #expect(throws: LorvexDataImporter.ImportError.missingManifest) {
    _ = try LorvexDataImporter.decode(zip)
  }
}

@Test
func decodeRejectsANativeZipWithAnIncompatibleManifestVersion() throws {
  let zip = try LorvexZipArchive.archive(entries: [
    .init(
      path: "manifest.json",
      data: try nativeManifestData(schemaVersion: "999", fileCounts: ["tasks": 1])),
    .init(path: "tasks.json", data: try oneTaskJSON()),
  ])
  #expect(
    throws: LorvexDataImporter.ImportError.incompatibleManifest(
      found: "999", supported: ExportManifest.currentSchemaVersion)
  ) {
    _ = try LorvexDataImporter.decode(zip)
  }
}

@Test
func decodeRejectsANativeZipWhoseManifestCountsDisagreeWithContents() throws {
  let zip = try LorvexZipArchive.archive(entries: [
    .init(
      path: "manifest.json",
      data: try nativeManifestData(
        schemaVersion: ExportManifest.currentSchemaVersion, fileCounts: ["tasks": 5])),
    .init(path: "tasks.json", data: try oneTaskJSON()),
  ])
  do {
    _ = try LorvexDataImporter.decode(zip)
    Issue.record("expected a manifest count mismatch to be rejected")
  } catch LorvexDataImporter.ImportError.manifestCountMismatch {
    // expected
  }
}

@Test
func decodeRejectsANativeZipWithDuplicateEntryPaths() throws {
  // Two tasks.json entries whose deduped inventory (1) would still match the
  // manifest, so the exact-inventory count check alone would pass. The duplicate
  // is rejected up front instead of silently keeping only the last occurrence.
  // The production writer itself rejects duplicates, so start with an equal-
  // length distinct path and patch both its local and central names to model a
  // hostile archive.
  var zip = try LorvexZipArchive.archive(entries: [
    .init(
      path: "manifest.json",
      data: try nativeManifestData(
        schemaVersion: ExportManifest.currentSchemaVersion, fileCounts: ["tasks": 1])),
    .init(path: "tasks.json", data: try oneTaskJSON()),
    .init(path: "xasks.json", data: try oneTaskJSON()),
  ])
  let original = Array("xasks.json".utf8)
  let replacement = Array("tasks.json".utf8)
  for offset in stride(from: zip.count - original.count, through: 0, by: -1)
  where Array(zip[offset..<(offset + original.count)]) == original {
    zip.replaceSubrange(offset..<(offset + original.count), with: replacement)
  }
  #expect(throws: LorvexDataImporter.ImportError.duplicateArchiveEntry("tasks.json")) {
    _ = try LorvexDataImporter.decode(zip)
  }
}

@Test
func decodeRejectsANativeZipWithAnUnexpectedEntry() throws {
  let zip = try LorvexZipArchive.archive(entries: [
    .init(
      path: "manifest.json",
      data: try nativeManifestData(
        schemaVersion: ExportManifest.currentSchemaVersion, fileCounts: ["tasks": 1])),
    .init(path: "tasks.json", data: try oneTaskJSON()),
    .init(path: "attachments/future.bin", data: Data([0x01, 0x02, 0x03])),
  ])
  #expect(
    throws: LorvexDataImporter.ImportError.unexpectedArchiveEntry(
      "attachments/future.bin")
  ) {
    _ = try LorvexDataImporter.decode(zip)
  }
}

@Test
func singleFileJsonExportIsVersionedAndRejectsAFutureFormat() throws {
  // The raw single-file JSON export stamps a format version, and the importer is
  // fail-fast: it rejects both a version it doesn't understand and an absent
  // version, rather than mis-decoding either. There are no released users or
  // legacy files to tolerate.
  let payload = LorvexDataExportPayload(
    manifest: ExportPayloadManifest(
      formatVersion: "1", schemaVersion: "1", source: ExportSource(),
      entityCounts: ["tasks": 1]),
    tasks: [
      ExportTask(
        id: "11111111-1111-4111-8111-111111111111", title: "T", notes: "",
        priority: "P2", status: "open", dueDate: nil, estimatedMinutes: nil, tags: [])
    ])
  #expect(payload.formatVersion == LorvexDataExportPayload.currentFormatVersion)

  // A current-version file round-trips.
  _ = try LorvexDataImporter.decode(try JSONEncoder().encode(payload))

  // A future version is rejected, not silently mis-decoded.
  #expect(
    throws: LorvexDataImporter.ImportError.incompatibleFormatVersion(
      found: "999", supported: LorvexDataExportPayload.currentFormatVersion)
  ) {
    _ = try LorvexDataImporter.decode(Data(#"{"formatVersion":"999","tasks":[]}"#.utf8))
  }

  // An absent version is rejected — an unversioned JSON is not a Lorvex backup.
  #expect(throws: LorvexDataImporter.ImportError.missingFormatVersion) {
    _ = try LorvexDataImporter.decode(Data(#"{"tasks":[]}"#.utf8))
  }
}

@Test
func decodeAcceptsAValidNativeZipAndPreservesCounts() throws {
  let payload = LorvexDataExportPayload(
    tasks: [
      ExportTask(
        id: "22222222-2222-4222-8222-222222222222", title: "Keep", notes: "", priority: "P2",
        status: "open", dueDate: nil, estimatedMinutes: nil, tags: [])
    ],
    lists: [ExportList(id: "33333333-3333-4333-8333-333333333333", name: "Inbox", description: "")])
  let zip = try LorvexDataExporter.renderZip(
    payload: payload, generatedAt: "2026-05-28T00:00:00Z", appVersion: "1.2.3")
  let decoded = try LorvexDataImporter.decode(zip)
  #expect(decoded.tasks?.count == 1)
  #expect(decoded.lists?.count == 1)
}

// MARK: - Fix 1: bulk import is non-destructive (skip-if-exists)

@Test("A stale backup does not overwrite newer local list/habit/memory; a new id still inserts")
func staleBackupIsNonDestructive() async throws {
  let core = try makeInMemoryCore()
  let listID = "2efda2e5-67b8-42b7-957e-4716cf92b91c"
  let habitID = "8e71df49-054b-4109-ad74-ad361c6b518d"
  // Newer local content at known ids.
  _ = try await core.importList(
    id: listID, name: "Local newer", description: "keep me", color: nil, icon: nil)
  _ = try await core.importHabit(
    id: habitID, name: "Local habit", icon: nil, color: nil, cue: "keep",
    frequencyType: "daily", weekdays: [], perPeriodTarget: nil, dayOfMonth: nil,
    targetCount: 5, milestoneTarget: nil, archived: false, position: 0)
  _ = try await core.upsertMemory(key: "profile", content: "local newer memory")

  let newListID = "11111111-1111-4111-8111-111111111111"
  let payload = LorvexDataExportPayload(
    lists: [
      ExportList(id: listID, name: "STALE list", description: "overwrite me"),
      ExportList(id: newListID, name: "Brand new"),
    ],
    habits: [
      ExportHabit(id: habitID, name: "STALE habit", cue: "", frequencyType: "daily", targetCount: 1)
    ],
    memory: [
      ExportMemoryEntry(
        key: "profile", content: "STALE memory",
        updatedAt: "2020-01-01T00:00:00Z")
    ])
  let plan = LorvexDataImporter.plan(for: payload)
  let result = await LorvexDataImporter.apply(plan: plan, payload: payload, using: core)

  // Existing ids kept their newer local content (skipped, not overwritten).
  #expect(try await core.getList(id: listID).name == "Local newer")
  let habit = try await core.loadHabits(date: "2026-06-03").habits.first { $0.id == habitID }
  #expect(habit?.name == "Local habit")
  let mem = try await core.loadMemory().entries.first { $0.key == "profile" }
  #expect(mem?.content == "local newer memory")
  // A genuinely new id still inserted.
  #expect((try? await core.getList(id: newListID)) != nil)
  // Skips are reported per category.
  #expect(result.results.first { $0.category == .lists }?.skipped == 1)
  #expect(result.results.first { $0.category == .habits }?.skipped == 1)
  #expect(result.results.first { $0.category == .memory }?.skipped == 1)
}

@Test(
  "A stale backup does not overwrite a newer local daily review / current focus / focus schedule"
)
func staleBackupDoesNotOverwriteContentCategories() async throws {
  let core = try makeInMemoryCore()
  let date = "2026-06-01"

  // Newer local content across the three user-authored date-scoped singletons
  // that import through a fresh-HLC upsert (no opaque id to presence-probe on).
  // Preferences are intentionally excluded — they carry read-time defaults and
  // import last-writer-wins (restore-your-settings), not skip-if-exists.
  _ = try await core.importDailyReview(
    date: date, summary: "Local newer review", mood: 5, energyLevel: 4,
    wins: "shipped", blockers: nil, learnings: nil)
  _ = try await core.setCurrentFocus(
    date: date, taskIDs: [], briefing: "Local newer focus", timezone: "UTC")
  _ = try await core.saveFocusSchedule(date: date, blocks: [], rationale: "Local newer schedule")

  // A stale backup carrying older content at the same dates.
  let payload = LorvexDataExportPayload(
    dailyReviews: [
      ExportDailyReview(
        date: date, summary: "STALE review", mood: 1, energyLevel: 1,
        wins: "", blockers: "", learnings: "")
    ],
    currentFocus: [
      ExportCurrentFocus(date: date, briefing: "STALE focus", timezone: "UTC", taskIDs: [])
    ],
    focusSchedules: [
      ExportFocusSchedule(date: date, rationale: "STALE schedule", timezone: "UTC", blocks: [])
    ])
  let plan = LorvexDataImporter.plan(for: payload)
  let result = await LorvexDataImporter.apply(plan: plan, payload: payload, using: core)

  // Newer local content is preserved (skip-if-exists), not overwritten by the
  // stale backup — and therefore not re-propagated fleet-wide at a fresh HLC.
  #expect(try await core.loadDailyReview(date: date)?.summary == "Local newer review")
  #expect(try await core.loadCurrentFocus(date: date)?.briefing == "Local newer focus")
  #expect(try await core.loadFocusSchedule(date: date)?.rationale == "Local newer schedule")
  // Each affected category reports the skip.
  #expect(result.results.first { $0.category == .dailyReviews }?.skipped == 1)
  #expect(result.results.first { $0.category == .currentFocus }?.skipped == 1)
  #expect(result.results.first { $0.category == .focusSchedules }?.skipped == 1)
}

@Test(
  "A stale backup skips focus aggregates when task and canonical-event tombstones win"
)
func staleBackupDoesNotMaterializeDanglingFocusAggregates() async throws {
  let core = try makeInMemoryCore()
  let task = try await core.createTask(title: "Delete after backup", notes: "")
  let event = try await core.createCalendarEvent(
    title: "Delete event after backup", startDate: "2026-07-21", endDate: nil,
    startTime: "10:00", endTime: "10:30", allDay: false,
    location: nil, notes: nil, recurrence: nil, timezone: "UTC", url: nil,
    color: nil, eventType: nil, personName: nil, attendees: nil)
  let planDate = "2026-07-21"
  let payload = LorvexDataExportPayload(
    tasks: [ExportTask(from: task)],
    calendarEvents: [ExportCalendarEvent(from: event)],
    currentFocus: [
      ExportCurrentFocus(date: planDate, timezone: "UTC", taskIDs: [task.id])
    ],
    focusSchedules: [
      ExportFocusSchedule(
        date: planDate,
        blocks: [
          ExportFocusScheduleBlock(
            position: 0, blockType: "task", startMinutes: 540, endMinutes: 600,
            taskID: task.id),
          ExportFocusScheduleBlock(
            position: 1, blockType: "event", startMinutes: 600, endMinutes: 630,
            calendarEventID: event.id, eventSource: .canonical, title: event.title),
        ])
    ])

  // This models a valid backup decoded before apply, followed by newer local
  // deletes while the import confirmation sheet is open. The root categories
  // are tombstone-guarded, so the schedule must follow that outcome atomically.
  try await core.permanentlyDeleteTask(id: task.id)
  _ = try await core.deleteCalendarEvent(id: event.id)

  let plan = LorvexDataImporter.plan(for: payload)
  let result = await LorvexDataImporter.apply(plan: plan, payload: payload, using: core)

  #expect(result.errors.isEmpty)
  #expect(result.results.first { $0.category == .tasks }?.skipped == 1)
  #expect(result.results.first { $0.category == .calendarEvents }?.skipped == 1)
  #expect(result.results.first { $0.category == .currentFocus }?.skipped == 1)
  #expect(result.results.first { $0.category == .focusSchedules }?.skipped == 1)
  #expect(try await core.loadCurrentFocus(date: planDate) == nil)
  #expect(try await core.loadFocusSchedule(date: planDate) == nil)
}

@Test("A provider hold remains importable without a local canonical event endpoint")
func providerFocusBlockDoesNotRequireCanonicalEndpoint() async throws {
  let core = try makeInMemoryCore()
  let planDate = "2026-07-22"
  let payload = LorvexDataExportPayload(
    focusSchedules: [
      ExportFocusSchedule(
        date: planDate,
        blocks: [
          ExportFocusScheduleBlock(
            position: 0, blockType: "event", startMinutes: 600, endMinutes: 660,
            eventSource: .provider, title: "Private provider title")
        ])
    ])

  let plan = LorvexDataImporter.plan(for: payload)
  let result = await LorvexDataImporter.apply(plan: plan, payload: payload, using: core)
  let schedule = try #require(try await core.loadFocusSchedule(date: planDate))

  #expect(result.errors.isEmpty)
  #expect(result.results.first { $0.category == .focusSchedules }?.imported == 1)
  #expect(schedule.blocks.count == 1)
  #expect(schedule.blocks[0].eventSource == .provider)
  #expect(schedule.blocks[0].calendarEventID == nil)
  #expect(schedule.blocks[0].title == "Event")
}

@Test("Import never restores ai_changelog_retention_policy (avoids the fleet-wide purge amplification)")
func importDoesNotOverwriteRetentionPolicy() async throws {
  let core = try makeInMemoryCore()
  // A local retention policy that keeps history.
  _ = try await core.setPreference(key: "ai_changelog_retention_policy", value: "maximum")
  let seededPolicy = try await core.getPreference(key: "ai_changelog_retention_policy")

  // A backup that would tighten retention to `off` (which, if applied, purges the
  // local changelog and emits deletes to every peer) plus an ordinary synced pref.
  let payload = LorvexDataExportPayload(
    preferences: [
      ExportPreference(key: "working_hours", value: #"{"start":"08:00","end":"16:00"}"#),
      ExportPreference(key: "ai_changelog_retention_policy", value: "off"),
    ])
  let plan = LorvexDataImporter.plan(for: payload)
  let result = await LorvexDataImporter.apply(plan: plan, payload: payload, using: core)

  // The retention policy is untouched; the ordinary synced preference still imports.
  #expect(try await core.getPreference(key: "ai_changelog_retention_policy") == seededPolicy)
  let prefs = result.results.first { $0.category == .preferences }
  #expect(prefs?.imported == 1)  // working_hours
  #expect(prefs?.skipped == 1)  // ai_changelog_retention_policy
}

// MARK: - Fix 6: the content plan reports file contents, not a write outcome

/// The import "File Contents" surface counts what the file HOLDS, not what a
/// restore will write. Apply is non-destructive (skip-if-exists,
/// tombstone-guarded), so a plan that promised a write outcome would be wrong
/// whenever records are already present or tombstoned locally. This pins the
/// honest contract: the plan reports every record in each supported category
/// (an upper bound on writes), a restore of the same file writes strictly fewer,
/// and building the plan mutates nothing (no rows, no outbox envelope).
@Test(
  "Content plan counts file contents including records apply skips as already-present/tombstoned; building it writes nothing"
)
func contentPlanCountsFileContentsNotWriteOutcome() async throws {
  let core = try makeInMemoryCore()
  let ts = "2026-06-02T00:00:00Z"

  // Present locally — a restore skips it as already-present.
  let listPresent = "b1f7c2a0-1111-4111-8111-111111111111"
  _ = try await core.importList(
    id: listPresent, name: "Present list", description: nil, color: nil, icon: nil)
  _ = try await core.upsertMemory(key: "mem-present", content: "present memory")

  // Tombstoned locally — a restore skips it (no resurrection at a fresh HLC). A
  // memory's tombstone is keyed on its opaque id, so create and re-import carry
  // the same exported id (mirroring a real export's stable id).
  let listTombstoned = "b1f7c2a0-2222-4222-8222-222222222222"
  _ = try await core.importList(
    id: listTombstoned, name: "Deleted list", description: nil, color: nil, icon: nil)
  try await core.deleteList(id: listTombstoned)
  let memTombstonedID = "c2e8d3b1-4444-4444-8444-444444444444"
  _ = try await core.importMemoryEntry(
    ExportMemoryEntry(id: memTombstonedID, key: "mem-tombstoned", content: "deleted memory",
      updatedAt: ts))
  _ = try await core.deleteMemory(key: "mem-tombstoned")

  // Brand-new — a restore actually writes it.
  let listNew = "b1f7c2a0-3333-4333-8333-333333333333"

  let payload = LorvexDataExportPayload(
    lists: [
      ExportList(id: listPresent, name: "Present list"),
      ExportList(id: listTombstoned, name: "Deleted list"),
      ExportList(id: listNew, name: "Brand new list"),
    ],
    memory: [
      ExportMemoryEntry(key: "mem-present", content: "present memory", updatedAt: ts),
      ExportMemoryEntry(id: memTombstonedID, key: "mem-tombstoned", content: "deleted memory",
        updatedAt: ts),
      ExportMemoryEntry(key: "mem-new", content: "brand new memory", updatedAt: ts),
    ])

  // Seeding above enqueued outbox envelopes; snapshot so we can prove the plan
  // adds none of its own.
  let outboxBeforePlan = try core.pendingOutbound().count

  let plan = LorvexDataImporter.plan(for: payload)

  // The surface reports what the FILE CONTAINS — every record in each supported
  // category, including the ones a restore will skip. Not a write-outcome diff.
  #expect(plan.entries.first { $0.category == .lists }?.recordCount == 3)
  #expect(plan.entries.first { $0.category == .memory }?.recordCount == 3)
  #expect(plan.supportedRecordCount == 6)

  // Building the plan mutated nothing: no outbox envelope, and the brand-new ids
  // still do not exist.
  #expect(try core.pendingOutbound().count == outboxBeforePlan)
  #expect((try? await core.getList(id: listNew)) == nil)
  #expect(try await core.loadMemory().entries.contains { $0.key == "mem-new" } == false)

  // Proof the count is CONTENTS, not a write prediction: an actual restore writes
  // only the one brand-new record per category, skipping the present and
  // tombstoned ones — strictly fewer than the plan's supportedRecordCount of 6.
  let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: core)
  #expect(summary.errors.isEmpty)
  let listResult = try #require(summary.results.first { $0.category == .lists })
  #expect(listResult.imported == 1)  // listNew
  #expect(listResult.skipped == 2)  // present + tombstoned
  let memoryResult = try #require(summary.results.first { $0.category == .memory })
  #expect(memoryResult.imported == 1)  // mem-new
  #expect(memoryResult.skipped == 2)  // present + tombstoned
  #expect(summary.totalImported == 2)
  #expect(summary.totalImported < plan.supportedRecordCount)
}
