import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// Wiring coverage for the apply-independent local retention maintenance entry
/// point in both non-live and live-safe modes.
///
/// The retention caps normally ride the post-apply sweep inside `applyInbound`,
/// which may not run on a signed-out install or while live CloudKit is gated,
/// paused, paced, or failing. `runLocalRetentionMaintenance` is the independent
/// trigger the refresh fan-out calls in every mode; this suite asserts its safe
/// subset always runs and its non-live mode can additionally bound the
/// never-pushed outbox WITHOUT any inbound apply.
final class SwiftLorvexCoreServiceMaintenanceGcTests: XCTestCase {

  /// Seed an outbox row for retention bookkeeping without exposing an
  /// unchecked enqueue API from the production sync module.
  private static func seedOutboxEnvelope(_ db: Database, _ envelope: SyncEnvelope) throws {
    try db.execute(
      sql: """
        INSERT INTO sync_outbox
          (entity_type, entity_id, operation, version, payload_schema_version,
           payload, device_id, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [
        envelope.entityType.asString, envelope.entityId, envelope.operation.asString,
        envelope.version.description, envelope.payloadSchemaVersion, envelope.payload,
        envelope.deviceId, SyncTimestampFormat.syncTimestampNow(),
      ])
  }

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(
      schemaSQL: schemaSQL, migrations: try SwiftLorvexCoreService.resolveSchemaMigrations())
    return SwiftLorvexCoreService(store: store)
  }

  /// With no `applyInbound`, `runLocalRetentionMaintenance` age-caps
  /// `error_logs`, removes an audit row older than the device's retention
  /// policy while keeping a recent one, and keeps an unrelated unsynced outbox
  /// row within the backlog cap.
  func testMaintenanceEnforcesRetentionCapsWithoutApply() throws {
    let service = try makeService()
    let outboxEntityId = "01966a3f-7c8b-7d4e-8f3a-00000000ab01"
    let auditId = "01966a3f-7c8b-7d4e-8f3a-00000000ab02"
    let recentAuditId = "01966a3f-7c8b-7d4e-8f3a-00000000ab03"

    try service.write { db in
      try AuditRetention.setPolicy(db, .days(30))

      // An aged error_logs row (reaped) and a recent one (kept).
      try db.execute(
        sql: """
          INSERT INTO error_logs (id, source, level, message, created_at)
          VALUES ('old', 's', 'warn', 'm', '2020-01-01T00:00:00.000Z')
          """)
      let recent = try String.fetchOne(db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now')")!
      try db.execute(
        sql: """
          INSERT INTO error_logs (id, source, level, message, created_at)
          VALUES ('recent', 's', 'warn', 'm', ?)
          """,
        arguments: [recent])

      // One unsynced outbox row — well within the generous cap.
      try Self.seedOutboxEnvelope(
        db,
        SyncEnvelope(
          entityType: .task, entityId: outboxEntityId, operation: .upsert,
          version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
          payloadSchemaVersion: 1, payload: #"{"title":"t"}"#, deviceId: "device-A"))

      try db.execute(
        sql: """
          INSERT INTO ai_changelog
            (id, timestamp, operation, entity_type, summary, initiated_by)
          VALUES (?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-100 days'),
                  'create', 'task', 'expired audit payload', 'ai'),
                 (?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
                  'create', 'task', 'recent audit payload', 'ai')
          """,
        arguments: [auditId, recentAuditId])
    }

    try service.runLocalRetentionMaintenance(includeActiveOutboxCap: true)

    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM error_logs WHERE id = 'old'"), 0,
        "an aged error_logs row is reaped")
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM error_logs WHERE id = 'recent'"), 1)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?",
          arguments: [outboxEntityId]),
        1, "a within-cap unsynced outbox row is retained for a later sign-in")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?", arguments: [auditId]),
        0, "an audit row older than the retention policy is pruned")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?",
          arguments: [recentAuditId]),
        1, "an audit row inside the retention window is kept")
    }
  }

  /// Live configuration still needs the policy/age subset when CloudKit cannot
  /// enter an apply cycle. Passing `false` disables only the lossy active-outbox
  /// cap; it must not disable audit retention itself.
  func testLiveSafeMaintenanceRunsWithoutActiveOutboxCap() throws {
    let service = try makeService()
    let auditId = "01966a3f-7c8b-7d4e-8f3a-00000000ac01"
    try service.write { db in
      try AuditRetention.setPolicy(db, .days(30))
      try db.execute(
        sql: """
          INSERT INTO ai_changelog
            (id, timestamp, operation, entity_type, summary, initiated_by)
          VALUES (?, '2020-01-01T00:00:00.000Z', 'create', 'task', 'private', 'ai')
          """,
        arguments: [auditId])
    }

    try service.runLocalRetentionMaintenance(includeActiveOutboxCap: false)

    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?", arguments: [auditId]),
        0)
    }
  }
}
