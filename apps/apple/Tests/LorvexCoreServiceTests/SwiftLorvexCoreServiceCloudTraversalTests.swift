import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

final class SwiftLorvexCoreServiceCloudTraversalTests: XCTestCase {
  private let account = "account-a"
  private let zone = "LorvexZone-g7"
  private let taskId = "01966a3f-7c8b-7d4e-8f3a-00000000c001"

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(
      store: try LorvexStore.openInMemory(schemaSQL: schemaSQL))
  }

  private func boundary(generation: Int = 7) throws -> CloudTraversalBoundary {
    try CloudTraversalBoundary(
      accountIdentifier: account, zoneIdentifier: zone, generation: generation,
      generationIdentifier: "generation-\(generation)",
      readyWitness: "ready-\(generation)")
  }

  private func proof(
    _ boundary: CloudTraversalBoundary, traversalIdentifier: String
  ) throws -> CloudTraversalPageObservation {
    try CloudTraversalPageObservation(
      generationRootIdentifier: boundary.generationIdentifier,
      readyWitness: boundary.readyWitness,
      traversalWitnessIdentifier: traversalIdentifier)
  }

  private func taskEnvelope(listID: String = "inbox") throws -> SyncEnvelope {
    let version = try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "id": .string(taskId),
        "list_id": .string(listID),
        "title": .string("Atomic traversal apply"),
        "status": .string("open"),
        "created_at": .string("2026-07-14T00:00:00.000Z"),
        "updated_at": .string("2026-07-14T00:00:00.000Z"),
        "version": .string(version.description),
      ]))
    return try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .task, entityId: taskId, operation: .upsert,
        version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "remote-device"))
  }

  private func listEnvelope(id: String) throws -> SyncEnvelope {
    let version = try Hlc.parse("1711234567891_0000_a1b2c3d4a1b2c3d4")
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "id": .string(id),
        "name": .string("Remote parent"),
        "created_at": .string("2026-07-14T00:00:00.000Z"),
        "updated_at": .string("2026-07-14T00:00:00.000Z"),
        "version": .string(version.description),
      ]))
    return try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .list, entityId: id, operation: .upsert,
        version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "remote-device"))
  }

  private func futureRecord(
    entityId: String = "future-record", payload: String = #"{"future":true}"#
  ) -> RawEnvelopeFields {
    RawEnvelopeFields(
      entityType: "future_entity", entityId: entityId,
      operation: SyncOperation.upsert.asString,
      version: "1711234567891_0000_b1c2d3e4b1c2d3e4",
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "future-device")
  }

  private func inboxRecord() throws -> AuthoritativeSnapshotRemoteRecord {
    let version = try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "id": .string("inbox"),
        "name": .string("Inbox"),
        "created_at": .string("2026-07-14T00:00:00.000Z"),
        "updated_at": .string("2026-07-14T00:00:00.000Z"),
        "version": .string(version.description),
      ]))
    let envelope = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .list, entityId: "inbox", operation: .upsert,
        version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "remote-device"))
    return AuthoritativeSnapshotRemoteRecord(
      recordName: SyncRecordName.opaque(entityType: EntityName.list, entityId: "inbox"),
      state: .decoded, envelope: envelope)
  }

  private func authoritativeRecord(_ envelope: SyncEnvelope) -> AuthoritativeSnapshotRemoteRecord {
    AuthoritativeSnapshotRemoteRecord(
      recordName: SyncRecordName.opaque(
        entityType: envelope.entityType.asString, entityId: envelope.entityId),
      state: .decoded, envelope: envelope)
  }

  private func timezonePreferenceEnvelope() throws -> SyncEnvelope {
    let version = try Hlc.parse("1711234567892_0000_a1b2c3d4a1b2c3d4")
    return try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .preference, entityId: PreferenceKeys.prefTimezone,
        operation: .upsert, version: version,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "key": .string(PreferenceKeys.prefTimezone),
            "value": .string("America/New_York"),
            "updated_at": .string("2026-07-21T20:00:00.000Z"),
            "version": .string(version.description),
          ])),
        deviceId: "remote-device"))
  }

  private func oldZoneReminderEnvelope() throws -> SyncEnvelope {
    let reminderID = "01966a3f-7c8b-7d4e-8f3a-00000000c002"
    let version = try Hlc.parse("1711234567893_0000_a1b2c3d4a1b2c3d4")
    return try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .taskReminder, entityId: reminderID,
        operation: .upsert, version: version,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "cancelled_at": .null,
            "created_at": .string("2026-07-21T20:00:00.000Z"),
            "dismissed_at": .null,
            "id": .string(reminderID),
            "original_local_time": .string("09:00"),
            "original_tz": .string("America/Los_Angeles"),
            "reminder_at": .string("2026-07-22T16:00:00.000Z"),
            "task_id": .string(taskId),
            "version": .string(version.description),
          ])),
        deviceId: "remote-device"))
  }

  func testOrdinaryTerminalPageAppliesAndWitnessesAtomically() throws {
    let service = try makeService()
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "ordinary-1", start: .baseline)

    let report = try service.applyInboundTraversalPage(
      [try taskEnvelope()], cloudReceipts: [], undecodable: 0,
      boundary: boundary, traversalIdentifier: "ordinary-1",
      page: try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: Data([0x01]), moreComing: false,
        observation: try proof(boundary, traversalIdentifier: "ordinary-1")),
      inboundObservation: CloudInboundPageObservation())
    XCTAssertEqual(report.applied, 1)
    XCTAssertEqual(try service.enrolledZoneEpoch(forAccountIdentifier: account), 7)
    let state = try service.cloudTraversalState(
      accountIdentifier: account, zoneIdentifier: zone)
    XCTAssertNil(state.progress)
    XCTAssertEqual(state.baselineWitness?.traversalIdentifier, "ordinary-1")
    XCTAssertEqual(state.baselineWitness?.finalChangeToken, Data([0x01]))
    let queriedTaskId = taskId
    XCTAssertEqual(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [queriedTaskId])
      },
      "Atomic traversal apply")

    let valid = try taskEnvelope()
    let invalidReplay = SyncEnvelope(
      entityType: valid.entityType, entityId: "", operation: valid.operation,
      version: valid.version, payloadSchemaVersion: valid.payloadSchemaVersion,
      payload: valid.payload, deviceId: valid.deviceId)
    let replay = try service.applyInboundTraversalPage(
      [invalidReplay], cloudReceipts: [], undecodable: 0,
      boundary: boundary, traversalIdentifier: "ordinary-1",
      page: try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: Data([0x01]), moreComing: false,
        observation: try proof(boundary, traversalIdentifier: "ordinary-1")),
      inboundObservation: CloudInboundPageObservation())
    XCTAssertEqual(replay.undecodable, 0)
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.inbound_invalid'")
          ?? 0
      },
      0, "a terminal replay must return before applying or logging the supplied payload")
  }

  func testTraversalCannotAcknowledgeUndecodableRecordsWithoutExactRecordNames() throws {
    let service = try makeService()
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "corrupt-proof", start: .baseline)
    let page = try CloudTraversalPageCommit(
      pageIndex: 0, continuationToken: Data([0x09]), moreComing: false,
      observation: try proof(boundary, traversalIdentifier: "corrupt-proof"))

    XCTAssertThrowsError(
      try service.applyInboundTraversalPage(
        [], deferredUnknownTypeRecords: [], cloudReceipts: [], undecodable: 1,
        boundary: boundary, traversalIdentifier: "corrupt-proof", page: page,
        inboundObservation: CloudInboundPageObservation())
    ) { error in
      XCTAssertEqual(
        error as? CloudInboundCompletenessError,
        .corruptRecordCountMismatch)
    }

    let state = try service.cloudTraversalState(
      accountIdentifier: account, zoneIdentifier: zone)
    XCTAssertEqual(state.progress?.nextPageIndex, 0)
    XCTAssertNil(state.baselineWitness)
  }

  func testInvalidCursorResetRestartsExactTraversalAsBaselineAtomically() throws {
    let service = try makeService()
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "baseline-before-expiry", start: .baseline)
    _ = try service.applyInboundTraversalPage(
      [], cloudReceipts: [], undecodable: 0, boundary: boundary,
      traversalIdentifier: "baseline-before-expiry",
      page: try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: Data([0x11]), moreComing: false,
        observation: try proof(
          boundary, traversalIdentifier: "baseline-before-expiry")),
      inboundObservation: CloudInboundPageObservation())
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "incremental-expired",
      start: try .incremental(from: Data([0x11])))
    _ = try service.applyInboundTraversalPage(
      [], cloudReceipts: [], undecodable: 0, boundary: boundary,
      traversalIdentifier: "incremental-expired",
      page: try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: Data([0x12]), moreComing: true,
        observation: try proof(boundary, traversalIdentifier: "incremental-expired")),
      inboundObservation: CloudInboundPageObservation())

    try service.resetCloudTraversalAfterInvalidCursor(
      boundary: boundary, traversalIdentifier: "incremental-expired",
      requireFullReseed: true)

    let progress = try XCTUnwrap(
      service.cloudTraversalState(
        accountIdentifier: account, zoneIdentifier: zone).progress)
    XCTAssertEqual(progress.traversalIdentifier, "incremental-expired")
    XCTAssertEqual(progress.mode, .baseline)
    XCTAssertEqual(progress.nextPageIndex, 0)
    XCTAssertNil(progress.startingChangeToken)
    XCTAssertNil(progress.continuationToken)
    XCTAssertTrue(try service.isReseedRequired())
  }

  func testInvalidCursorResetRejectsStaleTraversalWithoutReplacingNewProgress() throws {
    let service = try makeService()
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "stale-traversal", start: .baseline)
    try service.cancelCloudTraversal(
      boundary: boundary, traversalIdentifier: "stale-traversal")
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "new-traversal", start: .baseline)

    XCTAssertThrowsError(
      try service.resetCloudTraversalAfterInvalidCursor(
        boundary: boundary, traversalIdentifier: "stale-traversal",
        requireFullReseed: true)
    ) { error in
      XCTAssertEqual(error as? CloudTraversalStateError, .traversalBoundaryMismatch)
    }

    let progress = try XCTUnwrap(
      service.cloudTraversalState(
        accountIdentifier: account, zoneIdentifier: zone).progress)
    XCTAssertEqual(progress.traversalIdentifier, "new-traversal")
    XCTAssertEqual(progress.mode, .baseline)
    XCTAssertFalse(try service.isReseedRequired())
  }

  func testAccountAdoptionClearsPriorLineageFetchFailureAndReseedState() throws {
    let service = try makeService()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    XCTAssertTrue(
      try service.recordRemoteChangeFetchFailure(
        checkpointKey: "account-a-failure", threshold: 1))
    try service.write { db in
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyReseedRequired, value: "true")
    }
    XCTAssertTrue(try service.isReseedRequired())

    _ = try service.adoptCloudTraversalAccount(
      expectedCurrentAccountIdentifier: account,
      newAccountIdentifier: "account-b")

    XCTAssertFalse(try service.isReseedRequired())
    XCTAssertFalse(
      try service.recordRemoteChangeFetchFailure(
        checkpointKey: "account-b-failure", threshold: 2))
  }

  func testWitnessFailureRollsBackOrdinaryInboundApply() throws {
    let service = try makeService()
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "ordinary-1", start: .baseline)

    XCTAssertThrowsError(
      try service.applyInboundTraversalPage(
        [try taskEnvelope()], deferredUnknownTypeRecords: [futureRecord()], cloudReceipts: [],
        undecodable: 0,
        boundary: boundary, traversalIdentifier: "ordinary-1",
        page: try CloudTraversalPageCommit(
          pageIndex: 0, continuationToken: Data([0x08]), moreComing: false),
        inboundObservation: CloudInboundPageObservation())
    ) { error in
      XCTAssertEqual(
        error as? CloudTraversalStateError,
        .baselineProofIncomplete)
    }
    let queriedTaskId = taskId
    XCTAssertNil(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [queriedTaskId])
      })
    let state = try service.cloudTraversalState(
      accountIdentifier: account, zoneIdentifier: zone)
    XCTAssertEqual(state.progress?.nextPageIndex, 0)
    XCTAssertNil(state.baselineWitness)
    XCTAssertNil(try service.enrolledZoneEpoch(forAccountIdentifier: account))
    XCTAssertEqual(try service.unresolvedFutureRecordCount(), 0)
  }

  func testOrdinaryPageParksFutureRecordsWithCursorAndSkipsThemOnReplay() throws {
    let service = try makeService()
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "future-page", start: .baseline)
    let page = try CloudTraversalPageCommit(
      pageIndex: 0, continuationToken: Data([0x66]), moreComing: true,
      observation: CloudTraversalPageObservation(
        generationRootIdentifier: boundary.generationIdentifier))

    let first = try service.applyInboundTraversalPage(
      [], deferredUnknownTypeRecords: [futureRecord()], cloudReceipts: [], undecodable: 0,
      boundary: boundary, traversalIdentifier: "future-page", page: page,
      inboundObservation: CloudInboundPageObservation())
    XCTAssertEqual(first.deferredUnknownType, 1)
    XCTAssertEqual(try service.unresolvedFutureRecordCount(), 1)

    let replay = try service.applyInboundTraversalPage(
      [],
      deferredUnknownTypeRecords: [futureRecord(entityId: "", payload: "not-json")],
      cloudReceipts: [], undecodable: 0, boundary: boundary,
      traversalIdentifier: "future-page", page: page,
      inboundObservation: CloudInboundPageObservation())
    XCTAssertEqual(replay.deferredUnknownType, 0)
    XCTAssertEqual(try service.unresolvedFutureRecordCount(), 1)
    let state = try service.cloudTraversalState(
      accountIdentifier: account, zoneIdentifier: zone)
    XCTAssertEqual(state.progress?.nextPageIndex, 1)
    XCTAssertEqual(state.progress?.continuationToken, Data([0x66]))
  }

  func testPhysicalDeletionAtomicallyResolvesFutureAndQuarantineDebt() async throws {
    let service = try makeService()
    let localTask = try await service.createTask(
      title: "Preserved local intent", notes: "")
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "future-delete", start: .baseline)
    let futureVersion = "1711234567892_0000_b1c2d3e4b1c2d3e4"
    let future = RawEnvelopeFields(
      entityType: EntityName.task, entityId: localTask.id,
      operation: "future_operation",
      version: futureVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
      payload: #"{"future":true}"#, deviceId: "future-device")
    let firstPage = try CloudTraversalPageCommit(
      pageIndex: 0, continuationToken: Data([0x67]), moreComing: true,
      observation: CloudTraversalPageObservation(
        generationRootIdentifier: boundary.generationIdentifier))
    _ = try service.applyInboundTraversalPage(
      [], deferredUnknownTypeRecords: [future], cloudReceipts: [], undecodable: 0,
      boundary: boundary, traversalIdentifier: "future-delete", page: firstPage,
      inboundObservation: CloudInboundPageObservation())
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO sync_quarantine_blocklist
              (entity_type, entity_id, version, quarantined_at)
          VALUES (?, ?, ?, '2026-07-14T00:00:00.000Z')
          """,
        arguments: [EntityName.task, localTask.id, futureVersion])
    }

    XCTAssertEqual(
      try service.cloudInboundCompletenessState(boundary: boundary),
      CloudInboundCompletenessState(pendingRecordCount: 1, corruptRecordCount: 1))
    XCTAssertEqual(
      try service.read { db in
        try String.fetchOne(
          db,
          sql: """
            SELECT disposition FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.task, localTask.id])
      },
      Outbox.Disposition.futureRecordHold.rawValue)

    let recordName = SyncRecordName.opaque(
      entityType: EntityName.task, entityId: localTask.id)
    let terminalPage = try CloudTraversalPageCommit(
      pageIndex: 1, continuationToken: Data([0x68]), moreComing: false,
      observation: try proof(boundary, traversalIdentifier: "future-delete"))
    _ = try service.applyInboundTraversalPage(
      [], deferredUnknownTypeRecords: [], cloudReceipts: [], undecodable: 0,
      boundary: boundary, traversalIdentifier: "future-delete", page: terminalPage,
      inboundObservation: CloudInboundPageObservation(
        deletedRecordNames: [recordName]))

    XCTAssertTrue(
      try service.cloudInboundCompletenessState(boundary: boundary).isComplete)
    XCTAssertEqual(try service.unresolvedFutureRecordCount(), 0)
    XCTAssertEqual(try service.quarantinedInboundRecordCount(), 0)
    XCTAssertNil(
      try service.read { db in
        try String.fetchOne(
          db,
          sql: """
            SELECT disposition FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.task, localTask.id])
      })
    let preservedTask = try await service.loadTask(id: localTask.id)
    XCTAssertEqual(preservedTask.title, "Preserved local intent")
  }

  func testPhysicalDeletionWinsBeforeSamePageParentCanReplayPendingChild() throws {
    let service = try makeService()
    let boundary = try boundary()
    let parentID = "01966a3f-7c8b-7d4e-8f3a-00000000c002"
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "delete-before-drain", start: .baseline)

    let firstPage = try CloudTraversalPageCommit(
      pageIndex: 0, continuationToken: Data([0x69]), moreComing: true,
      observation: CloudTraversalPageObservation(
        generationRootIdentifier: boundary.generationIdentifier))
    let deferred = try service.applyInboundTraversalPage(
      [try taskEnvelope(listID: parentID)], cloudReceipts: [], undecodable: 0,
      boundary: boundary, traversalIdentifier: "delete-before-drain", page: firstPage,
      inboundObservation: CloudInboundPageObservation())
    XCTAssertEqual(deferred.deferred, 1)
    XCTAssertEqual(try service.unresolvedInboundRecordCount(), 1)

    let recordName = SyncRecordName.opaque(
      entityType: EntityName.task, entityId: taskId)
    let terminalPage = try CloudTraversalPageCommit(
      pageIndex: 1, continuationToken: Data([0x6A]), moreComing: false,
      observation: try proof(boundary, traversalIdentifier: "delete-before-drain"))
    _ = try service.applyInboundTraversalPage(
      [try listEnvelope(id: parentID)], cloudReceipts: [], undecodable: 0,
      boundary: boundary, traversalIdentifier: "delete-before-drain", page: terminalPage,
      inboundObservation: CloudInboundPageObservation(
        deletedRecordNames: [recordName]))

    XCTAssertEqual(try service.unresolvedInboundRecordCount(), 0)
    let deletedTaskID = taskId
    XCTAssertNil(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [deletedTaskID])
      })
    XCTAssertEqual(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT name FROM lists WHERE id = ?", arguments: [parentID])
      },
      "Remote parent")
  }

  func testDuplicateContinuationPageSkipsAllApplySideEffects() throws {
    let service = try makeService()
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "duplicate-page", start: .baseline)
    let valid = try taskEnvelope()
    let invalid = SyncEnvelope(
      entityType: valid.entityType, entityId: "", operation: valid.operation,
      version: valid.version, payloadSchemaVersion: valid.payloadSchemaVersion,
      payload: valid.payload, deviceId: valid.deviceId)
    let page = try CloudTraversalPageCommit(
      pageIndex: 0, continuationToken: Data([0x61]), moreComing: true,
      observation: CloudTraversalPageObservation(
        generationRootIdentifier: boundary.generationIdentifier))

    let first = try service.applyInboundTraversalPage(
      [invalid], cloudReceipts: [], undecodable: 0, boundary: boundary,
      traversalIdentifier: "duplicate-page", page: page,
      inboundObservation: CloudInboundPageObservation())
    XCTAssertEqual(first.undecodable, 1)
    let errorCountAfterFirst = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.inbound_invalid'") ?? 0
    }
    XCTAssertEqual(errorCountAfterFirst, 1)

    let replay = try service.applyInboundTraversalPage(
      [invalid], cloudReceipts: [], undecodable: 0, boundary: boundary,
      traversalIdentifier: "duplicate-page", page: page,
      inboundObservation: CloudInboundPageObservation())
    XCTAssertEqual(replay.undecodable, 0)
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.inbound_invalid'")
          ?? 0
      },
      errorCountAfterFirst,
      "preflight must recognize a durable replay before validation/logging runs again")
  }

  func testIncrementalTerminalPersistsCursorWithoutEstablishingEnrollment() throws {
    let service = try makeService()
    let boundary = try boundary()
    let baselineToken = Data([0x41])
    let incrementalToken = Data([0x42])
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "baseline", start: .baseline)
    _ = try service.applyInboundTraversalPage(
      [], cloudReceipts: [], undecodable: 0,
      boundary: boundary, traversalIdentifier: "baseline",
      page: try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: baselineToken, moreComing: false,
        observation: try proof(boundary, traversalIdentifier: "baseline")),
      inboundObservation: CloudInboundPageObservation())
    let accountIdentifier = account
    _ = try service.write { db in
      try SyncCheckpoints.clear(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: accountIdentifier))
    }

    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: "incremental",
      start: try .incremental(from: baselineToken))
    _ = try service.applyInboundTraversalPage(
      [], cloudReceipts: [], undecodable: 0,
      boundary: boundary, traversalIdentifier: "incremental",
      page: try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: incrementalToken, moreComing: false),
      inboundObservation: CloudInboundPageObservation())

    XCTAssertNil(try service.enrolledZoneEpoch(forAccountIdentifier: account))
    let state = try service.cloudTraversalState(
      accountIdentifier: account, zoneIdentifier: zone)
    XCTAssertEqual(state.baselineWitness?.traversalIdentifier, "baseline")
    XCTAssertEqual(state.incrementalCursor?.traversalIdentifier, "incremental")
    XCTAssertEqual(state.incrementalCursor?.changeToken, incrementalToken)
  }

  func testAuthoritativeSessionAndTraversalBeginRestartAndCancelAtomically() throws {
    let service = try makeService()
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)

    let session = try service.beginAuthoritativeSnapshot(boundary: boundary)
    var state = try service.cloudTraversalState(
      accountIdentifier: account, zoneIdentifier: zone)
    XCTAssertEqual(state.progress?.boundary, boundary)
    XCTAssertEqual(state.progress?.traversalIdentifier, session.sessionToken)
    XCTAssertEqual(state.progress?.mode, .baseline)
    XCTAssertEqual(state.progress?.nextPageIndex, 0)

    let resumed = try service.beginAuthoritativeSnapshot(boundary: boundary)
    XCTAssertEqual(resumed.sessionToken, session.sessionToken)
    try service.markAuthoritativeSnapshotReady(sessionToken: session.sessionToken)
    try service.stageAuthoritativeSnapshotContinuationPage(
      records: [], deletedRecordNames: [], sessionToken: session.sessionToken,
      boundary: boundary, traversalIdentifier: session.sessionToken,
      page: try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: Data([0x71]), moreComing: true,
        observation: CloudTraversalPageObservation(
          generationRootIdentifier: boundary.generationIdentifier)))
    state = try service.cloudTraversalState(
      accountIdentifier: account, zoneIdentifier: zone)
    XCTAssertEqual(state.progress?.nextPageIndex, 1)

    let restarted = try service.restartAuthoritativeSnapshot()
    XCTAssertEqual(restarted.sessionToken, session.sessionToken)
    XCTAssertEqual(restarted.phase, .preparing)
    state = try service.cloudTraversalState(
      accountIdentifier: account, zoneIdentifier: zone)
    XCTAssertEqual(state.progress?.nextPageIndex, 0)
    XCTAssertFalse(state.progress?.observedGenerationRoot ?? true)

    try service.cancelAuthoritativeSnapshot()
    XCTAssertNil(try service.authoritativeSnapshotSession())
    state = try service.cloudTraversalState(
      accountIdentifier: account, zoneIdentifier: zone)
    XCTAssertNil(state.progress)
    XCTAssertNil(state.baselineWitness)
  }

  func testAccountAdoptionNoOpPreservesSessionAndRealSwitchClearsContentProof() throws {
    let service = try makeService()
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    let session = try service.beginAuthoritativeSnapshot(boundary: boundary)

    let unchanged = try service.adoptCloudTraversalAccount(
      expectedCurrentAccountIdentifier: account, newAccountIdentifier: account)
    XCTAssertEqual(unchanged.accountIdentifier, account)
    XCTAssertEqual(
      try service.authoritativeSnapshotSession()?.sessionToken, session.sessionToken)
    XCTAssertEqual(
      try service.cloudTraversalState(
        accountIdentifier: account, zoneIdentifier: zone
      ).progress?.traversalIdentifier,
      session.sessionToken)

    let accountIdentifier = account
    try service.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: accountIdentifier),
        value: "7")
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: "account-b"),
        value: "4")
    }
    let switched = try service.adoptCloudTraversalAccount(
      expectedCurrentAccountIdentifier: account, newAccountIdentifier: "account-b")
    XCTAssertEqual(switched.accountIdentifier, "account-b")
    XCTAssertNil(try service.authoritativeSnapshotSession())
    XCTAssertNil(try service.enrolledZoneEpoch(forAccountIdentifier: account))
    XCTAssertNil(try service.enrolledZoneEpoch(forAccountIdentifier: "account-b"))
    let durableCounts = try service.read { db in
      (
        progress: try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_cloudkit_traversal_progress") ?? -1,
        descriptor: try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_cloudkit_generation_descriptor") ?? -1
      )
    }
    XCTAssertEqual(durableCounts.progress, 0)
    XCTAssertEqual(durableCounts.descriptor, 1)
  }

  func testDatabaseInstanceRotationClearsOldLineageEnrollmentAtomically() throws {
    let service = try makeService()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    let accountIdentifier = account
    try service.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: accountIdentifier),
        value: "7")
    }
    XCTAssertEqual(try service.enrolledZoneEpoch(forAccountIdentifier: account), 7)

    try service.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: "rotated-service-database-instance")
    }
    let rebound = try service.rebindCloudTraversalAfterDatabaseInstanceRotation(
      expectedAccountIdentifier: account)

    XCTAssertEqual(rebound.databaseInstanceIdentifier, "rotated-service-database-instance")
    XCTAssertNil(try service.enrolledZoneEpoch(forAccountIdentifier: account))
  }

  func testGenerationAuthorityWitnessIsPerAccountMonotonicAndSurvivesLineageRotation() throws {
    let service = try makeService()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    XCTAssertNil(
      try service.observedCloudGenerationAuthorityFloor(
        forAccountIdentifier: account))
    XCTAssertEqual(
      try service.recordObservedCloudGenerationAuthority(
        forAccountIdentifier: account, generation: 7),
      7)
    XCTAssertThrowsError(
      try service.recordObservedCloudGenerationAuthority(
        forAccountIdentifier: account, generation: 6)
    ) { error in
      XCTAssertEqual(
        error as? CloudTraversalStateError,
        .staleGeneration(current: 7, attempted: 6))
    }

    _ = try service.adoptCloudTraversalAccount(
      expectedCurrentAccountIdentifier: account,
      newAccountIdentifier: "account-b")
    XCTAssertNil(
      try service.observedCloudGenerationAuthorityFloor(
        forAccountIdentifier: "account-b"))
    _ = try service.recordObservedCloudGenerationAuthority(
      forAccountIdentifier: "account-b", generation: 2)
    _ = try service.adoptCloudTraversalAccount(
      expectedCurrentAccountIdentifier: "account-b",
      newAccountIdentifier: account)
    XCTAssertEqual(
      try service.observedCloudGenerationAuthorityFloor(
        forAccountIdentifier: account),
      7)

    try service.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: "rotated-authority-witness-database")
    }
    _ = try service.rebindCloudTraversalAfterDatabaseInstanceRotation(
      expectedAccountIdentifier: account)
    XCTAssertEqual(
      try service.observedCloudGenerationAuthorityFloor(
        forAccountIdentifier: account),
      7,
      "restore/clone rotation must retain the account's anti-rollback generation floor")

    _ = try service.adoptCloudTraversalAccount(
      expectedCurrentAccountIdentifier: account,
      newAccountIdentifier: "account-b")
    XCTAssertEqual(
      try service.observedCloudGenerationAuthorityFloor(
        forAccountIdentifier: "account-b"),
      2,
      "rotation must rebind every account-scoped authority fact carried by the database")
  }

  func testAuthoritativeTerminalPageStagesReconcilesAndWitnessesAtomically() throws {
    let service = try makeService()
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    let session = try service.beginAuthoritativeSnapshot(boundary: boundary)
    try service.markAuthoritativeSnapshotReady(sessionToken: session.sessionToken)

    let report = try service.finalizeAuthoritativeSnapshotTerminalPage(
      records: [try inboxRecord()], deletedRecordNames: [],
      sessionToken: session.sessionToken, boundary: boundary,
      traversalIdentifier: session.sessionToken,
      page: try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: Data([0xa7]), moreComing: false,
        observation: try proof(boundary, traversalIdentifier: session.sessionToken)))
    XCTAssertEqual(report.replayedRemoteRecords, 1)
    XCTAssertNil(try service.authoritativeSnapshotSession())
    XCTAssertEqual(try service.enrolledZoneEpoch(forAccountIdentifier: account), 7)
    let state = try service.cloudTraversalState(
      accountIdentifier: account, zoneIdentifier: zone)
    XCTAssertNil(state.progress)
    XCTAssertEqual(state.baselineWitness?.traversalIdentifier, session.sessionToken)

    let replay = try service.finalizeAuthoritativeSnapshotTerminalPage(
      records: [
        AuthoritativeSnapshotRemoteRecord(
          recordName: "would-fail-if-restaged", state: .corrupt, envelope: nil)
      ], deletedRecordNames: [], sessionToken: session.sessionToken,
      boundary: boundary, traversalIdentifier: session.sessionToken,
      page: try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: Data([0xa7]), moreComing: false,
        observation: try proof(boundary, traversalIdentifier: session.sessionToken)))
    XCTAssertEqual(replay, AuthoritativeSnapshotReport())
    XCTAssertNil(try service.authoritativeSnapshotSession())
  }

  func testAuthoritativeTerminalPageReanchorsReminderToAdoptedTimezoneAtomically() throws {
    let service = try makeService()
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    let session = try service.beginAuthoritativeSnapshot(boundary: boundary)
    try service.markAuthoritativeSnapshotReady(sessionToken: session.sessionToken)
    let task = try taskEnvelope()
    let timezone = try timezonePreferenceEnvelope()
    let oldZoneReminder = try oldZoneReminderEnvelope()

    let report = try service.finalizeAuthoritativeSnapshotTerminalPage(
      records: [
        try inboxRecord(), authoritativeRecord(task),
        authoritativeRecord(timezone), authoritativeRecord(oldZoneReminder),
      ], deletedRecordNames: [],
      sessionToken: session.sessionToken, boundary: boundary,
      traversalIdentifier: session.sessionToken,
      page: try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: Data([0xb7]), moreComing: false,
        observation: try proof(boundary, traversalIdentifier: session.sessionToken)))

    XCTAssertTrue(report.changedEntityTypes.contains(.taskReminder))
    let reminderState = try service.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT reminder_at, original_local_time, original_tz, version
          FROM task_reminders WHERE id = ?
          """,
        arguments: [oldZoneReminder.entityId])
    }
    let reminder = try XCTUnwrap(reminderState)
    XCTAssertEqual(reminder["reminder_at"] as String, "2026-07-22T13:00:00.000Z")
    XCTAssertEqual(reminder["original_local_time"] as String, "09:00")
    XCTAssertEqual(reminder["original_tz"] as String, "America/New_York")
    let repairedVersion = try Hlc.parse(reminder["version"] as String)
    XCTAssertGreaterThan(repairedVersion, oldZoneReminder.version)

    let successor = try XCTUnwrap(
      try service.pendingOutbound().first {
        $0.envelope.entityType == .taskReminder
          && $0.envelope.entityId == oldZoneReminder.entityId
      })
    XCTAssertEqual(successor.envelope.operation, .upsert)
    XCTAssertEqual(successor.envelope.version, repairedVersion)
    XCTAssertEqual(try service.enrolledZoneEpoch(forAccountIdentifier: account), 7)
  }

  func testAuthoritativeWitnessFailureRollsBackReconciliationAndSession() throws {
    let service = try makeService()
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    let session = try service.beginAuthoritativeSnapshot(boundary: boundary)
    try service.markAuthoritativeSnapshotReady(sessionToken: session.sessionToken)

    XCTAssertThrowsError(
      try service.finalizeAuthoritativeSnapshotTerminalPage(
        records: [try inboxRecord()], deletedRecordNames: [],
        sessionToken: session.sessionToken, boundary: boundary,
        traversalIdentifier: session.sessionToken,
        page: try CloudTraversalPageCommit(
          pageIndex: 1, continuationToken: nil, moreComing: false))
    ) { error in
      XCTAssertEqual(
        error as? CloudTraversalStateError,
        .pageSequenceMismatch(expected: 0, actual: 1))
    }
    XCTAssertEqual(try service.authoritativeSnapshotSession()?.phase, .ready)
    let state = try service.cloudTraversalState(
      accountIdentifier: account, zoneIdentifier: zone)
    XCTAssertEqual(state.progress?.nextPageIndex, 0)
    XCTAssertNil(state.baselineWitness)
    XCTAssertNil(try service.enrolledZoneEpoch(forAccountIdentifier: account))
  }
}
