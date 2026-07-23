import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class ProviderRepoTests: XCTestCase {

  private func tid(_ s: String) -> TaskId { TaskId(trusted: s) }

  private func insertTask(_ db: Database, taskId: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, priority, version, created_at, updated_at) \
        VALUES (?, 'Test', 'open', 2, '0000000000000_0000_0000000000000000', \
        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """,
      arguments: [taskId])
  }

  private func insertProviderEvent(
    _ db: Database, providerKind: String, providerScope: String, providerEventKey: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO provider_calendar_events \
            (provider_kind, provider_scope, provider_event_key, title, \
             start_date, all_day, last_seen_at) \
        VALUES (?, ?, ?, 'Event', '2026-06-01', 0, '2026-03-20T10:00:00Z')
        """,
      arguments: [providerKind, providerScope, providerEventKey])
  }

  private func setScopeRuntimeState(
    _ db: Database,
    providerKind: String, providerScope: String,
    availabilityState: String, lastRefreshSuccessAt: String?
  ) throws {
    let lastRefreshResult: String? = lastRefreshSuccessAt.map { _ in "success" }
    try db.execute(
      sql: """
        INSERT OR REPLACE INTO provider_scope_runtime_state \
            (provider_kind, provider_scope, availability_state, \
             last_refresh_success_at, last_refresh_result) \
        VALUES (?, ?, ?, ?, ?)
        """,
      arguments: [
        providerKind, providerScope, availabilityState,
        lastRefreshSuccessAt, lastRefreshResult,
      ])
  }

  private func setScopeRuntimeFailure(
    _ db: Database,
    providerKind: String, providerScope: String, lastRefreshSuccessAt: String?
  ) throws {
    try db.execute(
      sql: """
        INSERT OR REPLACE INTO provider_scope_runtime_state \
            (provider_kind, provider_scope, availability_state, \
             last_refresh_success_at, last_refresh_result) \
        VALUES (?, ?, 'enabled', ?, 'fetch_error')
        """,
      arguments: [providerKind, providerScope, lastRefreshSuccessAt])
  }

  // -- link CRUD --

  func testUpsertAndRemoveProviderLink() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, taskId: "t1")
    }
    let link = try store.writer.write { db in
      try ProviderRepo.upsertProviderEventLink(
        db, taskId: self.tid("t1"), providerKind: "eventkit",
        providerScope: "", providerEventKey: "ek-123")
    }
    XCTAssertEqual(link.taskId, "t1")
    XCTAssertEqual(link.providerKind, "eventkit")
    XCTAssertEqual(link.providerEventKey, "ek-123")

    let remaining = try store.writer.write { db in
      try ProviderRepo.deleteProviderEventLink(
        db, taskId: self.tid("t1"), providerKind: "eventkit",
        providerScope: "", providerEventKey: "ek-123")
    }
    XCTAssertTrue(remaining.deleted)
    XCTAssertNotNil(remaining.before)
    XCTAssertTrue(remaining.remainingLinks.isEmpty)
  }

  // -- resolved link state cases --

  func testResolvedLinksCacheHit() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, taskId: "t1")
      try self.insertProviderEvent(
        db, providerKind: "eventkit", providerScope: "", providerEventKey: "ek-123")
      try self.setScopeRuntimeState(
        db, providerKind: "eventkit", providerScope: "",
        availabilityState: "enabled",
        lastRefreshSuccessAt: "2026-03-20T10:00:00Z")
      _ = try ProviderRepo.upsertProviderEventLink(
        db, taskId: self.tid("t1"), providerKind: "eventkit",
        providerScope: "", providerEventKey: "ek-123")
    }
    let links = try store.writer.read { db in
      try ProviderRepo.getResolvedProviderLinksForTask(db, taskId: self.tid("t1"))
    }
    XCTAssertEqual(links.count, 1)
    XCTAssertEqual(links[0].resolutionState, .resolved)
    XCTAssertEqual(links[0].eventTitle, "Event")
  }

  func testResolvedLinksMissingWhenProviderOperationalButEventGone() throws {
    let store = try TestSupport.freshStore()
    let freshSuccess = SyncTimestamp.now().asString
    try store.writer.write { db in
      try self.insertTask(db, taskId: "t1")
      try self.insertProviderEvent(
        db, providerKind: "eventkit", providerScope: "", providerEventKey: "ek-other")
      try self.setScopeRuntimeState(
        db, providerKind: "eventkit", providerScope: "",
        availabilityState: "enabled", lastRefreshSuccessAt: freshSuccess)
      _ = try ProviderRepo.upsertProviderEventLink(
        db, taskId: self.tid("t1"), providerKind: "eventkit",
        providerScope: "", providerEventKey: "ek-gone")
    }
    let links = try store.writer.read { db in
      try ProviderRepo.getResolvedProviderLinksForTask(db, taskId: self.tid("t1"))
    }
    XCTAssertEqual(links.count, 1)
    XCTAssertEqual(links[0].resolutionState, .missing)
  }

  func testResolvedLinksUnavailableWhenProviderDisabled() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, taskId: "t1")
      try self.setScopeRuntimeState(
        db, providerKind: "eventkit", providerScope: "",
        availabilityState: "disabled",
        lastRefreshSuccessAt: "2026-03-20T10:00:00Z")
      _ = try ProviderRepo.upsertProviderEventLink(
        db, taskId: self.tid("t1"), providerKind: "eventkit",
        providerScope: "", providerEventKey: "ek-123")
    }
    let links = try store.writer.read { db in
      try ProviderRepo.getResolvedProviderLinksForTask(db, taskId: self.tid("t1"))
    }
    XCTAssertEqual(links.count, 1)
    XCTAssertEqual(links[0].resolutionState, .unavailable)
  }

  func testResolvedLinksUnavailableWhenNoRuntimeStateRow() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, taskId: "t1")
      _ = try ProviderRepo.upsertProviderEventLink(
        db, taskId: self.tid("t1"), providerKind: "eventkit",
        providerScope: "", providerEventKey: "ek-123")
    }
    let links = try store.writer.read { db in
      try ProviderRepo.getResolvedProviderLinksForTask(db, taskId: self.tid("t1"))
    }
    XCTAssertEqual(links.count, 1)
    XCTAssertEqual(links[0].resolutionState, .unavailable)
  }

  func testResolvedLinksPendingWhenScopeEnabledButNeverRefreshed() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, taskId: "t1")
      try self.setScopeRuntimeState(
        db, providerKind: "eventkit", providerScope: "",
        availabilityState: "enabled", lastRefreshSuccessAt: nil)
      _ = try ProviderRepo.upsertProviderEventLink(
        db, taskId: self.tid("t1"), providerKind: "eventkit",
        providerScope: "", providerEventKey: "ek-123")
    }
    let links = try store.writer.read { db in
      try ProviderRepo.getResolvedProviderLinksForTask(db, taskId: self.tid("t1"))
    }
    XCTAssertEqual(links.count, 1)
    XCTAssertEqual(links[0].resolutionState, .pending)
  }

  func testResolvedLinksStaleWhenScopeSuccessIsTooOld() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, taskId: "t1")
      try self.setScopeRuntimeState(
        db, providerKind: "eventkit", providerScope: "",
        availabilityState: "enabled",
        lastRefreshSuccessAt: "2000-01-01T00:00:00.000Z")
      _ = try ProviderRepo.upsertProviderEventLink(
        db, taskId: self.tid("t1"), providerKind: "eventkit",
        providerScope: "", providerEventKey: "ek-123")
    }
    let links = try store.writer.read { db in
      try ProviderRepo.getResolvedProviderLinksForTask(db, taskId: self.tid("t1"))
    }
    XCTAssertEqual(links.count, 1)
    XCTAssertEqual(links[0].resolutionState, .stale)
  }

  func testResolvedLinksUnavailableWhenEnabledScopeFailing() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, taskId: "t1")
      try self.setScopeRuntimeFailure(
        db, providerKind: "eventkit", providerScope: "",
        lastRefreshSuccessAt: "2000-01-01T00:00:00.000Z")
      _ = try ProviderRepo.upsertProviderEventLink(
        db, taskId: self.tid("t1"), providerKind: "eventkit",
        providerScope: "", providerEventKey: "ek-123")
    }
    let links = try store.writer.read { db in
      try ProviderRepo.getResolvedProviderLinksForTask(db, taskId: self.tid("t1"))
    }
    XCTAssertEqual(links.count, 1)
    XCTAssertEqual(links[0].resolutionState, .unavailable)
  }

  // -- provider event monotonic gate --

  func testUpsertProviderEventRejectsStaleLastSeenAt() throws {
    let store = try TestSupport.freshStore()
    let baseEvent = ProviderEventData(
      providerKind: "eventkit", providerScope: "feed-1",
      providerEventKey: "evt-1",
      title: "Initial", description: nil,
      startDate: "2026-06-01", startTime: nil,
      endDate: nil, endTime: nil, allDay: true,
      location: nil, organizerEmail: nil,
      sourceTimeKind: "floating", sourceTzid: nil,
      recurrence: nil, recurrenceExceptions: nil,
      color: nil, attendeesJson: nil, videoCallUrl: nil)
    let outcome1 = try store.writer.write { db in
      try ProviderRepo.upsertProviderEvent(
        db, event: baseEvent, now: "2026-04-28T12:00:00.000Z")
    }
    XCTAssertEqual(outcome1, .inserted)

    let winner = ProviderEventData(
      providerKind: baseEvent.providerKind, providerScope: baseEvent.providerScope,
      providerEventKey: baseEvent.providerEventKey, title: "Winner",
      description: baseEvent.description, startDate: baseEvent.startDate,
      startTime: baseEvent.startTime, endDate: baseEvent.endDate,
      endTime: baseEvent.endTime, allDay: baseEvent.allDay,
      location: baseEvent.location, organizerEmail: baseEvent.organizerEmail,
      sourceTimeKind: baseEvent.sourceTimeKind, sourceTzid: baseEvent.sourceTzid,
      recurrence: baseEvent.recurrence,
      recurrenceExceptions: baseEvent.recurrenceExceptions,
      color: baseEvent.color, attendeesJson: baseEvent.attendeesJson,
      videoCallUrl: baseEvent.videoCallUrl)
    let outcome2 = try store.writer.write { db in
      try ProviderRepo.upsertProviderEvent(
        db, event: winner, now: "2026-04-28T12:05:00.000Z")
    }
    XCTAssertEqual(outcome2, .updated)

    let loser = ProviderEventData(
      providerKind: baseEvent.providerKind, providerScope: baseEvent.providerScope,
      providerEventKey: baseEvent.providerEventKey, title: "Loser",
      description: baseEvent.description, startDate: baseEvent.startDate,
      startTime: baseEvent.startTime, endDate: baseEvent.endDate,
      endTime: baseEvent.endTime, allDay: baseEvent.allDay,
      location: baseEvent.location, organizerEmail: baseEvent.organizerEmail,
      sourceTimeKind: baseEvent.sourceTimeKind, sourceTzid: baseEvent.sourceTzid,
      recurrence: baseEvent.recurrence,
      recurrenceExceptions: baseEvent.recurrenceExceptions,
      color: baseEvent.color, attendeesJson: baseEvent.attendeesJson,
      videoCallUrl: baseEvent.videoCallUrl)
    let outcome3 = try store.writer.write { db in
      try ProviderRepo.upsertProviderEvent(
        db, event: loser, now: "2026-04-28T12:01:00.000Z")
    }
    XCTAssertEqual(outcome3, .unchanged)

    let (title, lastSeen) = try store.writer.read { db -> (String, String) in
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT title, last_seen_at FROM provider_calendar_events \
          WHERE provider_kind = 'eventkit' AND provider_scope = 'feed-1' \
            AND provider_event_key = 'evt-1'
          """)!
      return (row[0], row[1])
    }
    XCTAssertEqual(title, "Winner")
    XCTAssertEqual(lastSeen, "2026-04-28T12:05:00.000Z")
  }

  func testUpsertProviderEventUnchangedForRefreshWithoutVisibleChanges() throws {
    let store = try TestSupport.freshStore()
    let event = ProviderEventData(
      providerKind: "eventkit", providerScope: "feed-1",
      providerEventKey: "evt-1",
      title: "Stable", description: "unchanged",
      startDate: "2026-06-01", startTime: "09:00",
      endDate: "2026-06-01", endTime: "10:00", allDay: false,
      location: "Room", organizerEmail: "owner@example.com",
      sourceTimeKind: "tzid", sourceTzid: "America/New_York",
      recurrence: nil, recurrenceExceptions: nil,
      color: "#123456", attendeesJson: "[]",
      videoCallUrl: "https://example.com/meet")
    let o1 = try store.writer.write { db in
      try ProviderRepo.upsertProviderEvent(
        db, event: event, now: "2026-04-28T12:00:00.000Z")
    }
    XCTAssertEqual(o1, .inserted)
    let o2 = try store.writer.write { db in
      try ProviderRepo.upsertProviderEvent(
        db, event: event, now: "2026-04-28T12:10:00.000Z")
    }
    XCTAssertEqual(o2, .unchanged)
    let lastSeen = try store.writer.read { db -> String in
      try String.fetchOne(
        db,
        sql: """
          SELECT last_seen_at FROM provider_calendar_events \
          WHERE provider_kind = 'eventkit' AND provider_scope = 'feed-1' \
            AND provider_event_key = 'evt-1'
          """)!
    }
    XCTAssertEqual(lastSeen, "2026-04-28T12:10:00.000Z")
  }
}
