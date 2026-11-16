import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class ProviderCalendarOriginTests: XCTestCase {
  func testQualifiedKeysPreserveDistinctCopiesAndRoundTripOpaqueIdentifiers() throws {
    let base = "server:key.with/separators:事件"
    let first = EventKitProviderIdentity.key(base: base, calendarID: "calendar:a/一")
    let second = EventKitProviderIdentity.key(base: base, calendarID: "calendar:b/二")
    XCTAssertNotEqual(first, second)
    let parts = try XCTUnwrap(EventKitProviderIdentity.components(first + ":2026-11-16"))
    XCTAssertEqual(parts.calendarID, "calendar:a/一")
    XCTAssertEqual(parts.base, base)
    XCTAssertEqual(parts.suffix, ":2026-11-16")
    XCTAssertNil(EventKitProviderIdentity.components(base))
  }

  func testOriginRoundTripsAndBusyOnlyCannotProveEquality() throws {
    let store = try TestSupport.freshStore()
    let origins = [
      ProviderCalendarOrigin(calendarID: "a", calendarTitle: "Work", accountTitle: "Account"),
      ProviderCalendarOrigin(calendarID: "b", calendarTitle: "Personal"),
    ]
    let fetched = origins.map { origin in
      EventKitFetchedEvent(
        key: EventKitProviderIdentity.key(base: "same-server-uid", calendarID: origin.calendarID),
        title: "Standup", notes: "Notes", startDate: "2026-11-16", startTime: "10:00",
        endDate: "2026-11-16", endTime: "11:00", allDay: false, location: "Room B",
        timezone: nil, origin: origin)
    }
    let now = "2026-11-16T08:00:00Z"
    let rows = EventKitIngest.providerRows(from: fetched, scope: "device", accessMode: .fullDetails)
    try store.writer.write { db in
      for row in rows { _ = try ProviderRepo.upsertProviderEvent(db, event: row, now: now) }
      try ProviderRepo.updateProviderScopeState(
        db, providerKind: ProviderKind.eventkit,
        providerScope: "device", transition: .refreshSuccess(now: now))
    }
    let full = try store.writer.read { db in
      try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-11-16", to: "2026-11-16",
        accessMode: .fullDetails, anchorTimezone: "UTC")
    }
    XCTAssertEqual(full.count, 2)
    XCTAssertEqual(Set(full.compactMap(\.providerOrigin)), Set(origins))
    let busy = try store.writer.read { db in
      try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-11-16", to: "2026-11-16",
        accessMode: .busyOnly, anchorTimezone: "UTC")
    }
    XCTAssertEqual(busy.count, 2)
    XCTAssertTrue(busy.allSatisfy { $0.providerOrigin == nil })
    XCTAssertTrue(
      EventKitIngest.providerRows(from: fetched, scope: "device", accessMode: .busyOnly)
        .allSatisfy { $0.originJSON == nil })
  }

  func testCalendarRenameIsAVisibleCacheUpdate() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let row = ProviderEventData(
        providerKind: ProviderKind.eventkit, providerScope: "device",
        providerEventKey: "id", title: "Event", startDate: "2026-11-16", allDay: true,
        originJSON: ProviderCalendarOrigin(calendarID: "a", calendarTitle: "Before").encoded)
      XCTAssertEqual(
        try ProviderRepo.upsertProviderEvent(
          db, event: row,
          now: "2026-11-16T08:00:00Z"), .inserted)
      let renamed = ProviderEventData(
        providerKind: ProviderKind.eventkit, providerScope: "device",
        providerEventKey: "id", title: "Event", startDate: "2026-11-16", allDay: true,
        originJSON: ProviderCalendarOrigin(calendarID: "a", calendarTitle: "After").encoded)
      XCTAssertEqual(
        try ProviderRepo.upsertProviderEvent(
          db, event: renamed,
          now: "2026-11-16T09:00:00Z"), .updated)
    }
  }

  func testUpgradeRebuildsOnlyTheDisposableMirrorAndRetainsTaskLinks() throws {
    let migrations = try TestSupport.loadSchemaMigrations()
    let store = try LorvexStore.openInMemory(
      schemaSQL: TestSupport.loadSchemaSQL(), migrations: Array(migrations.dropLast()))
    try store.writer.write { db in
      try insertLinkedTask(db)
      try db.execute(
        sql: """
          INSERT INTO provider_calendar_events
            (provider_kind, provider_scope, provider_event_key, title, start_date, all_day, last_seen_at)
          VALUES ('eventkit', 'device', 'legacy', 'Cached event', '2026-11-16', 1, '2026-11-16T08:00:00Z')
          """)
      try db.execute(sql: XCTUnwrap(migrations.last).sql)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT count(*) FROM tasks"), 1)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT count(*) FROM task_provider_event_links"), 1)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT count(*) FROM provider_calendar_events"), 0)
    }
  }

  func testVerifiedLegacyAliasRepairsLinkButAmbiguousOrUnverifiedAliasesDoNot() throws {
    for kind in ["unique", "ambiguous", "unverified"] {
      let store = try TestSupport.freshStore()
      try store.writer.write { db in
        try insertLinkedTask(db)
        let first = ProviderEventData(
          providerKind: ProviderKind.eventkit, providerScope: "device", providerEventKey: "new-a",
          title: "Event", startDate: "2026-11-16", allDay: true,
          previousEventKey: kind == "unverified" ? nil : "legacy")
        var rows = [first]
        if kind == "ambiguous" {
          rows.append(
            .init(
              providerKind: ProviderKind.eventkit, providerScope: "device",
              providerEventKey: "new-b", title: "Event", startDate: "2026-11-16", allDay: true,
              previousEventKey: "legacy"))
        }
        try ProviderRepo.reassociateLegacyEventKitLinks(
          db, events: rows, now: "2026-11-16T09:00:00Z")
        XCTAssertEqual(
          try String.fetchOne(db, sql: "SELECT provider_event_key FROM task_provider_event_links"),
          kind == "unique" ? "new-a" : "legacy")
        XCTAssertEqual(
          try Int.fetchOne(db, sql: "SELECT count(*) FROM task_provider_event_links"), 1)
      }
    }
  }

  private func insertLinkedTask(_ db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, priority, version, created_at, updated_at)
        VALUES ('task', 'Task', 'open', 2, '0000000000000_0000_0000000000000000',
          '2026-11-16T08:00:00Z', '2026-11-16T08:00:00Z');
        INSERT INTO task_provider_event_links
          (task_id, provider_kind, provider_scope, provider_event_key, created_at, updated_at)
        VALUES ('task', 'eventkit', 'device', 'legacy', '2026-11-16T08:00:00Z', '2026-11-16T08:00:00Z');
        """)
  }
}
