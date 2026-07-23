import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class GenerationSnapshotStagingTests: XCTestCase {
  private let account = "icloud-account-generation-staging"
  private let sourceZone = "LorvexData-source"
  private let candidateZone = "LorvexData-candidate"
  private let versionSuffix = "1234567890abcdef"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func seedTasks(_ db: Database, count: Int) throws {
    let statement = try db.makeStatement(
      sql: """
        INSERT INTO tasks (
          id, title, status, defer_count, version, created_at, updated_at
        ) VALUES (?, ?, 'open', 0, ?, '2026-07-14T00:00:00.000Z',
                  '2026-07-14T00:00:00.000Z')
        """)
    for index in 0..<count {
      try statement.execute(
        arguments: [
          String(format: "%08x-0000-7000-8000-%012x", index + 1, index + 1),
          "Task \(index)", version(index + 1),
        ])
    }
  }

  private func version(_ counter: Int) -> String {
    "6000000000000_\(String(format: "%04d", counter))_\(versionSuffix)"
  }

  private func replayableVersion(_ counter: Int) -> String {
    "1700000000000_\(String(format: "%04d", counter))_\(versionSuffix)"
  }

  private func prepare(
    _ db: Database, candidateZone: String? = nil,
    lease: String = "candidate-lease"
  ) throws -> (GenerationSnapshotBinding, AuditRetentionCandidateAuthorization) {
    let cloudBinding = try CloudTraversalWitness.claimAccount(
      db, accountIdentifier: account)
    _ = try AuditRetentionFrontier.activateAccount(
      db, accountIdentifier: account, zoneName: sourceZone)
    let zone = candidateZone ?? self.candidateZone
    let authorization = try AuditRetentionFrontier.authorizeCandidateGeneration(
      db, accountIdentifier: account, candidateZoneName: zone)
    return (
      try GenerationSnapshotBinding(
        accountIdentifier: account,
        databaseInstanceIdentifier: cloudBinding.databaseInstanceIdentifier,
        candidateZoneName: zone, generation: 7,
        generationIdentifier: "generation-7", leaseIdentifier: lease,
        leaseOwnerIdentifier: cloudBinding.databaseInstanceIdentifier),
      authorization
    )
  }

  private func prepareActive(
    _ db: Database, lease: String = "active-lease"
  ) throws -> (GenerationSnapshotBinding, AuditRetentionOutboundAuthorization) {
    let cloudBinding = try CloudTraversalWitness.claimAccount(
      db, accountIdentifier: account)
    _ = try AuditRetentionFrontier.activateAccount(
      db, accountIdentifier: account, zoneName: candidateZone)
    let authorization = try AuditRetentionFrontier.authorizeOutboundAuditPush(
      db, accountIdentifier: account, zoneName: candidateZone,
      verifiedRemoteFrontier: .initial)
    return (
      try GenerationSnapshotBinding(
        accountIdentifier: account,
        databaseInstanceIdentifier: cloudBinding.databaseInstanceIdentifier,
        candidateZoneName: candidateZone, generation: 1,
        generationIdentifier: "active-generation", leaseIdentifier: lease,
        leaseOwnerIdentifier: cloudBinding.databaseInstanceIdentifier),
      authorization
    )
  }

  @discardableResult
  private func completeReadback(
    _ db: Database, binding: GenerationSnapshotBinding,
    transform: (inout [SyncEnvelope]) throws -> Void = { _ in }
  ) throws -> GenerationSnapshotStaging {
    var offset = 0
    var envelopes: [SyncEnvelope] = []
    while true {
      let page = try GenerationSnapshot.stagedPage(
        db, binding: binding, offset: offset)
      envelopes.append(contentsOf: page.envelopes)
      guard let next = page.nextOffset else { break }
      offset = next
    }
    try transform(&envelopes)
    return try GenerationSnapshot.recordReadbackPage(
      db, binding: binding, expectedPageIndex: 0,
      witnesses: try envelopes.map(GenerationSnapshot.witness(for:)),
      deletedRecordNames: [], continuationToken: Data([0x01]),
      observedTraversalWitness: true, terminal: true)
  }

  func testLargeSnapshotIsCapturedOnceAndPagedFromStableRows() throws {
    try withDB { db in
      try seedTasks(db, count: 450)
      let (binding, authorization) = try prepare(db)
      let captured = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 41)
      XCTAssertEqual(captured.manifest.recordCount, 452)
      XCTAssertEqual(captured.manifest.sourceLocalChangeSequence, 41)

      // Mutable source changes after capture must not leak into later pages.
      try db.execute(
        sql: "UPDATE tasks SET title = 'Changed after capture', version = ? WHERE id = ?",
        arguments: [version(900), "00000001-0000-7000-8000-000000000001"])
      let first = try GenerationSnapshot.stagedPage(db, binding: binding, offset: 0)
      let second = try GenerationSnapshot.stagedPage(
        db, binding: binding, offset: try XCTUnwrap(first.nextOffset))
      let third = try GenerationSnapshot.stagedPage(
        db, binding: binding, offset: try XCTUnwrap(second.nextOffset))
      XCTAssertEqual(first.envelopes.count, 200)
      XCTAssertEqual(second.envelopes.count, 200)
      XCTAssertEqual(third.envelopes.count, 52)
      XCTAssertNil(third.nextOffset)
      let capturedTask = try XCTUnwrap(
        first.envelopes.first {
          $0.entityType == .task
            && $0.entityId == "00000001-0000-7000-8000-000000000001"
        })
      XCTAssertTrue(capturedTask.payload.contains("Task 0"))
      XCTAssertFalse(capturedTask.payload.contains("Changed after capture"))
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_generation_snapshot_items"),
        captured.manifest.recordCount)

      // Exact lease recovery ignores the now-different source sequence and
      // returns the immutable original capture instead of rebuilding it.
      let resumed = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 99)
      XCTAssertEqual(resumed.manifest, captured.manifest)

      let firstBytes = try XCTUnwrap(
        Int.fetchOne(
          db,
          sql: """
            SELECT encoded_byte_count FROM sync_generation_snapshot_items
            WHERE lease_identifier = ? AND ordinal = 0
            """,
          arguments: [binding.leaseIdentifier]))
      let byteBounded = try GenerationSnapshot.stagedPage(
        db, binding: binding, offset: 0, limit: 200,
        maximumEncodedBytes: firstBytes)
      XCTAssertEqual(byteBounded.envelopes.count, 1)
      let encodedBytes = try byteBounded.envelopes
        .map { try GenerationSnapshot.canonicalEnvelopeData($0).count }
        .reduce(0, +)
      XCTAssertLessThanOrEqual(
        encodedBytes, firstBytes)
    }
  }

  func testCaptureExcludesVirtualControlPlanePreferenceRowAndTombstone() throws {
    try withDB { db in
      let (binding, authorization) = try prepare(db, lease: "control-plane-exclusion")
      let key = PreferenceKeys.prefAiChangelogRetentionPolicy
      try db.execute(
        sql: """
          INSERT INTO preferences (key, value, version, updated_at)
          VALUES (?, '"off"', ?, '2026-07-14T00:00:00.000Z')
          """,
        arguments: [key, version(91)])
      try Tombstone.createTombstone(
        db, entityType: EntityName.preference, entityId: key,
        version: version(92), deletedAt: "2026-07-14T00:00:00.000Z")

      _ = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 1)
      let page = try GenerationSnapshot.stagedPage(db, binding: binding, offset: 0)
      XCTAssertFalse(
        page.envelopes.contains {
          $0.entityType == .preference && $0.entityId == key
        })
    }
  }

  func testCaptureOmitsOnlyServerConfirmedTombstonesAtPublishedCutoff() throws {
    try withDB { db in
      let oldID = "00000001-0000-7000-8000-000000000101"
      let recentID = "00000001-0000-7000-8000-000000000102"
      let unconfirmedID = "00000001-0000-7000-8000-000000000103"
      let oldVersion = version(101)
      let recentVersion = version(102)
      let unconfirmedVersion = version(103)
      for (id, stamp) in [
        (oldID, oldVersion), (recentID, recentVersion),
        (unconfirmedID, unconfirmedVersion),
      ] {
        try Tombstone.createTombstone(
          db, entityType: EntityName.task, entityId: id,
          version: stamp, deletedAt: "2020-01-01T00:00:00.000Z")
      }
      _ = try Tombstone.confirmCloudPresence(
        db,
        confirmation: .init(
          entityType: EntityName.task, entityId: oldID, version: oldVersion,
          confirmedAt: "2024-01-01T00:00:00.000Z"))
      _ = try Tombstone.confirmCloudPresence(
        db,
        confirmation: .init(
          entityType: EntityName.task, entityId: recentID, version: recentVersion,
          confirmedAt: "2026-01-01T00:00:00.000Z"))

      let (binding, authorization) = try prepare(db, lease: "compaction-filter")
      let captured = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 1,
        tombstoneCompactionCutoff: "2025-01-01T00:00:00.000Z")
      let page = try GenerationSnapshot.stagedPage(db, binding: binding, offset: 0)

      XCTAssertEqual(
        captured.tombstoneCompactionCutoff, "2025-01-01T00:00:00.000Z")
      XCTAssertFalse(page.envelopes.contains { $0.entityId == oldID })
      XCTAssertTrue(page.envelopes.contains { $0.entityId == recentID })
      XCTAssertTrue(page.envelopes.contains { $0.entityId == unconfirmedID })
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT entity_id FROM sync_generation_snapshot_compacted_tombstones
            WHERE lease_identifier = ?
            """,
          arguments: [binding.leaseIdentifier]), oldID)
      XCTAssertEqual(captured.manifest.recordCount, page.envelopes.count)
    }
  }

  func testCaptureRetainsPermanentRedirectTargetDeathClosureForFreshReplay() throws {
    let targetID = "00000000-0000-7000-8000-000000000001"
    let middleID = "80000000-0000-7000-8000-000000000002"
    let sourceID = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let targetVersion = replayableVersion(201)
    let middleVersion = replayableVersion(202)
    let sourceVersion = replayableVersion(203)
    var capturedEnvelopes: [SyncEnvelope] = []

    try withDB { db in
      // Preserve an uncompressed on-disk chain so the snapshot must carry the
      // entire death closure, not merely the terminal row of a normalized path.
      try db.execute(
        sql: """
          INSERT INTO sync_entity_redirects
              (source_type, source_id, target_id, version, created_at)
          VALUES
              ('tag', ?, ?, ?, '2024-01-01T00:00:00.000Z'),
              ('tag', ?, ?, ?, '2024-01-01T00:00:00.000Z')
          """,
        arguments: [
          middleID, targetID, replayableVersion(101),
          sourceID, middleID, replayableVersion(102),
        ])
      for (id, stamp) in [
        (targetID, targetVersion), (middleID, middleVersion),
        (sourceID, sourceVersion),
      ] {
        try Tombstone.createTombstone(
          db, entityType: EntityName.tag, entityId: id,
          version: stamp, deletedAt: "2020-01-01T00:00:00.000Z")
        _ = try Tombstone.confirmCloudPresence(
          db,
          confirmation: .init(
            entityType: EntityName.tag, entityId: id, version: stamp,
            confirmedAt: "2024-01-02T00:00:00.000Z"))
      }

      let (binding, authorization) = try prepare(
        db, lease: "redirect-target-death-closure")
      _ = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 1,
        tombstoneCompactionCutoff: "2025-01-01T00:00:00.000Z")
      capturedEnvelopes = try GenerationSnapshot.stagedPage(
        db, binding: binding, offset: 0).envelopes

      let retainedTagDeaths = Set(
        capturedEnvelopes.compactMap {
          $0.entityType == .tag && $0.operation == .delete ? $0.entityId : nil
        })
      XCTAssertEqual(
        retainedTagDeaths, [targetID, middleID],
        "every direct redirect target death is closure state; the source-only death is derivable")
      let compactedIDs = Set(
        try String.fetchAll(
          db,
          sql: """
            SELECT entity_id FROM sync_generation_snapshot_compacted_tombstones
            WHERE lease_identifier = ? AND entity_type = 'tag'
            """,
          arguments: [binding.leaseIdentifier]))
      XCTAssertEqual(compactedIDs, [sourceID])
    }

    // A brand-new physical database must be able to consume the generation
    // without any pre-generation rows. Deletes establish the terminal closure;
    // aliases then apply nearest-target first and path-compress to the terminal.
    try withDB { db in
      let registry = EntityApplierRegistry(
        appliers: EntityApplierRegistry.defaultEntityAppliers())
      for envelope in capturedEnvelopes.filter({ $0.operation == .delete }) {
        let result = try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
        if case .deferred(let reason) = result {
          XCTFail("fresh replay unexpectedly deferred retained death: \(reason)")
        }
      }
      for source in [middleID, sourceID] {
        let wireID = EntityRedirect.wireEntityId(sourceType: .tag, sourceId: source)
        let envelope = try XCTUnwrap(
          capturedEnvelopes.first {
            $0.entityType == .entityRedirect && $0.entityId == wireID
          })
        let result = try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
        if case .deferred(let reason) = result {
          XCTFail("fresh replay unexpectedly deferred redirect: \(reason)")
        }
      }

      XCTAssertEqual(
        try EntityRedirect.get(
          db, sourceType: EntityName.tag, sourceId: sourceID)?.targetId,
        targetID)
      XCTAssertTrue(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.tag, entityId: targetID))
    }
  }

  func testCandidateDeleteReceiptIsLeaseScopedUntilReadyPublication() throws {
    try withDB { db in
      let id = "00000001-0000-7000-8000-000000000111"
      let stamp = version(111)
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: id,
        version: stamp, deletedAt: "2026-01-01T00:00:00.000Z")
      let (binding, authorization) = try prepare(db, lease: "receipt-discard")
      let captured = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 1)
      _ = try GenerationSnapshot.recordUploadProgressAndReceipts(
        db, binding: binding, expectedNextOrdinal: 0,
        nextOrdinal: captured.manifest.recordCount,
        tombstoneConfirmations: [
          .init(
            entityType: EntityName.task, entityId: id, version: stamp,
            confirmedAt: "2026-02-01T00:00:00.000Z")
        ])

      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: id)?.cloudConfirmedAt,
        "an unpublished candidate cannot globally confirm a delete")
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_generation_snapshot_tombstone_receipts
            WHERE lease_identifier = ?
            """,
          arguments: [binding.leaseIdentifier]), 1)

      try GenerationSnapshot.discard(db, binding: binding)
      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: id)?.cloudConfirmedAt)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_generation_snapshot_tombstone_receipts"), 0)
    }
  }

  func testReadyFinalizationPromotesReceiptsAndCompactsOnlyExactCapturedDeletes() throws {
    try withDB { db in
      let unchangedID = "00000001-0000-7000-8000-000000000121"
      let changedID = "00000001-0000-7000-8000-000000000122"
      let retainedID = "00000001-0000-7000-8000-000000000123"
      let oldUnchanged = version(121)
      let oldChanged = version(122)
      let retainedVersion = version(123)
      let newerChanged = version(124)
      for (id, stamp) in [
        (unchangedID, oldUnchanged), (changedID, oldChanged),
        (retainedID, retainedVersion),
      ] {
        try Tombstone.createTombstone(
          db, entityType: EntityName.task, entityId: id,
          version: stamp, deletedAt: "2020-01-01T00:00:00.000Z")
      }
      for (id, stamp) in [(unchangedID, oldUnchanged), (changedID, oldChanged)] {
        _ = try Tombstone.confirmCloudPresence(
          db,
          confirmation: .init(
            entityType: EntityName.task, entityId: id, version: stamp,
            confirmedAt: "2024-01-01T00:00:00.000Z"))
      }
      for (id, stamp) in [
        (unchangedID, oldUnchanged), (changedID, oldChanged),
        (retainedID, retainedVersion),
      ] {
        try SyncTestSupport.insertOutboxEnvelopeUnchecked(
          db,
          SyncEnvelope(
            entityType: .task, entityId: id, operation: .delete,
            version: try Hlc.parse(stamp), payloadSchemaVersion: 1,
            payload: "{}", deviceId: "generation-test-device"))
      }

      let (binding, authorization) = try prepare(db, lease: "compaction-finalize")
      let captured = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 1,
        tombstoneCompactionCutoff: "2025-01-01T00:00:00.000Z")
      let page = try GenerationSnapshot.stagedPage(db, binding: binding, offset: 0)
      let retainedOrdinal = try XCTUnwrap(
        page.envelopes.firstIndex { $0.entityId == retainedID })
      _ = try GenerationSnapshot.recordUploadProgressAndReceipts(
        db, binding: binding, expectedNextOrdinal: 0,
        nextOrdinal: captured.manifest.recordCount,
        tombstoneConfirmations: [
          .init(
            entityType: EntityName.task, entityId: retainedID,
            version: retainedVersion,
            confirmedAt: "2026-02-01T00:00:00.000Z")
        ])
      XCTAssertLessThan(retainedOrdinal, captured.manifest.recordCount)

      // A later callback can reveal an earlier (stronger) receipt for the same
      // exact omitted delete. Finalization must still remove both its tombstone
      // and outbox row; receipt MIN updates are not a new local delete.
      _ = try Tombstone.confirmCloudPresence(
        db,
        confirmation: .init(
          entityType: EntityName.task, entityId: unchangedID,
          version: oldUnchanged, confirmedAt: "2023-01-01T00:00:00.000Z"))

      // A newer local delete after immutable capture must survive late
      // publication; both the old confirmation and old outbox identity are
      // stale at this point.
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: changedID,
        version: newerChanged, deletedAt: "2026-03-01T00:00:00.000Z")
      try Outbox.enqueueCoalesced(
        db,
        try SyncTestSupport.completeEnvelope(
          entityType: .task, entityId: changedID, operation: .delete,
          version: try Hlc.parse(newerChanged), payloadSchemaVersion: 1,
          payload: "{}", deviceId: "generation-test-device"))

      _ = try completeReadback(db, binding: binding)
      try GenerationSnapshot.finalizePublished(db, binding: binding)

      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: unchangedID))
      XCTAssertEqual(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: changedID)?.version,
        newerChanged)
      XCTAssertEqual(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: retainedID)?.cloudConfirmedAt,
        "2026-02-01T00:00:00.000Z")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?",
          arguments: [unchangedID]), 0)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT version FROM sync_outbox WHERE entity_id = ?",
          arguments: [changedID]), newerChanged)
    }
  }

  func testFinalizationRechecksRedirectTargetsAddedAfterImmutableCapture() throws {
    try withDB { db in
      let targetID = "00000000-0000-7000-8000-000000000141"
      let sourceID = "ffffffff-ffff-7fff-8fff-fffffffffff1"
      let targetVersion = replayableVersion(141)
      try Tombstone.createTombstone(
        db, entityType: EntityName.tag, entityId: targetID,
        version: targetVersion, deletedAt: "2020-01-01T00:00:00.000Z")
      _ = try Tombstone.confirmCloudPresence(
        db,
        confirmation: .init(
          entityType: EntityName.tag, entityId: targetID,
          version: targetVersion,
          confirmedAt: "2024-01-01T00:00:00.000Z"))
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(
        db,
        SyncEnvelope(
          entityType: .tag, entityId: targetID, operation: .delete,
          version: try Hlc.parse(targetVersion), payloadSchemaVersion: 1,
          payload: "{}", deviceId: "generation-test-device"))

      let (binding, authorization) = try prepare(
        db, lease: "late-redirect-target-protection")
      _ = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 1,
        tombstoneCompactionCutoff: "2025-01-01T00:00:00.000Z")
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT entity_id FROM sync_generation_snapshot_compacted_tombstones
            WHERE lease_identifier = ? AND entity_type = 'tag'
            """,
          arguments: [binding.leaseIdentifier]),
        targetID)

      // The immutable capture legitimately omitted the death before the alias
      // existed. A later local mutation makes it closure state, so publication
      // finalization must recheck current redirects before physical deletion.
      _ = try EntityRedirect.upsertAndEnqueue(
        db, sourceType: .tag, sourceId: sourceID, targetId: targetID,
        version: replayableVersion(142),
        createdAt: "2024-02-01T00:00:00.000Z",
        deviceId: "generation-test-device")
      _ = try completeReadback(db, binding: binding)
      try GenerationSnapshot.finalizePublished(db, binding: binding)

      XCTAssertTrue(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.tag, entityId: targetID))
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = 'tag' AND entity_id = ?
              AND operation = 'delete'
            """,
          arguments: [targetID]),
        1)
    }
  }

  func testCaptureCountsAndVerifiesPermanentRedirectAsUpsertOnlyState() throws {
    try withDB { db in
      let targetID = "00000000-0000-7000-8000-000000000001"
      let sourceID = "ffffffff-ffff-7fff-8fff-ffffffffffff"
      try db.execute(
        sql: """
          INSERT INTO tags
              (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES (?, 'Canonical', 'canonical', ?, '2026-07-14T00:00:00.000Z',
                  '2026-07-14T00:00:00.000Z')
          """,
        arguments: [targetID, version(1)])
      try Tombstone.createTombstone(
        db, entityType: EntityName.tag, entityId: sourceID,
        version: version(2), deletedAt: "2026-07-14T00:00:00.000Z")
      _ = try EntityRedirect.upsertAndEnqueue(
        db, sourceType: .tag, sourceId: sourceID, targetId: targetID,
        version: version(3), createdAt: "2026-07-14T00:00:00.000Z",
        deviceId: "generation-test-device")
      // The ordinary death ledger excludes the independent upsert-only alias
      // kind at the SQLite boundary, rather than relying only on generation
      // reconstruction to filter a malformed row.
      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
            VALUES (?, ?, ?, '2026-07-14T00:00:00.000Z')
            """,
          arguments: [
            EntityName.entityRedirect,
            EntityRedirect.wireEntityId(sourceType: .tag, sourceId: sourceID),
            version(4),
          ]))

      let (binding, authorization) = try prepare(db)
      let captured = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 12)
      var offset = 0
      var envelopes: [SyncEnvelope] = []
      while true {
        let page = try GenerationSnapshot.stagedPage(
          db, binding: binding, offset: offset)
        envelopes.append(contentsOf: page.envelopes)
        guard let next = page.nextOffset else { break }
        offset = next
      }

      XCTAssertEqual(captured.manifest.recordCount, envelopes.count)
      let redirects = envelopes.filter { $0.entityType == .entityRedirect }
      XCTAssertEqual(redirects.count, 1)
      XCTAssertEqual(redirects.first?.operation, .upsert)
      XCTAssertEqual(
        redirects.first?.entityId,
        EntityRedirect.wireEntityId(sourceType: .tag, sourceId: sourceID))
      XCTAssertFalse(
        envelopes.contains {
          $0.entityType == .entityRedirect && $0.operation == .delete
        })
      let completed = try completeReadback(db, binding: binding)
      XCTAssertTrue(completed.progress.readbackComplete)
      XCTAssertEqual(completed.remoteManifest, captured.manifest)
    }
  }

  func testCountAndByteLimitFailuresAreAtomic() throws {
    try withDB { db in
      try seedTasks(db, count: 3)
      let (binding, authorization) = try prepare(db)
      let countLimits = try GenerationSnapshotCaptureLimits(
        maximumRecordCount: 2, maximumTotalEncodedBytes: 1_000_000)
      XCTAssertThrowsError(
        try GenerationSnapshot.capture(
          db, binding: binding, candidateAuthorization: authorization,
          sourceLocalChangeSequence: 0, limits: countLimits)
      ) { error in
        guard case .recordLimitExceeded(let limit, let observed)? =
          error as? GenerationSnapshotError
        else { return XCTFail("expected record limit failure, got \(error)") }
        XCTAssertEqual(limit, 2)
        XCTAssertGreaterThan(observed, 2)
      }
      XCTAssertNil(try GenerationSnapshot.staging(db, binding: binding))

      let byteLimits = try GenerationSnapshotCaptureLimits(
        maximumRecordCount: 10, maximumTotalEncodedBytes: 1)
      XCTAssertThrowsError(
        try GenerationSnapshot.capture(
          db, binding: binding, candidateAuthorization: authorization,
          sourceLocalChangeSequence: 0, limits: byteLimits)
      ) { error in
        guard case .byteLimitExceeded(let limit, let observed)? =
          error as? GenerationSnapshotError
        else { return XCTFail("expected byte limit failure, got \(error)") }
        XCTAssertEqual(limit, 1)
        XCTAssertGreaterThan(observed, 1)
      }
      XCTAssertNil(try GenerationSnapshot.staging(db, binding: binding))

      let original = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 0)
      let replacementZone = "LorvexData-replacement"
      let replacementAuthorization =
        try AuditRetentionFrontier.authorizeCandidateGeneration(
          db, accountIdentifier: account, candidateZoneName: replacementZone)
      let replacementBinding = try GenerationSnapshotBinding(
        accountIdentifier: account,
        databaseInstanceIdentifier: binding.databaseInstanceIdentifier,
        candidateZoneName: replacementZone, generation: 8,
        generationIdentifier: "generation-8", leaseIdentifier: "replacement-lease",
        leaseOwnerIdentifier: binding.databaseInstanceIdentifier)
      XCTAssertThrowsError(
        try GenerationSnapshot.capture(
          db, binding: replacementBinding,
          candidateAuthorization: replacementAuthorization,
          sourceLocalChangeSequence: 1, limits: byteLimits))
      XCTAssertEqual(
        try GenerationSnapshot.staging(db, binding: binding)?.manifest,
        original.manifest,
        "a failed replacement capture must roll back deletion of the old staging")
    }
  }

  func testCaptureRejectsParseableButNoncanonicalStoredVersions() throws {
    try withDB { db in
      try seedTasks(db, count: 1)
      let (binding, authorization) = try prepare(db)
      let taskID = "00000001-0000-7000-8000-000000000001"
      let unpadded = "6000000000000_1_\(versionSuffix)"
      XCTAssertNoThrow(try Hlc.parse(unpadded), "fixture must remain parseable")

      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: "UPDATE tasks SET version = ? WHERE id = ?",
          arguments: [unpadded, taskID])
      }
      XCTAssertThrowsError(
        try GenerationSnapshot.capture(
          db, binding: binding, candidateAuthorization: authorization,
          sourceLocalChangeSequence: 0)
      ) { error in
        XCTAssertEqual(
          error as? GenerationSnapshotError,
          .invalidStoredVersion(entityType: "task", entityId: taskID, version: unpadded))
      }
      XCTAssertNil(try GenerationSnapshot.staging(db, binding: binding))

      try db.execute(
        sql: "UPDATE tasks SET version = ? WHERE id = ?",
        arguments: [version(1), taskID])
      let deletedID = "00000002-0000-7000-8000-000000000002"
      let uppercase = "6000000000000_0002_1234567890ABCDEF"
      XCTAssertNoThrow(try Hlc.parse(uppercase), "fixture must remain parseable")
      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
            VALUES ('task', ?, ?, '2026-07-14T00:00:00.000Z')
            """,
          arguments: [deletedID, uppercase])
      }
      XCTAssertThrowsError(
        try GenerationSnapshot.capture(
          db, binding: binding, candidateAuthorization: authorization,
          sourceLocalChangeSequence: 0)
      ) { error in
        XCTAssertEqual(
          error as? GenerationSnapshotError,
          .invalidStoredVersion(entityType: "task", entityId: deletedID, version: uppercase))
      }
      XCTAssertNil(try GenerationSnapshot.staging(db, binding: binding))
    }
  }

  func testCaptureRejectsCanonicalVersionAboveOperationalWireCeiling() throws {
    try withDB { db in
      try seedTasks(db, count: 1)
      let (binding, authorization) = try prepare(db)
      let taskID = "00000001-0000-7000-8000-000000000001"
      let above = try Hlc(
        physicalMs: Hlc.maxOperationalWirePhysicalMs + 1, counter: 0,
        deviceSuffix: versionSuffix).description
      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: "UPDATE tasks SET version = ? WHERE id = ?",
          arguments: [above, taskID])
      }

      XCTAssertThrowsError(
        try GenerationSnapshot.capture(
          db, binding: binding, candidateAuthorization: authorization,
          sourceLocalChangeSequence: 0)
      ) { error in
        XCTAssertEqual(
          error as? GenerationSnapshotError,
          .invalidStoredVersion(entityType: "task", entityId: taskID, version: above))
      }
      XCTAssertNil(try GenerationSnapshot.staging(db, binding: binding))
    }
  }

  func testBindingMismatchFailsClosed() throws {
    try withDB { db in
      try seedTasks(db, count: 1)
      let (binding, authorization) = try prepare(db)
      _ = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 0)
      let wrong = try GenerationSnapshotBinding(
        accountIdentifier: account,
        databaseInstanceIdentifier: binding.databaseInstanceIdentifier,
        candidateZoneName: candidateZone, generation: 7,
        generationIdentifier: "generation-7", leaseIdentifier: "wrong-lease",
        leaseOwnerIdentifier: binding.databaseInstanceIdentifier)
      XCTAssertThrowsError(
        try GenerationSnapshot.stagedPage(db, binding: wrong, offset: 0)
      ) { error in
        XCTAssertEqual(error as? GenerationSnapshotError, .bindingMismatch)
      }
      XCTAssertThrowsError(
        try GenerationSnapshotBinding(
          accountIdentifier: account,
          databaseInstanceIdentifier: binding.databaseInstanceIdentifier,
          candidateZoneName: candidateZone, generation: 7,
          generationIdentifier: "generation-7", leaseIdentifier: "lease",
          leaseOwnerIdentifier: "another-database")
      ) { error in
        XCTAssertEqual(error as? GenerationSnapshotError, .invalidBinding)
      }
    }
  }

  func testInitialActiveAuthorizationCapturesBootstrapGeneration() throws {
    try withDB { db in
      try seedTasks(db, count: 1)
      let cloudBinding = try CloudTraversalWitness.claimAccount(
        db, accountIdentifier: account)
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: account, zoneName: candidateZone)
      let authorization = try AuditRetentionFrontier.authorizeOutboundAuditPush(
        db, accountIdentifier: account, zoneName: candidateZone,
        verifiedRemoteFrontier: .initial)
      let binding = try GenerationSnapshotBinding(
        accountIdentifier: account,
        databaseInstanceIdentifier: cloudBinding.databaseInstanceIdentifier,
        candidateZoneName: candidateZone, generation: 1,
        generationIdentifier: "bootstrap-generation",
        leaseIdentifier: "bootstrap-lease",
        leaseOwnerIdentifier: cloudBinding.databaseInstanceIdentifier)
      let staging = try GenerationSnapshot.capture(
        db, binding: binding, authorization: authorization,
        sourceLocalChangeSequence: 1)
      XCTAssertGreaterThanOrEqual(staging.manifest.recordCount, 1)
      XCTAssertEqual(
        try GenerationSnapshot.stagedPage(db, binding: binding, offset: 0).manifest,
        staging.manifest)
    }
  }

  func testCompactReadbackSupportsOverwriteDeletionCompletionAndCleanup() throws {
    try withDB { db in
      try seedTasks(db, count: 2)
      let (binding, authorization) = try prepare(db)
      let captured = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 5)
      let page = try GenerationSnapshot.stagedPage(db, binding: binding, offset: 0)
      let sourceWitnesses = try page.envelopes.map(GenerationSnapshot.witness(for:))
      var modifiedEnvelope = page.envelopes[0]
      modifiedEnvelope.deviceId = "different-readback-device"
      let modified = try GenerationSnapshot.witness(for: modifiedEnvelope)

      _ = try GenerationSnapshot.applyReadbackChanges(
        db, binding: binding, witnesses: [sourceWitnesses[0]],
        deletedRecordNames: [])
      _ = try GenerationSnapshot.applyReadbackChanges(
        db, binding: binding, witnesses: [sourceWitnesses[0], modified],
        deletedRecordNames: [])
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: "SELECT envelope_digest FROM sync_generation_snapshot_readback_items"),
        modified.envelopeDigest,
        "same-name later observation must represent final zone state")
      _ = try GenerationSnapshot.applyReadbackChanges(
        db, binding: binding, witnesses: [],
        deletedRecordNames: [modified.recordName])
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_generation_snapshot_readback_items"),
        0)

      _ = try GenerationSnapshot.resetReadbackProgress(db, binding: binding)
      let completed = try GenerationSnapshot.recordReadbackPage(
        db, binding: binding, expectedPageIndex: 0,
        witnesses: sourceWitnesses, deletedRecordNames: [],
        continuationToken: Data([0x01, 0x02]),
        observedTraversalWitness: true, terminal: true)
      XCTAssertEqual(completed.remoteManifest, captured.manifest)
      XCTAssertEqual(completed.progress.readbackPageIndex, 1)
      XCTAssertTrue(completed.progress.readbackComplete)
      XCTAssertTrue(completed.progress.readbackWitnessObserved)

      try GenerationSnapshot.discard(db, binding: binding)
      XCTAssertNil(try GenerationSnapshot.staging(db, binding: binding))
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM audit_retention_candidate_authorization"),
        0)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_generation_snapshot_items"), 0)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_generation_snapshot_readback_items"), 0)
    }
  }

  func testCandidateFinalizeRequiresExactRemoteManifestAndActivatesAtomically() throws {
    try withDB { db in
      try seedTasks(db, count: 1)
      let (binding, authorization) = try prepare(db)
      let captured = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 3)
      let completed = try completeReadback(db, binding: binding)
      XCTAssertEqual(completed.remoteManifest, captured.manifest)
      XCTAssertEqual(try GenerationSnapshot.currentStaging(db)?.binding, binding)

      try db.execute(
        sql: """
          CREATE TEMP TRIGGER fail_generation_snapshot_cleanup
          BEFORE DELETE ON sync_generation_snapshot_staging
          BEGIN
            SELECT RAISE(ABORT, 'simulated cleanup crash');
          END
          """)
      XCTAssertThrowsError(
        try GenerationSnapshot.finalizePublished(db, binding: binding))
      try db.execute(sql: "DROP TRIGGER fail_generation_snapshot_cleanup")

      XCTAssertEqual(try AuditRetentionFrontier.activeZoneName(db), sourceZone)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM audit_retention_candidate_authorization"),
        1,
        "failed cleanup must roll candidate activation back")
      XCTAssertEqual(try GenerationSnapshot.currentStaging(db)?.binding, binding)

      let recovered = try XCTUnwrap(GenerationSnapshot.currentStaging(db))
      try GenerationSnapshot.finalizePublished(db, binding: recovered.binding)
      XCTAssertEqual(try AuditRetentionFrontier.activeAccountIdentifier(db), account)
      XCTAssertEqual(try AuditRetentionFrontier.activeZoneName(db), candidateZone)
      XCTAssertNil(try GenerationSnapshot.currentStaging(db))
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM audit_retention_candidate_authorization"),
        0)
      XCTAssertThrowsError(
        try GenerationSnapshot.finalizePublished(db, binding: binding)
      ) { error in
        XCTAssertEqual(error as? GenerationSnapshotError, .stagingNotFound)
      }
    }
  }

  func testActiveFinalizePreservesActiveRoutingAuthorization() throws {
    try withDB { db in
      try seedTasks(db, count: 1)
      let (binding, authorization) = try prepareActive(db)
      _ = try GenerationSnapshot.capture(
        db, binding: binding, authorization: authorization,
        sourceLocalChangeSequence: 1)
      _ = try completeReadback(db, binding: binding)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM audit_retention_outbound_authorization"),
        1)

      try GenerationSnapshot.finalizePublished(db, binding: binding)

      XCTAssertEqual(try AuditRetentionFrontier.activeAccountIdentifier(db), account)
      XCTAssertEqual(try AuditRetentionFrontier.activeZoneName(db), candidateZone)
      XCTAssertNil(try GenerationSnapshot.currentStaging(db))
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM audit_retention_outbound_authorization"),
        1,
        "active bootstrap finalization must not revoke ordinary outbound")
    }
  }

  func testActiveFinalizeRejectsAChangedActiveContext() throws {
    try withDB { db in
      let (binding, authorization) = try prepareActive(db)
      _ = try GenerationSnapshot.capture(
        db, binding: binding, authorization: authorization,
        sourceLocalChangeSequence: 0)
      _ = try completeReadback(db, binding: binding)
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: account, zoneName: "different-active-zone")

      XCTAssertThrowsError(
        try GenerationSnapshot.finalizePublished(db, binding: binding)
      ) { error in
        XCTAssertEqual(error as? GenerationSnapshotError, .bindingMismatch)
      }
      XCTAssertEqual(
        try AuditRetentionFrontier.activeZoneName(db), "different-active-zone")
      XCTAssertEqual(try GenerationSnapshot.currentStaging(db)?.binding, binding)

      try GenerationSnapshot.discard(db, binding: binding)
      XCTAssertEqual(
        try AuditRetentionFrontier.activeZoneName(db), "different-active-zone")
    }
  }

  func testFinalizeRejectsIncompleteAndMismatchedReadbackWithoutCleanup() throws {
    try withDB { db in
      try seedTasks(db, count: 1)
      let (binding, authorization) = try prepare(db)
      _ = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 2)

      XCTAssertThrowsError(
        try GenerationSnapshot.finalizePublished(db, binding: binding)
      ) { error in
        XCTAssertEqual(error as? GenerationSnapshotError, .manifestMismatch)
      }
      XCTAssertEqual(try AuditRetentionFrontier.activeZoneName(db), sourceZone)
      XCTAssertNotNil(try GenerationSnapshot.currentStaging(db))

      let mismatched = try completeReadback(
        db, binding: binding
      ) { envelopes in
        envelopes[0].deviceId = "different-readback-device"
      }
      XCTAssertNotEqual(mismatched.remoteManifest, mismatched.manifest)
      XCTAssertThrowsError(
        try GenerationSnapshot.finalizePublished(db, binding: binding)
      ) { error in
        XCTAssertEqual(error as? GenerationSnapshotError, .manifestMismatch)
      }
      XCTAssertEqual(try AuditRetentionFrontier.activeZoneName(db), sourceZone)
      XCTAssertNotNil(try GenerationSnapshot.currentStaging(db))
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM audit_retention_candidate_authorization"),
        1)
    }
  }

  func testFinalizeRejectsNoncanonicalPersistedRetentionMetadata() throws {
    try withDB { db in
      let (binding, authorization) = try prepare(db)
      _ = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 0)
      _ = try completeReadback(db, binding: binding)
      try db.execute(
        sql: """
          UPDATE sync_generation_snapshot_staging
          SET retention_policy_value = 'unrecognized'
          WHERE lease_identifier = ?
          """,
        arguments: [binding.leaseIdentifier])

      XCTAssertThrowsError(
        try GenerationSnapshot.finalizePublished(db, binding: binding)
      ) { error in
        XCTAssertEqual(error as? GenerationSnapshotError, .corruptStaging)
      }
      XCTAssertEqual(try AuditRetentionFrontier.activeZoneName(db), sourceZone)
      XCTAssertEqual(try GenerationSnapshot.currentStaging(db)?.binding, binding)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM audit_retention_candidate_authorization"),
        1)
    }
  }

  func testFinalizeAndDiscardRejectEveryMismatchedBindingField() throws {
    try withDB { db in
      let (binding, authorization) = try prepare(db)
      _ = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 0)
      _ = try completeReadback(db, binding: binding)
      let mismatches = [
        try GenerationSnapshotBinding(
          accountIdentifier: "different-account",
          databaseInstanceIdentifier: binding.databaseInstanceIdentifier,
          candidateZoneName: binding.candidateZoneName,
          generation: binding.generation,
          generationIdentifier: binding.generationIdentifier,
          leaseIdentifier: binding.leaseIdentifier,
          leaseOwnerIdentifier: binding.leaseOwnerIdentifier),
        try GenerationSnapshotBinding(
          accountIdentifier: binding.accountIdentifier,
          databaseInstanceIdentifier: "different-database",
          candidateZoneName: binding.candidateZoneName,
          generation: binding.generation,
          generationIdentifier: binding.generationIdentifier,
          leaseIdentifier: binding.leaseIdentifier,
          leaseOwnerIdentifier: "different-database"),
        try GenerationSnapshotBinding(
          accountIdentifier: binding.accountIdentifier,
          databaseInstanceIdentifier: binding.databaseInstanceIdentifier,
          candidateZoneName: "different-zone",
          generation: binding.generation,
          generationIdentifier: binding.generationIdentifier,
          leaseIdentifier: binding.leaseIdentifier,
          leaseOwnerIdentifier: binding.leaseOwnerIdentifier),
        try GenerationSnapshotBinding(
          accountIdentifier: binding.accountIdentifier,
          databaseInstanceIdentifier: binding.databaseInstanceIdentifier,
          candidateZoneName: binding.candidateZoneName,
          generation: binding.generation + 1,
          generationIdentifier: binding.generationIdentifier,
          leaseIdentifier: binding.leaseIdentifier,
          leaseOwnerIdentifier: binding.leaseOwnerIdentifier),
        try GenerationSnapshotBinding(
          accountIdentifier: binding.accountIdentifier,
          databaseInstanceIdentifier: binding.databaseInstanceIdentifier,
          candidateZoneName: binding.candidateZoneName,
          generation: binding.generation,
          generationIdentifier: "different-generation",
          leaseIdentifier: binding.leaseIdentifier,
          leaseOwnerIdentifier: binding.leaseOwnerIdentifier),
        try GenerationSnapshotBinding(
          accountIdentifier: binding.accountIdentifier,
          databaseInstanceIdentifier: binding.databaseInstanceIdentifier,
          candidateZoneName: binding.candidateZoneName,
          generation: binding.generation,
          generationIdentifier: binding.generationIdentifier,
          leaseIdentifier: "different-lease",
          leaseOwnerIdentifier: binding.leaseOwnerIdentifier),
      ]

      for wrong in mismatches {
        for operation in [
          { try GenerationSnapshot.finalizePublished(db, binding: wrong) },
          { try GenerationSnapshot.discard(db, binding: wrong) },
        ] {
          XCTAssertThrowsError(try operation()) { error in
            XCTAssertEqual(error as? GenerationSnapshotError, .bindingMismatch)
          }
        }
      }
      XCTAssertEqual(try AuditRetentionFrontier.activeZoneName(db), sourceZone)
      XCTAssertEqual(try GenerationSnapshot.currentStaging(db)?.binding, binding)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM audit_retention_candidate_authorization"),
        1)
    }
  }

  func testCandidateDiscardRecoversAfterAuthorizationWasAlreadyRevoked() throws {
    try withDB { db in
      let (binding, authorization) = try prepare(db)
      _ = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 0)
      try AuditRetentionFrontier.revokeCandidateGeneration(
        db, authorization: authorization)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM audit_retention_candidate_authorization"),
        0)
      let recovered = try XCTUnwrap(GenerationSnapshot.currentStaging(db))

      try GenerationSnapshot.discard(db, binding: recovered.binding)

      XCTAssertNil(try GenerationSnapshot.currentStaging(db))
      XCTAssertEqual(try AuditRetentionFrontier.activeZoneName(db), sourceZone)
    }
  }

  func testCandidateDiscardRevocationAndCleanupAreAtomic() throws {
    try withDB { db in
      let (binding, authorization) = try prepare(db)
      _ = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 0)
      try db.execute(
        sql: """
          CREATE TEMP TRIGGER fail_generation_snapshot_discard
          BEFORE DELETE ON sync_generation_snapshot_staging
          BEGIN
            SELECT RAISE(ABORT, 'simulated cleanup crash');
          END
          """)

      XCTAssertThrowsError(try GenerationSnapshot.discard(db, binding: binding))
      try db.execute(sql: "DROP TRIGGER fail_generation_snapshot_discard")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM audit_retention_candidate_authorization"),
        1,
        "failed staging cleanup must roll candidate revocation back")
      XCTAssertNotNil(try GenerationSnapshot.currentStaging(db))

      try GenerationSnapshot.discard(db, binding: binding)
      XCTAssertNil(try GenerationSnapshot.currentStaging(db))
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM audit_retention_candidate_authorization"),
        0)
    }
  }

  func testLossyRetentionWaitsForGenerationStagingToFinish() throws {
    try withDB { db in
      let (binding, authorization) = try prepare(
        db, lease: "retention-exclusion")
      _ = try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: 0)
      try db.execute(
        sql: """
          INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            envelope_entity_type, envelope_entity_id, envelope_version,
            first_attempted_at, last_attempted_at, attempt_count
          ) VALUES (
            '{}', 'fk_unresolved', 'task', 'missing-parent',
            'task_reminder', 'expired-child',
            '1711234567890_0000_a1b2c3d4a1b2c3d4',
            '2020-01-01T00:00:00.000Z', '2020-01-01T00:00:00.000Z', 1
          )
          """)
      for index in 0..<3 {
        try SyncTestSupport.insertOutboxEnvelopeUnchecked(
          db,
          SyncEnvelope(
            entityType: .task,
            entityId: String(
              format: "01966a3f-7c8b-7d4e-8f3a-%012d", index + 1),
            operation: .upsert,
            version: try Hlc.parse(
              "171123456789\(index)_0000_a1b2c3d4a1b2c3d4"),
            payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
            payload: #"{"title":"test"}"#, deviceId: "device-A"))
      }

      SyncRetention.runPostApplyGC(
        db, syncedAt: "2026-07-17T00:00:00.000Z")
      XCTAssertEqual(try PendingInbox.countPending(db), 1)
      XCTAssertNil(
        try SyncCheckpoints.get(
          db, key: SyncNaming.reseedRequiredCheckpointKey))
      XCTAssertEqual(
        try SyncRetention.gcActiveOutboxAndFlagReseed(
          db, maxRows: 2, syncedAt: "2026-07-17T00:00:00.000Z"),
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE synced_at IS NULL AND disposition IS NULL
            """),
        3)

      try GenerationSnapshot.discard(db, binding: binding)
      SyncRetention.runPostApplyGC(
        db, syncedAt: "2026-07-17T00:00:00.000Z")
      XCTAssertEqual(try PendingInbox.countPending(db), 0)
      XCTAssertEqual(
        try SyncCheckpoints.get(
          db, key: SyncNaming.reseedRequiredCheckpointKey),
        "true")
      try db.execute(
        sql: "DELETE FROM sync_checkpoints WHERE key = ?",
        arguments: [SyncNaming.reseedRequiredCheckpointKey])
      XCTAssertEqual(
        try SyncRetention.gcActiveOutboxAndFlagReseed(
          db, maxRows: 2, syncedAt: "2026-07-17T00:00:00.000Z"),
        1)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE synced_at IS NULL AND disposition IS NULL
            """),
        2)
    }
  }

  func testActiveDiscardNeverRevokesActiveAuthorizationOrRouting() throws {
    try withDB { db in
      let (binding, authorization) = try prepareActive(db)
      _ = try GenerationSnapshot.capture(
        db, binding: binding, authorization: authorization,
        sourceLocalChangeSequence: 0)

      try GenerationSnapshot.discard(db, binding: binding)

      XCTAssertNil(try GenerationSnapshot.currentStaging(db))
      XCTAssertEqual(try AuditRetentionFrontier.activeZoneName(db), candidateZone)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM audit_retention_outbound_authorization"),
        1)
    }
  }
}
