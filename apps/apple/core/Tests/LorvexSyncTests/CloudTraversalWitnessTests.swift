import Foundation
import GRDB
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class CloudTraversalWitnessTests: XCTestCase {
  private let accountA = "account-a"
  private let accountB = "account-b"
  private let zone1 = "LorvexZone-g1"
  private let zone2 = "LorvexZone-g2"
  private let startedAt = "2026-07-14T10:00:00.000Z"
  private let completedAt = "2026-07-14T10:05:00.000Z"

  private func boundary(
    account: String = "account-a", zone: String = "LorvexZone-g1", generation: Int = 1,
    generationIdentifier: String? = nil, readyWitness: String? = nil,
    tombstoneCompactionCutoff: String? = nil
  ) throws -> CloudTraversalBoundary {
    try CloudTraversalBoundary(
      accountIdentifier: account, zoneIdentifier: zone, generation: generation,
      generationIdentifier: generationIdentifier ?? "generation-\(generation)",
      readyWitness: readyWitness ?? "ready-\(generation)",
      tombstoneCompactionCutoff: tombstoneCompactionCutoff)
  }

  private func proof(
    _ boundary: CloudTraversalBoundary, traversalIdentifier: String
  ) throws -> CloudTraversalPageObservation {
    try CloudTraversalPageObservation(
      generationRootIdentifier: boundary.generationIdentifier,
      readyWitness: boundary.readyWitness,
      traversalWitnessIdentifier: traversalIdentifier)
  }

  private func claim(_ db: Database, account: String = "account-a") throws {
    _ = try CloudTraversalWitness.claimAccount(
      db, accountIdentifier: account, boundAt: startedAt)
  }

  func testAccountBindingIsDatabaseBoundAndAccountSwitchIsExplicit() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try claim(db)
      let first = try XCTUnwrap(CloudTraversalWitness.accountBinding(db))
      XCTAssertEqual(first.accountIdentifier, accountA)
      XCTAssertEqual(first.boundAt, startedAt)
      XCTAssertEqual(
        first.databaseInstanceIdentifier,
        try SyncCheckpoints.get(db, key: SyncCheckpoints.keyDatabaseInstanceId))

      XCTAssertThrowsError(
        try CloudTraversalWitness.claimAccount(
          db, accountIdentifier: accountB, boundAt: startedAt)
      ) { error in
        XCTAssertEqual(
          error as? CloudTraversalStateError,
          .accountBoundaryMismatch(expected: self.accountA, actual: self.accountB))
      }

      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, list_id, version, created_at, updated_at)
          VALUES ('claimed-task', 'Claim owner', 'inbox',
                  '0000000000000_0000_0000000000000000',
                  '2026-07-14T10:00:00.000Z', '2026-07-14T10:00:00.000Z')
          """)
      try db.execute(
        sql: """
          INSERT INTO sync_list_fallback_reemit_claims (task_id, payload_list_id)
          VALUES ('claimed-task', 'old-account-list')
          """)

      let adopted = try CloudTraversalWitness.adoptAccount(
        db, expectedCurrentAccountIdentifier: accountA,
        newAccountIdentifier: accountB, boundAt: completedAt)
      XCTAssertEqual(adopted.accountIdentifier, accountB)
      XCTAssertEqual(adopted.boundAt, completedAt)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_list_fallback_reemit_claims"), 0,
        "an account switch must not carry peer-convergence claims into the new zone lineage")
      XCTAssertThrowsError(
        try CloudTraversalWitness.adoptAccount(
          db, expectedCurrentAccountIdentifier: accountA,
          newAccountIdentifier: accountB, boundAt: completedAt)
      ) { error in
        XCTAssertEqual(
          error as? CloudTraversalStateError, .accountBindingCompareAndSwapFailed)
      }
    }
  }

  func testMissingBindingCannotReclaimOrphanedTraversalProof() throws {
    let store = try SyncTestSupport.freshStore()
    let boundary = try boundary()
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: "orphaned", start: .baseline,
        startedAt: startedAt)
      try CloudTraversalWitness.cancel(
        db, boundary: boundary, traversalIdentifier: "orphaned")
      try db.execute(sql: "DELETE FROM sync_cloudkit_account_binding")

      XCTAssertThrowsError(
        try CloudTraversalWitness.claimAccount(
          db, accountIdentifier: self.accountA, boundAt: self.completedAt)
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .malformedStoredState)
      }
      XCTAssertNil(try CloudTraversalWitness.accountBinding(db))
    }
  }

  func testContinuationAndTerminalWitnessAreStrictlySequenced() throws {
    let store = try SyncTestSupport.freshStore()
    let boundary = try boundary()
    let firstToken = Data([0x01, 0x02])
    let finalToken = Data([0x03, 0x04])
    try store.writer.write { db in
      try claim(db)
      let begun = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: "traversal-1", start: .baseline,
        startedAt: startedAt)
      XCTAssertEqual(begun.nextPageIndex, 0)
      XCTAssertNil(begun.continuationToken)

      let firstPage = try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: firstToken, moreComing: true,
        observation: try CloudTraversalPageObservation(
          generationRootIdentifier: boundary.generationIdentifier))
      XCTAssertEqual(
        try CloudTraversalWitness.preflightPage(
          db, boundary: boundary, traversalIdentifier: "traversal-1", page: firstPage),
        .new)
      guard
        case .continuationRecorded(let progress) = try CloudTraversalWitness.commitPage(
          db, boundary: boundary, traversalIdentifier: "traversal-1", page: firstPage)
      else { return XCTFail("expected a durable continuation") }
      XCTAssertEqual(progress.nextPageIndex, 1)
      XCTAssertEqual(progress.continuationToken, firstToken)

      XCTAssertEqual(
        try CloudTraversalWitness.preflightPage(
          db, boundary: boundary, traversalIdentifier: "traversal-1", page: firstPage),
        .alreadyRecorded)
      XCTAssertEqual(
        try CloudTraversalWitness.commitPage(
          db, boundary: boundary, traversalIdentifier: "traversal-1", page: firstPage),
        .alreadyRecorded)
      XCTAssertThrowsError(
        try CloudTraversalWitness.commitPage(
          db, boundary: boundary, traversalIdentifier: "traversal-1",
          page: try CloudTraversalPageCommit(
            pageIndex: 0, continuationToken: Data([0xff]), moreComing: true))
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .continuationMismatch)
      }

      let terminal = try CloudTraversalPageCommit(
        pageIndex: 1, continuationToken: finalToken, moreComing: false,
        observation: try CloudTraversalPageObservation(
          readyWitness: boundary.readyWitness,
          traversalWitnessIdentifier: "traversal-1"))
      guard
        case .baselineCompleted(let completion) = try CloudTraversalWitness.commitPage(
          db, boundary: boundary, traversalIdentifier: "traversal-1",
          page: terminal, completedAt: completedAt)
      else { return XCTFail("expected a terminal witness") }
      XCTAssertEqual(completion.completedPageCount, 2)
      XCTAssertEqual(completion.finalChangeToken, finalToken)
      XCTAssertEqual(completion.completedAt, completedAt)

      let state = try CloudTraversalWitness.state(
        db, accountIdentifier: accountA, zoneIdentifier: zone1)
      XCTAssertNil(state.progress)
      XCTAssertEqual(state.baselineWitness, completion)
      XCTAssertEqual(
        try CloudTraversalWitness.preflightPage(
          db, boundary: boundary, traversalIdentifier: "traversal-1", page: terminal),
        .alreadyBaselineCompleted(completion))
      XCTAssertEqual(
        try CloudTraversalWitness.commitPage(
          db, boundary: boundary, traversalIdentifier: "traversal-1",
          page: terminal, completedAt: completedAt),
        .alreadyBaselineCompleted(completion))
    }
  }

  func testServerWitnessTimeBecomesRecoveryAuthorityOnlyAtTerminalCommit() throws {
    let store = try SyncTestSupport.freshStore()
    let boundary = try boundary()
    let traversal = "server-watermark"
    let serverTime = "2026-07-14T09:59:00.000Z"
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: traversal, start: .baseline,
        startedAt: startedAt)

      _ = try CloudTraversalWitness.commitPage(
        db, boundary: boundary, traversalIdentifier: traversal,
        page: try CloudTraversalPageCommit(
          pageIndex: 0, continuationToken: Data([0x11]), moreComing: true,
          observation: try CloudTraversalPageObservation(
            generationRootIdentifier: boundary.generationIdentifier,
            traversalWitnessIdentifier: traversal,
            traversalWitnessServerTime: serverTime)))

      XCTAssertFalse(
        try Tombstone.trustedTerminalServerTimeCovers(
          db, accountIdentifier: accountA, cutoff: serverTime),
        "a nonterminal page cannot authorize compaction-window recovery")
      XCTAssertEqual(
        try CloudTraversalWitness.state(
          db, accountIdentifier: accountA, zoneIdentifier: zone1)
          .progress?.observedTraversalWitnessServerTime,
        serverTime)

      _ = try CloudTraversalWitness.commitPage(
        db, boundary: boundary, traversalIdentifier: traversal,
        page: try CloudTraversalPageCommit(
          pageIndex: 1, continuationToken: Data([0x12]), moreComing: false,
          observation: try CloudTraversalPageObservation(
            readyWitness: boundary.readyWitness)),
        completedAt: "2099-01-01T00:00:00.000Z")

      XCTAssertFalse(
        try Tombstone.trustedTerminalServerTimeCovers(
          db, accountIdentifier: accountA, cutoff: serverTime),
        "equal millisecond timestamps cannot prove which event happened first")
      XCTAssertTrue(
        try Tombstone.trustedTerminalServerTimeCovers(
          db, accountIdentifier: accountA,
          cutoff: "2026-07-14T09:58:59.999Z"))
      XCTAssertFalse(
        try Tombstone.trustedTerminalServerTimeCovers(
          db, accountIdentifier: accountA,
          cutoff: "2026-07-14T09:59:00.001Z"),
        "the device-owned completedAt value cannot advance the server watermark")

      _ = try CloudTraversalWitness.adoptAccount(
        db, expectedCurrentAccountIdentifier: accountA,
        newAccountIdentifier: accountB, boundAt: completedAt)
      XCTAssertFalse(
        try Tombstone.trustedTerminalServerTimeCovers(
          db, accountIdentifier: accountB, cutoff: serverTime),
        "account adoption clears the old account's terminal authority")
    }
  }

  func testCompletedWitnessSurvivesLaterInProgressTraversal() throws {
    let store = try SyncTestSupport.freshStore()
    let boundary = try boundary()
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: "traversal-1", start: .baseline,
        startedAt: startedAt)
      _ = try CloudTraversalWitness.commitPage(
        db, boundary: boundary, traversalIdentifier: "traversal-1",
        page: try CloudTraversalPageCommit(
          pageIndex: 0, continuationToken: Data([0x01]), moreComing: false,
          observation: try proof(boundary, traversalIdentifier: "traversal-1")),
        completedAt: completedAt)
      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: "traversal-2", start: .baseline,
        startedAt: completedAt)

      let state = try CloudTraversalWitness.state(
        db, accountIdentifier: accountA, zoneIdentifier: zone1)
      XCTAssertEqual(state.progress?.traversalIdentifier, "traversal-2")
      XCTAssertEqual(state.baselineWitness?.traversalIdentifier, "traversal-1")
    }
  }

  func testGenerationFenceRejectsStaleOrConflictingZone() throws {
    let store = try SyncTestSupport.freshStore()
    let generation2 = try boundary(zone: zone2, generation: 2)
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: generation2, traversalIdentifier: "traversal-g2", start: .baseline,
        startedAt: startedAt)
      _ = try CloudTraversalWitness.commitPage(
        db, boundary: generation2, traversalIdentifier: "traversal-g2",
        page: try CloudTraversalPageCommit(
          pageIndex: 0, continuationToken: nil, moreComing: false,
          observation: try proof(generation2, traversalIdentifier: "traversal-g2")),
        completedAt: completedAt)

      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db, boundary: try self.boundary(generation: 1),
          traversalIdentifier: "stale", start: .baseline, startedAt: startedAt)
      ) { error in
        XCTAssertEqual(
          error as? CloudTraversalStateError, .staleGeneration(current: 2, attempted: 1))
      }
      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db, boundary: try self.boundary(zone: "different-g2", generation: 2),
          traversalIdentifier: "conflict", start: .baseline, startedAt: startedAt)
      ) { error in
        XCTAssertEqual(
          error as? CloudTraversalStateError,
          .generationDescriptorConflict(generation: 2))
      }
      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db,
          boundary: try self.boundary(
            zone: self.zone2, generation: 2,
            tombstoneCompactionCutoff: "2026-07-14T00:00:00.000Z"),
          traversalIdentifier: "cutoff-conflict", start: .baseline,
          startedAt: self.startedAt)
      ) { error in
        XCTAssertEqual(
          error as? CloudTraversalStateError,
          .generationDescriptorConflict(generation: 2))
      }
      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db,
          boundary: try self.boundary(
            zone: self.zone2, generation: 2, generationIdentifier: "different-generation"),
          traversalIdentifier: "generation-id-conflict", start: .baseline,
          startedAt: self.startedAt)
      ) { error in
        XCTAssertEqual(
          error as? CloudTraversalStateError,
          .generationDescriptorConflict(generation: 2))
      }
      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db,
          boundary: try self.boundary(
            zone: self.zone2, generation: 2, readyWitness: "different-ready"),
          traversalIdentifier: "ready-conflict", start: .baseline,
          startedAt: self.startedAt)
      ) { error in
        XCTAssertEqual(
          error as? CloudTraversalStateError,
          .generationDescriptorConflict(generation: 2))
      }
      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db, boundary: try self.boundary(zone: self.zone2, generation: 3),
          traversalIdentifier: "zone-reuse", start: .baseline,
          startedAt: self.startedAt)
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .generationZoneReuse)
      }
    }
  }

  func testCanceledTraversalCannotEraseGenerationOrHistoricalZoneFence() throws {
    let store = try SyncTestSupport.freshStore()
    let generation1 = try boundary()
    let generation2 = try boundary(zone: zone2, generation: 2)
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: generation1, traversalIdentifier: "generation-1", start: .baseline,
        startedAt: startedAt)
      try CloudTraversalWitness.cancel(
        db, boundary: generation1, traversalIdentifier: "generation-1")
      _ = try CloudTraversalWitness.begin(
        db, boundary: generation2, traversalIdentifier: "generation-2", start: .baseline,
        startedAt: completedAt)
      try CloudTraversalWitness.cancel(
        db, boundary: generation2, traversalIdentifier: "generation-2")

      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db, boundary: generation1, traversalIdentifier: "rollback", start: .baseline,
          startedAt: completedAt)
      ) { error in
        XCTAssertEqual(
          error as? CloudTraversalStateError,
          .staleGeneration(current: 2, attempted: 1))
      }
      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db, boundary: try self.boundary(zone: self.zone1, generation: 3),
          traversalIdentifier: "reuse-retired-zone", start: .baseline,
          startedAt: self.completedAt)
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .generationZoneReuse)
      }
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_cloudkit_generation_descriptor"),
        2)
    }
  }

  func testCancelRemovesOnlyTheExactTraversalProgress() throws {
    let store = try SyncTestSupport.freshStore()
    let boundary = try boundary()
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: "cancel-exact", start: .baseline,
        startedAt: startedAt)

      try CloudTraversalWitness.cancel(
        db, boundary: boundary, traversalIdentifier: "different-traversal")
      XCTAssertEqual(
        try CloudTraversalWitness.state(
          db, accountIdentifier: accountA, zoneIdentifier: zone1
        ).progress?.traversalIdentifier,
        "cancel-exact")

      try CloudTraversalWitness.cancel(
        db, boundary: boundary, traversalIdentifier: "cancel-exact")
      XCTAssertNil(
        try CloudTraversalWitness.state(
          db, accountIdentifier: accountA, zoneIdentifier: zone1
        ).progress)
    }
  }

  func testBaselineRequiresExactRemoteRootSealAndTraversalWitness() throws {
    let store = try SyncTestSupport.freshStore()
    let boundary = try boundary()
    let traversal = "proof-required"
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: traversal, start: .baseline,
        startedAt: startedAt)
      func terminal(_ observation: CloudTraversalPageObservation) throws
        -> CloudTraversalCommitResult
      {
        try CloudTraversalWitness.commitPage(
          db, boundary: boundary, traversalIdentifier: traversal,
          page: try CloudTraversalPageCommit(
            pageIndex: 0, continuationToken: Data([0xd1]), moreComing: false,
            observation: observation),
          completedAt: completedAt)
      }

      XCTAssertThrowsError(try terminal(.none)) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .baselineProofIncomplete)
      }
      XCTAssertThrowsError(
        try terminal(
          CloudTraversalPageObservation(generationRootIdentifier: "wrong-generation"))
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .generationRootMismatch)
      }
      XCTAssertThrowsError(
        try terminal(CloudTraversalPageObservation(readyWitness: "wrong-ready"))
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .readyWitnessMismatch)
      }
      XCTAssertThrowsError(
        try terminal(
          CloudTraversalPageObservation(traversalWitnessIdentifier: "wrong-traversal"))
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .traversalWitnessMismatch)
      }

      guard
        case .baselineCompleted = try terminal(
          proof(boundary, traversalIdentifier: traversal))
      else { return XCTFail("exact remote proof should complete the baseline") }
    }
  }

  func testDatabaseInstanceMismatchFailsClosed() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: try boundary(), traversalIdentifier: "traversal-1", start: .baseline,
        startedAt: startedAt)
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyDatabaseInstanceId, value: "replacement")
      XCTAssertThrowsError(try CloudTraversalWitness.accountBinding(db)) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .databaseInstanceMismatch)
      }
      XCTAssertThrowsError(
        try CloudTraversalWitness.state(
          db, accountIdentifier: self.accountA, zoneIdentifier: self.zone1)
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .databaseInstanceMismatch)
      }
    }
  }

  func testSemanticallyMalformedStoredTimestampFailsClosed() throws {
    let store = try SyncTestSupport.freshStore()
    let boundary = try boundary()
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: "traversal-1", start: .baseline,
        startedAt: startedAt)
      _ = try CloudTraversalWitness.commitPage(
        db, boundary: boundary, traversalIdentifier: "traversal-1",
        page: try CloudTraversalPageCommit(
          pageIndex: 0, continuationToken: nil, moreComing: false,
          observation: try proof(boundary, traversalIdentifier: "traversal-1")),
        completedAt: completedAt)
      try db.execute(
        sql: "UPDATE sync_cloudkit_traversal_witness SET completed_at = ?",
        arguments: ["2026-99-99T99:99:99.999Z"])
      XCTAssertThrowsError(
        try CloudTraversalWitness.state(
          db, accountIdentifier: self.accountA, zoneIdentifier: self.zone1)
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .invalidTimestamp)
      }
    }
  }

  func testTerminalTransitionRollsBackWithCallerTransaction() throws {
    struct DeliberateRollback: Error {}
    let store = try SyncTestSupport.freshStore()
    let boundary = try boundary()
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: "traversal-1", start: .baseline,
        startedAt: startedAt)
    }
    XCTAssertThrowsError(
      try store.writer.write { db in
        _ = try CloudTraversalWitness.commitPage(
          db, boundary: boundary, traversalIdentifier: "traversal-1",
          page: try CloudTraversalPageCommit(
            pageIndex: 0, continuationToken: nil, moreComing: false,
            observation: try proof(boundary, traversalIdentifier: "traversal-1")),
          completedAt: completedAt)
        throw DeliberateRollback()
      })
    try store.writer.read { db in
      let state = try CloudTraversalWitness.state(
        db, accountIdentifier: accountA, zoneIdentifier: zone1)
      XCTAssertEqual(state.progress?.traversalIdentifier, "traversal-1")
      XCTAssertNil(state.baselineWitness)
    }
  }

  func testTerminalCommitSavepointRollsBackPartialWitnessWhenCallerCatches() throws {
    let store = try SyncTestSupport.freshStore()
    let boundary = try boundary()
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: "savepoint-failure", start: .baseline,
        startedAt: startedAt)
      try db.execute(
        sql: """
          CREATE TEMP TRIGGER fail_traversal_progress_delete
          BEFORE DELETE ON sync_cloudkit_traversal_progress
          BEGIN
            SELECT RAISE(ABORT, 'forced progress delete failure');
          END
          """)
      XCTAssertThrowsError(
        try CloudTraversalWitness.commitPage(
          db, boundary: boundary, traversalIdentifier: "savepoint-failure",
          page: try CloudTraversalPageCommit(
            pageIndex: 0, continuationToken: Data([0xd7]), moreComing: false,
            observation: try proof(
              boundary, traversalIdentifier: "savepoint-failure")),
          completedAt: completedAt))
      try db.execute(sql: "DROP TRIGGER fail_traversal_progress_delete")

      let state = try CloudTraversalWitness.state(
        db, accountIdentifier: accountA, zoneIdentifier: zone1)
      XCTAssertEqual(state.progress?.traversalIdentifier, "savepoint-failure")
      XCTAssertNil(
        state.baselineWitness,
        "the witness insert before the forced delete failure must roll back to the savepoint")
    }
  }

  func testOnDiskRestoreCarriesWitnessWithoutExternalCheckpoint() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-traversal-witness-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("lorvex.sqlite")
    let schema = try SyncTestSupport.loadSchemaSQL()
    let boundary = try boundary()

    let firstOpen = try LorvexStore.open(at: databaseURL, schemaSQL: schema)
    try firstOpen.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: "traversal-restore", start: .baseline,
        startedAt: startedAt)
      _ = try CloudTraversalWitness.commitPage(
        db, boundary: boundary, traversalIdentifier: "traversal-restore",
        page: try CloudTraversalPageCommit(
          pageIndex: 0, continuationToken: Data([0xaa]), moreComing: false,
          observation: try proof(boundary, traversalIdentifier: "traversal-restore")),
        completedAt: completedAt)
    }
    try firstOpen.writer.close()

    let restored = try LorvexStore.open(at: databaseURL, schemaSQL: schema)
    defer { try? restored.writer.close() }
    try restored.writer.read { db in
      let state = try CloudTraversalWitness.state(
        db, accountIdentifier: accountA, zoneIdentifier: zone1)
      XCTAssertNil(state.progress)
      XCTAssertEqual(state.baselineWitness?.traversalIdentifier, "traversal-restore")
      XCTAssertEqual(state.baselineWitness?.finalChangeToken, Data([0xaa]))
      XCTAssertEqual(try CloudTraversalWitness.accountBinding(db)?.accountIdentifier, accountA)
    }
  }

  func testAccountRoundTripCannotReuseOldBaselineWitness() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try claim(db)
      let aBoundary = try boundary()
      _ = try CloudTraversalWitness.begin(
        db, boundary: aBoundary, traversalIdentifier: "a-before-switch", start: .baseline,
        startedAt: startedAt)
      _ = try CloudTraversalWitness.commitPage(
        db, boundary: aBoundary, traversalIdentifier: "a-before-switch",
        page: try CloudTraversalPageCommit(
          pageIndex: 0, continuationToken: Data([0xa1]), moreComing: false,
          observation: try proof(aBoundary, traversalIdentifier: "a-before-switch")),
        completedAt: completedAt)

      _ = try CloudTraversalWitness.adoptAccount(
        db, expectedCurrentAccountIdentifier: accountA,
        newAccountIdentifier: accountB, boundAt: completedAt)
      _ = try CloudTraversalWitness.adoptAccount(
        db, expectedCurrentAccountIdentifier: accountB,
        newAccountIdentifier: accountA, boundAt: completedAt)

      let returned = try CloudTraversalWitness.state(
        db, accountIdentifier: accountA, zoneIdentifier: zone1)
      XCTAssertNil(returned.progress)
      XCTAssertNil(returned.baselineWitness)
      XCTAssertNil(returned.incrementalCursor)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_cloudkit_generation_descriptor"),
        1, "account switching clears content proof but retains account-scoped anti-rollback history"
      )
      let fresh = try CloudTraversalWitness.begin(
        db, boundary: aBoundary, traversalIdentifier: "a-after-switch", start: .baseline,
        startedAt: completedAt)
      XCTAssertEqual(fresh.nextPageIndex, 0)
      XCTAssertNil(fresh.startingChangeToken)
      XCTAssertNil(fresh.continuationToken)
    }
  }

  func testAccountRoundTripRetainsPerAccountGenerationFenceWithoutCrossAccountLeakage() throws {
    let store = try SyncTestSupport.freshStore()
    let aGeneration2 = try boundary(zone: zone2, generation: 2)
    let bGeneration1 = try CloudTraversalBoundary(
      accountIdentifier: accountB, zoneIdentifier: zone2, generation: 1,
      generationIdentifier: aGeneration2.generationIdentifier,
      readyWitness: aGeneration2.readyWitness)
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: aGeneration2, traversalIdentifier: "a-g2", start: .baseline,
        startedAt: startedAt)
      try CloudTraversalWitness.cancel(
        db, boundary: aGeneration2, traversalIdentifier: "a-g2")

      _ = try CloudTraversalWitness.adoptAccount(
        db, expectedCurrentAccountIdentifier: accountA,
        newAccountIdentifier: accountB, boundAt: completedAt)
      let bProgress = try CloudTraversalWitness.begin(
        db, boundary: bGeneration1, traversalIdentifier: "b-g1", start: .baseline,
        startedAt: completedAt)
      XCTAssertEqual(bProgress.boundary, bGeneration1)
      try CloudTraversalWitness.cancel(
        db, boundary: bGeneration1, traversalIdentifier: "b-g1")

      _ = try CloudTraversalWitness.adoptAccount(
        db, expectedCurrentAccountIdentifier: accountB,
        newAccountIdentifier: accountA, boundAt: completedAt)
      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db, boundary: try self.boundary(generation: 1),
          traversalIdentifier: "a-rollback", start: .baseline,
          startedAt: self.completedAt)
      ) { error in
        XCTAssertEqual(
          error as? CloudTraversalStateError,
          .staleGeneration(current: 2, attempted: 1))
      }
      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db, boundary: try self.boundary(zone: self.zone2, generation: 3),
          traversalIdentifier: "a-zone-reuse", start: .baseline,
          startedAt: self.completedAt)
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .generationZoneReuse)
      }
      let fresh = try CloudTraversalWitness.begin(
        db, boundary: try self.boundary(zone: "LorvexZone-g3", generation: 3),
        traversalIdentifier: "a-g3", start: .baseline,
        startedAt: self.completedAt)
      XCTAssertEqual(fresh.boundary.generation, 3)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_cloudkit_generation_descriptor"),
        3)
    }
  }

  func testIncrementalCursorCannotReplaceBaselineProofButAdvancesTerminalWatermark() throws {
    let store = try SyncTestSupport.freshStore()
    let boundary = try boundary()
    let baselineToken = Data([0xb1])
    let incrementalToken = Data([0xb2])
    try store.writer.write { db in
      try claim(db)
      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db, boundary: boundary, traversalIdentifier: "incremental-too-early",
          start: try .incremental(from: baselineToken), startedAt: startedAt)
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .baselineWitnessRequired)
      }
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_cloudkit_generation_descriptor"),
        0,
        "a caught begin failure must roll back its descriptor reservation savepoint")

      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: "baseline", start: .baseline,
        startedAt: startedAt)
      _ = try CloudTraversalWitness.commitPage(
        db, boundary: boundary, traversalIdentifier: "baseline",
        page: try CloudTraversalPageCommit(
          pageIndex: 0, continuationToken: baselineToken, moreComing: false,
          observation: try CloudTraversalPageObservation(
            generationRootIdentifier: boundary.generationIdentifier,
            readyWitness: boundary.readyWitness,
            traversalWitnessIdentifier: "baseline",
            traversalWitnessServerTime: "2026-07-14T09:59:00.000Z")),
        completedAt: completedAt)
      let originalBaseline = try XCTUnwrap(
        CloudTraversalWitness.state(
          db, accountIdentifier: accountA, zoneIdentifier: zone1
        ).baselineWitness)

      let incrementalStart = try CloudTraversalStart.incremental(from: baselineToken)
      let progress = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: "incremental", start: incrementalStart,
        startedAt: completedAt)
      XCTAssertEqual(progress.mode, .incremental)
      XCTAssertEqual(progress.startingChangeToken, baselineToken)
      XCTAssertEqual(progress.continuationToken, baselineToken)
      guard
        case .incrementalCompleted(let cursor) = try CloudTraversalWitness.commitPage(
          db, boundary: boundary, traversalIdentifier: "incremental",
          page: try CloudTraversalPageCommit(
            pageIndex: 0, continuationToken: incrementalToken, moreComing: false,
            observation: try CloudTraversalPageObservation(
              traversalWitnessIdentifier: "incremental",
              traversalWitnessServerTime: "2099-01-01T00:00:00.000Z")),
          completedAt: completedAt)
      else { return XCTFail("expected an incremental cursor") }
      XCTAssertEqual(cursor.changeToken, incrementalToken)

      let state = try CloudTraversalWitness.state(
        db, accountIdentifier: accountA, zoneIdentifier: zone1)
      XCTAssertEqual(state.baselineWitness, originalBaseline)
      XCTAssertEqual(state.incrementalCursor, cursor)
      XCTAssertTrue(
        try Tombstone.trustedTerminalServerTimeCovers(
          db, accountIdentifier: accountA,
          cutoff: "2026-07-15T00:00:00.000Z"),
        "an exact incremental terminal witness advances recovery authority without replacing the baseline proof")
      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db, boundary: boundary, traversalIdentifier: "stale-incremental",
          start: try .incremental(from: baselineToken), startedAt: completedAt)
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .continuationMismatch)
      }
    }
  }

  func testNewGenerationBaselineReplacesInterruptedIncrementalTraversal() throws {
    let store = try SyncTestSupport.freshStore()
    let generation1 = try boundary()
    let generation2 = try boundary(zone: zone2, generation: 2)
    let baselineToken = Data([0xc1])
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: generation1, traversalIdentifier: "baseline-g1", start: .baseline,
        startedAt: startedAt)
      _ = try CloudTraversalWitness.commitPage(
        db, boundary: generation1, traversalIdentifier: "baseline-g1",
        page: try CloudTraversalPageCommit(
          pageIndex: 0, continuationToken: baselineToken, moreComing: false,
          observation: try proof(generation1, traversalIdentifier: "baseline-g1")),
        completedAt: completedAt)
      _ = try CloudTraversalWitness.begin(
        db, boundary: generation1, traversalIdentifier: "incremental-g1",
        start: try .incremental(from: baselineToken), startedAt: completedAt)

      let replacement = try CloudTraversalWitness.begin(
        db, boundary: generation2, traversalIdentifier: "baseline-g2", start: .baseline,
        startedAt: completedAt)

      XCTAssertEqual(replacement.boundary, generation2)
      XCTAssertEqual(replacement.mode, .baseline)
      XCTAssertEqual(replacement.nextPageIndex, 0)
      XCTAssertNil(replacement.startingChangeToken)
    }
  }

  func testRestoredDatabaseWithoutBaselineRejectsIncrementalStart() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-no-baseline-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("lorvex.sqlite")
    let schema = try SyncTestSupport.loadSchemaSQL()
    let firstOpen = try LorvexStore.open(at: databaseURL, schemaSQL: schema)
    try firstOpen.writer.write { db in try claim(db) }
    try firstOpen.writer.close()

    let restored = try LorvexStore.open(at: databaseURL, schemaSQL: schema)
    defer { try? restored.writer.close() }
    try restored.writer.write { db in
      let state = try CloudTraversalWitness.state(
        db, accountIdentifier: accountA, zoneIdentifier: zone1)
      XCTAssertNil(state.baselineWitness)
      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db, boundary: try boundary(), traversalIdentifier: "unproven-incremental",
          start: try .incremental(from: Data([0xee])), startedAt: completedAt)
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .baselineWitnessRequired)
      }
    }
  }

  func testDatabaseInstanceRotationClearsContentProofButPreservesGenerationHistory() throws {
    let store = try SyncTestSupport.freshStore()
    let boundary = try boundary()
    let newerBoundary = try self.boundary(zone: zone2, generation: 2)
    try store.writer.write { db in
      try claim(db)
      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: "before-restore", start: .baseline,
        startedAt: startedAt)
      _ = try CloudTraversalWitness.commitPage(
        db, boundary: boundary, traversalIdentifier: "before-restore",
        page: try CloudTraversalPageCommit(
          pageIndex: 0, continuationToken: Data([0xcc]), moreComing: false,
          observation: try CloudTraversalPageObservation(
            generationRootIdentifier: boundary.generationIdentifier,
            readyWitness: boundary.readyWitness,
            traversalWitnessIdentifier: "before-restore",
            traversalWitnessServerTime: "2026-07-14T10:00:00.000Z")),
        completedAt: completedAt)
      try Tombstone.observeTrustedServerTime(
        db, accountIdentifier: accountA,
        serverTime: "2026-07-14T10:01:00.000Z")
      XCTAssertTrue(
        try Tombstone.trustedTerminalServerTimeCovers(
          db, accountIdentifier: accountA,
          cutoff: "2026-07-14T09:59:59.999Z"))
      _ = try CloudTraversalWitness.begin(
        db, boundary: newerBoundary, traversalIdentifier: "newer-generation",
        start: .baseline, startedAt: completedAt)
      try CloudTraversalWitness.cancel(
        db, boundary: newerBoundary, traversalIdentifier: "newer-generation")
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId, value: "rotated-database-instance")

      XCTAssertThrowsError(
        try CloudTraversalWitness.claimAccount(db, accountIdentifier: accountA)
      ) { error in
        XCTAssertEqual(error as? CloudTraversalStateError, .databaseInstanceMismatch)
      }
      let rebound = try CloudTraversalWitness.rebindAfterDatabaseInstanceRotation(
        db, expectedAccountIdentifier: accountA, reboundAt: completedAt)
      XCTAssertEqual(rebound.databaseInstanceIdentifier, "rotated-database-instance")
      let state = try CloudTraversalWitness.state(
        db, accountIdentifier: accountA, zoneIdentifier: zone1)
      XCTAssertNil(state.progress)
      XCTAssertNil(state.baselineWitness)
      XCTAssertNil(state.incrementalCursor)
      XCTAssertFalse(
        try Tombstone.trustedTerminalServerTimeCovers(
          db, accountIdentifier: accountA,
          cutoff: "2026-07-14T09:59:59.999Z"))
      let reboundClocks = try Row.fetchOne(
        db,
        sql: """
          SELECT trusted_server_time, trusted_terminal_server_time
          FROM sync_cloudkit_account_binding WHERE singleton = 1
          """)
      let trustedServerTime: String? = reboundClocks?["trusted_server_time"]
      let trustedTerminalServerTime: String? =
        reboundClocks?["trusted_terminal_server_time"]
      XCTAssertNil(trustedServerTime)
      XCTAssertNil(trustedTerminalServerTime)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_cloudkit_generation_descriptor"),
        2, "restore/clone rotation must retain anti-rollback generation history")
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT database_instance_id
            FROM sync_cloudkit_generation_descriptor
            WHERE account_identifier = ? AND generation = ?
            """,
          arguments: [self.accountA, 2]),
        "rotated-database-instance")
      XCTAssertThrowsError(
        try CloudTraversalWitness.begin(
          db, boundary: boundary, traversalIdentifier: "rollback-after-restore",
          start: .baseline, startedAt: completedAt)
      ) { error in
        XCTAssertEqual(
          error as? CloudTraversalStateError,
          .staleGeneration(current: 2, attempted: 1))
      }
      XCTAssertThrowsError(
        try CloudTraversalWitness.rebindAfterDatabaseInstanceRotation(
          db, expectedAccountIdentifier: accountA, reboundAt: completedAt)
      ) { error in
        XCTAssertEqual(
          error as? CloudTraversalStateError, .databaseInstanceRotationNotDetected)
      }
    }
  }

  func testBindingOnlyLineageRotationCreatesNonNilAuthoritySentinel() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try claim(db)
      XCTAssertNil(
        try CloudTraversalWitness.observedGenerationAuthorityFloor(
          db, accountIdentifier: accountA),
        "same-lineage interrupted first bootstrap must remain resumable")
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: "rotated-binding-only-instance")

      _ = try CloudTraversalWitness.rebindAfterDatabaseInstanceRotation(
        db, expectedAccountIdentifier: accountA, reboundAt: completedAt)
      XCTAssertEqual(
        try CloudTraversalWitness.observedGenerationAuthorityFloor(
          db, accountIdentifier: accountA),
        0,
        "a restored/clone lineage must never become nil-authority fresh again")
    }
  }

  func testValueBoundsRejectMalformedInputsBeforeSQLite() throws {
    XCTAssertThrowsError(
      try CloudTraversalBoundary(
        accountIdentifier: "", zoneIdentifier: zone1, generation: 1,
        generationIdentifier: "generation-1", readyWitness: "ready-1"))
    XCTAssertThrowsError(
      try CloudTraversalBoundary(
        accountIdentifier: accountA, zoneIdentifier: "zone\u{7f}", generation: 1,
        generationIdentifier: "generation-1", readyWitness: "ready-1")
    ) { error in
      XCTAssertEqual(error as? CloudTraversalStateError, .invalidZoneIdentifier)
    }
    XCTAssertThrowsError(
      try CloudTraversalPageObservation(generationRootIdentifier: "generation\u{7}")
    ) { error in
      XCTAssertEqual(error as? CloudTraversalStateError, .invalidGenerationIdentifier)
    }
    XCTAssertThrowsError(
      try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: nil, moreComing: true))
    XCTAssertThrowsError(
      try CloudTraversalPageCommit(
        pageIndex: 0,
        continuationToken: Data(
          repeating: 0, count: CloudTraversalPageCommit.maxContinuationTokenBytes + 1),
        moreComing: true))
  }
}
