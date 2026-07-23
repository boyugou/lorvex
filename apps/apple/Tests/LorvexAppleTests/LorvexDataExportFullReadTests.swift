import Foundation
import LorvexCore
import LorvexDomain
import Testing

// MARK: - Full-read regression (E-1)

/// Regression for the lossy today-snapshot bug: completed and non-`open` tasks
/// must appear in the export. The previous implementation read
/// `loadToday().tasks` (priority-capped open tasks), so completed/cancelled/
/// someday tasks were silently dropped.
@Test
func exportIncludesNonOpenTasks() async throws {
  let core = try await makeSeededInMemoryCore()
  let done = try await core.createTask(title: "Archived finished task", notes: "")
  _ = try await core.completeTask(id: done.id)
  let dropped = try await core.createTask(title: "Dropped task", notes: "")
  _ = try await core.cancelTask(id: dropped.id)

  let json = try await core.exportData(entities: ["tasks"], format: "json")

  #expect(json.contains(done.id))
  #expect(json.contains("\"completed\""))
  #expect(json.contains(dropped.id))
  #expect(json.contains("\"cancelled\""))
}

/// Pagination must collect tasks beyond a single 500-row page.
@Test
func exportPaginatesBeyondOnePage() async throws {
  let core = try await makeSeededInMemoryCore()
  // batch_create_tasks caps a batch at 500 items; two batches exceed the
  // exporter's 500-row page.
  var created: [LorvexTask] = []
  for chunk in [0..<400, 400..<650] {
    let drafts = chunk.map { TaskCreateDraft(title: "Task \($0)") }
    created += try await core.batchCreateTasks(drafts)
  }

  let json = try await core.exportData(entities: ["tasks"], format: "json")

  for task in [created.first, created[created.count / 2], created.last].compactMap({ $0 }) {
    #expect(json.contains(task.id))
  }
}

// MARK: - New categories (E-1)

@Test
func exportIncludesNewCategoriesInJSON() async throws {
  let core = try await makeSeededInMemoryCore()

  let json = try await core.exportData(entities: ["all"], format: "json")

  #expect(json.contains("\"memory\""))
  #expect(json.contains("\"preferences\""))
}

/// The single-file JSON export is a semantic document: it stamps a provenance
/// manifest (format/schema version, `source.platform`, per-category counts) and
/// emits pipe-free first-class arrays for a task's tags, so an AI migration reads
/// structured relations instead of parsing delimiter-joined strings.
@Test
func singleFileJSONExportCarriesManifestAndArrayRelations() async throws {
  let core = try await makeSeededInMemoryCore()
  let created = try await core.createTask(title: "Tagged task", notes: "body text")
  _ = try await core.updateTask(
    id: created.id, title: "Tagged task", notes: "body text", priority: .p2,
    estimatedMinutes: nil, dueDate: nil, plannedDate: nil, availableFrom: nil,
    tags: ["alpha", "beta"], dependsOn: [])

  let json = try await core.exportData(entities: ["tasks"], format: "json")
  let payload = try JSONDecoder().decode(LorvexDataExportPayload.self, from: Data(json.utf8))

  // A2/A5: tags ride as a JSON array, never a pipe-joined string.
  let exported = try #require(payload.tasks?.first { $0.id == created.id })
  #expect(exported.tags?.sorted() == ["alpha", "beta"])
  #expect(json.contains("\"alpha\""))
  #expect(!json.contains("alpha|beta"))

  // A4: the export carries a provenance manifest with source identity + counts.
  let manifest = try #require(payload.manifest)
  #expect(manifest.formatVersion == LorvexDataExportPayload.currentFormatVersion)
  #expect(manifest.schemaVersion == ExportManifest.currentSchemaVersion)
  #expect(manifest.source.platform == "apple")
  #expect(manifest.entityCounts["tasks"] == payload.tasks?.count)
}

@Test
func exportIncludesNewCategorySectionsInCSV() async throws {
  let core = try await makeSeededInMemoryCore()

  let csv = try await core.exportData(entities: ["all"], format: "csv")

  #expect(csv.contains("## memory"))
  #expect(csv.contains("## preferences"))
}

// MARK: - Selective export (E-2)

@Test
func exportSelectionExcludesDeselectedCategories() async throws {
  let core = try await makeSeededInMemoryCore()

  let json = try await core.exportData(entities: ["tasks", "memory"], format: "json")

  #expect(json.contains("\"tasks\""))
  #expect(json.contains("\"memory\""))
  #expect(!json.contains("\"lists\""))
  #expect(!json.contains("\"habits\""))
  #expect(!json.contains("\"preferences\""))
}

@Test("Tasks-only export does not leak task-calendar link control state")
func tasksOnlyExportOmitsTaskCalendarLinkControlState() async throws {
  let core = try makeInMemoryCore()
  let task = try await core.createTask(title: "Linked task", notes: "")
  let event = try await core.createCalendarEvent(
    title: "Linked event", startDate: "2026-07-21", endDate: nil,
    startTime: "09:00", endTime: "09:30", allDay: false,
    location: nil, notes: nil, recurrence: nil, timezone: "UTC", url: nil,
    color: nil, eventType: nil, personName: nil, attendees: nil)
  let link = ExportTaskCalendarEventLink(taskID: task.id, calendarEventID: event.id)
  #expect(try await core.importTaskCalendarEventLink(link))
  #expect(try await core.unlinkTaskCalendarEventLink(taskID: task.id, calendarEventID: event.id))

  let tasksOnlyData = Data(
    try await core.exportData(entities: ["tasks"], format: "json").utf8)
  let tasksOnly = try LorvexDataImporter.decode(tasksOnlyData)
  let tasksOnlyGraph = try #require(tasksOnly.nativeTaskGraph)

  #expect(tasksOnly.taskCalendarEventLinks == nil)
  #expect(
    !tasksOnlyGraph.tombstones.contains { $0.entityType == .taskCalendarEventLink })
  #expect(
    !tasksOnlyGraph.payloadShadows.contains { $0.entityType == .taskCalendarEventLink })

  let withLinksData = Data(
    try await core.exportData(
      entities: ["tasks", "task_calendar_event_links"], format: "json").utf8)
  let withLinks = try LorvexDataImporter.decode(withLinksData)
  let withLinksGraph = try #require(withLinks.nativeTaskGraph)

  #expect(withLinks.taskCalendarEventLinks?.isEmpty == true)
  #expect(
    withLinksGraph.tombstones.contains { tombstone in
      tombstone.entityType == .taskCalendarEventLink
        && tombstone.entityID == "\(task.id):\(event.id)"
    })
}

/// Every category enum raw value resolves through the selector, so a
/// single-category selection produces exactly that category's section.
@Test
func everyCategoryRawValueDrivesItsOwnSection() async throws {
  let core = try await makeSeededInMemoryCore()

  for category in LorvexDataExportCategory.allCases {
    let json = try await core.exportData(entities: [category.rawValue], format: "json")
    #expect(json != "{}", "category \(category.rawValue) produced an empty export")
  }
}

/// The export's calendar read must span the full SQLite date domain rather
/// than any clock-derived window: a window anchored on "now" can silently
/// drop events outside it, which is exactly what a full backup must never do.
@Test
func dataExportCalendarWindowSpansFullDateDomain() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexCore/Services/LorvexCoreServicing+DataExportDefaults.swift"),
    encoding: .utf8
  )

  #expect(source.contains("rawCalendarFrom = \"0001-01-01\""))
  #expect(source.contains("rawCalendarTo = \"9999-12-31\""))
  #expect(!source.contains("date(byAdding: .year"))
  #expect(!source.contains("?? Date()"))
}

private func packageRoot() -> URL {
  var url = URL(fileURLWithPath: #filePath)
  while url.lastPathComponent != "apps" {
    url.deleteLastPathComponent()
  }
  return url.appending(path: "apple")
}

/// The export carries each task's children — checklist rows (ordered, with
/// completion state) and reminder timestamps — not just the flat columns.
/// Without them a "backup" restores bare tasks.
@Test
func exportCarriesChecklistAndReminders() async throws {
  let core = try await makeSeededInMemoryCore()
  let created = try await core.createTask(title: "Task with children", notes: "")
  var task = try await core.addTaskChecklistItem(taskID: created.id, text: "first step")
  if let added = task.checklistItems.max(by: { $0.position < $1.position }) {
    _ = try await core.toggleTaskChecklistItem(itemID: added.id, completed: true)
  }
  task = try await core.addTaskChecklistItem(taskID: created.id, text: "second step")
  _ = try await core.setTaskReminders(
    taskID: created.id, reminderAts: ["2026-07-01T08:00:00Z"])

  let json = try await core.exportData(entities: ["tasks"], format: "json")

  #expect(json.contains("first step"))
  #expect(json.contains("second step"))
  // Stored reminder instants carry millisecond precision.
  #expect(json.contains("2026-07-01T08:00:00.000Z"))
  let data = Data(json.utf8)
  let payload = try JSONDecoder().decode(LorvexDataExportPayload.self, from: data)
  let exported = try #require(payload.tasks?.first { $0.id == created.id })
  #expect(exported.checklist?.map(\.text) == ["first step", "second step"])
  #expect(exported.checklist?.map(\.completed) == [true, false])
  #expect(exported.reminders?.map(\.reminderAt) == ["2026-07-01T08:00:00.000Z"])
}
