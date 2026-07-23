import Foundation
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// End-to-end coverage for the ID/key-preserving idempotent import primitives on
/// the real `SwiftLorvexCoreService`, run against a temp store seeded with the
/// authoritative `schema/schema.sql`. These exercise the actual
/// `INSERT … ON CONFLICT(id) DO UPDATE` SQL (which the in-memory backend cannot
/// validate): the calendar all-day CHECK, the habits partial-unique index on
/// re-import, that non-daily cadences round-trip their typed detail, and that
/// each `ai_changelog` row is written inside the import transaction.
final class SwiftLorvexCoreServiceImportTests: XCTestCase {
  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  /// A canonical hyphenated lowercase UUID — the shape the sync outbox enqueue
  /// path requires for an entity id (real export ids are UUIDs).
  private func uuid() -> String { UUID().uuidString.lowercased() }

  // MARK: - Tasks (status restore via the importer)

  /// Apply a single-task payload through the real importer + SQL service.
  private func importTask(_ service: SwiftLorvexCoreService, _ task: ExportTask) async
    -> LorvexImportSummary
  {
    let payload = LorvexDataExportPayload(tasks: [task])
    let plan = LorvexDataImporter.plan(for: payload)
    return await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)
  }

  func testImportCancelledTaskRestoresCancelledStatus() async throws {
    let service = try makeService()
    let id = uuid()
    let summary = await importTask(
      service,
      ExportTask(
        id: id, title: "Abandoned", notes: "", priority: "P2", status: "cancelled",
        dueDate: nil, estimatedMinutes: nil, tags: []))
    XCTAssertTrue(summary.errors.isEmpty, "Cancelled import should not error: \(summary.errors)")
    let restored = try await service.loadTask(id: id)
    // `importRemoteTask` cannot express cancelled (a plain INSERT limited to
    // open/someday/completed); the importer transitions via `cancelTask` so the
    // true status is restored rather than silently left open.
    XCTAssertEqual(restored.status, .cancelled)
  }

  /// `in_progress` round-trips through export → import. The importer creates an
  /// open task, then restores the exact persisted lifecycle state under the
  /// create-version witness so a later live edit cannot be overwritten.
  func testInProgressTaskExportImportRoundTrips() async throws {
    let source = try makeService()
    let created = try await source.createTask(title: "Mid task", notes: "")
    _ = try await source.startTask(id: created.id)
    let exported = ExportTask(from: try await source.loadTask(id: created.id))
    XCTAssertEqual(exported.status, "in_progress", "export carries the status verbatim")

    let target = try makeService()
    let summary = await importTask(target, exported)
    XCTAssertTrue(summary.errors.isEmpty, "in_progress import should not error: \(summary.errors)")
    let restored = try await target.loadTask(id: created.id)
    XCTAssertEqual(restored.status, .inProgress)
  }

  func testPortableTaskImportRestoresAForwardDependencyThroughTheCreationWitness() async throws {
    let service = try makeService()
    let taskID = uuid()
    let dependencyID = uuid()
    let payload = LorvexDataExportPayload(tasks: [
      ExportTask(
        id: taskID, title: "Dependent", priority: "P2", status: "open",
        dueDate: nil, estimatedMinutes: nil, dependsOn: [dependencyID]),
      ExportTask(
        id: dependencyID, title: "Dependency", priority: "P2", status: "open",
        dueDate: nil, estimatedMinutes: nil),
    ])

    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: service)

    XCTAssertTrue(summary.errors.isEmpty, "Dependency import should not error: \(summary.errors)")
    let restored = try await service.loadTask(id: taskID)
    XCTAssertEqual(restored.dependsOn, [dependencyID])
  }

  func testImportRejectsDeferredAsANonStatus() async throws {
    let service = try makeService()
    let id = uuid()
    let future = LorvexDateFormatters.iso8601.string(
      from: Date().addingTimeInterval(60 * 60 * 24 * 30))
    let summary = await importTask(
      service,
      ExportTask(
        id: id, title: "Later", notes: "", priority: "P2", status: "deferred",
        dueDate: future, estimatedMinutes: nil, tags: []))
    // `deferred` is a derived lane, not a persisted status. Silently coercing it
    // would hide a broken or drifted export contract.
    XCTAssertTrue(
      summary.errors.contains { $0.message.contains("Unknown status") },
      "Expected deferred to be rejected, got \(summary.errors.map(\.message))")
    do {
      _ = try await service.loadTask(id: id)
      XCTFail("A task with the non-status deferred label must not be imported.")
    } catch {
      // Expected: the record was rejected and never created.
    }
  }

  func testImportUnknownStatusIsRejectedPerRecord() async throws {
    let service = try makeService()
    let id = uuid()
    let summary = await importTask(
      service,
      ExportTask(
        id: id, title: "Bogus status", notes: "", priority: "P2", status: "wat",
        dueDate: nil, estimatedMinutes: nil, tags: []))
    // An unrecognized status is a per-record error, not a silent coercion to open
    // (asymmetric with priority/date, which already reject).
    XCTAssertTrue(
      summary.errors.contains { $0.message.contains("Unknown status") },
      "Expected an 'Unknown status' per-record error, got \(summary.errors.map(\.message))")
    // The record was skipped, not imported as an open task.
    do {
      _ = try await service.loadTask(id: id)
      XCTFail("A task with an unknown status must not be imported.")
    } catch {
      // Expected: the record was rejected and never created.
    }
  }

  func testTransactionalImportSeamRejectsUnknownStatus() async throws {
    let service = try makeService()
    let task = ExportTask(
      id: uuid(), title: "Bogus status", notes: "", priority: "P2", status: "wat",
      dueDate: nil, estimatedMinutes: nil, tags: [])
    // The trusted native-import seam validates its own status rather than
    // coercing an unknown value to open.
    do {
      _ = try await service.importTaskRecordTransactionally(
        task, priority: .p2, dueDate: nil, plannedDate: nil, availableFrom: nil,
        dependenciesToApply: [])
      XCTFail("Unknown status must throw at the transactional import seam.")
    } catch {
      // Expected.
    }
  }

  func testTransactionalTaskImportDoesNotResurrectTombstone() async throws {
    let service = try makeService()
    let id = uuid()
    _ = try await service.importRemoteTask(
      id: id, title: "Original", notes: "", aiNotes: nil, rawInput: nil,
      priority: .p2, status: .open, estimatedMinutes: nil, dueDate: nil,
      plannedDate: nil, availableFrom: nil, tags: [], dependsOn: [])
    _ = try await service.archiveTask(id: id)
    try await service.deleteTask(id: id)

    let witness = try await service.importTaskRecordTransactionally(
      ExportTask(
        id: id, title: "Stale backup", notes: "", priority: "P2", status: "open",
        dueDate: nil, estimatedMinutes: nil),
      priority: .p2, dueDate: nil, plannedDate: nil, availableFrom: nil,
      dependenciesToApply: [])
    XCTAssertNil(witness, "A backup must not resurrect a locally tombstoned task.")
    do {
      _ = try await service.loadTask(id: id)
      XCTFail("The tombstoned task must remain absent.")
    } catch {
      // Expected.
    }
  }

  func testTaskImportExportPreservesArchivedMetadataAndExportsTrashRows() async throws {
    let service = try makeService()
    let id = uuid()
    let summary = await importTask(
      service,
      ExportTask(
        id: id,
        title: "Archived backup task",
        notes: "History",
        priority: "P1",
        status: "completed",
        dueDate: "2026-06-01T00:00:00Z",
        plannedDate: "2026-06-02T00:00:00Z",
        availableFrom: "2026-05-31T00:00:00Z",
        estimatedMinutes: 30,
        tags: ["archive"],
        rawInput: "raw archived text",
        checklist: [
          ExportChecklistItem(
            id: uuid(),
            position: 0,
            text: "Preserve checklist metadata",
            completed: true,
            completedAt: "2026-06-02T08:00:00Z",
            createdAt: "2026-05-30T08:00:00Z",
            updatedAt: "2026-06-02T08:00:00Z")
        ],
        reminders: [
          ExportTaskReminder(
            id: uuid(),
            reminderAt: "2026-06-01T07:00:00Z",
            dismissedAt: "2026-06-01T07:05:00Z",
            cancelledAt: "2026-06-01T07:10:00Z",
            createdAt: "2026-05-30T07:00:00Z",
            originalLocalTime: "07:00",
            originalTz: "America/Los_Angeles")
        ],
        deferCount: 4,
        lastDeferReason: "low_energy",
        lastDeferredAt: "2026-06-01T08:00:00Z",
        completedAt: "2026-06-02T09:00:00Z",
        createdAt: "2026-05-30T10:00:00Z",
        updatedAt: "2026-06-03T11:00:00Z",
        archivedAt: "2026-06-04T12:00:00Z"))

    XCTAssertTrue(summary.errors.isEmpty, "Archived metadata import should not error: \(summary.errors)")
    let restored = try await service.loadTask(id: id)
    XCTAssertEqual(restored.status, .completed)
    XCTAssertEqual(restored.archivedAt, "2026-06-04T12:00:00.000Z")
    XCTAssertEqual(restored.deferCount, 4)
    XCTAssertEqual(restored.lastDeferReason, "low_energy")
    XCTAssertEqual(restored.lastDeferredAt, "2026-06-01T08:00:00.000Z")
    XCTAssertEqual(restored.completedAt, "2026-06-02T09:00:00.000Z")
    XCTAssertEqual(restored.createdAt, "2026-05-30T10:00:00.000Z")
    XCTAssertEqual(restored.updatedAt, "2026-06-03T11:00:00.000Z")

    let activePage = try await service.listTasks(
      status: "all", listID: nil, priority: nil, text: nil, limit: 100, offset: 0)
    XCTAssertFalse(activePage.tasks.contains { $0.id == id })

    let json = try await service.exportData(entities: ["tasks"], format: "json")
    let payload = try JSONDecoder().decode(LorvexDataExportPayload.self, from: Data(json.utf8))
    let exported = try XCTUnwrap(payload.tasks?.first { $0.id == id })
    XCTAssertEqual(exported.archivedAt, "2026-06-04T12:00:00.000Z")
    XCTAssertEqual(exported.deferCount, 4)
    XCTAssertEqual(exported.createdAt, "2026-05-30T10:00:00.000Z")
    XCTAssertEqual(exported.updatedAt, "2026-06-03T11:00:00.000Z")
    let checklist = try XCTUnwrap(exported.checklist?.first)
    XCTAssertEqual(checklist.text, "Preserve checklist metadata")
    XCTAssertEqual(checklist.completedAt, "2026-06-02T08:00:00.000Z")
    XCTAssertEqual(checklist.createdAt, "2026-05-30T08:00:00.000Z")
    XCTAssertEqual(checklist.updatedAt, "2026-06-02T08:00:00.000Z")
    let reminder = try XCTUnwrap(exported.reminders?.first)
    XCTAssertEqual(reminder.reminderAt, "2026-06-01T07:00:00.000Z")
    XCTAssertEqual(reminder.dismissedAt, "2026-06-01T07:05:00.000Z")
    XCTAssertEqual(reminder.cancelledAt, "2026-06-01T07:10:00.000Z")
    XCTAssertEqual(reminder.createdAt, "2026-05-30T07:00:00.000Z")
    XCTAssertEqual(reminder.originalLocalTime, "07:00")
    XCTAssertEqual(reminder.originalTz, "America/Los_Angeles")
  }

  func testFocusImportExportPreservesAggregates() async throws {
    let service = try makeService()
    let taskAID = uuid()
    let taskBID = uuid()
    let payload = LorvexDataExportPayload(
      tasks: [
        ExportTask(
          id: taskAID, title: "Morning task", priority: "P2", status: "open",
          dueDate: nil, estimatedMinutes: nil),
        ExportTask(
          id: taskBID, title: "Afternoon task", priority: "P2", status: "open",
          dueDate: nil, estimatedMinutes: nil),
      ],
      currentFocus: [
        ExportCurrentFocus(
          date: "2026-06-02",
          briefing: "Protect morning",
          timezone: "America/Los_Angeles",
          taskIDs: [taskAID, taskBID],
          createdAt: "2026-06-02T08:00:00Z",
          updatedAt: "2026-06-02T09:00:00Z")
      ],
      focusSchedules: [
        ExportFocusSchedule(
          date: "2026-06-02",
          rationale: "Energy first",
          timezone: "America/Los_Angeles",
          blocks: [
            ExportFocusScheduleBlock(
              position: 0, blockType: "buffer", startMinutes: 540, endMinutes: 555,
              title: "Setup"),
            ExportFocusScheduleBlock(
              position: 1, blockType: "task", startMinutes: 555, endMinutes: 615,
              taskID: taskAID),
          ],
          createdAt: "2026-06-02T08:10:00Z",
          updatedAt: "2026-06-02T09:10:00Z")
      ])
    let plan = LorvexDataImporter.plan(for: payload)

    let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)

    XCTAssertTrue(summary.errors.isEmpty, "Focus import should not error: \(summary.errors)")
    let json = try await service.exportData(
      entities: ["current_focus", "focus_schedules"], format: "json")
    let exportedPayload = try JSONDecoder().decode(
      LorvexDataExportPayload.self, from: Data(json.utf8))
    let focus = try XCTUnwrap(exportedPayload.currentFocus?.first { $0.date == "2026-06-02" })
    XCTAssertEqual(focus.briefing, "Protect morning")
    XCTAssertEqual(focus.timezone, "America/Los_Angeles")
    XCTAssertEqual(focus.taskIDs, [taskAID, taskBID])
    XCTAssertEqual(focus.createdAt, "2026-06-02T08:00:00.000Z")
    XCTAssertEqual(focus.updatedAt, "2026-06-02T09:00:00.000Z")

    let schedule = try XCTUnwrap(
      exportedPayload.focusSchedules?.first { $0.date == "2026-06-02" })
    XCTAssertEqual(schedule.rationale, "Energy first")
    XCTAssertEqual(schedule.timezone, "America/Los_Angeles")
    XCTAssertEqual(schedule.createdAt, "2026-06-02T08:10:00.000Z")
    XCTAssertEqual(schedule.updatedAt, "2026-06-02T09:10:00.000Z")
    XCTAssertEqual(schedule.blocks.count, 2)
    XCTAssertEqual(schedule.blocks[0].blockType, "buffer")
    XCTAssertEqual(schedule.blocks[0].startMinutes, 540)
    XCTAssertEqual(schedule.blocks[1].blockType, "task")
    XCTAssertEqual(schedule.blocks[1].taskID, taskAID)
  }

  func testFocusImportExportPreservesProvenanceAndNeutralizesProviderTitle() async throws {
    let service = try makeService()
    let canonicalEventID = uuid()
    _ = try await service.importCalendarEvent(
      id: canonicalEventID, title: "Lorvex event", startDate: "2026-06-04",
      startTime: "10:00", endDate: "2026-06-04", endTime: "10:30",
      allDay: false, location: nil, notes: nil, url: nil, color: nil,
      eventType: nil, personName: nil, attendees: nil, timezone: nil,
      recurrence: nil, seriesId: nil, recurrenceInstanceDate: nil)
    try await service.importFocusSchedule(
      ExportFocusSchedule(
        date: "2026-06-04",
        blocks: [
          ExportFocusScheduleBlock(
            position: 0, blockType: "event", startMinutes: 540, endMinutes: 570,
            eventSource: .provider, title: "Private appointment"),
          ExportFocusScheduleBlock(
            position: 1, blockType: "event", startMinutes: 570, endMinutes: 600,
            eventSource: .freeform, title: "Lunch"),
          ExportFocusScheduleBlock(
            position: 2, blockType: "event", startMinutes: 600, endMinutes: 630,
            calendarEventID: canonicalEventID, eventSource: .canonical, title: "Lorvex event"),
        ]))

    let exportedSchedules = try await service.loadFocusSchedulesForDataExport()
    let schedule = try XCTUnwrap(exportedSchedules.first { $0.date == "2026-06-04" })
    XCTAssertEqual(schedule.blocks[0].eventSource, .provider)
    XCTAssertNil(schedule.blocks[0].calendarEventID)
    XCTAssertEqual(schedule.blocks[0].title, "Event")
    XCTAssertEqual(schedule.blocks[1].eventSource, .freeform)
    XCTAssertEqual(schedule.blocks[1].title, "Lunch")
    XCTAssertEqual(schedule.blocks[2].eventSource, .canonical)
    XCTAssertEqual(schedule.blocks[2].calendarEventID, canonicalEventID)
    XCTAssertEqual(schedule.blocks[2].title, "Lorvex event")
  }

  func testFocusImportRejectsInvalidPositionsIntervalsAndTaskIDsAtomically() async throws {
    let service = try makeService()
    for blocks in [
      [
        ExportFocusScheduleBlock(
          position: 1, blockType: "buffer", startMinutes: 540, endMinutes: 570)
      ],
      [
        ExportFocusScheduleBlock(
          position: 0, blockType: "buffer", startMinutes: 540, endMinutes: 540)
      ],
      [
        ExportFocusScheduleBlock(
          position: 0, blockType: "task", startMinutes: 540, endMinutes: 570,
          taskID: "not-a-uuid")
      ],
    ] {
      do {
        try await service.importFocusSchedule(
          ExportFocusSchedule(date: "2026-06-05", blocks: blocks))
        XCTFail("invalid focus schedule import should fail")
      } catch {
        let persistedSchedule = try await service.loadFocusSchedule(date: "2026-06-05")
        XCTAssertNil(persistedSchedule)
      }
    }
  }

  func testTaskCalendarEventLinkImportExportPreservesSyncableEdge() async throws {
    let service = try makeService()
    let taskID = uuid()
    let eventID = uuid()
    let payload = LorvexDataExportPayload(
      tasks: [
        ExportTask(
          id: taskID, title: "Linked task", notes: "", priority: "P2", status: "open",
          dueDate: nil, estimatedMinutes: nil, tags: [])
      ],
      calendarEvents: [
        ExportCalendarEvent(
          id: eventID, title: "Linked event", startDate: "2026-06-03",
          startTime: "09:00", endDate: "2026-06-03", endTime: "10:00",
          allDay: false, location: "")
      ],
      taskCalendarEventLinks: [
        ExportTaskCalendarEventLink(
          taskID: taskID,
          calendarEventID: eventID,
          createdAt: "2026-06-01T08:00:00Z",
          updatedAt: "2026-06-01T09:00:00Z")
      ])
    let plan = LorvexDataImporter.plan(for: payload)

    let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)

    XCTAssertTrue(
      summary.errors.isEmpty,
      "Task-calendar event link import should not error: \(summary.errors)")
    let json = try await service.exportData(
      entities: ["task_calendar_event_links"], format: "json")
    let exportedPayload = try JSONDecoder().decode(
      LorvexDataExportPayload.self, from: Data(json.utf8))
    let exported = try XCTUnwrap(
      exportedPayload.taskCalendarEventLinks?.first {
        $0.taskID == taskID && $0.calendarEventID == eventID
      })
    XCTAssertEqual(exported.createdAt, "2026-06-01T08:00:00.000Z")
    XCTAssertEqual(exported.updatedAt, "2026-06-01T09:00:00.000Z")
  }

  /// A data-file restore binds `import` around the whole run, so every
  /// id-preserving importer — including the canonical task↔event link — records
  /// `import` provenance, distinct from a live assistant re-link's `assistant`.
  func testDataImportAttributesTaskCalendarLinkChangelogToImport() async throws {
    let service = try makeService()
    let taskID = uuid()
    let eventID = uuid()
    let payload = LorvexDataExportPayload(
      tasks: [
        ExportTask(
          id: taskID, title: "Linked task", notes: "", priority: "P2", status: "open",
          dueDate: nil, estimatedMinutes: nil, tags: [])
      ],
      calendarEvents: [
        ExportCalendarEvent(
          id: eventID, title: "Linked event", startDate: "2026-06-03",
          startTime: "09:00", endDate: "2026-06-03", endTime: "10:00",
          allDay: false, location: "")
      ],
      taskCalendarEventLinks: [
        ExportTaskCalendarEventLink(
          taskID: taskID, calendarEventID: eventID,
          createdAt: "2026-06-01T08:00:00Z", updatedAt: "2026-06-01T09:00:00Z")
      ])
    let plan = LorvexDataImporter.plan(for: payload)

    let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)
    XCTAssertTrue(summary.errors.isEmpty, "Import should not error: \(summary.errors)")

    let linkInitiatedBy = try service.read { db in
      try String.fetchOne(
        db,
        sql:
          "SELECT initiated_by FROM ai_changelog WHERE entity_id = ? AND summary LIKE 'Linked task%' ORDER BY timestamp DESC",
        arguments: [taskID])
    }
    XCTAssertEqual(linkInitiatedBy, "import")
  }

  func testTagImportExportPreservesSyncableRootAndTaskImportReusesIt() async throws {
    let service = try makeService()
    let tagID = uuid()
    let taskID = uuid()
    let payload = LorvexDataExportPayload(
      tasks: [
        ExportTask(
          id: taskID, title: "Tagged task", notes: "", priority: "P2", status: "open",
          dueDate: nil, estimatedMinutes: nil, tags: ["Focus"])
      ],
      tags: [
        ExportTag(
          id: tagID,
          displayName: "Focus",
          color: "#0EA5E9",
          createdAt: "2026-06-01T08:00:00Z",
          updatedAt: "2026-06-01T09:00:00Z")
      ])
    let plan = LorvexDataImporter.plan(for: payload)

    let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)

    XCTAssertTrue(summary.errors.isEmpty, "Tag import should not error: \(summary.errors)")
    let json = try await service.exportData(entities: ["tags"], format: "json")
    let exportedPayload = try JSONDecoder().decode(
      LorvexDataExportPayload.self, from: Data(json.utf8))
    let exported = try XCTUnwrap(exportedPayload.tags?.first { $0.id == tagID })
    XCTAssertEqual(exported.displayName, "Focus")
    XCTAssertEqual(exported.color, "#0EA5E9")
    XCTAssertEqual(exported.createdAt, "2026-06-01T08:00:00.000Z")
    XCTAssertEqual(exported.updatedAt, "2026-06-01T09:00:00.000Z")

    let restoredTask = try await service.loadTask(id: taskID)
    XCTAssertEqual(restoredTask.tags, ["Focus"])
  }

  // MARK: - Daily reviews

  func testDailyReviewImportPreservesTimezoneAndLinks() async throws {
    let service = try makeService()
    let taskID = uuid()
    let listID = uuid()
    let payload = LorvexDataExportPayload(
      tasks: [
        ExportTask(
          id: taskID,
          title: "Linked review task",
          notes: "",
          priority: "P2",
          status: "open",
          dueDate: nil,
          estimatedMinutes: nil,
          tags: [],
          listID: listID)
      ],
      lists: [
        ExportList(id: listID, name: "Linked review list", description: "")
      ],
      dailyReviews: [
        ExportDailyReview(
          date: "2026-06-02",
          summary: "Restored review",
          mood: 5,
          energyLevel: 4,
          wins: "Link context survives",
          blockers: "",
          learnings: "",
          timezone: "America/New_York",
          updatedAt: "2026-06-02T23:00:00Z",
          linkedTaskIDs: [taskID],
          linkedListIDs: [listID])
      ])
    let plan = LorvexDataImporter.plan(for: payload)

    let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)

    XCTAssertTrue(summary.errors.isEmpty, "Daily review import should not error: \(summary.errors)")
    let loaded = try await service.loadDailyReview(date: "2026-06-02")
    let restored = try XCTUnwrap(loaded)
    XCTAssertEqual(restored.summary, "Restored review")
    XCTAssertEqual(restored.timezone, "America/New_York")
    XCTAssertEqual(restored.updatedAt, "2026-06-02T23:00:00.000Z")
    XCTAssertEqual(restored.linkedTaskIDs, [taskID])
    XCTAssertEqual(restored.linkedListIDs, [listID])

    let exportedJSON = try await service.exportData(entities: ["daily_reviews"], format: "json")
    let exported = try JSONDecoder().decode(
      LorvexDataExportPayload.self, from: Data(exportedJSON.utf8))
    let review = try XCTUnwrap(exported.dailyReviews?.first { $0.date == "2026-06-02" })
    XCTAssertEqual(review.timezone, "America/New_York")
    XCTAssertEqual(review.updatedAt, "2026-06-02T23:00:00.000Z")
    XCTAssertEqual(review.linkedTaskIDs, [taskID])
    XCTAssertEqual(review.linkedListIDs, [listID])
  }

  func testMemoryImportPreservesContentAndUpdatedAt() async throws {
    let service = try makeService()
    let payload = LorvexDataExportPayload(
      memory: [
        ExportMemoryEntry(
          id: uuid(),
          key: "restored-memory",
          content: "Imported memory",
          updatedAt: "2026-06-02T00:00:00Z")
      ])
    let plan = LorvexDataImporter.plan(for: payload)

    let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)

    XCTAssertTrue(summary.errors.isEmpty, "Memory import should not error: \(summary.errors)")
    let loadedMemory = try await service.loadMemory()
    let restored = try XCTUnwrap(loadedMemory.entries.first { $0.key == "restored-memory" })
    XCTAssertEqual(restored.content, "Imported memory")
    XCTAssertEqual(restored.updatedAt, "2026-06-02T00:00:00.000Z")

    let exportedJSON = try await service.exportData(entities: ["memory"], format: "json")
    let exported = try JSONDecoder().decode(
      LorvexDataExportPayload.self, from: Data(exportedJSON.utf8))
    let exportedMemory = try XCTUnwrap(exported.memory?.first { $0.key == "restored-memory" })
    XCTAssertNotNil(exportedMemory.id)
    XCTAssertEqual(exportedMemory.content, "Imported memory")
    XCTAssertEqual(exportedMemory.updatedAt, "2026-06-02T00:00:00.000Z")
  }

  func testMemoryImportReplacesNonCanonicalExportedMemoryId() async throws {
    let service = try makeService()
    let payload = LorvexDataExportPayload(
      memory: [
        ExportMemoryEntry(
          id: "legacy-human-memory-key",
          key: "legacy-memory",
          content: "Imported content",
          updatedAt: "2026-06-02T00:00:00Z")
      ])
    let plan = LorvexDataImporter.plan(for: payload)

    let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)

    XCTAssertTrue(summary.errors.isEmpty, "Memory import should not error: \(summary.errors)")
    let storedId = try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(db, sql: "SELECT id FROM memories WHERE key = ?", arguments: ["legacy-memory"])
      })
    XCTAssertNotEqual(storedId, "legacy-human-memory-key")
    if case .failure(let error) = SyncEntityId.validateForKind(.memory, storedId) {
      XCTFail("imported memory id must be a canonical sync id: \(error)")
    }
    let pendingMemory = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityType == .memory }?.envelope)
    XCTAssertEqual(pendingMemory.entityId, storedId)
  }

  // MARK: - Lists

  func testImportListIsIdempotentAndPreservesId() async throws {
    let service = try makeService()
    let id = uuid()
    let first = try await service.importList(
      id: id, name: "Restored", description: "v1", color: "#112233", icon: "tray")
    XCTAssertEqual(first.id, id)
    XCTAssertEqual(first.name, "Restored")

    let before = try await service.loadLists().lists.count
    // Re-import same id, changed content: overwrites in place, no duplicate.
    let second = try await service.importList(
      id: id, name: "Restored v2", description: "v2", color: nil, icon: nil)
    XCTAssertEqual(second.name, "Restored v2")
    let after = try await service.loadLists().lists.count
    XCTAssertEqual(after, before)
  }

  func testImportListPreservesArchivedStateAndPosition() async throws {
    let service = try makeService()
    let id = uuid()

    let imported = try await service.importList(
      id: id,
      name: "Archived restore",
      description: nil,
      color: nil,
      icon: nil,
      archivedAt: "2026-06-10T00:00:00Z",
      position: 12)

    XCTAssertEqual(imported.archivedAt, "2026-06-10T00:00:00.000Z")
    XCTAssertEqual(imported.position, 12)
    let activeLists = try await service.loadLists().lists
    XCTAssertFalse(activeLists.contains { $0.id == id })
    let archived = try await service.loadArchivedLists().lists.first { $0.id == id }
    XCTAssertEqual(archived?.position, 12)
  }

  // MARK: - Habits

  func testImportDailyHabitIsIdempotentAcrossLookupKeyIndex() async throws {
    let service = try makeService()
    let id = uuid()
    let first = try await service.importHabit(
      id: id, name: "Stretch", cue: "After coffee",
      frequencyType: "daily", weekdays: [], perPeriodTarget: nil, dayOfMonth: nil,
      targetCount: 2)
    XCTAssertEqual(first.id, id)
    XCTAssertEqual(first.frequencyType, "daily")
    XCTAssertEqual(first.targetCount, 2)

    let before = try await service.loadHabits(date: "2026-06-03").habits.count
    // Re-import same id + same lookup_key: ON CONFLICT(id) overwrites the same
    // row, so the active partial-unique index on lookup_key is not tripped.
    let second = try await service.importHabit(
      id: id, name: "Stretch", cue: "Before bed",
      frequencyType: "daily", weekdays: [], perPeriodTarget: nil, dayOfMonth: nil,
      targetCount: 3)
    XCTAssertEqual(second.targetCount, 3)
    XCTAssertEqual(second.cue, "Before bed")
    let after = try await service.loadHabits(date: "2026-06-03").habits.count
    XCTAssertEqual(after, before)
  }

  func testImportNonDailyHabitRoundTripsCadence() async throws {
    let service = try makeService()

    // A weekly habit round-trips its Monday-first weekday set.
    let weekly = try await service.importHabit(
      id: uuid(), name: "Habit weekly", cue: nil,
      frequencyType: "weekly", weekdays: [0, 2], perPeriodTarget: nil, dayOfMonth: nil,
      targetCount: 1)
    XCTAssertEqual(weekly.frequencyType, "weekly")
    XCTAssertEqual(weekly.weekdays, [0, 2])

    // A monthly habit round-trips its day-of-month.
    let monthly = try await service.importHabit(
      id: uuid(), name: "Habit monthly", cue: nil,
      frequencyType: "monthly", weekdays: [], perPeriodTarget: nil, dayOfMonth: 1,
      targetCount: 1)
    XCTAssertEqual(monthly.frequencyType, "monthly")
    XCTAssertEqual(monthly.dayOfMonth, 1)

    // A times_per_week habit round-trips its per-period target.
    let timesPerWeek = try await service.importHabit(
      id: uuid(), name: "Habit times_per_week", cue: nil,
      frequencyType: "times_per_week", weekdays: [], perPeriodTarget: 3, dayOfMonth: nil,
      targetCount: 1)
    XCTAssertEqual(timesPerWeek.frequencyType, "times_per_week")
    XCTAssertEqual(timesPerWeek.perPeriodTarget, 3)

    // All three were written.
    let habits = try await service.loadHabits(date: "2026-06-03").habits
    XCTAssertEqual(habits.count, 3)
  }

  func testHabitImportPreservesCompletionHistory() async throws {
    let service = try makeService()
    let id = uuid()
    let payload = LorvexDataExportPayload(
      habits: [
        ExportHabit(
          id: id,
          name: "Completion restore",
          cue: "",
          frequencyType: "daily",
          targetCount: 3,
          completions: [
            ExportHabitCompletion(
              completedDate: "2026-06-01",
              value: 2,
              note: "restored partial",
              createdAt: "2026-06-01T08:00:00Z",
              updatedAt: "2026-06-01T09:00:00Z")
          ],
          reminderPolicies: [
            ExportHabitReminderPolicy(
              id: uuid(),
              reminderTime: "07:30",
              enabled: false,
              createdAt: "2026-05-31T07:00:00Z",
              updatedAt: "2026-06-01T07:00:00Z")
          ])
      ])
    let plan = LorvexDataImporter.plan(for: payload)

    let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)

    XCTAssertTrue(summary.errors.isEmpty, "Habit completion import should not error: \(summary.errors)")
    let completions = try await service.getHabitCompletions(
      id: id, from: nil, to: nil, limit: 10).completions
    let restored = try XCTUnwrap(completions.first)
    XCTAssertEqual(restored.completedDate, "2026-06-01")
    XCTAssertEqual(restored.value, 2)
    XCTAssertEqual(restored.note, "restored partial")
    XCTAssertEqual(restored.createdAt, "2026-06-01T08:00:00.000Z")
    XCTAssertEqual(restored.updatedAt, "2026-06-01T09:00:00.000Z")
    let policies = try await service.getHabitReminderPolicies(id: id)
    let policy = try XCTUnwrap(policies.first)
    XCTAssertEqual(policy.reminderTime, "07:30")
    XCTAssertEqual(policy.enabled, false)
    XCTAssertEqual(policy.createdAt, "2026-05-31T07:00:00.000Z")
    XCTAssertEqual(policy.updatedAt, "2026-06-01T07:00:00.000Z")

    let exportedJSON = try await service.exportData(entities: ["habits"], format: "json")
    let exported = try JSONDecoder().decode(
      LorvexDataExportPayload.self, from: Data(exportedJSON.utf8))
    let exportedHabit = try XCTUnwrap(exported.habits?.first { $0.id == id })
    XCTAssertEqual(exportedHabit.completions.first?.completedDate, "2026-06-01")
    XCTAssertEqual(exportedHabit.completions.first?.value, 2)
    XCTAssertEqual(exportedHabit.completions.first?.note, "restored partial")
    XCTAssertEqual(exportedHabit.reminderPolicies.first?.reminderTime, "07:30")
    XCTAssertEqual(exportedHabit.reminderPolicies.first?.enabled, false)
  }

  // MARK: - Calendar events

  func testImportTimedCalendarEventIsIdempotent() async throws {
    let service = try makeService()
    let id = uuid()
    _ = try await service.importCalendarEvent(
      id: id, title: "Standup", startDate: "2026-06-03",
      startTime: "09:00", endDate: "2026-06-03", endTime: "09:30",
      allDay: false, location: "HQ")
    func count() async throws -> Int {
      try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-30")
        .events.filter { $0.id == id }.count
    }
    let firstCount = try await count()
    XCTAssertEqual(firstCount, 1)
    let updated = try await service.importCalendarEvent(
      id: id, title: "Standup moved", startDate: "2026-06-04",
      startTime: "10:00", endDate: "2026-06-04", endTime: "10:30",
      allDay: false, location: "Remote")
    XCTAssertEqual(updated.title, "Standup moved")
    let secondCount = try await count()
    XCTAssertEqual(secondCount, 1)
  }

  func testImportAllDayCalendarEventSatisfiesCheckConstraint() async throws {
    let service = try makeService()
    // The export shape stores absent times as ""; an all-day event must carry no
    // times or the `all_day = 0 OR (start_time IS NULL AND end_time IS NULL)`
    // CHECK throws at INSERT. The primitive normalizes "" → nil and forces nil.
    let event = try await service.importCalendarEvent(
      id: uuid(), title: "Holiday", startDate: "2026-07-04",
      startTime: "", endDate: "", endTime: "", allDay: true, location: "")
    XCTAssertTrue(event.allDay)
    XCTAssertNil(event.startTime)
    XCTAssertNil(event.endTime)
  }

  func testCalendarImportExportPreservesNativeFinalState() async throws {
    let service = try makeService()
    let masterId = uuid()
    let generation = "0000000000000_0000_0000000000000001"
    let occurrenceDate = "2026-06-10"
    let decisionId = CalendarOccurrenceDecisionID.make(
      seriesId: masterId, recurrenceGeneration: generation,
      recurrenceInstanceDate: occurrenceDate)
    _ = try await service.importCalendarEvent(
      id: masterId,
      title: "Deep work",
      startDate: "2026-06-03",
      startTime: "09:00",
      endDate: "2026-06-03",
      endTime: "10:00",
      allDay: false,
      location: "HQ",
      notes: "Focus notes",
      url: "https://example.com/focus",
      color: "#2563EB",
      eventType: "event",
      personName: "Ava",
      attendees: [
        CalendarEventAttendee(email: "ava@example.com", name: "Ava")
      ],
      timezone: "America/Los_Angeles",
      recurrence: #"{"BYDAY":["WE"],"FREQ":"WEEKLY","INTERVAL":1}"#,
      seriesId: nil,
      recurrenceInstanceDate: nil,
      occurrenceState: nil,
      recurrenceGeneration: generation)
    _ = try await service.importCalendarEvent(
      id: decisionId,
      title: "Deep work moved",
      startDate: "2026-06-10",
      startTime: "11:00",
      endDate: "2026-06-10",
      endTime: "12:00",
      allDay: false,
      location: "Remote",
      notes: nil,
      url: nil,
      color: nil,
      eventType: "event",
      personName: nil,
      attendees: [],
      timezone: "America/Los_Angeles",
      recurrence: nil,
      seriesId: masterId,
      recurrenceInstanceDate: occurrenceDate,
      occurrenceState: "replacement",
      recurrenceGeneration: generation)

    let json = try await service.exportData(entities: ["calendar_events"], format: "json")
    let payload = try JSONDecoder().decode(LorvexDataExportPayload.self, from: Data(json.utf8))
    let exported = payload.calendarEvents ?? []
    XCTAssertEqual(exported.count, 2)
    let master = try XCTUnwrap(exported.first { $0.id == masterId })
    XCTAssertEqual(master.notes, "Focus notes")
    XCTAssertEqual(master.url, "https://example.com/focus")
    XCTAssertEqual(master.color, "#2563EB")
    XCTAssertEqual(master.personName, "Ava")
    XCTAssertEqual(master.attendees?.first?.email, "ava@example.com")
    XCTAssertEqual(master.timezone, "America/Los_Angeles")
    XCTAssertNotNil(master.recurrence)
    XCTAssertEqual(master.recurrenceGeneration, generation)
    let decision = try XCTUnwrap(exported.first { $0.id == decisionId })
    XCTAssertEqual(decision.seriesId, masterId)
    XCTAssertEqual(decision.recurrenceInstanceDate, occurrenceDate)
    XCTAssertEqual(decision.occurrenceState, "replacement")
    XCTAssertEqual(decision.recurrenceGeneration, generation)
  }

  /// Cancelled occurrences are native decision rows. Backup restore must retain
  /// their deterministic identity and generation so the cancellation remains
  /// authoritative when CloudKit resumes.
  func testCalendarOccurrenceDecisionsRoundTrip() async throws {
    let service = try makeService()
    let masterID = uuid()
    let generation = "0000000000000_0000_0000000000000003"
    let dates = ["2026-06-10", "2026-06-17"]
    let decisions = dates.map { date in
      ExportCalendarEvent(
        id: CalendarOccurrenceDecisionID.make(
          seriesId: masterID, recurrenceGeneration: generation,
          recurrenceInstanceDate: date),
        title: "Weekly sync", startDate: date, startTime: "09:00",
        endDate: date, endTime: "10:00", allDay: false,
        seriesId: masterID, recurrenceInstanceDate: date,
        occurrenceState: "cancelled", recurrenceGeneration: generation)
    }
    let payload = LorvexDataExportPayload(
      calendarEvents:
        [
        ExportCalendarEvent(
          id: masterID, title: "Weekly sync", startDate: "2026-06-03", startTime: "09:00",
          endDate: "2026-06-03", endTime: "10:00", allDay: false,
          recurrence: ExportCalendarRecurrenceRule(freq: "WEEKLY"),
          recurrenceGeneration: generation)
      ] + decisions)
    let plan = LorvexDataImporter.plan(for: payload)
    let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)
    XCTAssertTrue(summary.errors.isEmpty, "Calendar import should not error: \(summary.errors)")

    let json = try await service.exportData(entities: ["calendar_events"], format: "json")
    let decoded = try JSONDecoder().decode(LorvexDataExportPayload.self, from: Data(json.utf8))
    let restored = decoded.calendarEvents ?? []
    XCTAssertEqual(restored.count, 3)
    XCTAssertEqual(
      Set(restored.compactMap { $0.occurrenceState == "cancelled" ? $0.recurrenceInstanceDate : nil }),
      Set(dates))
    XCTAssertTrue(
      restored.filter { $0.occurrenceState == "cancelled" }
        .allSatisfy { $0.recurrenceGeneration == generation })
  }

  /// A calendar event's structured recurrence rule survives an import→export
  /// round-trip: it stores as the canonical uppercase JSON and re-exports as the
  /// identical structured object.
  func testCalendarRecurrenceRoundTripsAsStructuredObject() async throws {
    let service = try makeService()
    let id = uuid()
    let rule = ExportCalendarRecurrenceRule(
      freq: "MONTHLY", interval: 2, byDay: ["MO"], bySetPos: [1], count: 10)
    let payload = LorvexDataExportPayload(
      calendarEvents: [
        ExportCalendarEvent(
          id: id, title: "Board meeting", startDate: "2026-06-01", startTime: "09:00",
          endDate: "2026-06-01", endTime: "10:00", allDay: false, recurrence: rule)
      ])
    let plan = LorvexDataImporter.plan(for: payload)
    let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)
    XCTAssertTrue(summary.errors.isEmpty, "Calendar import should not error: \(summary.errors)")

    // Stored as the canonical uppercase JSON: sorted keys, INTERVAL applied.
    let timeline = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-30")
    let stored = try XCTUnwrap(timeline.events.first { $0.eventID == id })
    XCTAssertEqual(
      stored.recurrenceRule,
      #"{"BYDAY":["MO"],"BYSETPOS":[1],"COUNT":10,"FREQ":"MONTHLY","INTERVAL":2}"#)

    // Re-exports as the identical structured object.
    let json = try await service.exportData(entities: ["calendar_events"], format: "json")
    let decoded = try JSONDecoder().decode(LorvexDataExportPayload.self, from: Data(json.utf8))
    let event = try XCTUnwrap(decoded.calendarEvents?.first { $0.id == id })
    XCTAssertEqual(event.recurrence, rule)
  }

  // MARK: - ai_changelog

  func testImportWritesChangelogRows() async throws {
    let service = try makeService()
    // The id-preserving importers inherit the ambient initiator; a data-file
    // restore binds `import` (as `LorvexDataImporter.apply` does), which the
    // assistant-facing changelog surface includes. Bare calls would record
    // `user` and be filtered out.
    try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.importAttribution
    ) {
      _ = try await service.importList(
        id: uuid(), name: "CL list", description: nil, color: nil, icon: nil)
      _ = try await service.importHabit(
        id: uuid(), name: "CL habit", cue: nil, frequencyType: "daily",
        weekdays: [], perPeriodTarget: nil, dayOfMonth: nil, targetCount: 1)
      _ = try await service.importCalendarEvent(
        id: uuid(), title: "CL event", startDate: "2026-06-03", startTime: "08:00",
        endDate: nil, endTime: nil, allDay: false, location: nil)
    }
    let entries = try await service.loadRuntimeDiagnostics().changelog.entries
    // Each import wrote a changelog row in its own transaction (Core Design
    // Rule 2): one per imported entity type, all carrying the import summary.
    let loggedTypes = Set(entries.map(\.entityType))
    XCTAssertTrue(loggedTypes.isSuperset(of: ["list", "habit", "calendar_event"]))
    XCTAssertTrue(entries.contains { $0.summary.contains("Imported list 'CL list'") })
  }

  // MARK: - Transactional record import (no partial data, no orphan outbox)

  /// A child failure inside a task record rolls the whole record — and every
  /// sync-outbox envelope it enqueued — back, so a half-applied task never
  /// reaches CloudKit. Here an empty-text checklist item fails after the task
  /// body and its outbox envelope were written in the same transaction.
  func testFailingChecklistItemRollsBackWholeTaskWithNoOutbox() async throws {
    let service = try makeService()
    let id = uuid()
    let summary = await importTask(
      service,
      ExportTask(
        id: id, title: "Has bad checklist", notes: "", priority: "P2", status: "open",
        dueDate: nil, estimatedMinutes: nil, tags: [],
        checklist: [ExportChecklistItem(id: uuid(), position: 0, text: "", completed: false)]))
    XCTAssertTrue(
      summary.errors.contains { $0.recordRef == id },
      "a failing child must surface a per-record error")
    do {
      _ = try await service.loadTask(id: id)
      XCTFail("the task must not exist after its record rolled back")
    } catch {
      // Expected: the whole record rolled back, so the task is absent.
    }
    let outbound = try service.pendingOutbound()
    XCTAssertFalse(
      outbound.contains { $0.envelope.entityId == id },
      "a rolled-back task must leave no sync-outbox envelope")
  }

  /// A failing completion inside a habit record rolls the whole habit back,
  /// leaving no habit row and no outbox envelope.
  func testFailingHabitCompletionRollsBackWholeHabitWithNoOutbox() async throws {
    let service = try makeService()
    let id = uuid()
    let payload = LorvexDataExportPayload(
      habits: [
        ExportHabit(
          id: id, name: "Bad completion", cue: "", frequencyType: "daily", targetCount: 1,
          completions: [
            ExportHabitCompletion(
              completedDate: "2026-06-01", value: 0, note: nil,
              createdAt: "2026-06-01T08:00:00Z", updatedAt: "2026-06-01T08:00:00Z")
          ],
          reminderPolicies: [])
      ])
    let plan = LorvexDataImporter.plan(for: payload)
    let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)
    XCTAssertTrue(summary.errors.contains { $0.recordRef == id })
    let habits = try await service.loadHabits(date: "2026-06-03").habits
    XCTAssertFalse(habits.contains { $0.id == id }, "the habit must not exist after rollback")
    let outbound = try service.pendingOutbound()
    XCTAssertFalse(
      outbound.contains { $0.envelope.entityId == id },
      "a rolled-back habit must leave no sync-outbox envelope")
  }

  // MARK: - Device-local preferences never cross the export/import boundary

  func testExportExcludesDeviceLocalPreferences() async throws {
    let service = try makeService()
    _ = try await service.setPreference(
      key: PreferenceKeys.prefWorkingHours, value: #"{"start":"09:00","end":"17:00"}"#)
    _ = try await service.setPreference(key: PreferenceKeys.prefTheme, value: "dark")

    let json = try await service.exportData(entities: ["preferences"], format: "json")
    let payload = try JSONDecoder().decode(LorvexDataExportPayload.self, from: Data(json.utf8))
    let keys = Set((payload.preferences ?? []).map(\.key))
    XCTAssertTrue(
      keys.contains(PreferenceKeys.prefWorkingHours), "a portable preference should export")
    XCTAssertFalse(
      keys.contains(PreferenceKeys.prefTheme),
      "a device-local preference (theme) must never be exported")
  }

  func testImportSkipsDeviceLocalPreferences() async throws {
    let service = try makeService()
    let payload = LorvexDataExportPayload(
      preferences: [
        ExportPreference(key: PreferenceKeys.prefTheme, value: "dark"),
        ExportPreference(
          key: PreferenceKeys.prefWorkingHours, value: #"{"start":"09:00","end":"17:00"}"#),
      ])
    let plan = LorvexDataImporter.plan(for: payload)

    let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)

    XCTAssertTrue(summary.errors.isEmpty, "preference import should not error: \(summary.errors)")
    let portable = try await service.getPreference(key: PreferenceKeys.prefWorkingHours)
    XCTAssertNotNil(portable, "a portable preference should be applied on import")
    let localOnly = try await service.getPreference(key: PreferenceKeys.prefTheme)
    XCTAssertNil(localOnly, "a device-local preference (theme) must never be applied from an import")
    let prefResult = summary.results.first { $0.category == .preferences }
    XCTAssertEqual(prefResult?.skipped, 1, "the device-local preference should count as skipped")
  }
}
