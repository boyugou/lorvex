import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// ACF-14: the `ai_changelog` audit stream now emits one upsert envelope per row
/// at the local-mutation choke point (`writeChangelogRow`), converging across a
/// user's devices by id-dedup. Verified through the real write surface:
/// - a mutation enqueues exactly one `ai_changelog` upsert on the row's stable id;
/// - retention pruning creates exact-zone physical-delete work, never audit
///   delete envelopes or tombstones;
/// - under the `.off` retention policy, neither the audit row nor its envelope
///   is written.
final class SwiftLorvexCoreServiceChangelogSyncTests: XCTestCase {

  private func makeStore() throws -> LorvexStore {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexCoreServiceTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return try LorvexStore.openInMemory(schemaSQL: schemaSQL)
  }

  private func makeService() throws -> SwiftLorvexCoreService {
    SwiftLorvexCoreService(store: try makeStore())
  }

  private func changelogEnvelopes(_ service: SwiftLorvexCoreService) throws
    -> [PendingOutboundEnvelope]
  {
    try service.pendingOutbound().filter { $0.envelope.entityType == .aiChangelog }
  }

  private func changelogRowIDs(_ service: SwiftLorvexCoreService) throws -> [String] {
    try service.read { db in try String.fetchAll(db, sql: "SELECT id FROM ai_changelog") }
  }

  func testMutationEnqueuesExactlyOneChangelogUpsertOnStableRowID() async throws {
    let service = try makeService()
    _ = try await service.createTask(TaskCreateDraft(title: "A"))

    let rowIDs = try changelogRowIDs(service)
    XCTAssertEqual(rowIDs.count, 1, "one createTask should write exactly one audit row")

    let envelopes = try changelogEnvelopes(service)
    XCTAssertEqual(envelopes.count, 1)
    let envelope = try XCTUnwrap(envelopes.first).envelope
    XCTAssertEqual(envelope.entityType, .aiChangelog)
    XCTAssertEqual(envelope.operation, .upsert)
    // Envelope is keyed on the audit row's stable id (id-dedup convergence).
    XCTAssertEqual(envelope.entityId, rowIDs.first)
  }

  func testOrdinaryEntityDeleteProducesAuditUpsertNotAuditDelete() async throws {
    let service = try makeService()
    // A create then a delete: the delete emits a `list` delete envelope AND a
    // changelog UPSERT auditing the deletion. Retention does not use sync DELETE
    // envelopes either; exact-zone physical deletion is a separate transport.
    let list = try await service.createList(name: "Scratch", description: nil)
    try await service.deleteList(id: list.id)

    let pending = try service.pendingOutbound()
    XCTAssertFalse(
      pending.contains {
        $0.envelope.entityType == .aiChangelog && $0.envelope.operation == .delete
      },
      "an ordinary entity delete must not masquerade as an audit-retention delete")
    // Every emitted changelog envelope is an upsert, and there is at least one
    // (the create and the delete were both audited).
    let changelog = try changelogEnvelopes(service)
    XCTAssertGreaterThanOrEqual(changelog.count, 1)
    XCTAssertTrue(changelog.allSatisfy { $0.envelope.operation == .upsert })
    // One envelope per audit row, keyed by stable id.
    XCTAssertEqual(
      Set(changelog.map { $0.envelope.entityId }), Set(try changelogRowIDs(service)))
  }

  /// Tightening the changelog retention window applies immediately (before any
  /// sync cycle) AND creates durable physical-delete work for every exact zone
  /// where the full-content audit may exist. No sync DELETE or tombstone is used.
  func testRetentionPolicyTighteningQueuesExactZonePhysicalDeletes() async throws {
    let store = try makeStore()
    let service = SwiftLorvexCoreService(store: store)
    let account = "icloud-account-a"
    let zone = "LorvexZone-g1"
    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: account, zoneName: zone)

    // A fleet-wide rolling retention frontier must be derived from CloudKit
    // server time, never this device's wall clock. Production has this binding
    // before an account-scoped policy is enforced; make the fixture model that
    // same prerequisite explicitly.
    try await store.writer.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: "changelog-retention-test-database")
      _ = try CloudTraversalWitness.claimAccount(
        db, accountIdentifier: account)
      let serverTime = try XCTUnwrap(
        String.fetchOne(db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"))
      try Tombstone.observeTrustedServerTime(
        db, accountIdentifier: account, serverTime: serverTime)
    }

    // Seed audit rows out-of-band with backdated timestamps: two older than a
    // 7-day window (doomed) and one inside it (kept). Canonical UUID ids so the
    // outbound delete envelope validates.
    let oldA = UUID().uuidString.lowercased()
    let oldB = UUID().uuidString.lowercased()
    let recent = UUID().uuidString.lowercased()
    try await store.writer.write { db in
      for (id, daysAgo) in [(oldA, 90), (oldB, 45), (recent, 1)] {
        try db.execute(
          sql: """
            INSERT INTO ai_changelog (
              id, timestamp, operation, entity_type, summary, initiated_by,
              retention_epoch, retention_account_identifier
            ) VALUES (
              ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?),
              'create', 'task', 'seed', 'ai', 0, ?
            )
            """,
          arguments: [id, "-\(daysAgo) days", account])
        try db.execute(
          sql: """
            INSERT INTO audit_changelog_cloud_presence (
              account_identifier, zone_name, entity_id, retention_epoch, marked_at
            ) VALUES (?, ?, ?, 0, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
            """,
          arguments: [account, zone, id])
      }
    }

    _ = try await service.setPreference(
      key: PreferenceKeys.prefAiChangelogRetentionPolicy,
      value: ChangelogRetentionPolicy.days(7).wireValue)

    // The two backdated rows are gone locally; the in-window row survives.
    let survivingIDs = Set(try changelogRowIDs(service))
    XCTAssertFalse(survivingIDs.contains(oldA))
    XCTAssertFalse(survivingIDs.contains(oldB))
    XCTAssertTrue(survivingIDs.contains(recent))

    // Pruning never invents sync DELETE envelopes or local tombstones.
    let deletes = try service.pendingOutbound().filter {
      $0.envelope.entityType == .aiChangelog && $0.envelope.operation == .delete
    }
    XCTAssertTrue(deletes.isEmpty)
    try service.read { db in
      XCTAssertFalse(
        try Tombstone.isTombstoned(db, entityType: EntityName.aiChangelog, entityId: oldA))
      XCTAssertFalse(
        try Tombstone.isTombstoned(db, entityType: EntityName.aiChangelog, entityId: oldB))
      XCTAssertFalse(
        try Tombstone.isTombstoned(db, entityType: EntityName.aiChangelog, entityId: recent))
    }
    let purges = try service.pendingAuditRetentionPurges(
      forAccountIdentifier: account, zoneName: zone, limit: 100)
    XCTAssertEqual(Set(purges.map(\.entityId)), [oldA, oldB])
    XCTAssertTrue(purges.allSatisfy { $0.zoneName == zone })
  }

  func testOffPolicyWritesNoChangelogRowAndNoEnvelope() async throws {
    let service = try makeService()
    _ = try await service.setPreference(
      key: PreferenceKeys.prefAiChangelogRetentionPolicy,
      value: ChangelogRetentionPolicy.off.wireValue)

    _ = try await service.createTask(TaskCreateDraft(title: "hidden"))

    // Mutation committed, but no audit row...
    XCTAssertEqual(
      try service.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks") ?? -1 }, 1)
    XCTAssertEqual(try changelogRowIDs(service).count, 0)
    // ...and no audit envelope was enqueued.
    XCTAssertEqual(try changelogEnvelopes(service).count, 0)
  }

  func testInvalidRetentionPolicyWriteIsRejectedWithoutChangingThePolicy() async throws {
    let service = try makeService()
    let key = PreferenceKeys.prefAiChangelogRetentionPolicy

    do {
      _ = try await service.setPreference(key: key, value: "someday")
      XCTFail("expected an invalid retention value to be rejected")
    } catch let StoreError.validation(message) {
      XCTAssertEqual(
        message,
        "preference '\(key)' must be 'maximum', 'off', or a positive integer day count")
    }

    let storedPolicy = try await service.getPreference(key: key)
    XCTAssertEqual(storedPolicy, "\"maximum\"")
    XCTAssertEqual(try changelogRowIDs(service).count, 0)
    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM preferences WHERE key = ?",
          arguments: [key]),
        0)
    }
  }

  func testRetentionPreferenceIsVirtualAndAccountScopedAcrossSwitches() async throws {
    let service = try makeService()
    let key = PreferenceKeys.prefAiChangelogRetentionPolicy

    _ = try await service.setPreference(
      key: key, value: ChangelogRetentionPolicy.off.wireValue)
    let unboundRead = try await service.getPreference(key: key)
    let unboundSnapshot = try await service.getAllPreferences()
    XCTAssertEqual(unboundRead, "\"off\"")
    XCTAssertEqual(unboundSnapshot.values[key], "\"off\"")
    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM preferences WHERE key = ?", arguments: [key]),
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.preference, key]),
        0)
    }

    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: "icloud-account-a", zoneName: "LorvexZone-g1")
    let accountARead = try await service.getPreference(key: key)
    XCTAssertEqual(accountARead, "\"off\"")

    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: "icloud-account-b", zoneName: "LorvexZone-g1")
    let neutralBRead = try await service.getPreference(key: key)
    XCTAssertEqual(
      neutralBRead, "\"maximum\"",
      "a new account must expose its neutral policy, never account A's choice")
    _ = try service.initializeAuditRetentionForVerifiedEmptyAccount(
      accountIdentifier: "icloud-account-b")
    _ = try await service.setPreference(
      key: key, value: ChangelogRetentionPolicy.days(30).wireValue)
    let accountBRead = try await service.getPreference(key: key)
    XCTAssertEqual(accountBRead, "30")

    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: "icloud-account-a", zoneName: "LorvexZone-g1")
    let resumedARead = try await service.getPreference(key: key)
    XCTAssertEqual(resumedARead, "\"off\"")
    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: "icloud-account-b", zoneName: "LorvexZone-g1")
    let resumedBRead = try await service.getPreference(key: key)
    XCTAssertEqual(resumedBRead, "30")
  }

  func testExplicitRetentionPreferenceDominatesFarFutureMetadataVersion() async throws {
    let service = try makeService()
    let account = "icloud-account-future-policy"
    let key = PreferenceKeys.prefAiChangelogRetentionPolicy
    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: account, zoneName: "LorvexZone-g1")
    let remoteVersion = "9000000000000_0000_b1b2c3d4b1b2c3d4"
    _ = try service.adoptAuditRetentionPolicy(
      .off, policyVersion: remoteVersion, forAccountIdentifier: account)

    _ = try await service.setPreference(key: key, value: "maximum")

    let state = try XCTUnwrap(
      service.auditRetentionState(forAccountIdentifier: account))
    XCTAssertEqual(state.policy, .maximum)
    XCTAssertGreaterThan(try Hlc.parse(state.policyVersion), try Hlc.parse(remoteVersion))
    let afterSetRead = try await service.getPreference(key: key)
    XCTAssertEqual(afterSetRead, "\"maximum\"")
    try service.read { db in
      XCTAssertEqual(ChangelogRetentionPolicy.read(db), state.policy)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM preferences WHERE key = ?", arguments: [key]),
        0)
    }

    let laterRemoteVersion = "9500000000000_0000_c1c2d3e4c1c2d3e4"
    _ = try service.adoptAuditRetentionPolicy(
      .off, policyVersion: laterRemoteVersion, forAccountIdentifier: account)
    try await service.deletePreference(key: key)
    let afterDelete = try XCTUnwrap(
      service.auditRetentionState(forAccountIdentifier: account))
    XCTAssertEqual(afterDelete.policy, .maximum)
    XCTAssertGreaterThan(
      try Hlc.parse(afterDelete.policyVersion), try Hlc.parse(laterRemoteVersion))
    let afterDeleteRead = try await service.getPreference(key: key)
    XCTAssertEqual(afterDeleteRead, "\"maximum\"")
  }

  func testAccountSwitchHidesPriorAuditFromServiceAndBumpsLocalChangeSequence() async throws {
    let service = try makeService()
    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: "icloud-account-a", zoneName: "LorvexZone-g1")
    _ = try await service.createTask(TaskCreateDraft(title: "private account A task"))
    let before = try service.read { db in try LocalChangeSeq.read(db) }
    XCTAssertFalse(try changelogRowIDs(service).isEmpty)

    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: "icloud-account-b", zoneName: "LorvexZone-g1")

    let after = try service.read { db in try LocalChangeSeq.read(db) }
    XCTAssertGreaterThan(after, before)
    XCTAssertTrue(try changelogRowIDs(service).isEmpty)
    XCTAssertTrue(try changelogEnvelopes(service).isEmpty)
    let visible = try await service.loadAIChangelog(
      limit: 50, offset: 0, entityType: nil, operation: nil,
      entityID: nil, since: nil)
    XCTAssertTrue(
      visible.entries.isEmpty,
      "UI and MCP share this reader and must not expose the prior account")
  }

  /// An inbound full-content audit record rejected by the local retention
  /// horizon is still a known exact-zone CloudKit record. The receive path must
  /// create durable physical-delete work before removing local full content.
  func testOffPolicyInboundAuditQueuesPhysicalDelete() async throws {
    let service = try makeService()
    let account = "icloud-account-a"
    let zone = "LorvexZone-g1"
    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: account, zoneName: zone)
    _ = try await service.setPreference(
      key: PreferenceKeys.prefAiChangelogRetentionPolicy,
      value: ChangelogRetentionPolicy.off.wireValue)

    let id = UUID().uuidString.lowercased()
    let incomingVersion = try Hlc.parse("8000000000000_0000_b1b2c3d4b1b2c3d4")
    let row = ChangelogWrite.ChangelogRow(
      id: id, timestamp: "2026-07-14T12:00:00.000Z", operation: "update",
      entityType: "task", entityId: UUID().uuidString.lowercased(),
      summary: "private peer audit content", initiatedBy: "assistant",
      sourceDeviceId: "peer-device", retentionEpoch: 1)
    let payload = try SyncCanonicalize.canonicalizeJSON(
      ChangelogWrite.buildChangelogSyncPayload(row))
    let envelope = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .aiChangelog, entityId: id, operation: .upsert,
        version: incomingVersion, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "peer-device"))

    _ = try service.applyInbound([envelope], undecodable: 0)

    XCTAssertEqual(try changelogRowIDs(service).count, 0)
    XCTAssertFalse(
      try changelogEnvelopes(service).contains {
        $0.envelope.entityId == id && $0.envelope.operation == .delete
      })
    let purge = try XCTUnwrap(
      service.pendingAuditRetentionPurges(
        forAccountIdentifier: account, zoneName: zone, limit: 100
      ).first { $0.entityId == id })
    XCTAssertEqual(purge.zoneName, zone)
    XCTAssertEqual(purge.reason, .policyHorizon)
  }

  /// Redelivery of the same rejected full-content record must stay idempotent:
  /// one physical-delete obligation and no private conflict-log copy.
  func testRepeatedRejectedInboundAuditKeepsOnePurgeWithoutConflictCopy() async throws {
    let service = try makeService()
    let account = "icloud-account-a"
    let zone = "LorvexZone-g1"
    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: account, zoneName: zone)
    _ = try await service.setPreference(
      key: PreferenceKeys.prefAiChangelogRetentionPolicy,
      value: ChangelogRetentionPolicy.off.wireValue)
    let id = UUID().uuidString.lowercased()
    let incomingVersion = try Hlc.parse("7000000000000_0000_b1b2c3d4b1b2c3d4")
    let row = ChangelogWrite.ChangelogRow(
      id: id, timestamp: "2026-07-01T12:00:00.000Z", operation: "update",
      entityType: "task", entityId: UUID().uuidString.lowercased(),
      summary: "private stale peer content", initiatedBy: "assistant",
      sourceDeviceId: "peer-device", retentionEpoch: 1)
    let envelope = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .aiChangelog, entityId: id, operation: .upsert,
        version: incomingVersion, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          ChangelogWrite.buildChangelogSyncPayload(row)),
        deviceId: "peer-device"))

    _ = try service.applyInbound([envelope], undecodable: 0)
    _ = try service.applyInbound([envelope], undecodable: 0)

    let purges = try service.pendingAuditRetentionPurges(
      forAccountIdentifier: account, zoneName: zone, limit: 100
    ).filter { $0.entityId == id }
    XCTAssertEqual(purges.count, 1)
    XCTAssertEqual(purges.first?.zoneName, zone)
    try service.read { db in
      let copiedPayload = try String.fetchOne(
        db,
        sql: """
          SELECT loser_payload FROM sync_conflict_log
          WHERE entity_type = ? AND entity_id = ?
          ORDER BY id DESC LIMIT 1
          """,
        arguments: [EntityName.aiChangelog, id])
      XCTAssertNil(
        copiedPayload,
        "retention refusal must not copy private audit content into conflict history")
      XCTAssertFalse(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.aiChangelog, entityId: id))
    }
  }
}
