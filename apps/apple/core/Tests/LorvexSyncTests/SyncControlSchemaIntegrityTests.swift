import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class SyncControlSchemaIntegrityTests: XCTestCase {
  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  func testControlTablesUseOneIndexPerInvariant() throws {
    try withDB { db in
      let habitCompletionIndexes = try Row.fetchAll(
        db, sql: "PRAGMA index_list('habit_completions')")
      XCTAssertFalse(
        habitCompletionIndexes.contains {
          $0["name"] as String == "idx_habit_completions_date"
        },
        "the (habit_id, completed_date) primary key already serves this ordering")

      let providerEventIndexes = try Row.fetchAll(
        db, sql: "PRAGMA index_list('provider_calendar_events')")
      XCTAssertFalse(
        providerEventIndexes.contains {
          $0["name"] as String == "idx_provider_events_scope"
        },
        "the provider composite primary key already serves scope-prefix lookups")
    }
  }

  func testOutboxPayloadSchemaVersionMatchesTheUInt32WireDomain() throws {
    try withDB { db in
      let version = "1800000000000_0000_1111222233334444"
      func insert(_ value: Int64, id: String) throws {
        try db.execute(
          sql: """
            INSERT INTO sync_outbox
                (entity_type, entity_id, operation, version,
                 payload_schema_version, payload, device_id)
            VALUES ('list', ?, 'upsert', ?, ?, '{}', 'schema-integrity')
            """,
          arguments: [id, version, value])
      }

      XCTAssertNoThrow(try insert(1, id: "schema-version-min"))
      XCTAssertNoThrow(try insert(4_294_967_295, id: "schema-version-max"))
      for (value, id) in [
        (-1, "schema-version-negative"),
        (0, "schema-version-zero"),
        (4_294_967_296, "schema-version-overflow"),
      ] as [(Int64, String)] {
        XCTAssertThrowsError(try insert(value, id: id))
      }
    }
  }

  /// CKSyncEngine owns account identity, change tokens, zone traversal, and
  /// record-fetch retries, so the tables the custom transport kept for those
  /// purposes, and the audit-retention bookkeeping tied to it, do not exist in
  /// the migrated schema.
  func testRetiredTransportTablesAreAbsentFromTheMigratedSchema() throws {
    try withDB { db in
      let tables = Set(
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
      let retired = [
        "sync_cloudkit_account_binding", "sync_cloudkit_authority_witness",
        "sync_cloudkit_generation_descriptor", "sync_cloudkit_traversal_progress",
        "sync_cloudkit_traversal_witness", "sync_cloudkit_incremental_cursor",
        "sync_cloudkit_corrupt_record_fences", "sync_generation_snapshot_staging",
        "sync_generation_snapshot_items", "sync_generation_snapshot_readback_items",
        "sync_generation_snapshot_tombstone_receipts",
        "sync_generation_snapshot_compacted_tombstones", "sync_authoritative_snapshot",
        "sync_authoritative_snapshot_records", "audit_retention_binding",
        "audit_retention_account_state", "audit_retention_candidate_authorization",
        "audit_retention_outbound_authorization", "audit_retention_purge_queue",
        "audit_changelog_cloud_presence",
      ]
      for table in retired {
        XCTAssertFalse(tables.contains(table), "\(table) must not exist after the ladder")
      }
      for table in ["sync_outbox", "sync_tombstones", "ai_changelog", "ai_changelog_entities"] {
        XCTAssertTrue(tables.contains(table), "\(table) must survive the ladder")
      }
    }
  }

  func testRetiredColumnsAreAbsentFromTheMigratedSchema() throws {
    try withDB { db in
      func columns(_ table: String) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('\(table)')"))
      }
      let outbox = try columns("sync_outbox")
      XCTAssertFalse(outbox.contains("authoritative_session_token"))
      XCTAssertFalse(outbox.contains("future_record_resolution"))
      XCTAssertTrue(outbox.contains("future_record_version"))
      let audit = try columns("ai_changelog")
      XCTAssertFalse(audit.contains("retention_epoch"))
      XCTAssertFalse(audit.contains("retention_account_identifier"))
      XCTAssertFalse(try columns("sync_tombstones").contains("cloud_confirmed_at"))
    }
  }

  /// The outbox keeps two dispositions; the retired authoritative-adoption
  /// fence is no longer a storable value.
  func testOutboxDispositionAcceptsOnlyRetryWaitAndFutureRecordHold() throws {
    try withDB { db in
      let version = "1800000000000_0000_1111222233334444"
      func insert(disposition: String, id: String) throws {
        try db.execute(
          sql: """
            INSERT INTO sync_outbox
                (entity_type, entity_id, operation, version,
                 payload_schema_version, payload, device_id, disposition,
                 next_retry_at, future_record_version)
            VALUES ('list', ?, 'upsert', ?, 1, '{}', 'schema-integrity', ?, ?, ?)
            """,
          arguments: [
            id, version, disposition,
            disposition == "retry_wait" ? "2026-07-15T00:00:00.000Z" : nil,
            disposition == "future_record_hold" ? version : nil,
          ])
      }
      XCTAssertNoThrow(try insert(disposition: "retry_wait", id: "disposition-retry"))
      XCTAssertNoThrow(try insert(disposition: "future_record_hold", id: "disposition-hold"))
      XCTAssertThrowsError(try insert(disposition: "authoritative_adoption", id: "disposition-old"))
    }
  }

  func testInvalidPendingInboxShapeIsRejectedBySQLite() throws {
    try withDB { db in
      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO sync_pending_inbox (
              envelope, reason, envelope_entity_type, envelope_entity_id,
              envelope_version, first_attempted_at, last_attempted_at, attempt_count
            ) VALUES ('{}', 'test', 'task', 'task-1', 'version',
                      '2026-07-14T00:00:00.000Z', '2026-07-14T00:00:00.000Z', 0)
            """))
    }
  }

  func testEveryOrderingHlcColumnHasCanonicalSchemaGuard() throws {
    try withDB { db in
      let expected: Set<String> = [
        "calendar_series_cutovers.version",
        "calendar_events.content_version",
        "calendar_events.recurrence_generation",
        "calendar_events.recurrence_topology_version",
        "calendar_events.version",
        "daily_briefings.version",
        "daily_reviews.version",
        "habit_completions.version",
        "habit_reminder_policies.version",
        "habits.version",
        "lists.version",
        "memories.version",
        "preferences.version",
        "sync_entity_redirects.version",
        "sync_outbox.future_record_version",
        "sync_outbox.version",
        "sync_payload_shadow.base_version",
        "sync_pending_inbox.envelope_version",
        "sync_quarantine_blocklist.version",
        "sync_tombstones.version",
        "tags.version",
        "task_calendar_event_links.version",
        "task_checklist_items.version",
        "task_dependencies.version",
        "task_reminders.version",
        "task_tags.version",
        "tasks.archive_version",
        "tasks.content_version",
        "tasks.lifecycle_version",
        "tasks.schedule_version",
        "tasks.spawned_from_version",
        "tasks.version",
      ]
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT m.name AS table_name, p.name AS column_name, m.sql AS table_sql
          FROM sqlite_master AS m
          JOIN pragma_table_info(m.name) AS p
          WHERE m.type = 'table' AND p.type = 'TEXT'
            AND (
              p.name = 'version' OR p.name LIKE '%_version'
              OR (m.name = 'calendar_events' AND p.name = 'recurrence_generation')
            )
          ORDER BY m.name, p.cid
          """)
      let exemptDiagnostics: Set<String> = [
        "sync_conflict_log.winner_version",
        "sync_conflict_log.loser_version",
      ]
      let rawFutureProvenance: Set<String> = [
        "sync_outbox.future_record_version",
        "sync_pending_inbox.envelope_version",
      ]
      let observed = Set(rows.map { row in
        "\(row["table_name"] as String).\(row["column_name"] as String)"
      })
      XCTAssertEqual(observed, expected.union(exemptDiagnostics))

      for row in rows {
        let table: String = row["table_name"]
        let column: String = row["column_name"]
        let key = "\(table).\(column)"
        guard !exemptDiagnostics.contains(key) else { continue }
        let tableSQL: String = row["table_sql"]
        XCTAssertTrue(
          tableSQL.contains(
            "substr(\(column), 20, 16) NOT GLOB '*[^0-9a-f]*'"),
          "\(key) must reject noncanonical HLC spellings at the SQLite boundary")
        if rawFutureProvenance.contains(key) {
          XCTAssertFalse(
            tableSQL.contains(
              "substr(\(column), 1, 13) <= '\(Hlc.maxOperationalWirePhysicalMs)'"),
            "\(key) must retain canonical future HLCs above today's operational ceiling")
        } else {
          XCTAssertTrue(
            tableSQL.contains(
              "substr(\(column), 1, 13) <= '\(Hlc.maxOperationalWirePhysicalMs)'"),
            "\(key) must enforce the same operational HLC ceiling as Swift")
        }
      }

      XCTAssertThrowsError(
        try db.execute(sql: "UPDATE lists SET version = 'v1' WHERE id = 'inbox'"))
      XCTAssertThrowsError(
        try db.execute(
          sql: "UPDATE preferences SET version = ? WHERE key = 'default_list_id'",
          arguments: ["1711234567890_0000_A1B2C3D4A1B2C3D4"]))

      let aboveOperational = try Hlc(
        physicalMs: Hlc.maxOperationalWirePhysicalMs + 1, counter: 0,
        deviceSuffix: "ffffffffffffffff").description
      XCTAssertThrowsError(
        try db.execute(
          sql: "UPDATE lists SET version = ? WHERE id = 'inbox'",
          arguments: [aboveOperational]))
      XCTAssertNoThrow(
        try db.execute(
          sql: """
            INSERT INTO sync_pending_inbox (
              envelope, reason, envelope_entity_type, envelope_entity_id,
              envelope_version, first_attempted_at, last_attempted_at, attempt_count
            ) VALUES ('{}', ?, 'future_entity', 'future-id', ?,
                      '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z', 1)
            """,
          arguments: [PendingInboxDrain.entityTypeTooNewReason, aboveOperational]),
        "opaque future provenance must remain durably parkable")
    }
  }

  func testEntityRedirectLedgerRejectsUnsupportedAndNonDescendingAliases() throws {
    try withDB { db in
      let source = "ffffffff-ffff-7fff-8fff-ffffffffffff"
      let target = "00000000-0000-7000-8000-000000000001"
      let version = "1800000000000_0000_1111222233334444"
      let timestamp = "2026-07-15T00:00:00.000Z"

      try db.execute(
        sql: """
          INSERT INTO sync_entity_redirects
              (source_type, source_id, target_id, version, created_at)
          VALUES ('tag', ?, ?, ?, ?)
          """,
        arguments: [source, target, version, timestamp])

      for unsupportedType in ["list", "task", "calendar_event"] {
        XCTAssertThrowsError(
          try db.execute(
            sql: """
              INSERT INTO sync_entity_redirects
                  (source_type, source_id, target_id, version, created_at)
              VALUES (?, ?, ?, ?, ?)
              """,
            arguments: [unsupportedType, source, target, version, timestamp]))
      }
      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO sync_entity_redirects
                (source_type, source_id, target_id, version, created_at)
            VALUES ('tag', ?, ?, ?, ?)
            """,
          arguments: [target, source, version, timestamp]))
      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO sync_entity_redirects
                (source_type, source_id, target_id, version, created_at)
            VALUES ('habit', ?, ?, ?, ?)
            """,
          arguments: [source, source, version, timestamp]))
    }
  }

  func testOrdinaryDeathLedgerRejectsUpsertOnlyWireKinds() throws {
    try withDB { db in
      for entityType in [EntityName.aiChangelog, EntityName.entityRedirect] {
        XCTAssertThrowsError(
          try Tombstone.createTombstone(
            db, entityType: entityType,
            entityId: "00000000-0000-7000-8000-000000000001",
            version: "1800000000000_0000_1111222233334444",
            deletedAt: "2026-07-15T00:00:00.000Z"),
          "\(entityType) must never enter the ordinary death ledger")
      }
    }
  }
}
