import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

final class CalendarSeriesCutoverServiceTests: XCTestCase {
  private func schemaSQL() throws -> String {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    return try String(contentsOf: schemaURL, encoding: .utf8)
  }

  private func makeService() throws -> SwiftLorvexCoreService {
    let sql = try schemaSQL()
    return SwiftLorvexCoreService(store: try LorvexStore.openInMemory(schemaSQL: sql))
  }

  private func makeDailySeries(
    _ service: SwiftLorvexCoreService
  ) async throws -> CalendarTimelineEvent {
    try await service.createCalendarEvent(
      title: "Daily series", startDate: "2026-06-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false,
      location: nil, notes: nil,
      recurrence: TaskRecurrenceRule(freq: .daily),
      timezone: "America/Los_Angeles", url: nil, color: nil,
      eventType: nil, personName: nil, attendees: nil)
  }

  private func split(
    _ service: SwiftLorvexCoreService,
    eventID: String,
    date: String,
    title: String
  ) async throws -> CalendarTimelineEvent {
    let result = try await service.editScopedCalendarEvent(
      eventID: eventID, occurrenceDate: date, scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(title: title))
    return try XCTUnwrap(result.replacementEvent)
  }

  private func makeSplitBundle() async throws -> (
    bundle: ExportCalendarBundle, root: CalendarTimelineEvent, tail: CalendarTimelineEvent
  ) {
    let source = try makeService()
    let root = try await makeDailySeries(source)
    let tail = try await split(
      source, eventID: root.id, date: "2026-06-03", title: "Tail")
    return (try await source.loadCalendarBundleForDataExport(), root, tail)
  }

  private func assertCalendarStoreIsEmpty(
    _ service: SwiftLorvexCoreService, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let counts = try service.read { db in
      (
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_series_cutovers") ?? -1,
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_events") ?? -1
      )
    }
    XCTAssertEqual(counts.0, 0, file: file, line: line)
    XCTAssertEqual(counts.1, 0, file: file, line: line)
  }

  func testNestedSplitsUseRootDerivedIDsWithoutTruncatingStoredRecurrence() async throws {
    let service = try makeService()
    let root = try await makeDailySeries(service)
    let originalRecurrence: String = try service.read { db in
      try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT recurrence FROM calendar_events WHERE id = ?", arguments: [root.id]))
    }

    let first = try await split(
      service, eventID: root.id, date: "2026-06-03", title: "First tail")
    let firstID = CalendarSeriesCutoverID.make(
      lineageRootId: root.id, cutoverDate: "2026-06-03")
    XCTAssertEqual(first.id, firstID)

    let second = try await split(
      service, eventID: first.id, date: "2026-06-05", title: "Nested tail")
    let secondID = CalendarSeriesCutoverID.make(
      lineageRootId: root.id, cutoverDate: "2026-06-05")
    XCTAssertEqual(second.id, secondID)
    XCTAssertNotEqual(
      second.id,
      CalendarSeriesCutoverID.make(
        lineageRootId: first.id, cutoverDate: "2026-06-05"),
      "nested splits stay in the original lineage")

    let rows = try service.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT event.id, event.recurrence, event.series_cutover_id,
                 cutover.lineage_root_id, cutover.cutover_date, cutover.state
          FROM calendar_events event
          LEFT JOIN calendar_series_cutovers cutover
            ON cutover.id = event.series_cutover_id
          WHERE event.id IN (?, ?, ?)
          ORDER BY event.id
          """,
        arguments: [root.id, firstID, secondID])
    }
    XCTAssertEqual(rows.count, 3)
    for row in rows {
      let id: String = row[0]
      let recurrence: String? = row[1]
      XCTAssertEqual(recurrence, originalRecurrence)
      if id == root.id {
        XCTAssertNil(row[2] as String?)
      } else {
        XCTAssertEqual(row[2] as String?, id)
        XCTAssertEqual(row[3] as String?, root.id)
        XCTAssertEqual(row[5] as String?, "active")
      }
    }

    let timeline = try await service.loadCalendarTimeline(
      from: "2026-06-01", to: "2026-06-07")
    let dates = timeline.events.compactMap(\.occurrenceDate)
    XCTAssertEqual(dates, [
      "2026-06-01", "2026-06-02", "2026-06-03", "2026-06-04",
      "2026-06-05", "2026-06-06", "2026-06-07",
    ])
  }

  func testStalePredecessorCannotMutateATailOwnedOccurrence() async throws {
    let service = try makeService()
    let root = try await makeDailySeries(service)
    _ = try await split(
      service, eventID: root.id, date: "2026-06-03", title: "Tail")

    do {
      _ = try await service.editScopedCalendarEvent(
        eventID: root.id, occurrenceDate: "2026-06-03", scope: "this_only",
        updates: ScopedCalendarEventUpdates(title: "Stale write"))
      XCTFail("a predecessor must not author a decision in its successor interval")
    } catch let error as LorvexCoreError {
      guard case .validation(let field, _) = error else {
        return XCTFail("expected typed validation, got \(error)")
      }
      XCTAssertEqual(field, "occurrence_date")
    }
    let staleDecisions: Int = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM calendar_events WHERE series_id = ?",
        arguments: [root.id]) ?? -1
    }
    XCTAssertEqual(staleDecisions, 0)
  }

  func testSplitAtSegmentFirstOccurrenceReusesSegmentAndCanClearRecurrence() async throws {
    let service = try makeService()
    let root = try await makeDailySeries(service)
    let tail = try await split(
      service, eventID: root.id, date: "2026-06-03", title: "Tail")

    let result = try await service.editScopedCalendarEvent(
      eventID: tail.id, occurrenceDate: "2026-06-03", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(
        title: "One-off tail", recurrence: .clear))
    XCTAssertEqual(result.replacementEvent?.id, tail.id)
    XCTAssertFalse(try XCTUnwrap(result.replacementEvent).isRecurring)

    let state = try service.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT recurrence, recurrence_generation, series_cutover_id,
                 (SELECT COUNT(*) FROM calendar_series_cutovers) AS cutover_count
          FROM calendar_events WHERE id = ?
          """,
        arguments: [tail.id])!
    }
    XCTAssertNil(state[0] as String?)
    XCTAssertNil(state[1] as String?)
    XCTAssertEqual(state[2] as String?, tail.id)
    XCTAssertEqual(state[3] as Int, 1)
  }

  func testMovedTailUsesFirstEffectiveOccurrenceForEditAndDelete() async throws {
    let service = try makeService()
    let root = try await makeDailySeries(service)
    let splitResult = try await service.editScopedCalendarEvent(
      eventID: root.id, occurrenceDate: "2026-06-03", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(
        title: "Moved tail", startDate: "2026-06-04"))
    let tail = try XCTUnwrap(splitResult.replacementEvent)
    XCTAssertEqual(tail.startDate, "2026-06-04")

    let editResult = try await service.editScopedCalendarEvent(
      eventID: tail.id, occurrenceDate: "2026-06-04", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(title: "Renamed moved tail"))
    let editedTail = try XCTUnwrap(editResult.replacementEvent)
    XCTAssertEqual(editedTail.id, tail.id)
    XCTAssertEqual(editedTail.startDate, "2026-06-04")
    XCTAssertEqual(editedTail.title, "Renamed moved tail")

    let activeBoundary = try service.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT id, cutover_date, state,
                 (SELECT COUNT(*) FROM calendar_series_cutovers) AS cutover_count
          FROM calendar_series_cutovers WHERE id = ?
          """,
        arguments: [tail.id])!
    }
    XCTAssertEqual(activeBoundary[0] as String, tail.id)
    XCTAssertEqual(activeBoundary[1] as String, "2026-06-03")
    XCTAssertEqual(activeBoundary[2] as String, "active")
    XCTAssertEqual(activeBoundary[3] as Int, 1)

    _ = try await service.deleteScopedCalendarEvent(
      eventID: tail.id, occurrenceDate: "2026-06-04", scope: "this_and_following")
    let removedTail = try await service.getCalendarEvent(id: tail.id)
    XCTAssertNil(removedTail)
    let deletedBoundary = try service.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT cutover_date, state,
                 (SELECT COUNT(*) FROM calendar_series_cutovers) AS cutover_count
          FROM calendar_series_cutovers WHERE id = ?
          """,
        arguments: [tail.id])!
    }
    XCTAssertEqual(deletedBoundary[0] as String, "2026-06-03")
    XCTAssertEqual(deletedBoundary[1] as String, "deleted")
    XCTAssertEqual(deletedBoundary[2] as Int, 1)
  }

  func testTailMovedBeforeBoundaryReusesFirstRecurrenceInsideOwnership() async throws {
    let service = try makeService()
    let root = try await makeDailySeries(service)
    let splitResult = try await service.editScopedCalendarEvent(
      eventID: root.id, occurrenceDate: "2026-06-03", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(
        title: "Back-shifted tail", startDate: "2026-06-01"))
    let tail = try XCTUnwrap(splitResult.replacementEvent)
    XCTAssertEqual(tail.startDate, "2026-06-01")

    let editResult = try await service.editScopedCalendarEvent(
      eventID: tail.id, occurrenceDate: "2026-06-03", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(title: "Renamed back-shifted tail"))
    XCTAssertEqual(editResult.replacementEvent?.id, tail.id)
    XCTAssertEqual(editResult.replacementEvent?.startDate, "2026-06-01")
    let boundaryCount: Int = try service.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_series_cutovers") ?? -1
    }
    XCTAssertEqual(boundaryCount, 1)
  }

  func testDeletingMiddleSegmentLeavesRootAndLaterTailWithOneGap() async throws {
    let service = try makeService()
    let root = try await makeDailySeries(service)
    let middle = try await split(
      service, eventID: root.id, date: "2026-06-03", title: "Middle")
    let later = try await split(
      service, eventID: middle.id, date: "2026-06-05", title: "Later")
    let decision = try await service.editScopedCalendarEvent(
      eventID: middle.id, occurrenceDate: "2026-06-04", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Middle decision"))
    let decisionID = try XCTUnwrap(decision.replacementEvent?.id)

    _ = try await service.deleteScopedCalendarEvent(
      eventID: middle.id, occurrenceDate: "2026-06-03", scope: "all_in_series")

    let stored = try service.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT id, state FROM calendar_series_cutovers ORDER BY cutover_date
          """)
    }
    XCTAssertEqual(stored.count, 2)
    XCTAssertEqual(stored[0][0] as String, middle.id)
    XCTAssertEqual(stored[0][1] as String, "deleted")
    XCTAssertEqual(stored[1][0] as String, later.id)
    XCTAssertEqual(stored[1][1] as String, "active")
    let deletedMiddle = try await service.getCalendarEvent(id: middle.id)
    let deletedDecision = try await service.getCalendarEvent(id: decisionID)
    let retainedRoot = try await service.getCalendarEvent(id: root.id)
    let retainedLater = try await service.getCalendarEvent(id: later.id)
    XCTAssertNil(deletedMiddle)
    XCTAssertNil(deletedDecision)
    XCTAssertNotNil(retainedRoot)
    XCTAssertNotNil(retainedLater)

    let timeline = try await service.loadCalendarTimeline(
      from: "2026-06-01", to: "2026-06-06")
    XCTAssertEqual(
      timeline.events.compactMap(\.occurrenceDate),
      ["2026-06-01", "2026-06-02", "2026-06-05", "2026-06-06"])
  }

  func testDeleteThisAndFollowingCreatesGapUntilExistingLaterCutover() async throws {
    let service = try makeService()
    let root = try await makeDailySeries(service)
    let later = try await split(
      service, eventID: root.id, date: "2026-06-05", title: "Later")

    _ = try await service.deleteScopedCalendarEvent(
      eventID: root.id, occurrenceDate: "2026-06-03", scope: "this_and_following")

    let deletedID = CalendarSeriesCutoverID.make(
      lineageRootId: root.id, cutoverDate: "2026-06-03")
    let states: [String: String] = try service.read { db in
      let rows = try Row.fetchAll(
        db, sql: "SELECT id, state FROM calendar_series_cutovers")
      return Dictionary(uniqueKeysWithValues: rows.map { ($0[0] as String, $0[1] as String) })
    }
    XCTAssertEqual(states[deletedID], "deleted")
    XCTAssertEqual(states[later.id], "active")
    let retainedRoot = try await service.getCalendarEvent(id: root.id)
    let retainedLater = try await service.getCalendarEvent(id: later.id)
    XCTAssertNotNil(retainedRoot)
    XCTAssertNotNil(retainedLater)

    let timeline = try await service.loadCalendarTimeline(
      from: "2026-06-01", to: "2026-06-06")
    XCTAssertEqual(
      timeline.events.compactMap(\.occurrenceDate),
      ["2026-06-01", "2026-06-02", "2026-06-05", "2026-06-06"])
  }

  func testNativeImportJoinsDeletedAsAbsorbingAndCleansActiveTail() async throws {
    let service = try makeService()
    let root = try await makeDailySeries(service)
    let tail = try await split(
      service, eventID: root.id, date: "2026-06-03", title: "Tail")
    let preDeleteBundle = try await service.loadCalendarBundleForDataExport()
    let exportedTail = try XCTUnwrap(
      preDeleteBundle.events.first { $0.id == tail.id })
    let deleted = ExportCalendarSeriesCutover(
      id: tail.id, lineageRootId: root.id,
      cutoverDate: "2026-06-03", state: "deleted")

    _ = try await service.importCalendarBundle(cutovers: [deleted], events: [])
    let removedTail = try await service.getCalendarEvent(id: tail.id)
    XCTAssertNil(removedTail)
    let active = ExportCalendarSeriesCutover(
      id: tail.id, lineageRootId: root.id,
      cutoverDate: "2026-06-03", state: "active")
    let attemptedReactivation = try await service.importCalendarBundle(
      cutovers: [active], events: [exportedTail])
    XCTAssertEqual(attemptedReactivation.importedEvents, 0)
    XCTAssertEqual(attemptedReactivation.skippedEvents, 1)
    let state: String? = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT state FROM calendar_series_cutovers WHERE id = ?",
        arguments: [tail.id])
    }
    XCTAssertEqual(state, "deleted")
  }

  func testNativeImportRejectsDerivedUuidV8AsNestedLineageRoot() async throws {
    let rootID = "11111111-1111-4111-8111-111111111111"
    let derivedRoot = CalendarSeriesCutoverID.make(
      lineageRootId: rootID, cutoverDate: "2026-06-03")
    let nestedID = CalendarSeriesCutoverID.make(
      lineageRootId: derivedRoot, cutoverDate: "2026-06-05")
    let nested = ExportCalendarSeriesCutover(
      id: nestedID, lineageRootId: derivedRoot,
      cutoverDate: "2026-06-05", state: "deleted")
    let target = try makeService()

    do {
      _ = try await target.importCalendarBundle(cutovers: [nested], events: [])
      XCTFail("a deterministic segment identity must never root a nested lineage")
    } catch let error as LorvexCoreError {
      guard case .validation(let field, let message) = error else {
        return XCTFail("expected typed validation, got \(error)")
      }
      XCTAssertEqual(field, "calendarSeriesCutovers")
      XCTAssertTrue(message.contains("UUIDv8"), "unexpected rejection: \(message)")
    }
    try assertCalendarStoreIsEmpty(target)
  }

  func testActiveBoundaryWithoutSegmentRejectsBeforeAnyCalendarWrite() async throws {
    let fixture = try await makeSplitBundle()
    let target = try makeService()
    let events = fixture.bundle.events.filter { $0.id != fixture.tail.id }

    do {
      _ = try await target.importCalendarBundle(
        cutovers: fixture.bundle.cutovers, events: events)
      XCTFail("an active boundary without its deterministic segment must fail closed")
    } catch {}
    try assertCalendarStoreIsEmpty(target)
  }

  func testMalformedSegmentMarkerRejectsBeforeAnyCalendarWrite() async throws {
    let fixture = try await makeSplitBundle()
    let target = try makeService()
    var events = fixture.bundle.events
    let tailIndex = try XCTUnwrap(events.firstIndex { $0.id == fixture.tail.id })
    events[tailIndex].seriesCutoverId = nil

    do {
      _ = try await target.importCalendarBundle(
        cutovers: fixture.bundle.cutovers, events: events)
      XCTFail("a segment without its boundary marker must fail closed")
    } catch {}
    try assertCalendarStoreIsEmpty(target)
  }

  func testEventValidationFailureRollsBackBoundaryAndEarlierEvents() async throws {
    let fixture = try await makeSplitBundle()
    let target = try makeService()
    var events = fixture.bundle.events
    let tailIndex = try XCTUnwrap(events.firstIndex { $0.id == fixture.tail.id })
    events[tailIndex].title = ""

    do {
      _ = try await target.importCalendarBundle(
        cutovers: fixture.bundle.cutovers, events: events)
      XCTFail("an invalid segment must abort the whole calendar bundle")
    } catch {}
    try assertCalendarStoreIsEmpty(target)
  }

  func testTombstonedSegmentConvertsRestoredActiveBoundaryToDeleted() async throws {
    let fixture = try await makeSplitBundle()
    let target = try makeService()
    try target.write { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.calendarEvent, entityId: fixture.tail.id,
        version: Hlc.testVersion, deletedAt: SyncTimestampFormat.syncTimestampNow())
    }

    let result = try await target.importCalendarBundle(
      cutovers: fixture.bundle.cutovers, events: fixture.bundle.events)
    XCTAssertEqual(result.importedEvents, 1)
    XCTAssertEqual(result.skippedEvents, 1)
    let state: String? = try target.read { db in
      try String.fetchOne(
        db, sql: "SELECT state FROM calendar_series_cutovers WHERE id = ?",
        arguments: [fixture.tail.id])
    }
    XCTAssertEqual(state, "deleted")
    let deletedTail = try await target.getCalendarEvent(id: fixture.tail.id)
    let restoredRoot = try await target.getCalendarEvent(id: fixture.root.id)
    XCTAssertNil(deletedTail)
    XCTAssertNotNil(restoredRoot)
  }

  func testPureDeletedBoundaryBackupEnablesAndAppliesWithZeroDisplayedEvents() async throws {
    let source = try makeService()
    let root = try await makeDailySeries(source)
    let tail = try await split(
      source, eventID: root.id, date: "2026-06-03", title: "Disposable tail")
    _ = try await source.deleteCalendarEvent(id: tail.id)
    _ = try await source.deleteCalendarEvent(id: root.id)
    let json = try await source.exportData(
      entities: [LorvexDataExportCategory.calendarEvents.rawValue], format: "json")
    let payload = try JSONDecoder().decode(
      LorvexDataExportPayload.self, from: Data(json.utf8))
    XCTAssertEqual(payload.calendarEvents?.count, 0)
    XCTAssertEqual(payload.calendarSeriesCutovers?.count, 1)
    XCTAssertEqual(payload.calendarSeriesCutovers?.first?.state, "deleted")
    let plan = LorvexDataImporter.plan(for: payload)
    let entry = try XCTUnwrap(
      plan.entries.first { $0.category == .calendarEvents })
    XCTAssertEqual(entry.recordCount, 0)
    XCTAssertTrue(entry.hasInternalDependencyData)
    XCTAssertTrue(plan.hasSupportedRecords)

    let target = try makeService()
    let summary = await LorvexDataImporter.apply(
      plan: plan, payload: payload, using: target)
    XCTAssertTrue(summary.errors.isEmpty)
    XCTAssertEqual(summary.results.first?.imported, 0)
    let state: String? = try target.read { db in
      try String.fetchOne(
        db, sql: "SELECT state FROM calendar_series_cutovers WHERE id = ?",
        arguments: [tail.id])
    }
    XCTAssertEqual(state, "deleted")
  }

  func testCalendarBundleExportUsesOneSnapshotAcrossConcurrentSplit() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lorvex-calendar-export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("lorvex.sqlite")
    let sql = try schemaSQL()
    let source = SwiftLorvexCoreService(databasePath: databaseURL.path, schemaSQL: sql)
    let peer = SwiftLorvexCoreService(databasePath: databaseURL.path, schemaSQL: sql)
    let root = try await makeDailySeries(source)
    _ = try await peer.getCalendarEvent(id: root.id)  // open the peer before interleaving

    let hookEntered = expectation(description: "calendar export opened its read snapshot")
    let continueExport = DispatchSemaphore(value: 0)
    let exportTask = Task {
      try await SwiftLorvexCoreService.$afterCalendarCutoverExportReadForTesting.withValue({
        hookEntered.fulfill()
        _ = continueExport.wait(timeout: .now() + 5)
      }) {
        try await source.loadCalendarBundleForDataExport()
      }
    }
    await fulfillment(of: [hookEntered], timeout: 5)
    let tail: CalendarTimelineEvent
    do {
      tail = try await split(
        peer, eventID: root.id, date: "2026-06-03", title: "Concurrent tail")
    } catch {
      continueExport.signal()
      throw error
    }
    continueExport.signal()

    let concurrentBundle = try await exportTask.value
    XCTAssertTrue(concurrentBundle.cutovers.isEmpty)
    XCTAssertEqual(concurrentBundle.events.map(\.id), [root.id])

    let freshBundle = try await source.loadCalendarBundleForDataExport()
    XCTAssertEqual(freshBundle.cutovers.map(\.id), [tail.id])
    XCTAssertEqual(Set(freshBundle.events.map(\.id)), Set([root.id, tail.id]))
  }

  func testCalendarBundleExportRejectsActiveBoundaryWithoutSegment() async throws {
    let service = try makeService()
    let root = try await makeDailySeries(service)
    let cutoverDate = "2026-06-03"
    let cutoverID = CalendarSeriesCutoverID.make(
      lineageRootId: root.id, cutoverDate: cutoverDate)
    _ = try service.write { db in
      try CalendarSeriesCutoverRepo.upsert(
        db,
        row: CalendarSeriesCutoverRow(
          id: cutoverID, lineageRootId: root.id, cutoverDate: cutoverDate,
          state: .active, version: Hlc.testVersion,
          createdAt: "2026-06-01T00:00:00.000Z",
          updatedAt: "2026-06-01T00:00:00.000Z"))
    }

    do {
      _ = try await service.loadCalendarBundleForDataExport()
      XCTFail("an active boundary without its segment must never become an archive")
    } catch let error as LorvexCoreError {
      guard case .validation(let field, let message) = error else {
        return XCTFail("expected typed validation, got \(error)")
      }
      XCTAssertEqual(field, "calendarEvents")
      XCTAssertTrue(message.contains("Retry the export"))
    }
  }

  func testCalendarBundleExportRejectsSegmentWhoseBoundaryHasNotArrived() async throws {
    let service = try makeService()
    let root = try await makeDailySeries(service)
    let tail = try await split(
      service, eventID: root.id, date: "2026-06-03", title: "Tail")
    try service.write { db in
      try db.execute(
        sql: "DELETE FROM calendar_series_cutovers WHERE id = ?",
        arguments: [tail.id])
    }

    do {
      _ = try await service.loadCalendarBundleForDataExport()
      XCTFail("a segment awaiting its boundary must never be silently omitted")
    } catch let error as LorvexCoreError {
      guard case .validation(let field, let message) = error else {
        return XCTFail("expected typed validation, got \(error)")
      }
      XCTAssertEqual(field, "calendarEvents")
      XCTAssertTrue(message.contains("Retry the export"))
    }
  }

  func testCalendarBackupRestoresBoundariesBeforeEventsWithoutExposingCategory() async throws {
    let source = try makeService()
    let root = try await makeDailySeries(source)
    let middle = try await split(
      source, eventID: root.id, date: "2026-06-03", title: "Middle")
    let later = try await split(
      source, eventID: middle.id, date: "2026-06-05", title: "Later")
    _ = try await source.deleteScopedCalendarEvent(
      eventID: middle.id, occurrenceDate: "2026-06-03", scope: "all_in_series")

    let json = try await source.exportData(
      entities: [LorvexDataExportCategory.calendarEvents.rawValue], format: "json")
    let payload = try JSONDecoder().decode(
      LorvexDataExportPayload.self, from: Data(json.utf8))
    XCTAssertEqual(payload.calendarSeriesCutovers?.count, 2)
    XCTAssertEqual(payload.calendarEvents?.count, 2)
    XCTAssertEqual(
      payload.calendarEvents?.first(where: { $0.id == later.id })?.seriesCutoverId,
      later.id)
    XCTAssertFalse(
      LorvexDataExportCategory.allCases.map(\.rawValue).contains("calendar_series_cutovers"))

    let zip = try await source.exportDataZip(
      entities: [LorvexDataExportCategory.calendarEvents.rawValue],
      generatedAt: "2026-06-08T00:00:00.000Z", appVersion: "test")
    let zipPayload = try LorvexDataImporter.decode(zip)
    XCTAssertEqual(zipPayload.calendarSeriesCutovers?.count, 2)
    XCTAssertEqual(zipPayload.calendarEvents?.count, 2)
    XCTAssertEqual(
      zipPayload.calendarEvents?.first(where: { $0.id == later.id })?.seriesCutoverId,
      later.id)

    let plan = LorvexDataImporter.plan(for: payload)
    let calendarEntry = try XCTUnwrap(
      plan.entries.first(where: { $0.category == .calendarEvents }))
    XCTAssertEqual(calendarEntry.recordCount, 2, "internal boundaries do not inflate UI counts")

    let target = try makeService()
    let summary = await LorvexDataImporter.apply(
      plan: plan, payload: payload, using: target)
    XCTAssertTrue(summary.errors.isEmpty, "restore failed: \(summary.errors)")
    let restored = try target.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT cutover.id, cutover.state, event.series_cutover_id
          FROM calendar_series_cutovers cutover
          LEFT JOIN calendar_events event ON event.id = cutover.id
          ORDER BY cutover.cutover_date
          """)
    }
    XCTAssertEqual(restored.count, 2)
    XCTAssertEqual(restored[0][0] as String, middle.id)
    XCTAssertEqual(restored[0][1] as String, "deleted")
    XCTAssertNil(restored[0][2] as String?)
    XCTAssertEqual(restored[1][0] as String, later.id)
    XCTAssertEqual(restored[1][1] as String, "active")
    XCTAssertEqual(restored[1][2] as String?, later.id)
  }

  func testMovedTailRoundTripsOwnershipDateSeparatelyFromDisplayAnchor() async throws {
    let source = try makeService()
    let root = try await makeDailySeries(source)
    let splitResult = try await source.editScopedCalendarEvent(
      eventID: root.id, occurrenceDate: "2026-06-03", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(
        title: "Moved tail", startDate: "2026-06-04"))
    let tail = try XCTUnwrap(splitResult.replacementEvent)
    let bundle = try await source.loadCalendarBundleForDataExport()
    XCTAssertEqual(bundle.cutovers.first?.cutoverDate, "2026-06-03")
    XCTAssertEqual(bundle.events.first { $0.id == tail.id }?.startDate, "2026-06-04")

    let target = try makeService()
    let result = try await target.importCalendarBundle(
      cutovers: bundle.cutovers, events: bundle.events)
    XCTAssertEqual(result.importedEvents, bundle.events.count)
    let restored = try target.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT cutover.cutover_date, event.start_date, event.series_cutover_id
          FROM calendar_series_cutovers cutover
          JOIN calendar_events event ON event.id = cutover.id
          WHERE cutover.id = ?
          """,
        arguments: [tail.id])
    }
    XCTAssertEqual(restored?[0] as String?, "2026-06-03")
    XCTAssertEqual(restored?[1] as String?, "2026-06-04")
    XCTAssertEqual(restored?[2] as String?, tail.id)
  }
}
