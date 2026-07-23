import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Adversarial coverage for account-relative audit frontiers and durable
/// CloudKit physical-delete work. These tests intentionally pin crash ordering,
/// account switches, stale generations, and equal-timestamp total ordering.
final class RetentionPropagationTests: XCTestCase {
  private let accountA = "icloud-account-a"
  private let accountB = "icloud-account-b"
  private let zoneA = "LorvexZone-g1"
  private let zoneB = "LorvexZone-g2"
  private let suffix = "a1b2c3d4a1b2c3d4"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func uuid(_ n: Int) -> String {
    "\(String(format: "%08x", n))-0000-7000-8000-000000000000"
  }

  private func version(_ counter: Int) -> String {
    "6000000000000_\(String(format: "%04d", counter))_\(suffix)"
  }

  @discardableResult
  private func insertAudit(
    _ db: Database, id: String, timestamp: String = "2026-01-01T00:00:00.000Z",
    operation: String = "update", epoch: Int64 = 0, account: String? = nil,
    enqueue: Bool = true, versionCounter: Int = 1
  ) throws -> Int64? {
    let row = ChangelogWrite.ChangelogRow(
      id: id, timestamp: timestamp, operation: operation, entityType: "task",
      entityId: self.uuid(9_000), summary: "private audit payload",
      initiatedBy: "assistant", sourceDeviceId: "device-local",
      retentionEpoch: epoch, retentionAccountIdentifier: account)
    try ChangelogWrite.writeChangelogRow(db, row)
    guard enqueue else { return nil }
    try OutboxEnqueue.enqueuePayloadUpsert(
      db, entityType: EntityName.aiChangelog, entityId: id,
      payload: ChangelogWrite.buildChangelogSyncPayload(row),
      context: OutboxWriteContext(
        version: self.version(versionCounter), deviceId: "device-local"))
    return try Int64.fetchOne(
      db,
      sql: """
        SELECT id FROM sync_outbox
        WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
        """,
      arguments: [EntityName.aiChangelog, id])
  }

  private func pendingAuditEnvelope(
    id: String, epoch: Int64, versionCounter: Int
  ) throws -> SyncEnvelope {
    let row = ChangelogWrite.ChangelogRow(
      id: id, timestamp: "2026-01-01T00:00:00.000Z", operation: "update",
      entityType: "task", summary: "held audit", initiatedBy: "assistant",
      sourceDeviceId: "peer", retentionEpoch: epoch)
    return try SyncTestSupport.completeEnvelope(
      entityType: .aiChangelog, entityId: id, operation: .upsert,
      version: try Hlc.parse(self.version(versionCounter)),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
      payload: try SyncCanonicalize.canonicalizeJSON(
        ChangelogWrite.buildChangelogSyncPayload(row)),
      deviceId: "peer")
  }

  func testEqualVersionPolicyCollisionAdoptsDataPreservingWinnerInEitherOrder() throws {
    let collisionPairs: [[ChangelogRetentionPolicy]] = [
      [.off, .maximum], [.maximum, .off], [.days(30), .days(365)],
      [.days(365), .days(30)],
    ]
    for policies in collisionPairs {
      try withDB { db in
        _ = try AuditRetentionFrontier.activateAccount(
          db, accountIdentifier: self.accountA, zoneName: self.zoneA)
        _ = try AuditRetentionFrontier.adoptPolicyForActiveAccount(
          db, accountIdentifier: self.accountA, policy: policies[0],
          policyVersion: self.version(1))
        let repaired = try AuditRetentionFrontier.adoptPolicyForActiveAccount(
          db, accountIdentifier: self.accountA, policy: policies[1],
          policyVersion: self.version(1))
        let expected = ChangelogRetentionPolicy.conservativeCollisionWinner(
          policies[0], policies[1])
        XCTAssertEqual(repaired.policy, expected)
        XCTAssertEqual(repaired.policyVersion, self.version(1))
        XCTAssertTrue(repaired.isPolicyReady)
        XCTAssertEqual(repaired.policyAuthorizedEpoch, repaired.frontierEpoch)
      }
    }
  }

  func testFleetDaysRetentionUsesTrustedServerClockNotDeviceWallClock() throws {
    try withDB { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId, value: "retention-clock-database")
      _ = try CloudTraversalWitness.claimAccount(
        db, accountIdentifier: self.accountA,
        boundAt: "2026-01-01T00:00:00.000Z")
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      _ = try AuditRetentionFrontier.adoptPolicyForActiveAccount(
        db, accountIdentifier: self.accountA, policy: .days(30),
        policyVersion: self.version(1))
      let oldID = self.uuid(88)
      _ = try self.insertAudit(
        db, id: oldID, timestamp: "2026-01-01T00:00:00.000Z",
        epoch: 0, account: self.accountA, enqueue: false)

      // Even an absurdly fast device clock cannot move a fleet frontier before
      // CloudKit has supplied an account-bound server timestamp.
      try AuditRetention.enforcePolicyForAccount(
        db, accountIdentifier: self.accountA,
        now: "2099-12-31T23:59:59.999Z")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?", arguments: [oldID]),
        1)
      var state = try XCTUnwrap(
        AuditRetentionFrontier.state(db, accountIdentifier: self.accountA))
      XCTAssertEqual(state.frontier.minimumRetainedTimestamp, "")

      try Tombstone.observeTrustedServerTime(
        db, accountIdentifier: self.accountA,
        serverTime: "2026-07-15T12:00:00.000Z")
      XCTAssertEqual(
        try AuditRetention.trustedDaysCutoffISO(
          db, accountIdentifier: self.accountA, days: 30),
        "2026-06-15T12:00:00.000Z")
      try AuditRetention.enforcePolicyForAccount(
        db, accountIdentifier: self.accountA,
        now: "1900-01-01T00:00:00.000Z")

      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?", arguments: [oldID]),
        0)
      state = try XCTUnwrap(
        AuditRetentionFrontier.state(db, accountIdentifier: self.accountA))
      XCTAssertEqual(
        state.frontier.minimumRetainedTimestamp,
        "2026-06-15T12:00:00.000Z")
    }
  }

  func testFirstBindingNormalizesOnlyCloudUnseenCandidateGeneration() throws {
    try withDB { db in
      try AuditRetentionFrontier.adoptPolicyForCurrentScope(
        db, policy: .off, policyVersion: self.version(1))
      try AuditRetentionFrontier.adoptPolicyForCurrentScope(
        db, policy: .maximum, policyVersion: self.version(2))
      let id = self.uuid(1)
      let outboxId = try XCTUnwrap(
        self.insertAudit(db, id: id, epoch: 0, versionCounter: 3))

      let activation = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      XCTAssertEqual(activation.kind, .firstBinding)
      XCTAssertEqual(activation.state.frontierEpoch, 2)
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT retention_epoch, retention_account_identifier
            FROM ai_changelog WHERE id = ?
            """,
          arguments: [id]))
      XCTAssertEqual(row["retention_epoch"] as Int64, 2)
      XCTAssertEqual(row["retention_account_identifier"] as String?, self.accountA)
      let payload = try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT payload FROM sync_outbox WHERE id = ?", arguments: [outboxId]))
      guard case .object(let object)? = JSONValue.parse(payload) else {
        return XCTFail("normalized outbox payload must remain valid JSON")
      }
      XCTAssertEqual(object["retention_epoch"], .int(2))
      XCTAssertNil(object["retention_account_identifier"])
      XCTAssertNil(object["cloud_presence_possible"])
    }
  }

  func testFirstBindingNeverUploadsDeviceLocalForensicAudit() throws {
    try withDB { db in
      let localOnlyId = self.uuid(90)
      _ = try self.insertAudit(
        db, id: localOnlyId,
        operation: SyncNaming.localAuditCoalescedDeleteDropped,
        enqueue: false)
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      XCTAssertNil(
        try String.fetchOne(
          db,
          sql: """
            SELECT retention_account_identifier FROM ai_changelog WHERE id = ?
            """,
          arguments: [localOnlyId]))

      let authorization = try AuditRetentionFrontier.authorizeOutboundAuditPush(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA,
        verifiedRemoteFrontier: .initial)
      let component = try AuditRetentionFrontier.generationSnapshotComponent(
        db, authorization: authorization)
      XCTAssertEqual(component.recordCount, 0)
      XCTAssertTrue(component.envelopes.isEmpty)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.aiChangelog, localOnlyId]),
        0)

      _ = try AuditRetentionFrontier.adoptPolicyForActiveAccount(
        db, accountIdentifier: self.accountA, policy: .off,
        policyVersion: self.version(1))
      XCTAssertEqual(try AuditRetention.gcChangelog(db), 1)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?",
          arguments: [localOnlyId]),
        0, "device-local forensic audit must still obey retention after binding")
    }
  }

  func testDeferredAuditRetryWakeFollowsTheActiveAccount() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let auditID = self.uuid(91)
      let outboxID = try XCTUnwrap(
        self.insertAudit(
          db, id: auditID, account: self.accountA, versionCounter: 91))
      let due = "2026-02-01T00:00:00.000Z"
      try db.execute(
        sql: """
          UPDATE sync_outbox
          SET retry_count = ?, disposition = ?, next_retry_at = ?,
              recovery_round = 1
          WHERE id = ?
          """,
        arguments: [
          Outbox.maxRetries, Outbox.Disposition.retryWait.rawValue, due,
          outboxID,
        ])

      XCTAssertEqual(
        try Outbox.earliestRetryAt(db),
        try XCTUnwrap(SyncTimestamp.parse(due)).date)

      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountB, zoneName: self.zoneB)
      XCTAssertNil(
        try Outbox.earliestRetryAt(db),
        "account A's parked audit must not wake account B's coordinator")
    }
  }

  func testAccountSwitchSwapsCompleteAuditWorkingSetAndSameIDRemainsAccountScoped() throws {
    try withDB { db in
      let id = self.uuid(2)
      _ = try self.insertAudit(db, id: id, versionCounter: 1)
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      _ = try AuditRetentionFrontier.advanceMinimumRetainedKey(
        db, accountIdentifier: self.accountA,
        minimumRetainedTimestamp: "2020-01-01T00:00:00.000Z")
      let held = try self.pendingAuditEnvelope(id: self.uuid(3), epoch: 4, versionCounter: 2)
      try PendingInboxDrain.enqueuePending(
        db, envelope: held,
        reason: DeferralReason.auditRetentionFrontierRefresh(requiredEpoch: 4).message,
        missingEntityType: nil, missingEntityID: nil, countsTowardRetryBudget: false)
      let now = "2026-07-15T00:00:00.000Z"
      try db.execute(
        sql: """
          INSERT INTO sync_payload_shadow (
            entity_type, entity_id, base_version, payload_schema_version,
            raw_payload_json, source_device_id, updated_at
          ) VALUES (?, ?, ?, ?, '{}', 'peer-a', ?)
          """,
        arguments: [
          EntityName.aiChangelog, id, self.version(1),
          LorvexVersion.payloadSchemaVersion + 1, now,
        ])
      try db.execute(
        sql: """
          INSERT INTO sync_quarantine_blocklist (
            entity_type, entity_id, version, quarantined_at
          ) VALUES (?, ?, ?, ?)
          """,
        arguments: [EntityName.aiChangelog, id, self.version(1), now])
      // Integrity fixture for a file that contains a forbidden legacy audit
      // tombstone: account activation must still repair it.
      try db.execute(sql: "PRAGMA ignore_check_constraints = ON")
      try db.execute(
        sql: """
          INSERT INTO sync_tombstones (
            entity_type, entity_id, version, deleted_at
          ) VALUES (?, ?, ?, ?)
          """,
        arguments: [EntityName.aiChangelog, id, self.version(1), now])
      try db.execute(sql: "PRAGMA ignore_check_constraints = OFF")
      try db.execute(
        sql: """
          INSERT INTO audit_changelog_cloud_presence (
            account_identifier, zone_name, entity_id, retention_epoch, marked_at
          ) VALUES (?, ?, ?, 0, ?)
          """,
        arguments: [self.accountA, self.zoneA, id, now])
      try db.execute(
        sql: """
          INSERT INTO audit_retention_purge_queue (
            account_identifier, zone_name, entity_id, retention_epoch, reason,
            attempt_count, created_at, updated_at
          ) VALUES (?, ?, ?, 0, 'local_retention', 0, ?, ?)
          """,
        arguments: [self.accountA, self.zoneA, id, now, now])

      let activationB = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountB, zoneName: self.zoneB)
      XCTAssertEqual(activationB.kind, .newAccount)
      XCTAssertEqual(activationB.state.frontier, .initial)
      XCTAssertFalse(activationB.state.isPolicyReady)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog"), 0)
      XCTAssertTrue(
        try AiChangelogQueryRepo.listAiChangelog(
          db, query: AiChangelogQuery(limit: 50)
        ).isEmpty,
        "the shared UI/MCP reader must not expose account A after binding B")
      for tableAndColumn in [
        ("sync_outbox", "entity_type"),
        ("sync_pending_inbox", "envelope_entity_type"),
        ("sync_payload_shadow", "entity_type"),
        ("sync_quarantine_blocklist", "entity_type"),
        ("sync_tombstones", "entity_type"),
      ] {
        XCTAssertEqual(
          try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM \(tableAndColumn.0) WHERE \(tableAndColumn.1) = ?",
            arguments: [EntityName.aiChangelog]),
          0)
      }
      XCTAssertEqual(try PendingInbox.countPending(db), 0)
      let stateA = try XCTUnwrap(
        AuditRetentionFrontier.state(db, accountIdentifier: self.accountA))
      XCTAssertEqual(stateA.frontierCutoffTimestamp, "2020-01-01T00:00:00.000Z")
      XCTAssertEqual(activationB.state.frontierCutoffTimestamp, "")
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM audit_changelog_cloud_presence
            WHERE account_identifier = ? AND entity_id = ?
            """,
          arguments: [self.accountA, id]), 1)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM audit_retention_purge_queue
            WHERE account_identifier = ? AND entity_id = ?
            """,
          arguments: [self.accountA, id]), 1)

      _ = try AuditRetentionFrontier.initializePolicyForVerifiedEmptyAccount(
        db, accountIdentifier: self.accountB)
      let rowB = ChangelogWrite.ChangelogRow(
        id: id, timestamp: "2026-07-15T01:00:00.000Z", operation: "update",
        entityType: "task", entityId: self.uuid(9_001), summary: "account B payload",
        initiatedBy: "assistant", sourceDeviceId: "peer-b",
        retentionEpoch: 0, retentionAccountIdentifier: nil)
      let envelopeB = try SyncTestSupport.completeEnvelope(
        entityType: .aiChangelog, entityId: id, operation: .upsert,
        version: try Hlc.parse(self.version(3)),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          ChangelogWrite.buildChangelogSyncPayload(rowB)),
        deviceId: "peer-b")
      let outcome = try Apply.applyEnvelope(
        db,
        registry: EntityApplierRegistry(
          appliers: EntityApplierRegistry.defaultEntityAppliers()),
        envelope: envelopeB)
      guard case .applied = outcome else {
        return XCTFail("same audit id from account B must land after the working-set swap")
      }
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: "SELECT retention_account_identifier FROM ai_changelog WHERE id = ?",
          arguments: [id]), self.accountB)

      _ = try AuditRetentionFrontier.pruneLocalAuditIdentity(
        db, entityId: id, accountIdentifier: self.accountB,
        reason: .localRetention, now: now)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM audit_retention_purge_queue
            WHERE account_identifier = ? AND entity_id = ?
            """,
          arguments: [self.accountA, id]), 1,
        "account B retention must not enqueue or rewrite deletion work in account A")
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM audit_retention_purge_queue
            WHERE account_identifier = ? AND entity_id = ?
            """,
          arguments: [self.accountB, id]), 1)
    }
  }

  func testVerifiedEmptyLaterAccountStartsFromNeutralPolicyWithoutInheritingPriorAccount() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let stateA = try AuditRetentionFrontier.adoptPolicyForActiveAccount(
        db, accountIdentifier: self.accountA, policy: .off,
        policyVersion: self.version(1))
      XCTAssertEqual(stateA.policy, .off)
      XCTAssertEqual(stateA.frontierEpoch, 1)

      let activationB = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountB, zoneName: self.zoneB)
      XCTAssertEqual(activationB.kind, .newAccount)
      XCTAssertFalse(activationB.state.isPolicyReady)

      let initialized = try AuditRetentionFrontier.initializePolicyForVerifiedEmptyAccount(
        db, accountIdentifier: self.accountB)
      XCTAssertTrue(initialized.isPolicyReady)
      XCTAssertEqual(initialized.frontier, .initial)
      XCTAssertEqual(initialized.confirmedFrontier, .initial)
      XCTAssertEqual(initialized.policy, .maximum)
      XCTAssertEqual(initialized.policyVersion, "")
      XCTAssertEqual(initialized.policyAuthorizedEpoch, 0)

      let retried = try AuditRetentionFrontier.initializePolicyForVerifiedEmptyAccount(
        db, accountIdentifier: self.accountB)
      XCTAssertEqual(retried, initialized, "verified-empty initialization must be idempotent")
      let persistedA = try XCTUnwrap(
        AuditRetentionFrontier.state(db, accountIdentifier: self.accountA))
      XCTAssertEqual(persistedA, stateA, "account B initialization must not rewrite account A")
    }
  }

  func testSameAccountZoneSwitchPreservesPendingAuditUpserts() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let id = self.uuid(4)
      let outboxId = try XCTUnwrap(
        self.insertAudit(
          db, id: id, account: self.accountA, versionCounter: 1))
      let held = try self.pendingAuditEnvelope(
        id: self.uuid(5), epoch: 4, versionCounter: 2)
      try PendingInboxDrain.enqueuePending(
        db, envelope: held,
        reason: DeferralReason.auditRetentionFrontierRefresh(requiredEpoch: 4).message,
        missingEntityType: nil, missingEntityID: nil,
        countsTowardRetryBudget: false)

      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneB)
      XCTAssertEqual(try AuditRetentionFrontier.activeZoneName(db), self.zoneB)
      XCTAssertEqual(
        try Int64.fetchOne(
          db,
          sql: """
            SELECT id FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.aiChangelog, id]),
        outboxId, "same-account generation switch must preserve unsent audit")
      XCTAssertEqual(try PendingInbox.countPending(db), 0)
    }
  }

  func testCandidateGenerationSnapshotReadsEveryRetainedAuditWithoutTouchingOutbox() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let ids = [self.uuid(8), self.uuid(9)]
      var originalOutboxes: [Int64] = []
      for (index, id) in ids.enumerated() {
        originalOutboxes.append(
          try XCTUnwrap(
            self.insertAudit(
              db, id: id, account: self.accountA,
              versionCounter: index + 1)))
      }
      _ = try self.insertAudit(
        db, id: self.uuid(99), account: self.accountB, enqueue: false)

      let oldAuthorization = try AuditRetentionFrontier.authorizeOutboundAuditPush(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA,
        verifiedRemoteFrontier: .initial)
      XCTAssertEqual(
        try AuditRetentionFrontier.markCloudPresencePossible(
          db, outboxId: originalOutboxes[0], authorization: oldAuthorization),
        .marked)

      let candidateAuthorization =
        try AuditRetentionFrontier.authorizeCandidateGeneration(
          db, accountIdentifier: self.accountA,
          candidateZoneName: self.zoneB)
      XCTAssertEqual(
        try AuditRetentionFrontier.activeZoneName(db), self.zoneA,
        "building a candidate must not redirect ordinary retention routing")
      let outboxBefore = try Row.fetchAll(
        db,
        sql: """
          SELECT id, entity_id, version, payload FROM sync_outbox
          WHERE synced_at IS NULL ORDER BY id
          """
      ).map { row -> String in
        let id: Int64 = row["id"]
        let entityId: String = row["entity_id"]
        let version: String = row["version"]
        let payload: String = row["payload"]
        return "\(id)\u{0}\(entityId)\u{0}\(version)\u{0}\(payload)"
      }
      let first = try AuditRetentionFrontier.generationSnapshotComponent(
        db, candidateAuthorization: candidateAuthorization)
      XCTAssertEqual(first.recordCount, 2)
      XCTAssertEqual(first.envelopes.count, 2)
      XCTAssertEqual(first.witnessDigest.count, 64)
      XCTAssertEqual(first.envelopes.map(\.entityId), ids)
      let outboxAfter = try Row.fetchAll(
        db,
        sql: """
          SELECT id, entity_id, version, payload FROM sync_outbox
          WHERE synced_at IS NULL ORDER BY id
          """
      ).map { row -> String in
        let id: Int64 = row["id"]
        let entityId: String = row["entity_id"]
        let version: String = row["version"]
        let payload: String = row["payload"]
        return "\(id)\u{0}\(entityId)\u{0}\(version)\u{0}\(payload)"
      }
      XCTAssertEqual(
        outboxAfter, outboxBefore,
        "snapshot enumeration must be side-effect-free")

      for envelope in first.envelopes {
        XCTAssertEqual(
          try AuditRetentionFrontier.markGenerationSnapshotCloudPresencePossible(
            db, envelope: envelope,
            candidateAuthorization: candidateAuthorization),
          .marked)
      }
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM audit_changelog_cloud_presence
            WHERE account_identifier = ? AND zone_name = ?
            """,
          arguments: [self.accountA, self.zoneB]),
        2)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM audit_changelog_cloud_presence
            WHERE account_identifier = ? AND zone_name = ?
            """,
          arguments: [self.accountA, self.zoneA]),
        1)

      let retried = try AuditRetentionFrontier.generationSnapshotComponent(
        db, candidateAuthorization: candidateAuthorization)
      XCTAssertEqual(retried, first, "crash/retry snapshot witness must be stable")

      // Simulate an abandoned candidate. The previous ordinary capability and
      // active routing remain usable; only the staged capability is revoked.
      try AuditRetentionFrontier.revokeCandidateGeneration(
        db, authorization: candidateAuthorization)
      XCTAssertEqual(try AuditRetentionFrontier.activeZoneName(db), self.zoneA)
      XCTAssertEqual(
        try AuditRetentionFrontier.markCloudPresencePossible(
          db, outboxId: originalOutboxes[1], authorization: oldAuthorization),
        .marked)
      XCTAssertThrowsError(
        try AuditRetentionFrontier.generationSnapshotComponent(
          db, candidateAuthorization: candidateAuthorization)
      ) { error in
        XCTAssertEqual(
          error as? AuditRetentionStateError,
          .invalidOutboundAuthorization)
      }
    }
  }

  func testCandidateAuthorizationResumesExactLeaseTokenAfterRelaunch() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let first = try AuditRetentionFrontier.authorizeCandidateGeneration(
        db, accountIdentifier: self.accountA, candidateZoneName: self.zoneB)
      let resumed = try AuditRetentionFrontier.authorizeCandidateGeneration(
        db, accountIdentifier: self.accountA, candidateZoneName: self.zoneB)
      XCTAssertEqual(resumed, first)

      let replacement = try AuditRetentionFrontier.authorizeCandidateGeneration(
        db, accountIdentifier: self.accountA,
        candidateZoneName: "LorvexZone-g3")
      XCTAssertNotEqual(replacement.token, first.token)
      XCTAssertEqual(replacement.candidateZoneName, "LorvexZone-g3")
      XCTAssertThrowsError(
        try AuditRetentionFrontier.generationSnapshotComponent(
          db, candidateAuthorization: first)
      ) { error in
        XCTAssertEqual(
          error as? AuditRetentionStateError,
          .invalidOutboundAuthorization)
      }
    }
  }

  func testEqualTimestampCutoffPrunesDeterministicPrefixAndQueuesOnlyCloudKnownRows() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let timestamp = "2026-01-01T00:00:00.000Z"
      let ids = [self.uuid(10), self.uuid(11), self.uuid(12)]
      var outboxIds: [Int64] = []
      for (index, id) in ids.enumerated() {
        outboxIds.append(
          try XCTUnwrap(
            self.insertAudit(
              db, id: id, timestamp: timestamp, account: self.accountA,
              versionCounter: index + 1)))
      }
      let authorization = try AuditRetentionFrontier.authorizeOutboundAuditPush(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA,
        verifiedRemoteFrontier: .initial)
      for outboxId in outboxIds {
        XCTAssertEqual(
          try AuditRetentionFrontier.markCloudPresencePossible(
            db, outboxId: outboxId, authorization: authorization),
          .marked)
      }

      let state = try AuditRetentionFrontier.advanceMinimumRetainedKey(
        db, accountIdentifier: self.accountA,
        minimumRetainedTimestamp: timestamp,
        minimumRetainedEntityId: ids[1])
      XCTAssertEqual(state.frontierCutoffEntityId, ids[1])
      XCTAssertEqual(
        try String.fetchAll(db, sql: "SELECT id FROM ai_changelog ORDER BY id"),
        [ids[1], ids[2]])
      XCTAssertEqual(
        try String.fetchAll(
          db, sql: "SELECT entity_id FROM audit_retention_purge_queue ORDER BY entity_id"),
        [ids[0]])
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ?
            """,
          arguments: [EntityName.aiChangelog, ids[0]]),
        0)
    }
  }

  func testFutureGenerationHoldsUntilMatchingPolicyAuthorizesJoinedFrontier() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let id = self.uuid(20)
      XCTAssertEqual(
        try AuditRetentionFrontier.classifyInboundAuditUpsert(
          db, entityId: id, retentionEpoch: 1,
          timestamp: "2026-01-01T00:00:00.000Z"),
        .holdForFrontierRefresh(requiredEpoch: 1))
      let joined = try AuditRetentionFrontier.joinRemoteFrontier(
        db, accountIdentifier: self.accountA,
        frontier: AuditRetentionFrontierValue(epoch: 1))
      XCTAssertFalse(joined.isPolicyReady)
      XCTAssertEqual(joined.policyAuthorizedEpoch, 0)
      XCTAssertThrowsError(
        try AuditRetentionFrontier.authorizeOutboundAuditPush(
          db, accountIdentifier: self.accountA, zoneName: self.zoneA,
          verifiedRemoteFrontier: joined.frontier)
      ) { error in
        XCTAssertEqual(
          error as? AuditRetentionStateError,
          .policyNotReady(self.accountA))
      }
      XCTAssertEqual(
        try AuditRetentionFrontier.classifyInboundAuditUpsert(
          db, entityId: id, retentionEpoch: 1,
          timestamp: "2026-01-01T00:00:00.000Z"),
        .holdForFrontierRefresh(requiredEpoch: 1),
        "frontier observation alone must not authorize a policy generation")
      let ready = try AuditRetentionFrontier.adoptPolicyForActiveAccount(
        db, accountIdentifier: self.accountA, policy: .maximum,
        policyVersion: self.version(1))
      XCTAssertEqual(ready.policyAuthorizedEpoch, 1)
      XCTAssertNil(ready.refreshRequiredEpoch)
      XCTAssertEqual(
        try AuditRetentionFrontier.classifyInboundAuditUpsert(
          db, entityId: id, retentionEpoch: 1,
          timestamp: "2026-01-01T00:00:00.000Z"),
        .accept)
      XCTAssertEqual(
        try AuditRetentionFrontier.classifyInboundAuditUpsert(
          db, entityId: self.uuid(21), retentionEpoch: 0,
          timestamp: "2026-01-01T00:00:00.000Z"),
        .rejectAndPurge(.belowFrontier))
    }
  }

  func testDisableAndReenableAdvanceEpochAndFenceStaleDevices() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let disabled = try AuditRetentionFrontier.adoptPolicyForActiveAccount(
        db, accountIdentifier: self.accountA, policy: .off,
        policyVersion: self.version(1))
      XCTAssertEqual(disabled.frontierEpoch, 1)
      XCTAssertEqual(
        try AuditRetentionFrontier.classifyInboundAuditUpsert(
          db, entityId: self.uuid(30), retentionEpoch: 0,
          timestamp: "2026-01-01T00:00:00.000Z"),
        .rejectAndPurge(.belowFrontier))
      XCTAssertEqual(
        try AuditRetentionFrontier.classifyInboundAuditUpsert(
          db, entityId: self.uuid(31), retentionEpoch: 1,
          timestamp: "2026-01-01T00:00:00.000Z"),
        .rejectAndPurge(.policyHorizon))

      let reenabled = try AuditRetentionFrontier.adoptPolicyForActiveAccount(
        db, accountIdentifier: self.accountA, policy: .maximum,
        policyVersion: self.version(2))
      XCTAssertEqual(reenabled.frontierEpoch, 2)
      XCTAssertEqual(
        try AuditRetentionFrontier.classifyInboundAuditUpsert(
          db, entityId: self.uuid(32), retentionEpoch: 1,
          timestamp: "2026-01-01T00:00:00.000Z"),
        .rejectAndPurge(.belowFrontier))
      XCTAssertEqual(
        try AuditRetentionFrontier.classifyInboundAuditUpsert(
          db, entityId: self.uuid(33), retentionEpoch: 2,
          timestamp: "2026-01-01T00:00:00.000Z"),
        .accept)
    }
  }

  func testOutboundAuthorizationIsInvalidatedByEveryActivation() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let outboxId = try XCTUnwrap(
        self.insertAudit(
          db, id: self.uuid(40), account: self.accountA,
          versionCounter: 1))
      let authorization = try AuditRetentionFrontier.authorizeOutboundAuditPush(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA,
        verifiedRemoteFrontier: .initial)
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      XCTAssertThrowsError(
        try AuditRetentionFrontier.markCloudPresencePossible(
          db, outboxId: outboxId, authorization: authorization)
      ) { error in
        XCTAssertEqual(error as? AuditRetentionStateError, .invalidOutboundAuthorization)
      }
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountB, zoneName: self.zoneB)
      XCTAssertThrowsError(
        try AuditRetentionFrontier.markCloudPresencePossible(
          db, outboxId: outboxId, authorization: authorization))
    }
  }

  func testPolicyChangeInvalidatesAuthorizationAndEnforcesNewHorizon() throws {
    try withDB { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: "policy-horizon-database")
      _ = try CloudTraversalWitness.claimAccount(
        db, accountIdentifier: self.accountA,
        boundAt: "2026-01-01T00:00:00.000Z")
      try Tombstone.observeTrustedServerTime(
        db, accountIdentifier: self.accountA,
        serverTime: "2026-02-01T00:00:00.000Z")
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let id = self.uuid(41)
      let outboxId = try XCTUnwrap(
        self.insertAudit(
          db, id: id, timestamp: "2000-01-01T00:00:00.000Z",
          account: self.accountA, versionCounter: 1))
      let authorization = try AuditRetentionFrontier.authorizeOutboundAuditPush(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA,
        verifiedRemoteFrontier: .initial)

      _ = try AuditRetentionFrontier.adoptPolicyForActiveAccount(
        db, accountIdentifier: self.accountA, policy: .days(1),
        policyVersion: self.version(2))
      XCTAssertThrowsError(
        try AuditRetentionFrontier.markCloudPresencePossible(
          db, outboxId: outboxId, authorization: authorization)
      ) { error in
        XCTAssertEqual(error as? AuditRetentionStateError, .invalidOutboundAuthorization)
      }

      try AuditRetention.enforcePolicyForAccount(
        db, accountIdentifier: self.accountA,
        now: "2026-02-01T00:00:00.000Z")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?", arguments: [id]),
        0)
      XCTAssertNil(
        try Int64.fetchOne(
          db,
          sql: "SELECT id FROM sync_outbox WHERE id = ? AND synced_at IS NULL",
          arguments: [outboxId]))
    }
  }

  func testMarkBeforeCloudThenPruneSurvivesCrashFailureAndAccountSwitchUntilAck() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let id = self.uuid(50)
      let outboxId = try XCTUnwrap(
        self.insertAudit(
          db, id: id, timestamp: "2026-01-01T00:00:00.000Z",
          account: self.accountA, versionCounter: 1))
      let authorization = try AuditRetentionFrontier.authorizeOutboundAuditPush(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA,
        verifiedRemoteFrontier: .initial)
      XCTAssertEqual(
        try AuditRetentionFrontier.markCloudPresencePossible(
          db, outboxId: outboxId, authorization: authorization,
          now: "2026-01-01T00:00:01.000Z"),
        .marked)

      _ = try AuditRetentionFrontier.advanceMinimumRetainedKey(
        db, accountIdentifier: self.accountA,
        minimumRetainedTimestamp: "2026-02-01T00:00:00.000Z",
        now: "2026-02-01T00:00:00.000Z")
      XCTAssertEqual(
        try AuditRetentionFrontier.pendingPurges(
          db, accountIdentifier: self.accountA, zoneName: self.zoneA,
          now: "2026-02-01T00:00:00.000Z"
        ).map(\.entityId),
        [id])
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?", arguments: [id]),
        0)
      XCTAssertFalse(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.aiChangelog, entityId: id))

      try AuditRetentionFrontier.recordPurgeFailure(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA, entityId: id,
        error: "network unavailable", now: "2026-02-01T00:00:00.000Z")
      XCTAssertEqual(
        try AuditRetentionFrontier.earliestPurgeRetryAt(
          db, accountIdentifier: self.accountA, zoneName: self.zoneA),
        try XCTUnwrap(SyncTimestamp.parse("2026-02-01T00:00:30.000Z")).date)
      XCTAssertTrue(
        try AuditRetentionFrontier.pendingPurges(
          db, accountIdentifier: self.accountA, zoneName: self.zoneA,
          now: "2026-02-01T00:00:29.999Z"
        ).isEmpty)
      XCTAssertEqual(
        try AuditRetentionFrontier.pendingPurges(
          db, accountIdentifier: self.accountA, zoneName: self.zoneA,
          now: "2026-02-01T00:00:30.000Z"
        ).first?.attemptCount,
        1)

      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountB, zoneName: self.zoneB)
      XCTAssertNil(
        try AuditRetentionFrontier.earliestPurgeRetryAt(
          db, accountIdentifier: self.accountB, zoneName: self.zoneB))
      XCTAssertTrue(
        try AuditRetentionFrontier.pendingPurges(
          db, accountIdentifier: self.accountB, zoneName: self.zoneB,
          now: "2026-02-01T00:01:00.000Z"
        ).isEmpty)
      XCTAssertThrowsError(
        try AuditRetentionFrontier.acknowledgePurges(
          db, accountIdentifier: self.accountA, zoneName: self.zoneA,
          entityIds: [id]))

      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      try AuditRetentionFrontier.acknowledgePurges(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA,
        entityIds: [id])
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM audit_retention_purge_queue
            WHERE account_identifier = ? AND entity_id = ?
            """,
          arguments: [self.accountA, id]),
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM audit_changelog_cloud_presence
            WHERE account_identifier = ? AND entity_id = ?
            """,
          arguments: [self.accountA, id]),
        0)
    }
  }

  func testPurgeFailureRejectsMalformedNowWithoutMutatingRetryState() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let id = self.uuid(51)
      try AuditRetentionFrontier.rejectInboundAuditAndQueuePurge(
        db, entityId: id, retentionEpoch: 0, reason: .belowFrontier,
        now: "2026-02-01T00:00:00.000Z")
      let before = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT attempt_count, next_attempt_at, last_error, updated_at
            FROM audit_retention_purge_queue
            WHERE account_identifier = ? AND zone_name = ? AND entity_id = ?
            """,
          arguments: [self.accountA, self.zoneA, id]))

      XCTAssertThrowsError(
        try AuditRetentionFrontier.recordPurgeFailure(
          db, accountIdentifier: self.accountA, zoneName: self.zoneA,
          entityId: id, error: "must not persist", now: "not-a-timestamp")
      ) { error in
        XCTAssertEqual(
          error as? AuditRetentionStateError,
          .invalidTimestamp("not-a-timestamp"))
      }

      let after = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
              SELECT attempt_count, next_attempt_at, last_error, updated_at
              FROM audit_retention_purge_queue
              WHERE account_identifier = ? AND zone_name = ? AND entity_id = ?
            """,
          arguments: [self.accountA, self.zoneA, id]))
      let beforeNextAttempt: String? = before["next_attempt_at"]
      let afterNextAttempt: String? = after["next_attempt_at"]
      let beforeError: String? = before["last_error"]
      let afterError: String? = after["last_error"]
      XCTAssertEqual(after["attempt_count"] as Int, before["attempt_count"] as Int)
      XCTAssertEqual(afterNextAttempt, beforeNextAttempt)
      XCTAssertEqual(afterError, beforeError)
      XCTAssertEqual(after["updated_at"] as String, before["updated_at"] as String)
    }
  }

  func testPruneBeforeMarkSuppressesOrphanedUploadWithoutInventingCloudDelete() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let id = self.uuid(60)
      let outboxId = try XCTUnwrap(
        self.insertAudit(db, id: id, account: self.accountA, versionCounter: 1))
      let authorization = try AuditRetentionFrontier.authorizeOutboundAuditPush(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA,
        verifiedRemoteFrontier: .initial)
      _ = try AuditRetentionFrontier.pruneLocalAuditIdentity(
        db, entityId: id, accountIdentifier: self.accountA,
        reason: .localRetention)
      XCTAssertEqual(
        try AuditRetentionFrontier.markCloudPresencePossible(
          db, outboxId: outboxId, authorization: authorization),
        .noLongerPending)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM audit_retention_purge_queue"), 0)
    }
  }

  func testMarkRejectsOutboxPayloadThatDriftedFromCanonicalAuditRow() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let id = self.uuid(65)
      let outboxId = try XCTUnwrap(
        self.insertAudit(
          db, id: id, timestamp: "2026-02-01T00:00:00.000Z",
          account: self.accountA, versionCounter: 1))
      let authorization = try AuditRetentionFrontier.authorizeOutboundAuditPush(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA,
        verifiedRemoteFrontier: .initial)
      let payload = try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT payload FROM sync_outbox WHERE id = ?",
          arguments: [outboxId]))
      guard case .object(var object)? = JSONValue.parse(payload) else {
        return XCTFail("seeded audit payload must be an object")
      }
      object["timestamp"] = .string("2020-01-01T00:00:00.000Z")
      try db.execute(
        sql: "UPDATE sync_outbox SET payload = ? WHERE id = ?",
        arguments: [try SyncCanonicalize.canonicalizeJSON(.object(object)), outboxId])

      XCTAssertThrowsError(
        try AuditRetentionFrontier.markCloudPresencePossible(
          db, outboxId: outboxId, authorization: authorization)
      ) { error in
        XCTAssertEqual(
          error as? AuditRetentionStateError,
          .invalidOutboundAuditRow(outboxId))
      }
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM audit_changelog_cloud_presence"), 0)
    }
  }

  func testMarkRejectsSyntheticPayloadVersionThatDoesNotMatchEnvelope() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let id = self.uuid(64)
      let outboxId = try XCTUnwrap(
        self.insertAudit(
          db, id: id, account: self.accountA, versionCounter: 1))
      let authorization = try AuditRetentionFrontier.authorizeOutboundAuditPush(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA,
        verifiedRemoteFrontier: .initial)
      let payload = try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT payload FROM sync_outbox WHERE id = ?",
          arguments: [outboxId]))
      guard case .object(var object)? = JSONValue.parse(payload) else {
        return XCTFail("seeded audit payload must be an object")
      }
      object["version"] = .string(self.version(9))
      try db.execute(
        sql: "UPDATE sync_outbox SET payload = ? WHERE id = ?",
        arguments: [
          try SyncCanonicalize.canonicalizeJSON(.object(object)), outboxId,
        ])

      XCTAssertThrowsError(
        try AuditRetentionFrontier.markCloudPresencePossible(
          db, outboxId: outboxId, authorization: authorization)
      ) { error in
        XCTAssertEqual(
          error as? AuditRetentionStateError,
          .invalidOutboundAuditRow(outboxId))
      }
    }
  }

  func testPurgeEvidenceIsScopedPerZoneGenerationAndAcknowledgedIndependently() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let id = self.uuid(66)
      try AuditRetentionFrontier.rejectInboundAuditAndQueuePurge(
        db, entityId: id, retentionEpoch: 0, reason: .resetTombstone)

      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneB)
      try AuditRetentionFrontier.rejectInboundAuditAndQueuePurge(
        db, entityId: id, retentionEpoch: 0, reason: .belowFrontier)
      let zoneAPending = try AuditRetentionFrontier.pendingPurges(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      let zoneBPending = try AuditRetentionFrontier.pendingPurges(
        db, accountIdentifier: self.accountA, zoneName: self.zoneB)
      XCTAssertEqual(zoneAPending.map(\.entityId), [id])
      XCTAssertEqual(zoneBPending.map(\.entityId), [id])

      try AuditRetentionFrontier.acknowledgePurges(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA,
        entityIds: [id])
      let remaining = try AuditRetentionFrontier.pendingPurges(
        db, accountIdentifier: self.accountA, zoneName: self.zoneB)
      XCTAssertEqual(remaining.first?.reason, .belowFrontier)
      XCTAssertTrue(
        try AuditRetentionFrontier.pendingPurges(
          db, accountIdentifier: self.accountA, zoneName: self.zoneA
        ).isEmpty)

      try AuditRetentionFrontier.acknowledgeZoneDeletion(
        db, accountIdentifier: self.accountA, zoneName: self.zoneB)
      XCTAssertTrue(
        try AuditRetentionFrontier.pendingPurges(
          db, accountIdentifier: self.accountA, zoneName: self.zoneB
        ).isEmpty)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM audit_changelog_cloud_presence
            WHERE account_identifier = ? AND zone_name = ?
            """,
          arguments: [self.accountA, self.zoneB]),
        0)
    }
  }

  func testCurrentZonePurgePageCannotBeStarvedByRetiredZoneRows() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneB)
      let createdAt = "2026-07-01T00:00:00.000Z"
      for ordinal in 1_000..<1_250 {
        try db.execute(
          sql: """
            INSERT INTO audit_retention_purge_queue (
              account_identifier, zone_name, entity_id, retention_epoch, reason,
              attempt_count, created_at, updated_at
            ) VALUES (?, ?, ?, 0, 'local_retention', 0, ?, ?)
            """,
          arguments: [
            self.accountA, self.zoneA, self.uuid(ordinal), createdAt, createdAt,
          ])
      }
      let activeEntityId = self.uuid(2_000)
      try db.execute(
        sql: """
          INSERT INTO audit_retention_purge_queue (
            account_identifier, zone_name, entity_id, retention_epoch, reason,
            attempt_count, created_at, updated_at
          ) VALUES (?, ?, ?, 0, 'local_retention', 0, ?, ?)
          """,
        arguments: [
          self.accountA, self.zoneB, activeEntityId,
          "2026-07-02T00:00:00.000Z", "2026-07-02T00:00:00.000Z",
        ])

      let activePage = try AuditRetentionFrontier.pendingPurges(
        db, accountIdentifier: self.accountA, zoneName: self.zoneB, limit: 200,
        now: "2026-07-03T00:00:00.000Z")
      XCTAssertEqual(activePage.map(\.entityId), [activeEntityId])
      XCTAssertTrue(activePage.allSatisfy { $0.zoneName == self.zoneB })
    }
  }

  func testResetTombstonePurgeFailsClosedBeforeActivationAndFitsSchemaAfterActivation() throws {
    try withDB { db in
      let id = self.uuid(67)
      XCTAssertThrowsError(
        try AuditRetentionFrontier.rejectInboundAuditAndQueuePurge(
          db, entityId: id, retentionEpoch: 0, reason: .resetTombstone)
      ) { error in
        XCTAssertEqual(error as? AuditRetentionStateError, .noActiveAccount)
      }
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      XCTAssertNoThrow(
        try AuditRetentionFrontier.rejectInboundAuditAndQueuePurge(
          db, entityId: id, retentionEpoch: 0, reason: .resetTombstone))
      let item = try XCTUnwrap(
        AuditRetentionFrontier.pendingPurges(
          db, accountIdentifier: self.accountA, zoneName: self.zoneA
        ).first)
      XCTAssertEqual(item.zoneName, self.zoneA)
      XCTAssertEqual(item.reason, .resetTombstone)
    }
  }

  func testMalformedFrontierAndTimestampFailClosed() throws {
    try withDB { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: self.accountA, zoneName: self.zoneA)
      XCTAssertThrowsError(
        try AuditRetentionFrontier.authorizeOutboundAuditPush(
          db, accountIdentifier: self.accountA, zoneName: self.zoneA,
          verifiedRemoteFrontier: AuditRetentionFrontierValue(
            epoch: 0, minimumRetainedTimestamp: "not-a-timestamp"))
      ) {
        error in
        XCTAssertEqual(error as? AuditRetentionStateError, .invalidFrontier)
      }
      XCTAssertThrowsError(
        try AuditRetentionFrontier.classifyInboundAuditUpsert(
          db, entityId: self.uuid(70), retentionEpoch: 0,
          timestamp: "2026-01-01")
      ) {
        error in
        XCTAssertEqual(error as? AuditRetentionStateError, .invalidFrontier)
      }
    }
  }
}
