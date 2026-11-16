import Foundation
import GRDB
import XCTest

@testable import LorvexStore

final class ProviderOccurrenceMigrationTests: XCTestCase {
  func testVersionFourUpgradePreservesLinksThroughCacheRebuild() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-provider-instants-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let schema = try TestSupport.loadSchemaSQL()
    let ladder = try TestSupport.loadSchemaMigrations()
    let path = directory.appendingPathComponent("db.sqlite")
    let old = try LorvexStore.open(
      at: path, schemaSQL: schema,
      schemaChecksum: MigrationSqlChecksum.hexDigest(schema),
      migrations: ladder.filter { $0.version <= 4 })
    try old.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, priority, version, created_at, updated_at)
          VALUES ('migration-task', 'Linked task', 'open', 2, '1800000000000_0000_1111222233334444',
            '2026-10-01T00:00:00Z', '2026-10-01T00:00:00Z');
          INSERT INTO provider_calendar_events
            (provider_kind, provider_scope, provider_event_key, title, start_date, start_time,
             end_time, source_time_kind, source_tzid, last_seen_at)
          VALUES ('eventkit', 'device', 'legacy', 'Legacy event', '2026-11-01', '09:00',
            '10:00', 'tzid', 'America/New_York', '2026-10-01T00:00:00Z');
          INSERT INTO task_provider_event_links
            (task_id, provider_kind, provider_scope, provider_event_key, created_at, updated_at)
          VALUES ('migration-task', 'eventkit', 'device', 'legacy',
            '2026-10-01T00:00:00Z', '2026-10-01T00:00:00Z');
          """)
      try ProviderRepo.updateProviderScopeState(
        db, providerKind: "eventkit", providerScope: "device",
        transition: .refreshSuccess(now: "2026-10-01T00:00:00Z"))
    }
    try old.writer.close()
    let upgraded = try LorvexStore.open(
      at: path, schemaSQL: schema,
      schemaChecksum: MigrationSqlChecksum.hexDigest(schema), migrations: ladder.filter { $0.version <= 5 })
    XCTAssertNil(upgraded.recovery)
    try upgraded.writer.read { db in
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations"), 5)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task_provider_event_links"), 1)
      XCTAssertNil(
        try String.fetchOne(db, sql: "SELECT occurrence_instants FROM provider_calendar_events"))
      XCTAssertEqual(try String.fetchOne(db, sql: "SELECT start_time FROM provider_calendar_events"), "09:00")
      XCTAssertEqual(try String.fetchOne(db, sql: "SELECT source_tzid FROM provider_calendar_events"), "America/New_York")
      XCTAssertEqual(try String.fetchOne(db, sql: "SELECT provider_event_key FROM provider_calendar_events"), "legacy")
    }
    try upgraded.writer.close()
    let reopened = try LorvexStore.open(
      at: path, schemaSQL: schema,
      schemaChecksum: MigrationSqlChecksum.hexDigest(schema), migrations: ladder)
    XCTAssertNil(reopened.recovery)
    try reopened.writer.read { db in
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations"), ladder.last?.version)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks"), 1)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task_provider_event_links"), 1)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM provider_calendar_events"), 0)
      XCTAssertTrue(try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-11-01", to: "2026-11-01",
        accessMode: .fullDetails, anchorTimezone: "UTC").isEmpty)
    }
    try reopened.writer.close()
  }
}
