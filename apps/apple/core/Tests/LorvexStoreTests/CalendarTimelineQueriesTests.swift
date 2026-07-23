import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports `calendar_timeline/queries/tests.rs`.
final class CalendarTimelineQueriesTests: XCTestCase {

  private func ymd(_ s: String) -> LorvexDate { try! LorvexDate.parse(s).get() }
  private func hm(_ s: String) -> TimeOfDay { try! TimeOfDay.parse(s).get() }

  private func insertMaster(
    _ db: Database,
    id: String,
    title: String = "Series master",
    recurrence: String = #"{"FREQ":"DAILY","INTERVAL":1}"#,
    startDate: String = "2026-08-10",
    seriesCutoverId: String? = nil,
    generation: String,
    topology: String
  ) throws {
    try CalendarEventWriteRepo.createCalendarEvent(
      db,
      params: CalendarEventCreateParams(
        id: id, title: title, recurrence: recurrence, timezone: "UTC",
        startDate: startDate, startTime: "09:00",
        endDate: startDate, endTime: "09:30", allDay: false,
        eventType: "event", seriesCutoverId: seriesCutoverId,
        seriesId: nil, recurrenceInstanceDate: nil,
        occurrenceState: nil, recurrenceGeneration: generation,
        recurrenceTopologyVersion: topology, version: topology,
        now: "2026-08-01T00:00:00Z"))
  }

  private func insertCutover(
    _ db: Database,
    lineageRootId: String,
    cutoverDate: String,
    state: CalendarSeriesCutoverState = .active,
    version: String
  ) throws -> String {
    let id = CalendarSeriesCutoverID.make(
      lineageRootId: lineageRootId, cutoverDate: cutoverDate)
    try CalendarSeriesCutoverRepo.upsert(
      db,
      row: CalendarSeriesCutoverRow(
        id: id, lineageRootId: lineageRootId, cutoverDate: cutoverDate,
        state: state, version: version,
        createdAt: "2026-08-01T00:00:00.000Z",
        updatedAt: "2026-08-01T00:00:00.000Z"))
    return id
  }

  @discardableResult
  private func insertDecision(
    _ db: Database,
    seriesId: String,
    instanceDate: String,
    state: CalendarOccurrenceState,
    generation: String,
    actualDate: String? = nil,
    title: String
  ) throws -> String {
    let id = CalendarOccurrenceDecisionID.make(
      seriesId: seriesId,
      recurrenceGeneration: generation,
      recurrenceInstanceDate: instanceDate)
    let date = actualDate ?? instanceDate
    try CalendarEventWriteRepo.createCalendarEvent(
      db,
      params: CalendarEventCreateParams(
        id: id, title: title, timezone: "UTC",
        startDate: date, startTime: "10:00", endDate: date, endTime: "10:30",
        allDay: false, eventType: "event", seriesId: seriesId,
        recurrenceInstanceDate: instanceDate, occurrenceState: state,
        recurrenceGeneration: generation, recurrenceTopologyVersion: nil,
        version: "1800000000100_0000_4444444444444444",
        now: "2026-08-02T00:00:00Z"))
    return id
  }

  private func pointEventItem(endTime: TimeOfDay?) -> CalendarTimelineItem {
    guard case let .success(item) = CalendarTimelineItem.make(
      source: .canonical, editable: true, id: "evt-1", title: "Point event",
      startDate: ymd("2026-04-26"), startTime: hm("09:00"), endDate: ymd("2026-04-26"),
      endTime: endTime, allDay: false, location: nil, color: nil, eventType: "appointment",
      personName: nil, timezone: nil, providerKind: nil, providerScope: nil,
      isRecurring: false, sourceTimeKind: nil, sourceTzid: nil, url: nil, attendeesJson: nil)
    else { fatalError("fixture") }
    return item
  }

  func testBlockingRangeDropsPointEventWithoutEndTime() throws {
    let queryDate = try CalendarRecurrence.parseYmd("2026-04-26")
    let item = pointEventItem(endTime: nil)
    let result = CalendarTimelineQueries.timelineItemToBlockingRange(item, queryDate, [])
    XCTAssertNil(result, "timed event with no end_time must be a 0-length point event")
  }

  func testBlockingRangeKeepsEventWithExplicitEndTime() throws {
    let queryDate = try CalendarRecurrence.parseYmd("2026-04-26")
    guard case let .success(item) = CalendarTimelineItem.make(
      source: .canonical, editable: true, id: "evt-2", title: "Real meeting",
      startDate: ymd("2026-04-26"), startTime: hm("10:00"), endDate: ymd("2026-04-26"),
      endTime: hm("11:30"), allDay: false, location: nil, color: nil, eventType: "appointment",
      personName: nil, timezone: nil, providerKind: nil, providerScope: nil,
      isRecurring: false, sourceTimeKind: nil, sourceTzid: nil, url: nil, attendeesJson: nil)
    else { return XCTFail("fixture") }
    let range = CalendarTimelineQueries.timelineItemToBlockingRange(item, queryDate, [])
    XCTAssertEqual(range?.startMinutes, 600)
    XCTAssertEqual(range?.endMinutes, 690)
  }

  func testGetDayBlockingRangesPropagatesStaleScopeQueryFailures() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(sql: "DROP TABLE provider_scope_runtime_state")
    }
    XCTAssertThrowsError(
      try store.writer.write { db in
        try CalendarTimelineQueries.getDayBlockingRanges(
          db, date: "2026-03-29", anchorTimezone: "UTC", accessMode: .off)
      }
    ) { error in
      XCTAssertTrue("\(error)".contains("provider_scope_runtime_state"), "unexpected: \(error)")
    }
  }

  func testProviderStaleScopesFlagsRowsOlderThan24h() throws {
    let store = try TestSupport.freshStore()
    let now = Date()
    func iso(_ d: Date) -> String {
      let f = ISO8601DateFormatter()
      f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      f.timeZone = TimeZone(identifier: "UTC")
      return f.string(from: d)
    }
    let boundaryTs = iso(now.addingTimeInterval(-(24 * 3600 + 60)))
    let farOldTs = iso(now.addingTimeInterval(-(48 * 3600)))
    let freshTs = iso(now.addingTimeInterval(-3600))

    try store.writer.write { db in
      for (scope, ts) in [
        ("scope-boundary", boundaryTs), ("scope-far-old", farOldTs), ("scope-fresh", freshTs),
      ] {
        try db.execute(
          sql: """
            INSERT INTO provider_scope_runtime_state \
            (provider_kind, provider_scope, availability_state, \
             last_refresh_attempt_at, last_refresh_success_at, last_refresh_result, last_error) \
            VALUES ('eventkit', ?, 'enabled', ?, ?, 'success', NULL)
            """,
          arguments: [scope, ts, ts])
      }
    }

    let stale = try store.writer.read { db in
      try CalendarTimelineQueries.providerStaleScopes(db)
    }
    XCTAssertTrue(
      stale.contains(.init(kind: "eventkit", scope: "scope-boundary")),
      "row past the 24h cutoff must be stale; got \(stale)")
    XCTAssertTrue(
      stale.contains(.init(kind: "eventkit", scope: "scope-far-old")),
      "48h-old row must be stale; got \(stale)")
    XCTAssertFalse(
      stale.contains(.init(kind: "eventkit", scope: "scope-fresh")),
      "1h-old row must NOT be stale; got \(stale)")
  }

  // -- end-to-end: recurrence expansion + occurrence decisions ------------

  /// A cancelled decision suppresses exactly one natural master occurrence.
  func testDailyTimelineExpandsAndSuppressesCancelledDecision() throws {
    let store = try TestSupport.freshStore()
    let generation = "0000000000000_0000_0000000000000000"
    try store.writer.write { db in
      let p = CalendarEventCreateParams(
        id: "evt-daily", title: "Standup",
        recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
        timezone: "UTC",
        startDate: "2026-03-20", startTime: "09:00",
        endDate: "2026-03-20", endTime: "09:30",
        allDay: false, eventType: "event",
        seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
        recurrenceGeneration: generation, recurrenceTopologyVersion: generation,
        version: generation, now: "2026-03-20T00:00:00Z")
      try CalendarEventWriteRepo.createCalendarEvent(db, params: p)
      let decisionId = CalendarOccurrenceDecisionID.make(
        seriesId: "evt-daily", recurrenceGeneration: generation,
        recurrenceInstanceDate: "2026-03-22")
      try CalendarEventWriteRepo.createCalendarEvent(
        db,
        params: CalendarEventCreateParams(
          id: decisionId, title: "Standup",
          timezone: "UTC", startDate: "2026-03-22", startTime: "09:00",
          endDate: "2026-03-22", endTime: "09:30", allDay: false,
          eventType: "event", seriesId: "evt-daily",
          recurrenceInstanceDate: "2026-03-22", occurrenceState: .cancelled,
          recurrenceGeneration: generation, recurrenceTopologyVersion: nil,
          version: "0000000000001_0000_0000000000000001",
          now: "2026-03-21T00:00:00Z"))
    }

    let items = try store.writer.read { db in
      try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-03-20", to: "2026-03-24", accessMode: .off, anchorTimezone: "UTC")
    }
    let dates = items.map { $0.startDate.asString }
    XCTAssertEqual(dates, ["2026-03-20", "2026-03-21", "2026-03-23", "2026-03-24"])
    XCTAssertTrue(items.allSatisfy { $0.isRecurring })
  }

  func testMovedReplacementAppearsOnceAtActualTimeAndNaturalIdsAreStable() throws {
    let store = try TestSupport.freshStore()
    let generation = "1800000000000_0001_1111111111111111"
    let topology = "1800000000000_0002_2222222222222222"
    let replacementId = try store.writer.write { db in
      try insertMaster(
        db, id: "series-moved", generation: generation, topology: topology)
      return try insertDecision(
        db, seriesId: "series-moved", instanceDate: "2026-08-11",
        state: .replacement, generation: generation, actualDate: "2026-08-14",
        title: "Moved occurrence")
    }

    let items = try store.writer.read { db in
      try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-08-10", to: "2026-08-15",
        accessMode: .off, anchorTimezone: "UTC")
    }
    XCTAssertFalse(
      items.contains { $0.startDate.asString == "2026-08-11" },
      "the replacement must suppress its original master occurrence")
    let replacement = try XCTUnwrap(items.first { $0.id == replacementId })
    XCTAssertEqual(replacement.startDate.asString, "2026-08-14")
    XCTAssertEqual(replacement.occurrenceState, .replacement)
    XCTAssertEqual(replacement.seriesId, "series-moved")
    XCTAssertEqual(replacement.recurrenceInstanceDate, "2026-08-11")
    XCTAssertEqual(replacement.recurrenceGeneration, generation)
    XCTAssertEqual(items.filter { $0.id == replacementId }.count, 1)

    let natural = try XCTUnwrap(
      items.first { $0.recurrenceInstanceDate == "2026-08-10" })
    XCTAssertNil(natural.occurrenceState)
    XCTAssertEqual(natural.seriesId, "series-moved")
    XCTAssertEqual(
      natural.id,
      CalendarOccurrenceDecisionID.make(
        seriesId: "series-moved", recurrenceGeneration: generation,
        recurrenceInstanceDate: "2026-08-10"))
  }

  func testVisibleReadsAndNativeExportApplyDifferentDecisionPolicies() throws {
    let store = try TestSupport.freshStore()
    let generation = "1800000000000_0001_1111111111111111"
    let staleGeneration = "1799999999999_0001_9999999999999999"
    let topology = "1800000000000_0002_2222222222222222"
    var replacementId = ""
    var cancelledId = ""
    var inheritId = ""
    var staleId = ""
    var orphanId = ""
    var outsideGridId = ""
    try store.writer.write { db in
      try insertMaster(
        db, id: "series-export", recurrence: #"{"FREQ":"DAILY","COUNT":3}"#,
        generation: generation, topology: topology)
      replacementId = try insertDecision(
        db, seriesId: "series-export", instanceDate: "2026-08-10",
        state: .replacement, generation: generation, title: "VisibleReplacement")
      cancelledId = try insertDecision(
        db, seriesId: "series-export", instanceDate: "2026-08-11",
        state: .cancelled, generation: generation, title: "InvisibleCancel")
      inheritId = try insertDecision(
        db, seriesId: "series-export", instanceDate: "2026-08-12",
        state: .inherit, generation: generation, title: "InvisibleInherit")
      staleId = try insertDecision(
        db, seriesId: "series-export", instanceDate: "2026-08-10",
        state: .replacement, generation: staleGeneration, title: "StaleReplacement")
      orphanId = try insertDecision(
        db, seriesId: "missing-series", instanceDate: "2026-08-10",
        state: .cancelled, generation: generation, title: "OrphanCancel")
      outsideGridId = try insertDecision(
        db, seriesId: "series-export", instanceDate: "2026-08-13",
        state: .replacement, generation: generation, title: "OutsideGrid")
    }

    try store.writer.read { db in
      let listed = try CalendarTimelineQueries.listCalendarEvents(
        db, from: "2026-08-01", to: "2026-08-31", limit: 100, offset: 0)
      XCTAssertEqual(Set(listed.map(\.id)), ["series-export", replacementId])
      XCTAssertNotNil(try CalendarTimelineQueries.getCalendarEvent(db, id: replacementId))
      for hiddenId in [cancelledId, inheritId, staleId, orphanId, outsideGridId] {
        XCTAssertNil(try CalendarTimelineQueries.getCalendarEvent(db, id: hiddenId))
      }

      XCTAssertEqual(
        try CalendarTimelineQueries.searchCalendarEvents(
          db, predicate: CalendarSearchPredicate(query: "VisibleReplacement"), limit: 10
        ).map(\.id),
        [replacementId])
      for hiddenTitle in [
        "InvisibleCancel", "InvisibleInherit", "StaleReplacement", "OrphanCancel", "OutsideGrid",
      ] {
        XCTAssertTrue(
          try CalendarTimelineQueries.searchCalendarEvents(
            db, predicate: CalendarSearchPredicate(query: hiddenTitle), limit: 10
          ).isEmpty)
      }

      let master = try XCTUnwrap(
        CalendarTimelineQueries.getCalendarEvent(db, id: "series-export"))
      XCTAssertEqual(
        master.recurrenceExceptions,
        #"["2026-08-10","2026-08-11","2026-08-13"]"#,
        "replacement/cancelled suppress; inherit does not; grid membership is a read concern")

      let exported = try CalendarTimelineQueries.listCalendarEventRowsForNativeExport(
        db, limit: 100, offset: 0)
      XCTAssertEqual(exported.first?.id, "series-export")
      XCTAssertEqual(
        Set(exported.map(\.id)), ["series-export", replacementId, cancelledId, inheritId])
      XCTAssertFalse(exported.contains { [staleId, orphanId, outsideGridId].contains($0.id) })
      XCTAssertEqual(
        try CalendarTimelineQueries.listCalendarEventRowsForNativeExport(
          db, limit: 2, offset: 1).map(\.id),
        Array(exported.dropFirst().prefix(2)).map(\.id))
    }
  }

  func testListCalendarEventsPrunesEndedSeriesBeforeApplyingTheResultCap() throws {
    let store = try TestSupport.freshStore()
    let generation = "1800000000000_0001_1111111111111111"
    let topology = "1800000000000_0002_2222222222222222"
    try store.writer.write { db in
      for index in 0..<5_000 {
        try insertMaster(
          db,
          id: String(format: "ended-series-%04d", index),
          recurrence: #"{"FREQ":"DAILY","UNTIL":"2020-01-02"}"#,
          startDate: "2020-01-01",
          generation: generation,
          topology: topology)
      }
      try insertMaster(
        db,
        id: "requested-series",
        recurrence: #"{"FREQ":"DAILY","UNTIL":"2030-01-03"}"#,
        startDate: "2030-01-01",
        generation: generation,
        topology: topology)
    }

    let listed = try store.writer.read { db in
      try CalendarTimelineQueries.listCalendarEvents(
        db, from: "2030-01-01", to: "2030-01-05", limit: 5_000, offset: 0)
    }

    XCTAssertEqual(listed.map(\.id), ["requested-series"])
  }

  func testDurableCutoversPartitionLineageAndRootDeletionLeavesTailsVisible() throws {
    let store = try TestSupport.freshStore()
    let rootId = "11111111-1111-4111-8111-111111111111"
    let generation = "1800000000000_0001_1111111111111111"
    let topology = "1800000000000_0002_2222222222222222"
    var firstTailId = ""
    var secondTailId = ""
    try store.writer.write { db in
      try insertMaster(
        db, id: rootId, title: "Root", generation: generation, topology: topology)
      firstTailId = try insertCutover(
        db, lineageRootId: rootId, cutoverDate: "2026-08-12",
        version: "1800000000001_0000_1111111111111111")
      try insertMaster(
        db, id: firstTailId, title: "First tail", startDate: "2026-08-12",
        seriesCutoverId: firstTailId, generation: generation, topology: topology)
      secondTailId = try insertCutover(
        db, lineageRootId: rootId, cutoverDate: "2026-08-14",
        version: "1800000000002_0000_1111111111111111")
      try insertMaster(
        db, id: secondTailId, title: "Second tail", startDate: "2026-08-14",
        seriesCutoverId: secondTailId, generation: generation, topology: topology)
    }

    func timeline() throws -> [CalendarTimelineItem] {
      try store.writer.read { db in
        try CalendarTimelineQueries.getCalendarTimeline(
          db, from: "2026-08-10", to: "2026-08-16",
          accessMode: .off, anchorTimezone: "UTC")
      }
    }

    let partitioned = try timeline()
    XCTAssertEqual(
      partitioned.map { "\($0.title)@\($0.recurrenceInstanceDate ?? "nil")" },
      [
        "Root@2026-08-10", "Root@2026-08-11",
        "First tail@2026-08-12", "First tail@2026-08-13",
        "Second tail@2026-08-14", "Second tail@2026-08-15",
        "Second tail@2026-08-16",
      ])

    try store.writer.write { db in
      try db.execute(sql: "DELETE FROM calendar_events WHERE id = ?", arguments: [rootId])
    }
    let withoutRoot = try timeline()
    XCTAssertFalse(withoutRoot.contains { $0.title == "Root" })
    XCTAssertEqual(
      withoutRoot.filter { $0.title == "First tail" }.map(\.recurrenceInstanceDate),
      ["2026-08-12", "2026-08-13"])
    XCTAssertEqual(
      withoutRoot.filter { $0.title == "Second tail" }.map(\.recurrenceInstanceDate),
      ["2026-08-14", "2026-08-15", "2026-08-16"])

    try store.writer.read { db in
      let ownership = try XCTUnwrap(
        CalendarTimelineQueries.getCalendarSeriesOwnership(db, eventId: firstTailId))
      XCTAssertEqual(ownership.lineageRootId, rootId)
      XCTAssertEqual(ownership.lowerBoundCutoverDate, "2026-08-12")
      XCTAssertEqual(ownership.nextCutoverDate, "2026-08-14")
      XCTAssertTrue(ownership.owns(recurrenceInstanceDate: "2026-08-13"))
      XCTAssertFalse(ownership.owns(recurrenceInstanceDate: "2026-08-14"))
    }
  }

  func testSegmentIdentityOwnershipDoesNotRequireCalendarEventArrival() throws {
    let store = try TestSupport.freshStore()
    let rootId = "55555555-5555-4555-8555-555555555555"
    var activeTailId = ""
    var deletedTailId = ""
    try store.writer.write { db in
      activeTailId = try insertCutover(
        db, lineageRootId: rootId, cutoverDate: "2026-08-12",
        version: "1800000000001_0000_1111111111111111")
      deletedTailId = try insertCutover(
        db, lineageRootId: rootId, cutoverDate: "2026-08-14", state: .deleted,
        version: "1800000000002_0000_1111111111111111")
    }

    try store.writer.read { db in
      let root = try XCTUnwrap(
        CalendarTimelineQueries.getCalendarSeriesOwnershipForSegmentIdentity(
          db, segmentEventId: rootId))
      XCTAssertNil(root.lowerBoundCutoverDate)
      XCTAssertEqual(root.nextCutoverDate, "2026-08-12")

      let active = try XCTUnwrap(
        CalendarTimelineQueries.getCalendarSeriesOwnershipForSegmentIdentity(
          db, segmentEventId: activeTailId))
      XCTAssertTrue(active.isActive)
      XCTAssertEqual(active.nextCutoverDate, "2026-08-14")

      let deleted = try XCTUnwrap(
        CalendarTimelineQueries.getCalendarSeriesOwnershipForSegmentIdentity(
          db, segmentEventId: deletedTailId))
      XCTAssertFalse(deleted.isActive)
      XCTAssertNil(deleted.nextCutoverDate)

      XCTAssertNil(
        try CalendarTimelineQueries.getCalendarSeriesOwnershipForSegmentIdentity(
          db, segmentEventId: "66666666-6666-4666-8666-666666666666"))
    }
  }

  func testProjectionIndexLoadsOnlyRequestedLineagesAndResolvesTailIdentity() throws {
    let store = try TestSupport.freshStore()
    let firstRootId = "77777777-7777-4777-8777-777777777777"
    let secondRootId = "99999999-9999-4999-8999-999999999999"
    var firstTailId = ""
    var secondTailId = ""
    var secondSuccessorId = ""
    try store.writer.write { db in
      firstTailId = try insertCutover(
        db, lineageRootId: firstRootId, cutoverDate: "2026-09-02",
        version: "1800000000001_0000_1111111111111111")
      secondTailId = try insertCutover(
        db, lineageRootId: secondRootId, cutoverDate: "2026-09-03",
        version: "1800000000002_0000_1111111111111111")
      secondSuccessorId = try insertCutover(
        db, lineageRootId: secondRootId, cutoverDate: "2026-09-05",
        version: "1800000000003_0000_1111111111111111")
    }

    try store.writer.read { db in
      var index = try CalendarSeriesProjectionIndex(
        db, candidates: .init(lineageRootIds: [firstRootId]))
      XCTAssertEqual(
        index.ownershipForSegmentIdentity(firstRootId)?.nextCutoverDate,
        "2026-09-02")
      XCTAssertNotNil(index.ownershipForSegmentIdentity(firstTailId))
      XCTAssertNil(
        index.ownershipForSegmentIdentity(secondRootId),
        "a lineage-bound index must not preload an unrelated boundary set")

      try index.load(db, candidates: .init(cutoverIds: [secondTailId]))
      XCTAssertEqual(
        index.ownershipForSegmentIdentity(secondRootId)?.nextCutoverDate,
        "2026-09-03")
      XCTAssertEqual(
        index.ownershipForSegmentIdentity(secondTailId)?.nextCutoverDate,
        "2026-09-05")
      XCTAssertNil(
        index.ownershipForSegmentIdentity(secondSuccessorId)?.nextCutoverDate)
    }
  }

  func testDeletedCutoverCreatesGapAndHidesRetainedSegmentFromEveryRead() throws {
    let store = try TestSupport.freshStore()
    let rootId = "22222222-2222-4222-8222-222222222222"
    let generation = "1800000000000_0001_1111111111111111"
    let topology = "1800000000000_0002_2222222222222222"
    var deletedTailId = ""
    var resumedTailId = ""
    try store.writer.write { db in
      try insertMaster(
        db, id: rootId, title: "Gap root", generation: generation, topology: topology)
      deletedTailId = try insertCutover(
        db, lineageRootId: rootId, cutoverDate: "2026-08-12",
        version: "1800000000001_0000_1111111111111111")
      try insertMaster(
        db, id: deletedTailId, title: "Private deleted tail", startDate: "2026-08-12",
        seriesCutoverId: deletedTailId, generation: generation, topology: topology)
      _ = try insertCutover(
        db, lineageRootId: rootId, cutoverDate: "2026-08-12", state: .deleted,
        version: "1800000000001_0001_1111111111111111")
      resumedTailId = try insertCutover(
        db, lineageRootId: rootId, cutoverDate: "2026-08-14",
        version: "1800000000002_0000_1111111111111111")
      try insertMaster(
        db, id: resumedTailId, title: "Resumed tail", startDate: "2026-08-14",
        seriesCutoverId: resumedTailId, generation: generation, topology: topology)
    }

    try store.writer.read { db in
      let items = try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-08-10", to: "2026-08-15",
        accessMode: .off, anchorTimezone: "UTC")
      XCTAssertEqual(
        items.map { "\($0.title)@\($0.recurrenceInstanceDate ?? "nil")" },
        [
          "Gap root@2026-08-10", "Gap root@2026-08-11",
          "Resumed tail@2026-08-14", "Resumed tail@2026-08-15",
        ])
      XCTAssertNil(try CalendarTimelineQueries.getCalendarEvent(db, id: deletedTailId))
      XCTAssertTrue(
        try CalendarTimelineQueries.searchCalendarEvents(
          db, predicate: CalendarSearchPredicate(query: "Private deleted tail"), limit: 10
        ).isEmpty)
      XCTAssertFalse(
        try CalendarTimelineQueries.listCalendarEventRowsForNativeExport(
          db, limit: 100, offset: 0).contains { $0.id == deletedTailId })
      XCTAssertFalse(
        try CalendarTimelineQueries.listCalendarEvents(
          db, from: "2026-08-20", to: "2026-08-21", limit: 100, offset: 0
        ).contains { $0.id == rootId })
      XCTAssertEqual(
        try CalendarTimelineQueries.searchCalendarEvents(
          db,
          predicate: CalendarSearchPredicate(
            query: "Gap root", from: "2026-08-11", to: "2026-08-11"),
          limit: 10
        ).map(\.id),
        [rootId])
      XCTAssertTrue(
        try CalendarTimelineQueries.searchCalendarEvents(
          db,
          predicate: CalendarSearchPredicate(
            query: "Gap root", from: "2026-08-20", to: "2026-08-21"),
          limit: 10
        ).isEmpty)
    }
  }

  func testDecisionOwnershipUsesOriginalSlotWhenReplacementMovesAcrossCutover() throws {
    let store = try TestSupport.freshStore()
    let rootId = "33333333-3333-4333-8333-333333333333"
    let generation = "1800000000000_0001_1111111111111111"
    let topology = "1800000000000_0002_2222222222222222"
    var firstTailId = ""
    var movedId = ""
    var staleId = ""
    try store.writer.write { db in
      try insertMaster(
        db, id: rootId, title: "Root", generation: generation, topology: topology)
      firstTailId = try insertCutover(
        db, lineageRootId: rootId, cutoverDate: "2026-08-12",
        version: "1800000000001_0000_1111111111111111")
      try insertMaster(
        db, id: firstTailId, title: "First tail", startDate: "2026-08-12",
        seriesCutoverId: firstTailId, generation: generation, topology: topology)
      let secondTailId = try insertCutover(
        db, lineageRootId: rootId, cutoverDate: "2026-08-14",
        version: "1800000000002_0000_1111111111111111")
      try insertMaster(
        db, id: secondTailId, title: "Second tail", startDate: "2026-08-14",
        seriesCutoverId: secondTailId, generation: generation, topology: topology)
      movedId = try insertDecision(
        db, seriesId: firstTailId, instanceDate: "2026-08-13",
        state: .replacement, generation: generation, actualDate: "2026-08-15",
        title: "Moved across boundary")
      staleId = try insertDecision(
        db, seriesId: firstTailId, instanceDate: "2026-08-14",
        state: .replacement, generation: generation, actualDate: "2026-08-13",
        title: "Outside owned interval")
    }

    try store.writer.read { db in
      let items = try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-08-12", to: "2026-08-15",
        accessMode: .off, anchorTimezone: "UTC")
      let moved = try XCTUnwrap(items.first { $0.id == movedId })
      XCTAssertEqual(moved.startDate.asString, "2026-08-15")
      XCTAssertEqual(moved.recurrenceInstanceDate, "2026-08-13")
      XCTAssertFalse(items.contains { $0.id == staleId })
      XCTAssertNotNil(try CalendarTimelineQueries.getCalendarEvent(db, id: movedId))
      XCTAssertNil(try CalendarTimelineQueries.getCalendarEvent(db, id: staleId))
      let ownership = try XCTUnwrap(
        CalendarTimelineQueries.getCalendarSeriesOwnership(db, eventId: movedId))
      XCTAssertEqual(ownership.segmentEventId, firstTailId)
      XCTAssertTrue(ownership.owns(recurrenceInstanceDate: "2026-08-13"))
    }
  }

  func testNonRecurringTailKeepsCutoverSlotWhenDisplayDateMovesPastNextBoundary() throws {
    let store = try TestSupport.freshStore()
    let rootId = "44444444-4444-4444-8444-444444444444"
    let generation = "1800000000000_0001_1111111111111111"
    let topology = "1800000000000_0002_2222222222222222"
    var oneOffTailId = ""
    try store.writer.write { db in
      try insertMaster(
        db, id: rootId, title: "Root", generation: generation, topology: topology)
      oneOffTailId = try insertCutover(
        db, lineageRootId: rootId, cutoverDate: "2026-08-12",
        version: "1800000000001_0000_1111111111111111")
      try CalendarEventWriteRepo.createCalendarEvent(
        db,
        params: CalendarEventCreateParams(
          id: oneOffTailId, title: "Moved one-off tail", timezone: "UTC",
          startDate: "2026-08-15", startTime: "11:00",
          endDate: "2026-08-15", endTime: "11:30", allDay: false,
          eventType: "event", seriesCutoverId: oneOffTailId,
          seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
          recurrenceGeneration: nil, recurrenceTopologyVersion: topology,
          version: topology, now: "2026-08-01T00:00:00Z"))
      let resumedId = try insertCutover(
        db, lineageRootId: rootId, cutoverDate: "2026-08-14",
        version: "1800000000002_0000_1111111111111111")
      try insertMaster(
        db, id: resumedId, title: "Resumed", startDate: "2026-08-14",
        seriesCutoverId: resumedId, generation: generation, topology: topology)
    }

    let items = try store.writer.read { db in
      try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-08-15", to: "2026-08-15",
        accessMode: .off, anchorTimezone: "UTC")
    }
    XCTAssertEqual(items.filter { $0.id == oneOffTailId }.map(\.title), ["Moved one-off tail"])
    XCTAssertTrue(items.contains { $0.title == "Resumed" })
  }

  /// A recurring event whose occurrences roll past the representable date
  /// range (year ≥ 10000, which `LorvexDate.parse` rejects as an 11-character
  /// string) stops expansion at the boundary instead of force-unwrapping a
  /// failed parse and trapping. Here a two-day all-day event anchored at
  /// 9999-12-30 recurs daily: the 9999-12-31 occurrence's end date is
  /// 10000-01-01, which previously crashed `expandRowForRange`.
  func testFarFutureRecurrenceStopsAtParseBoundaryWithoutCrashing() throws {
    guard case let .success(item) = CalendarTimelineItem.make(
      source: .canonical, editable: true, id: "evt-far-future", title: "End of days",
      startDate: ymd("9999-12-30"), startTime: nil, endDate: ymd("9999-12-31"),
      endTime: nil, allDay: true, location: nil, color: nil, eventType: "event",
      personName: nil, timezone: "UTC", providerKind: nil, providerScope: nil,
      isRecurring: true, sourceTimeKind: nil, sourceTzid: nil, url: nil, attendeesJson: nil)
    else { return XCTFail("fixture") }

    let row = CalendarTimeline.RawCalendarRow(
      item: item, recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#, recurrenceExceptions: nil)
    let from = try CalendarRecurrence.parseYmd("9999-12-30")
    let to = try CalendarRecurrence.parseYmd("9999-12-31")

    let expanded = try CalendarTimeline.expandRowForRange(row, from, to, "UTC")
    // Only the fully representable occurrence survives; expansion halts before
    // the 10000-01-01 end date rather than trapping.
    XCTAssertEqual(expanded.items.map { $0.startDate.asString }, ["9999-12-30"])
    XCTAssertFalse(expanded.truncatedAtStepCap)
  }

  /// Provider `description` / `organizer_email` / `video_call_url` are projected
  /// onto the timeline item so the full tier exposes them (previously
  /// write-only), and `redactProviderDetails` nils them for the busy tier so the
  /// read surface honors the tier as defense in depth.
  func testProviderTimelineSurfacesAndRedactsPrivateDetailFields() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO provider_calendar_events \
            (provider_kind, provider_scope, provider_event_key, title, description, \
             start_date, start_time, end_date, end_time, all_day, \
             organizer_email, video_call_url, source_time_kind, source_tzid, last_seen_at) \
          VALUES ('eventkit', 'device', 'ek-1', 'Design sync', 'confidential agenda', \
                  '2026-06-02', '10:00', '2026-06-02', '11:00', 0, \
                  'alice@example.com', 'https://meet.example.com/xyz', \
                  'tzid', 'America/New_York', \
                  '2026-06-01T00:00:00Z')
          """)
      try db.execute(
        sql: """
          INSERT INTO provider_scope_runtime_state \
            (provider_kind, provider_scope, availability_state, \
             last_refresh_success_at, last_refresh_result) \
          VALUES ('eventkit', 'device', 'enabled', '2026-06-01T00:00:00Z', 'success')
          """)
    }

    // Full tier surfaces the private detail fields.
    let full = try store.writer.read { db in
      try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-06-01", to: "2026-06-05", accessMode: .fullDetails, anchorTimezone: "UTC")
    }
    let fullItem = try XCTUnwrap(full.first { $0.source == .provider })
    XCTAssertEqual(fullItem.title, "Design sync")
    XCTAssertEqual(fullItem.description, "confidential agenda")
    XCTAssertEqual(fullItem.personName, "alice@example.com")
    XCTAssertEqual(fullItem.url, "https://meet.example.com/xyz")
    XCTAssertEqual(fullItem.eventType, "event")
    XCTAssertEqual(fullItem.timezone, "America/New_York")
    XCTAssertEqual(fullItem.sourceTimeKind, "tzid")
    XCTAssertEqual(fullItem.sourceTzid, "America/New_York")

    let organizerHits = try store.writer.read { db in
      try CalendarTimelineQueries.searchProviderCalendarEvents(
        db, predicate: CalendarSearchPredicate(query: "alice@example.com"), limit: 10)
    }
    XCTAssertEqual(organizerHits.map(\.id), ["eventkit:device:ek-1"])
    XCTAssertEqual(organizerHits.first?.timezone, "America/New_York")
    XCTAssertEqual(organizerHits.first?.sourceTzid, "America/New_York")

    // Busy tier redacts them at the read layer.
    let busy = try store.writer.read { db in
      try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-06-01", to: "2026-06-05", accessMode: .busyOnly, anchorTimezone: "UTC")
    }
    let busyItem = try XCTUnwrap(busy.first { $0.source == .provider })
    XCTAssertEqual(busyItem.title, "Busy")
    XCTAssertNil(busyItem.description)
    XCTAssertNil(busyItem.personName)
    XCTAssertNil(busyItem.url)
  }

  func testProviderTimelineProjectsUTCSourceWithoutTZID() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO provider_calendar_events \
            (provider_kind, provider_scope, provider_event_key, title, \
             start_date, start_time, end_date, end_time, all_day, \
             source_time_kind, source_tzid, last_seen_at) \
          VALUES ('eventkit', 'device', 'ek-utc', 'UTC event', \
                  '2026-06-02', '10:00', '2026-06-02', '11:00', 0, \
                  'utc', NULL, '2026-06-01T00:00:00Z')
          """)
      try db.execute(
        sql: """
          INSERT INTO provider_scope_runtime_state \
            (provider_kind, provider_scope, availability_state, \
             last_refresh_success_at, last_refresh_result) \
          VALUES ('eventkit', 'device', 'enabled', '2026-06-01T00:00:00Z', 'success')
          """)
    }

    let items = try store.writer.read { db in
      try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-06-02", to: "2026-06-02",
        accessMode: .fullDetails, anchorTimezone: "UTC")
    }
    let item = try XCTUnwrap(items.first { $0.id == "eventkit:device:ek-utc" })
    XCTAssertEqual(item.timezone, "UTC")
    XCTAssertEqual(item.sourceTimeKind, "utc")
    XCTAssertNil(item.sourceTzid)
  }

  /// Non-recurring single-day timed event appears when the window overlaps.
  func testSingleEventInWindow() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let p = CalendarEventCreateParams(
        id: "evt-one", title: "One-off",
        timezone: "UTC",
        startDate: "2026-04-10", startTime: "14:00",
        endDate: "2026-04-10", endTime: "15:00",
        allDay: false, eventType: "event",
        seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
        recurrenceGeneration: nil,
        recurrenceTopologyVersion: "0000000000000_0000_0000000000000000",
        version: "0000000000000_0000_0000000000000000", now: "2026-04-10T00:00:00Z")
      try CalendarEventWriteRepo.createCalendarEvent(db, params: p)
    }
    let inWindow = try store.writer.read { db in
      try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-04-09", to: "2026-04-11", accessMode: .off, anchorTimezone: "UTC")
    }
    XCTAssertEqual(inWindow.map { $0.id }, ["evt-one"])
    let outOfWindow = try store.writer.read { db in
      try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-05-01", to: "2026-05-02", accessMode: .off, anchorTimezone: "UTC")
    }
    XCTAssertTrue(outOfWindow.isEmpty)
  }

  /// A timed COUNT-bounded series renders exactly COUNT occurrences even when
  /// the query window extends well past the count terminal. The timed
  /// projection buffer (bufferDays = 1) must widen only the scan window, never
  /// the series bound: a 09:00 America/New_York event with
  /// `{"FREQ":"DAILY","COUNT":3}` from Jan 1, queried Jan 1..Jan 10, must yield
  /// Jan 1/2/3 — not a phantom Jan 4 (the COUNT+1)th step.
  func testTimedCountBoundedSeriesDoesNotRenderPhantomOccurrence() throws {
    guard case let .success(item) = CalendarTimelineItem.make(
      source: .canonical, editable: true, id: "evt-count-3", title: "Standup",
      startDate: ymd("2026-01-01"), startTime: hm("09:00"), endDate: ymd("2026-01-01"),
      endTime: nil, allDay: false, location: nil, color: nil, eventType: "event",
      personName: nil, timezone: "America/New_York", providerKind: nil, providerScope: nil,
      isRecurring: true, sourceTimeKind: nil, sourceTzid: nil, url: nil, attendeesJson: nil)
    else { return XCTFail("fixture") }

    let row = CalendarTimeline.RawCalendarRow(
      item: item, recurrence: #"{"FREQ":"DAILY","INTERVAL":1,"COUNT":3}"#,
      recurrenceExceptions: nil)
    let from = try CalendarRecurrence.parseYmd("2026-01-01")
    let to = try CalendarRecurrence.parseYmd("2026-01-10")

    let expanded = try CalendarTimeline.expandRowForRange(row, from, to, "America/New_York")
    XCTAssertEqual(
      expanded.items.map { $0.startDate.asString },
      ["2026-01-01", "2026-01-02", "2026-01-03"])
    XCTAssertFalse(expanded.truncatedAtStepCap)
  }

  /// The COUNT clamp holds when the series straddles a DST transition. The
  /// projection buffer (bufferDays = 1) exists to catch occurrences whose local
  /// wall clock crosses midnight under timezone projection — exactly the case a
  /// DST boundary provokes — so this is where clamping the series bound to the
  /// COUNT terminal matters most. A 09:00 America/New_York event with
  /// `{"FREQ":"DAILY","COUNT":3}` from Mar 7 2026 spans the US spring-forward on
  /// Mar 8; queried across the whole month it must yield Mar 7/8/9 — not a
  /// phantom Mar 10 (the COUNT+1)th step.
  func testTimedCountBoundedSeriesClampsAcrossDstBoundary() throws {
    guard case let .success(item) = CalendarTimelineItem.make(
      source: .canonical, editable: true, id: "evt-count-dst", title: "Standup",
      startDate: ymd("2026-03-07"), startTime: hm("09:00"), endDate: ymd("2026-03-07"),
      endTime: nil, allDay: false, location: nil, color: nil, eventType: "event",
      personName: nil, timezone: "America/New_York", providerKind: nil, providerScope: nil,
      isRecurring: true, sourceTimeKind: nil, sourceTzid: nil, url: nil, attendeesJson: nil)
    else { return XCTFail("fixture") }

    let row = CalendarTimeline.RawCalendarRow(
      item: item, recurrence: #"{"FREQ":"DAILY","INTERVAL":1,"COUNT":3}"#,
      recurrenceExceptions: nil)
    let from = try CalendarRecurrence.parseYmd("2026-03-01")
    let to = try CalendarRecurrence.parseYmd("2026-03-31")

    let expanded = try CalendarTimeline.expandRowForRange(row, from, to, "America/New_York")
    XCTAssertEqual(
      expanded.items.map { $0.startDate.asString },
      ["2026-03-07", "2026-03-08", "2026-03-09"])
    XCTAssertFalse(expanded.truncatedAtStepCap)
  }
}
