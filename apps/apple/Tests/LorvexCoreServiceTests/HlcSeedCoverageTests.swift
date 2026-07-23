import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import XCTest

@testable import LorvexCore

/// The process HLC clock is seeded past the highest HLC this device has
/// persisted locally, so a restart with a backward wall clock cannot mint a
/// non-monotonic HLC. These tests pin two properties of that seed scan:
///   - it covers every HLC-bearing table, not just `tasks`, so a device whose
///     high-water mark lives in a calendar event / habit / tag is not regressed;
///   - it only counts rows this device authored, so the clock is not inflated
///     past remote-origin HLCs (which would skew future LWW outcomes).
final class HlcSeedCoverageTests: XCTestCase {

  private static func seedIgnoringCheckConstraints<T>(
    _ db: Database, _ body: () throws -> T
  ) throws -> T {
    try db.execute(sql: "PRAGMA ignore_check_constraints = ON")
    do {
      let result = try body()
      try db.execute(sql: "PRAGMA ignore_check_constraints = OFF")
      return result
    } catch {
      try? db.execute(sql: "PRAGMA ignore_check_constraints = OFF")
      throw error
    }
  }

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexCoreServiceTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(store: try LorvexStore.openInMemory(schemaSQL: schemaSQL))
  }

  func testSeedCoversNonTaskTablesAndIgnoresRemoteRows() throws {
    let service = try makeService()
    let appSuffix = DeviceIdentity.deviceIdToHlcSuffix(
      "11111111-1111-7111-8111-111111111111", surface: .app)
    let remoteSuffix = DeviceIdentity.deviceIdToHlcSuffix(
      "22222222-2222-7222-8222-222222222222", surface: .app)
    XCTAssertNotEqual(appSuffix, remoteSuffix)

    // The local high-water mark lives in a tag (a non-task table). The remote
    // row carries a numerically higher HLC but a foreign suffix.
    let localVersion = "1700000000000_0000_\(appSuffix)"
    let remoteVersion = "1900000000000_0000_\(remoteSuffix)"

    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES ('tag-local', 'Local', 'local', ?, '2026-01-01T00:00:00.000Z',
                  '2026-01-01T00:00:00.000Z')
          """,
        arguments: [localVersion])
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES ('tag-remote', 'Remote', 'remote', ?, '2026-01-01T00:00:00.000Z',
                  '2026-01-01T00:00:00.000Z')
          """,
        arguments: [remoteVersion])
    }

    let observed = try service.read { db in
      try SwiftLorvexCoreService.HlcClock.maxLocalHlc(db, suffixes: [appSuffix])
    }
    XCTAssertEqual(observed, try Hlc.parse(localVersion))
  }

  func testSeedFindsRetainedLocalCalendarGenerationUnderRemoteRegisterClocks() throws {
    let service = try makeService()
    let localSuffix = DeviceIdentity.deviceIdToHlcSuffix(
      "12121212-1212-7212-8212-121212121212", surface: .app)
    let remoteSuffix = DeviceIdentity.deviceIdToHlcSuffix(
      "34343434-3434-7434-8434-343434343434", surface: .app)
    let localGeneration = "1700000000000_0000_\(localSuffix)"
    let remoteVersion = "1900000000000_0000_\(remoteSuffix)"

    // A grouped merge may retain device A's recurrence generation while the
    // row/content/topology clocks are all authored later by device B. The
    // suffix-filtered restart fallback must still recover A's local floor.
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO calendar_events (
            id, title, start_date, all_day, recurrence, event_type,
            recurrence_generation, recurrence_topology_version, content_version,
            version, created_at, updated_at
          ) VALUES (
            '01966a3f-7c8b-7d4e-8f3a-0000000000d1', 'Retained generation',
            '2026-07-17', 1, '{"FREQ":"DAILY"}', 'event', ?, ?, ?, ?,
            '2026-07-17T00:00:00.000Z', '2026-07-17T00:00:00.000Z'
          )
          """,
        arguments: [localGeneration, remoteVersion, remoteVersion, remoteVersion])
    }

    let observed = try service.read { db in
      try SwiftLorvexCoreService.HlcClock.maxLocalHlc(db, suffixes: [localSuffix])
    }
    XCTAssertEqual(observed, try Hlc.parse(localGeneration))
  }

  func testSeedBoundsForwardDriftFromAbsurdFuturePhysicalTime() throws {
    // A stored version with this device's suffix but an absurd (year-2286) physical
    // time — a peer forging the local suffix, or the device's own past far-forward
    // skew — must not pin the seeded clock to that future. The seed applies the same
    // bounded-drift ceiling as the normal receive path, so the next minted HLC stays
    // near wall-clock + drift, not at the ceiling.
    let deviceId = "44444444-4444-7444-8444-444444444444"
    let appSuffix = DeviceIdentity.deviceIdToHlcSuffix(deviceId, surface: .app)
    let absurdFuture = "\(Hlc.maxPhysicalMs)_0000_\(appSuffix)"

    let service = try makeService()
    try service.write { db in
      try Self.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
            VALUES ('tag-absurd', 'Absurd', 'absurd', ?, '2026-01-01T00:00:00.000Z',
                    '2026-01-01T00:00:00.000Z')
            """,
          arguments: [absurdFuture])
      }
    }

    let clock = try SwiftLorvexCoreService.HlcClock(deviceId: deviceId, surface: .app)
    try service.read { db in clock.seedIfNeeded(db) }

    let minted = clock.generate()
    let nowMsUpperBound = UInt64(Date().timeIntervalSince1970 * 1000)
    let ceiling = nowMsUpperBound &+ HlcState.maxInboundForwardDriftMs
    XCTAssertLessThanOrEqual(
      minted.physicalMs, ceiling,
      "seed must not advance the clock beyond wall-clock + bounded drift")
    XCTAssertLessThan(
      minted.physicalMs, Hlc.maxPhysicalMs,
      "an absurd-future stored version must not pin the seeded clock to the ceiling")
  }

  func testTrustedNormalHighWaterIsRestoredWithoutForwardClamp() throws {
    let service = try makeService()
    let deviceId = "55555555-5555-7555-8555-555555555555"
    let clock = try SwiftLorvexCoreService.HlcClock(deviceId: deviceId, surface: .app)
    let trusted = try Hlc(
      physicalMs: UInt64(Date().timeIntervalSince1970 * 1000) + 14 * 24 * 60 * 60 * 1000,
      counter: 7, deviceSuffix: clock.deviceSuffix)
    try service.write { db in
      try SyncCheckpoints.set(
        db, key: clock.normalHighWaterKey, value: trusted.description)
    }

    let minted = try service.write { db -> Hlc in
      let transaction = try clock.makeTransactionHandle(db)
      let value = transaction.generate()
      try transaction.persistHighWaters(db)
      return value
    }
    XCTAssertGreaterThan(
      minted, trusted,
      "a trusted local-only normal high-water must preserve own-author monotonicity")
  }

  func testDetachedFutureNeverSeedsTheNormalLane() throws {
    let service = try makeService()
    let deviceId = "66666666-6666-7666-8666-666666666666"
    let clock = try SwiftLorvexCoreService.HlcClock(deviceId: deviceId, surface: .app)
    let detachedFuture = try Hlc(
      physicalMs: UInt64(Date().timeIntervalSince1970 * 1000) + 30 * 24 * 60 * 60 * 1000,
      counter: 0, deviceSuffix: "bbbbbbbbbbbbbbbb")

    let exceptional = try service.write { db -> Hlc in
      let transaction = try clock.makeTransactionHandle(db)
      transaction.enterDetached(dominating: detachedFuture)
      let value = transaction.generate()
      try transaction.persistHighWaters(db)
      return value
    }
    XCTAssertGreaterThan(exceptional, detachedFuture)

    let minted = try service.write { db -> Hlc in
      let transaction = try clock.makeTransactionHandle(db)
      let value = transaction.generate()
      try transaction.persistHighWaters(db)
      return value
    }
    let now = UInt64(Date().timeIntervalSince1970 * 1000)
    XCTAssertLessThan(minted, detachedFuture)
    XCTAssertLessThanOrEqual(
      minted.physicalMs, now + HlcState.maxInboundForwardDriftMs,
      "the durable detached future lane must never leak into ordinary writes")
  }

  func testDetachedTransactionsWithDifferentFloorsStayUniqueAndOrdered() throws {
    let service = try makeService()
    let clock = try SwiftLorvexCoreService.HlcClock(
      deviceId: "67676767-6767-7676-8676-676767676767", surface: .app)
    let firstFloor = try Hlc(
      physicalMs: UInt64(Date().timeIntervalSince1970 * 1000) + 30 * 24 * 60 * 60 * 1000,
      counter: 10, deviceSuffix: "ffffffffffffffff")
    let secondFloor = try Hlc(
      physicalMs: firstFloor.physicalMs,
      counter: 9, deviceSuffix: "eeeeeeeeeeeeeeee")

    func mintDetached(dominating floor: Hlc) throws -> Hlc {
      try service.write { db in
        let transaction = try clock.makeTransactionHandle(db)
        transaction.enterDetached(dominating: floor)
        let value = transaction.generate()
        try transaction.persistHighWaters(db)
        return value
      }
    }

    let first = try mintDetached(dominating: firstFloor)
    let second = try mintDetached(dominating: secondFloor)
    XCTAssertGreaterThan(first, firstFloor)
    XCTAssertGreaterThan(second, secondFloor)
    XCTAssertGreaterThan(second, first)
    XCTAssertNotEqual(first, second)
  }

  func testRotatedDeviceSuffixDoesNotTrustPriorInstallHighWater() throws {
    let service = try makeService()
    let oldClock = try SwiftLorvexCoreService.HlcClock(
      deviceId: "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa", surface: .app)
    let newClock = try SwiftLorvexCoreService.HlcClock(
      deviceId: "bbbbbbbb-bbbb-7bbb-8bbb-bbbbbbbbbbbb", surface: .app)
    let oldFuture = try Hlc(
      physicalMs: UInt64(Date().timeIntervalSince1970 * 1000) + 14 * 24 * 60 * 60 * 1000,
      counter: 7, deviceSuffix: oldClock.deviceSuffix)
    try service.write { db in
      try SyncCheckpoints.set(
        db, key: oldClock.normalHighWaterKey, value: oldFuture.description)
    }

    let minted = try service.write { db -> Hlc in
      let transaction = try newClock.makeTransactionHandle(db)
      let value = transaction.generate()
      try transaction.persistHighWaters(db)
      return value
    }
    let now = UInt64(Date().timeIntervalSince1970 * 1000)
    XCTAssertLessThan(minted, oldFuture)
    XCTAssertLessThanOrEqual(minted.physicalMs, now + HlcState.maxInboundForwardDriftMs)
    XCTAssertNotEqual(oldClock.normalHighWaterKey, newClock.normalHighWaterKey)
  }

  func testMalformedTrustedHighWaterFailsClosed() throws {
    let service = try makeService()
    let clock = try SwiftLorvexCoreService.HlcClock(
      deviceId: "77777777-7777-7777-8777-777777777777", surface: .app)
    try service.write { db in
      try SyncCheckpoints.set(db, key: clock.normalHighWaterKey, value: "not-an-hlc")
    }

    XCTAssertThrowsError(
      try service.write { db in
        _ = try clock.makeTransactionHandle(db)
      }
    ) { error in
      XCTAssertEqual(
        error as? SwiftLorvexCoreService.HlcHighWaterError,
        .invalidCheckpoint(key: clock.normalHighWaterKey, value: "not-an-hlc"))
    }
  }

  func testMalformedDetachedHighWaterFailsClosed() throws {
    let service = try makeService()
    let clock = try SwiftLorvexCoreService.HlcClock(
      deviceId: "78787878-7878-7878-8878-787878787878", surface: .app)
    try service.write { db in
      try SyncCheckpoints.set(db, key: clock.detachedHighWaterKey, value: "not-an-hlc")
    }

    XCTAssertThrowsError(
      try service.write { db in
        _ = try clock.makeTransactionHandle(db)
      }
    ) { error in
      XCTAssertEqual(
        error as? SwiftLorvexCoreService.HlcHighWaterError,
        .invalidCheckpoint(key: clock.detachedHighWaterKey, value: "not-an-hlc"))
    }
  }

  func testOperationalWireCeilingCannotCrashAndRollsBackTransaction() throws {
    let service = try makeService()
    let clock = try SwiftLorvexCoreService.HlcClock(
      deviceId: "79797979-7979-7979-8979-797979797979", surface: .app)
    let ceiling = try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs, counter: Hlc.maxCounter,
      deviceSuffix: "ffffffffffffffff")

    XCTAssertThrowsError(
      try service.write { db in
        let transaction = try clock.makeTransactionHandle(db)
        transaction.enterDetached(dominating: ceiling)
        _ = transaction.generate()
        try db.execute(
          sql: "UPDATE lists SET name = 'must roll back' WHERE id = 'inbox'")
        try transaction.persistHighWaters(db)
      }
    ) { error in
      guard case .unrecoverableFloor(let value) =
        error as? SwiftLorvexCoreService.HlcHighWaterError,
        let unusable = try? Hlc.parseCanonical(value)
      else {
        return XCTFail("expected an unrecoverable operational-wire floor, got \(error)")
      }
      XCTAssertGreaterThan(unusable, ceiling)
      XCTAssertFalse(Hlc.isOperationallyAcceptableWire(unusable))
    }
    try service.read { db in
      XCTAssertNotEqual(
        try String.fetchOne(db, sql: "SELECT name FROM lists WHERE id = 'inbox'"),
        "must roll back")
      XCTAssertNil(try SyncCheckpoints.get(db, key: clock.detachedHighWaterKey))
    }
  }

  func testDetachedLaneUsesTheSingleRemainingOperationalSuccessor() throws {
    let service = try makeService()
    let clock = try SwiftLorvexCoreService.HlcClock(
      deviceId: "79797979-7979-7979-8979-797979797970", surface: .app)
    let penultimate = try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs,
      counter: Hlc.maxCounter - 1,
      deviceSuffix: "ffffffffffffffff")

    let minted = try service.write { db in
      let transaction = try clock.makeTransactionHandle(db)
      transaction.enterDetached(dominating: penultimate)
      let value = transaction.generate()
      try transaction.persistHighWaters(db)
      return value
    }

    XCTAssertGreaterThan(minted, penultimate)
    XCTAssertEqual(minted.physicalMs, Hlc.maxOperationalWirePhysicalMs)
    XCTAssertEqual(minted.counter, Hlc.maxCounter)
    XCTAssertTrue(Hlc.isOperationallyAcceptableWire(minted))
  }

  func testTaintedCeilingDetachedCheckpointFailsTypedWithoutMutation() throws {
    let service = try makeService()
    let clock = try SwiftLorvexCoreService.HlcClock(
      deviceId: "80808080-8080-7080-8080-808080808080", surface: .app)
    let checkpoint = try Hlc(
      physicalMs: Hlc.maxPhysicalMs, counter: Hlc.maxCounter,
      deviceSuffix: clock.deviceSuffix)
    try service.write { db in
      try SyncCheckpoints.set(
        db, key: clock.detachedHighWaterKey, value: checkpoint.description)
    }

    XCTAssertThrowsError(
      try service.write { db in
        let transaction = try clock.makeTransactionHandle(db)
        transaction.enterDetached(
          dominating: try Hlc.parseCanonical(
            "1711234567890_0000_aaaaaaaaaaaaaaaa"))
        _ = transaction.generate()
        try db.execute(
          sql: "UPDATE lists SET name = 'must roll back' WHERE id = 'inbox'")
        try transaction.persistHighWaters(db)
      }
    ) { error in
      XCTAssertEqual(
        error as? SwiftLorvexCoreService.HlcHighWaterError,
        .unrecoverableFloor(value: checkpoint.description))
    }
    try service.read { db in
      XCTAssertNotEqual(
        try String.fetchOne(db, sql: "SELECT name FROM lists WHERE id = 'inbox'"),
        "must roll back")
      XCTAssertEqual(
        try SyncCheckpoints.get(db, key: clock.detachedHighWaterKey), checkpoint.description)
    }
  }

  func testGlobalRetryCeilingIncludesPayloadShadowButExcludesOutboxHistory() throws {
    let service = try makeService()
    let shadowVersion = "1900000000000_0001_aaaaaaaaaaaaaaaa"
    let transportOnlyVersion = "9900000000000_0001_bbbbbbbbbbbbbbbb"
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO sync_payload_shadow
            (entity_type, entity_id, base_version, payload_schema_version,
             raw_payload_json, source_device_id, updated_at)
          VALUES ('task', 'shadow-task', ?, 1, '{}', 'remote',
                  '2026-07-14T12:00:00.000Z')
          """,
        arguments: [shadowVersion])
      try db.execute(
        sql: """
          INSERT INTO sync_outbox
            (entity_type, entity_id, operation, version, payload_schema_version,
             payload, device_id, synced_at)
          VALUES ('task', 'old-transport-row', 'upsert', ?, 1, '{}', 'old-device',
                  '2026-07-14T12:00:00.000Z')
          """,
        arguments: [transportOnlyVersion])
    }

    let ceiling = try service.read { db in
      try SwiftLorvexCoreService.HlcClock.maxAnyLocalHlc(db)
    }
    XCTAssertEqual(ceiling, try Hlc.parse(shadowVersion))
  }

  func testGlobalRetryCeilingIncludesActiveAuditPolicyVersion() throws {
    let service = try makeService()
    let account = "future-policy-account"
    let version = "9000000000000_0001_bbbbbbbbbbbbbbbb"
    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: account, zoneName: "LorvexZone-g1")
    _ = try service.adoptAuditRetentionPolicy(
      .off, policyVersion: version, forAccountIdentifier: account)

    let ceiling = try service.read { db in
      try SwiftLorvexCoreService.HlcClock.maxAnyLocalHlc(db)
    }
    XCTAssertEqual(ceiling, try Hlc.parse(version))
  }

  func testGlobalRetryCeilingRejectsParseableNoncanonicalStoredVersion() throws {
    let service = try makeService()
    let unpadded = "1900000000000_1_aaaaaaaaaaaaaaaa"
    try service.write { db in
      try Self.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO sync_payload_shadow
              (entity_type, entity_id, base_version, payload_schema_version,
               raw_payload_json, source_device_id, updated_at)
            VALUES ('task', 'noncanonical-shadow', ?, 1, '{}', 'remote',
                    '2026-07-14T12:00:00.000Z')
            """,
          arguments: [unpadded])
      }
    }

    XCTAssertThrowsError(
      try service.read { db in
        try SwiftLorvexCoreService.HlcClock.maxAnyLocalHlc(db)
      }
    ) { error in
      XCTAssertEqual(
        error as? SwiftLorvexCoreService.HlcHighWaterError,
        .invalidStoredVersion(
          table: "sync_payload_shadow", column: "base_version", value: unpadded))
    }
  }

  func testFallbackSeedIgnoresNoncanonicalValueWithoutHidingCanonicalFloor() throws {
    let service = try makeService()
    let appSuffix = DeviceIdentity.deviceIdToHlcSuffix(
      "89898989-8989-7989-8989-898989898989", surface: .app)
    let canonical = "1800000000000_0001_\(appSuffix)"
    let unpadded = "1900000000000_1_\(appSuffix)"
    try service.write { db in
      try Self.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
            VALUES
              ('tag-canonical', 'Canonical', 'canonical', ?,
               '2026-07-14T12:00:00.000Z', '2026-07-14T12:00:00.000Z'),
              ('tag-noncanonical', 'Noncanonical', 'noncanonical', ?,
               '2026-07-14T12:00:00.000Z', '2026-07-14T12:00:00.000Z')
            """,
          arguments: [canonical, unpadded])
      }
    }

    let observed = try service.read { db in
      try SwiftLorvexCoreService.HlcClock.maxLocalHlc(db, suffixes: [appSuffix])
    }
    XCTAssertEqual(observed, try Hlc.parse(canonical))
  }

  func testSeedReturnsNilWithoutLocalHistory() throws {
    let service = try makeService()
    let appSuffix = DeviceIdentity.deviceIdToHlcSuffix(
      "33333333-3333-7333-8333-333333333333", surface: .app)
    let observed = try service.read { db in
      try SwiftLorvexCoreService.HlcClock.maxLocalHlc(db, suffixes: [appSuffix])
    }
    XCTAssertNil(observed)
  }

  func testSeedTableListCoversEverySchemaHlcVersionColumn() throws {
    let service = try makeService()
    let schemaPairs = try service.read { db -> Set<String> in
      let tables = try String.fetchAll(
        db,
        sql: """
          SELECT name FROM sqlite_master
          WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
          ORDER BY name
          """)
      var pairs = Set<String>()
      for table in tables {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
        for row in rows {
          let column: String = row["name"]
          if column == "version" || column.hasSuffix("_version")
            || (table == "calendar_events" && column == "recurrence_generation")
          {
            pairs.insert("\(table).\(column)")
          }
        }
      }
      return pairs
    }
    let scannedPairs = Set(
      SwiftLorvexCoreService.HlcClock.hlcBearingTables.map { "\($0.table).\($0.column)" })
    let deliberateNonClockSeedVersionColumns: Set<String> = [
      // Numeric schema/protocol revisions, not HLCs.
      "schema_migrations.version",
      "sync_outbox.payload_schema_version",
      "sync_payload_shadow.payload_schema_version",
      // Remote-only or loser-only observations must not seed a local writer.
      "sync_conflict_log.loser_version",
      "sync_outbox.future_record_version",
      "sync_pending_inbox.envelope_version",
      // These capabilities/snapshots copy the policy HLC already retained by
      // audit_retention_account_state or audit_retention_binding; they never
      // mint an independent version.
      "audit_retention_candidate_authorization.policy_version",
      "sync_generation_snapshot_staging.retention_policy_version",
    ]
    XCTAssertEqual(scannedPairs, schemaPairs.subtracting(deliberateNonClockSeedVersionColumns))
  }
}
