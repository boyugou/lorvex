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
      let generationIndexes = try Row.fetchAll(
        db, sql: "PRAGMA index_list('sync_generation_snapshot_items')")
      XCTAssertFalse(
        generationIndexes.contains {
          $0["name"] as String == "idx_generation_snapshot_items_record_name"
        },
        "the UNIQUE(lease_identifier, record_name) autoindex already serves this lookup")
      XCTAssertTrue(
        generationIndexes.contains {
          $0["origin"] as String == "u" && ($0["unique"] as Int64) == 1
        })

      let progressColumns = try Row.fetchAll(
        db, sql: "PRAGMA table_info('sync_cloudkit_traversal_progress')")
      let primaryKeyColumns = progressColumns
        .filter { ($0["pk"] as Int64) > 0 }
        .sorted { ($0["pk"] as Int64) < ($1["pk"] as Int64) }
        .map { $0["name"] as String }
      XCTAssertEqual(primaryKeyColumns, ["account_identifier"])
      let progressIndexes = try Row.fetchAll(
        db, sql: "PRAGMA index_list('sync_cloudkit_traversal_progress')")
      XCTAssertFalse(
        progressIndexes.contains {
          $0["name"] as String == "idx_sync_cloudkit_traversal_progress_account"
        })

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

  func testAuditRetentionIndexesServeExactZonePagingAndEntityPresence() throws {
    try withDB { db in
      let pendingColumns = try Row.fetchAll(
        db, sql: "PRAGMA index_info('idx_audit_retention_purge_pending')")
        .sorted { ($0["seqno"] as Int64) < ($1["seqno"] as Int64) }
        .map { $0["name"] as String }
      XCTAssertEqual(
        pendingColumns,
        ["account_identifier", "zone_name", "next_attempt_at", "created_at", "entity_id"])

      let pendingPlan = try Row.fetchAll(
        db,
        sql: """
          EXPLAIN QUERY PLAN
          SELECT entity_id FROM audit_retention_purge_queue
          WHERE account_identifier = ? AND zone_name = ?
            AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
          ORDER BY created_at ASC, entity_id ASC
          LIMIT ?
          """,
        arguments: [
          "account", "zone", "2026-07-15T00:00:00.000Z", 200,
        ])
      let pendingDetail = pendingPlan.map { $0["detail"] as String }.joined(separator: "\n")
      XCTAssertTrue(
        pendingDetail.contains("idx_audit_retention_purge_pending"),
        "exact-zone purge paging must use its composite index; plan:\n\(pendingDetail)")

      let presenceColumns = try Row.fetchAll(
        db, sql: "PRAGMA index_info('idx_audit_changelog_presence_entity')")
        .sorted { ($0["seqno"] as Int64) < ($1["seqno"] as Int64) }
        .map { $0["name"] as String }
      XCTAssertEqual(presenceColumns, ["entity_id", "account_identifier", "zone_name"])

      let presencePlan = try Row.fetchAll(
        db,
        sql: """
          EXPLAIN QUERY PLAN
          SELECT account_identifier, zone_name, retention_epoch
          FROM audit_changelog_cloud_presence WHERE entity_id = ?
          """,
        arguments: ["audit-id"])
      let presenceDetail = presencePlan.map { $0["detail"] as String }.joined(separator: "\n")
      XCTAssertTrue(
        presenceDetail.contains("idx_audit_changelog_presence_entity"),
        "entity-presence lookup must use its covering index; plan:\n\(presenceDetail)")
    }
  }

  func testSnapshotManifestsAreBoundToThePhysicalAccountDatabase() throws {
    try withDB { db in
      for table in ["sync_generation_snapshot_staging", "sync_authoritative_snapshot"] {
        let rows = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list('\(table)')")
          .filter { $0["table"] as String == "sync_cloudkit_account_binding" }
          .sorted { ($0["seq"] as Int64) < ($1["seq"] as Int64) }
        XCTAssertEqual(rows.map { $0["from"] as String }, [
          "account_identifier", "database_instance_id",
        ])
        XCTAssertEqual(rows.map { $0["to"] as String }, [
          "account_identifier", "database_instance_id",
        ])
      }
    }
  }

  func testRetryAndAuditReadinessInvalidShapesAreRejectedBySQLite() throws {
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

      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO audit_retention_account_state (
              account_identifier, frontier_epoch, policy_authorized_epoch,
              policy_ready, created_at, updated_at
            ) VALUES ('invalid-ready-account', 1, 0, 1,
                      '2026-07-14T00:00:00.000Z', '2026-07-14T00:00:00.000Z')
            """))

      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO audit_changelog_cloud_presence (
              account_identifier, zone_name, entity_id, retention_epoch, marked_at
            ) VALUES ('orphan-account', 'zone', 'audit-1', 0,
                      '2026-07-14T00:00:00.000Z')
            """),
        "cloud-presence evidence cannot exist without durable account state")
    }
  }

  func testEveryOrderingHlcColumnHasCanonicalSchemaGuard() throws {
    try withDB { db in
      let expected: Set<String> = [
        "audit_retention_account_state.policy_version",
        "audit_retention_binding.unbound_policy_version",
        "audit_retention_candidate_authorization.policy_version",
        "calendar_series_cutovers.version",
        "calendar_events.content_version",
        "calendar_events.recurrence_generation",
        "calendar_events.recurrence_topology_version",
        "calendar_events.version",
        "current_focus.version",
        "daily_reviews.version",
        "focus_schedule.version",
        "habit_completions.version",
        "habit_reminder_policies.version",
        "habits.version",
        "lists.version",
        "memories.version",
        "preferences.version",
        "sync_entity_redirects.version",
        "sync_generation_snapshot_compacted_tombstones.version",
        "sync_generation_snapshot_staging.retention_policy_version",
        "sync_generation_snapshot_tombstone_receipts.version",
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

  func testAuthoritativeEnvelopeHasTheSamePerRecordDiskBoundAsGenerationStaging() throws {
    try withDB { db in
      let databaseID = "schema-integrity-database"
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId, value: databaseID)
      _ = try CloudTraversalWitness.claimAccount(
        db, accountIdentifier: "schema-integrity-account")
      let session = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: "schema-integrity-account",
          zoneIdentifier: "schema-integrity-zone"),
        databaseInstanceId: databaseID)

      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO sync_authoritative_snapshot_records
                (session_id, record_name, state, envelope)
            VALUES (?, 'oversized-record', 'decoded', ?)
            """,
          arguments: [
            session.sessionToken,
            String(repeating: "x", count: GenerationSnapshot.maximumEncodedEnvelopeBytes + 1),
          ]))
    }
  }
}
