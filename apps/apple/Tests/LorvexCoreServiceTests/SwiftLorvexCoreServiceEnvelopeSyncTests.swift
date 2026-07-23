import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// Coverage for the `EnvelopeSyncServicing` facade on `SwiftLorvexCoreService`:
/// the seam a sync transport uses to read the outbox and apply inbound
/// envelopes through the ported engine. Conflict resolution itself lives in the
/// engine and is covered by `LorvexSyncTests`; these tests verify the facade
/// wires the engine in and reports outcomes.
final class SwiftLorvexCoreServiceEnvelopeSyncTests: XCTestCase {

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
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  /// A schema-valid task upsert payload. `list_id` points at the seeded inbox
  /// list so the FK preflight does not defer the envelope.
  private func taskUpsertEnvelope(
    id: String = "01966a3f-7c8b-7d4e-8f3a-000000000001",
    title: String = "Inbound task",
    listId: String
  ) -> SyncEnvelope {
    let version = try! Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
    let payload = (try? SyncCanonicalize.canonicalizeJSON(.object([
      "ai_notes": .null,
      "archive_version": .string(version.description),
      "archived_at": .null,
      "available_from": .null,
      "body": .null,
      "canonical_occurrence_date": .null,
      "completed_at": .null,
      "content_version": .string(version.description),
      "defer_count": .int(0),
      "due_date": .null,
      "estimated_minutes": .null,
      "id": .string(id),
      "last_defer_reason": .null,
      "last_deferred_at": .null,
      "lifecycle_version": .string(version.description),
      "title": .string(title),
      "status": .string("open"),
      "list_id": .string(listId),
      "planned_date": .null,
      "priority": .null,
      "raw_input": .null,
      "recurrence": .null,
      "recurrence_exceptions": .null,
      "recurrence_group_id": .null,
      "recurrence_instance_key": .null,
      "recurrence_rollover_state": .string("none"),
      "recurrence_successor_id": .null,
      "schedule_version": .string(version.description),
      "spawned_from": .null,
      "spawned_from_version": .null,
      "created_at": .string("2026-04-01T00:00:00.000Z"),
      "updated_at": .string("2026-04-01T00:00:00.000Z"),
      "version": .string(version.description),
    ]))) ?? "{}"
    return SyncEnvelope(
      entityType: .task,
      entityId: id,
      operation: .upsert,
      version: version,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload,
      deviceId: "device-remote")
  }

  private func taskDependencyEnvelope(
    taskId: String,
    dependsOn: String,
    version: String
  ) throws -> SyncEnvelope {
    try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .taskDependency,
        entityId: "\(taskId):\(dependsOn)",
        operation: .upsert,
        version: try Hlc.parse(version),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: #"{"created_at":"2026-04-01T00:00:00.000Z"}"#,
        deviceId: "device-remote"))
  }

  private func taskEnvelope(
    byReplacingTitle source: SyncEnvelope, with title: String,
    version: Hlc? = nil
  ) throws -> SyncEnvelope {
    guard case .object(var object)? = JSONValue.parse(source.payload) else {
      throw XCTSkip("task fixture payload was not an object")
    }
    let targetVersion = version ?? source.version
    object["title"] = .string(title)
    object["version"] = .string(targetVersion.description)
    return SyncEnvelope(
      entityType: source.entityType, entityId: source.entityId,
      operation: source.operation, version: targetVersion,
      payloadSchemaVersion: source.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)),
      deviceId: "server-clone")
  }

  private func calendarBaseEnvelope(
    id: String, title: String, startDate: String,
    contentVersion: Hlc, topologyVersion: Hlc, rowVersion: Hlc,
    deviceId: String
  ) throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "all_day": .bool(false),
      "attendees": .null,
      "color": .null,
      "content_version": .string(contentVersion.description),
      "created_at": .string("2026-07-15T00:00:00.000Z"),
      "description": .null,
      "end_date": .string(startDate),
      "end_time": .string("10:00"),
      "event_type": .string("event"),
      "id": .string(id),
      "location": .null,
      "occurrence_state": .null,
      "person_name": .null,
      "recurrence": .null,
      "recurrence_generation": .null,
      "recurrence_instance_date": .null,
      "recurrence_topology_version": .string(topologyVersion.description),
      "series_cutover_id": .null,
      "series_id": .null,
      "start_date": .string(startDate),
      "start_time": .string("09:00"),
      "timezone": .string("America/Los_Angeles"),
      "title": .string(title),
      "updated_at": .string("2026-07-15T00:00:00.000Z"),
      "url": .null,
      "version": .string(rowVersion.description),
    ]))
    return SyncEnvelope(
      entityType: .calendarEvent, entityId: id, operation: .upsert,
      version: rowVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceId)
  }

  private func calendarCutoverEnvelope(
    lineageRootId: String, date: String,
    state: CalendarSeriesCutoverState, version: Hlc,
    deviceId: String
  ) throws -> SyncEnvelope {
    let id = CalendarSeriesCutoverID.make(
      lineageRootId: lineageRootId, cutoverDate: date)
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "created_at": .string("2026-07-15T00:00:00.000Z"),
      "cutover_date": .string(date),
      "id": .string(id),
      "lineage_root_id": .string(lineageRootId),
      "state": .string(state.rawValue),
      "updated_at": .string("2026-07-15T00:00:00.000Z"),
      "version": .string(version.description),
    ]))
    return SyncEnvelope(
      entityType: .calendarSeriesCutover, entityId: id, operation: .upsert,
      version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceId)
  }

  private func redirectEnvelope(
    sourceType: EntityKind, sourceId: String, targetId: String,
    version: Hlc, deviceId: String
  ) throws -> SyncEnvelope {
    let wireId = EntityRedirect.wireEntityId(
      sourceType: sourceType, sourceId: sourceId)
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "source_id": .string(sourceId),
      "source_type": .string(sourceType.asString),
      "target_id": .string(targetId),
      "version": .string(version.description),
    ]))
    return SyncEnvelope(
      entityType: .entityRedirect, entityId: wireId, operation: .upsert,
      version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceId)
  }

  private func forwardCompatibleClient(_ source: SyncEnvelope) throws -> SyncEnvelope {
    guard case .object(var object)? = JSONValue.parse(source.payload) else {
      throw XCTSkip("forward-compatible fixture payload was not an object")
    }
    object["future_probe"] = .string("preserve-me")
    return SyncEnvelope(
      entityType: source.entityType, entityId: source.entityId,
      operation: source.operation, version: source.version,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)),
      deviceId: source.deviceId)
  }

  /// The id of a list that exists in the freshly-opened store, so a task
  /// envelope's `list_id` FK resolves and the upsert applies rather than
  /// deferring.
  private func seededListId(_ service: SwiftLorvexCoreService) throws -> String {
    try service.read { db in
      try String.fetchOne(db, sql: "SELECT id FROM lists ORDER BY id LIMIT 1")
    } ?? "inbox"
  }

  private func mutationCounts(_ service: SwiftLorvexCoreService) throws
    -> (outbox: Int64, changelog: Int64)
  {
    try service.read { db in
      let outbox = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? 0
      let changelog = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
      return (outbox, changelog)
    }
  }

  private struct OutboundReconciliationFixture {
    let request: OutboundReconciliationRequest
    let winnerEntityId: String
    let unknownEntityType: String
    let failedOutboxId: Int64
    let confirmedOutboxId: Int64
  }

  private func makeOutboundReconciliationFixture(
    _ service: SwiftLorvexCoreService
  ) async throws -> OutboundReconciliationFixture {
    let failedTask = try await service.createTask(title: "Failure bookkeeping", notes: "")
    let confirmedTask = try await service.createTask(title: "Successful confirmation", notes: "")
    let pending = try service.pendingOutbound()
    let failedOutboxId = try XCTUnwrap(
      pending.first { $0.envelope.entityId == failedTask.id }?.outboxId)
    let confirmedOutboxId = try XCTUnwrap(
      pending.first { $0.envelope.entityId == confirmedTask.id }?.outboxId)
    let winnerEntityId = "01966a3f-7c8b-7d4e-8f3a-00000000a701"
    let winner = taskUpsertEnvelope(
      id: winnerEntityId, title: "Server winner", listId: try seededListId(service))
    let unknownEntityType = "future_atomic_entity"
    let raw = RawEnvelopeFields(
      entityType: unknownEntityType,
      entityId: "01966a3f-7c8b-7d4e-8f3a-00000000a702",
      operation: "upsert",
      version: "1711234567891_0000_b1c2d3e4b1c2d3e4",
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
      payload: #"{"future_field":"retained"}"#,
      deviceId: "future-device")
    return OutboundReconciliationFixture(
      request: OutboundReconciliationRequest(
        serverWinnerEnvelopes: [winner],
        deferredUnknownTypeRecords: [raw],
        failures: [
          OutboundFailureRecord(
            outboxId: failedOutboxId, error: "per-record rejection", kind: .perRecord)
        ],
        confirmedOutboxIds: [confirmedOutboxId]),
      winnerEntityId: winnerEntityId,
      unknownEntityType: unknownEntityType,
      failedOutboxId: failedOutboxId,
      confirmedOutboxId: confirmedOutboxId)
  }

  private func assertOutboundReconciliationRolledBack(
    _ service: SwiftLorvexCoreService,
    fixture: OutboundReconciliationFixture,
    triggerSQL: String,
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let sequenceBefore = try service.read { db in try LocalChangeSeq.read(db) }
    try service.write { db in try db.execute(sql: triggerSQL) }

    XCTAssertThrowsError(
      try service.reconcileOutbound(fixture.request), file: file, line: line)

    let state = try service.read { db in
      (
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?",
          arguments: [fixture.winnerEntityId]) ?? -1,
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_pending_inbox WHERE envelope_entity_type = ?",
          arguments: [fixture.unknownEntityType]) ?? -1,
        try Row.fetchOne(
          db,
          sql: "SELECT retry_count, last_retry_at, last_error FROM sync_outbox WHERE id = ?",
          arguments: [fixture.failedOutboxId]),
        try String.fetchOne(
          db, sql: "SELECT synced_at FROM sync_outbox WHERE id = ?",
          arguments: [fixture.confirmedOutboxId]),
        try LocalChangeSeq.read(db)
      )
    }
    XCTAssertEqual(state.0, 0, "server winner must roll back", file: file, line: line)
    XCTAssertEqual(state.1, 0, "future-record parking must roll back", file: file, line: line)
    let failed = try XCTUnwrap(state.2, file: file, line: line)
    XCTAssertEqual(failed["retry_count"] as Int64, 0, file: file, line: line)
    XCTAssertNil(failed["last_retry_at"] as String?, file: file, line: line)
    XCTAssertNil(failed["last_error"] as String?, file: file, line: line)
    XCTAssertNil(state.3, "confirmation must roll back", file: file, line: line)
    XCTAssertEqual(state.4, sequenceBefore, "change witness must roll back", file: file, line: line)
  }

  func testStartupShadowPromotionBumpsCanonicalChangeSequenceExactlyOnce() throws {
    let service = try makeService()
    let taskID = "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa"
    let version = "1711234567890_0201_deadbeefdeadbeef"
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at)
          VALUES (?, 'Shadow task', 'open', 'inbox', ?,
                  '2026-03-27T09:00:00Z', '2026-03-27T09:00:00Z')
          """,
        arguments: [taskID, version])
      try db.execute(
        sql: """
          INSERT INTO sync_payload_shadow
            (entity_type, entity_id, base_version, payload_schema_version,
             raw_payload_json, source_device_id, updated_at)
          VALUES ('task', ?, ?, ?, ?, 'device-remote', '2026-03-27T09:00:00Z')
          """,
        arguments: [
          taskID, version, LorvexVersion.payloadSchemaVersion,
          """
          {"id":"\(taskID)","title":"Shadow task","status":"open","list_id":"inbox",\
          "body":"Recovered from shadow","created_at":"2026-03-27T09:00:00Z",\
          "updated_at":"2026-03-27T09:00:00Z"}
          """,
        ])
    }
    let before = try service.read { db in try LocalChangeSeq.read(db) }

    XCTAssertEqual(
      try SwiftLorvexCoreService.promoteStartupPayloadShadows(service.store()), 1)

    let state = try service.read { db in
      (
        try LocalChangeSeq.read(db),
        try String.fetchOne(db, sql: "SELECT body FROM tasks WHERE id = ?", arguments: [taskID]),
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_payload_shadow WHERE entity_id = ?",
          arguments: [taskID]) ?? -1
      )
    }
    XCTAssertEqual(state.0, before + 1)
    XCTAssertEqual(state.1, "Recovered from shadow")
    XCTAssertEqual(state.2, 0)
  }

  private func beginAuthoritativeSnapshot(
    _ service: SwiftLorvexCoreService, accountIdentifier: String,
    zoneIdentifier: String = "LorvexZone"
  ) throws -> AuthoritativeSnapshotSession {
    _ = try service.claimCloudTraversalAccount(accountIdentifier: accountIdentifier)
    let boundary = try CloudTraversalBoundary(
      accountIdentifier: accountIdentifier, zoneIdentifier: zoneIdentifier,
      generation: 1, generationIdentifier: "test-generation",
      readyWitness: "test-ready-witness")
    return try service.beginAuthoritativeSnapshot(boundary: boundary)
  }

  /// `createTask` enqueues a `task` Upsert envelope to `sync_outbox` for the
  /// created id, version-stamped from the mutation's HLC, so the coordinator's
  /// `pendingOutbound()` has the new task to ship.
  func testCreateTaskEnqueuesOutboundUpsert() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Local task", notes: "")

    let pending = try service.pendingOutbound()
    let taskEnvelopes = pending.filter {
      $0.envelope.entityType == .task && $0.envelope.entityId == task.id
    }
    XCTAssertEqual(taskEnvelopes.count, 1)
    let envelope = try XCTUnwrap(taskEnvelopes.first?.envelope)
    XCTAssertEqual(envelope.operation, .upsert)
    XCTAssertFalse(envelope.version.description.isEmpty)
  }

  /// SY3: `pendingOutbound()` must run the poison-row retry-state UPDATE that
  /// `Outbox.getPending` performs inside a WRITE transaction. An undecodable
  /// outbox row (here an unparseable `version`) must be parked — the update must
  /// COMMIT (not throw `SQLITE_READONLY`) — and a subsequent
  /// fetch must proceed, returning the healthy sibling rather than wedging
  /// outbound sync forever on the one poison row.
  func testPendingOutboundParksPoisonRowAndProceeds() async throws {
    let service = try makeService()
    // A healthy sibling that must keep shipping despite the poison row.
    let task = try await service.createTask(title: "Healthy row", notes: "")

    // Insert a structurally-poison outbox row: a valid `operation` (the schema
    // CHECK-constrains it) but a `version` string `Hlc.parse` rejects.
    try service.write { db in
      try Self.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO sync_outbox
              (entity_type, entity_id, operation, version, payload_schema_version,
               payload, device_id, created_at)
            VALUES ('task', '01966a3f-7c8b-7d4e-8f3a-0000000000ee', 'upsert',
                    'not-a-parseable-hlc', 1, '{"title":"poison"}', 'device-remote',
                    '2026-04-01T00:00:00.000Z')
            """)
      }
    }

    // Must NOT throw (the pre-fix read-only transaction failed the retry-state
    // UPDATE with SQLITE_READONLY). The healthy row comes back; the poison row is
    // excluded once parked.
    let pending = try service.pendingOutbound()
    XCTAssertTrue(
      pending.contains { $0.envelope.entityId == task.id },
      "the healthy sibling must still be pending")

    // The poison row entered retry wait and the update committed.
    let poison = try service.read { db in
      try Row.fetchOne(
        db,
        sql: "SELECT retry_count, last_error FROM sync_outbox WHERE entity_id = ?",
        arguments: ["01966a3f-7c8b-7d4e-8f3a-0000000000ee"])
    }
    let poisonRow = try XCTUnwrap(poison)
    XCTAssertEqual(poisonRow["retry_count"] as Int64, Outbox.maxRetries)
    XCTAssertNotNil(poisonRow["last_error"] as String?)

    // A subsequent cycle proceeds: the parked row is now excluded, the
    // healthy row still returns, and nothing throws.
    let second = try service.pendingOutbound()
    XCTAssertFalse(
      second.contains { $0.envelope.entityId == "01966a3f-7c8b-7d4e-8f3a-0000000000ee" })
    XCTAssertTrue(second.contains { $0.envelope.entityId == task.id })
  }

  /// SY2: a TRANSIENT outbound failure (network down) recorded repeatedly with
  /// the identical error — the exact pattern that would fast-forward a persistent
  /// error to maxRetries — must never pause the healthy row. It stays
  /// pending at `retry_count == 0` so it ships once the transport recovers.
  func testTransientOutboundFailureDoesNotAdvanceRetryWait() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Offline edit", notes: "")
    let id = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == task.id }?.outboxId)

    let transientError = "push chunk failed: The Internet connection appears to be offline."
    for _ in 0..<5 {
      try service.recordOutboundFailure(outboxId: id, error: transientError, kind: .transient)
    }

    XCTAssertTrue(
      try service.pendingOutbound().contains { $0.outboxId == id },
      "a transient outage must leave the row pending")
    let retryCount = try service.read { db in
      try Int64.fetchOne(db, sql: "SELECT retry_count FROM sync_outbox WHERE id = ?", arguments: [id])
    }
    XCTAssertEqual(retryCount, 0, "a transient outage must not advance retry_count")
    let retryWaitLogs = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.outbox.retry_wait'") ?? -1
    }
    XCTAssertEqual(retryWaitLogs, 0, "a transient outage must not enter retry wait")
  }

  func testOutboundReconciliationRollsBackWhenFutureRecordParkingFails() async throws {
    let service = try makeService()
    let fixture = try await makeOutboundReconciliationFixture(service)
    try assertOutboundReconciliationRolledBack(
      service, fixture: fixture,
      triggerSQL: """
        CREATE TEMP TRIGGER fail_atomic_future_parking
        BEFORE INSERT ON sync_pending_inbox
        BEGIN SELECT RAISE(ABORT, 'injected future parking failure'); END
        """)
  }

  func testOutboundReconciliationRollsBackWhenFailureBookkeepingFails() async throws {
    let service = try makeService()
    let fixture = try await makeOutboundReconciliationFixture(service)
    try assertOutboundReconciliationRolledBack(
      service, fixture: fixture,
      triggerSQL: """
        CREATE TEMP TRIGGER fail_atomic_failure_bookkeeping
        BEFORE UPDATE OF retry_count ON sync_outbox
        WHEN OLD.id = \(fixture.failedOutboxId)
        BEGIN SELECT RAISE(ABORT, 'injected failure bookkeeping failure'); END
        """)
  }

  func testOutboundReconciliationRollsBackWhenConfirmationFails() async throws {
    let service = try makeService()
    let fixture = try await makeOutboundReconciliationFixture(service)
    try assertOutboundReconciliationRolledBack(
      service, fixture: fixture,
      triggerSQL: """
        CREATE TEMP TRIGGER fail_atomic_confirmation
        BEFORE UPDATE OF synced_at ON sync_outbox
        WHEN OLD.id = \(fixture.confirmedOutboxId)
        BEGIN SELECT RAISE(ABORT, 'injected confirmation failure'); END
        """)
  }

  func testOutboundReconciliationCommitsAllStagesAndReturnsWinnerReport() async throws {
    let service = try makeService()
    let fixture = try await makeOutboundReconciliationFixture(service)

    let report = try service.reconcileOutbound(fixture.request)

    XCTAssertEqual(report.inbound.applied, 1)
    XCTAssertEqual(report.inbound.deferredUnknownType, 1)
    XCTAssertEqual(report.inbound.appliedEntityTypes, [.task])
    let state = try service.read { db in
      (
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?",
          arguments: [fixture.winnerEntityId]),
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_pending_inbox WHERE envelope_entity_type = ?",
          arguments: [fixture.unknownEntityType]) ?? -1,
        try Int64.fetchOne(
          db, sql: "SELECT retry_count FROM sync_outbox WHERE id = ?",
          arguments: [fixture.failedOutboxId]),
        try String.fetchOne(
          db, sql: "SELECT synced_at FROM sync_outbox WHERE id = ?",
          arguments: [fixture.confirmedOutboxId])
      )
    }
    XCTAssertEqual(state.0, "Server winner")
    XCTAssertEqual(state.1, 1)
    XCTAssertEqual(state.2, 1)
    XCTAssertNotNil(state.3)
  }

  func testInboundThreeWayEqualVersionCollisionJoinsEveryContender() throws {
    let service = try makeService()
    let base = taskUpsertEnvelope(title: "Alpha", listId: try seededListId(service))
    XCTAssertEqual(try service.applyInbound([base], undecodable: 0).applied, 1)

    // Use the canonical materialized projection as the common shape so the
    // only semantic difference between the cloned contenders is the title.
    // With pairwise sequential repair, the second obligation could overwrite
    // the first pair's winner. Coalescing must instead compute max(A, B, C)
    // before minting the one strict successor.
    let canonical = try service.read { db -> SyncEnvelope in
      let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: base.entityType.asString, entityId: base.entityId)
      return SyncEnvelope(
        entityType: base.entityType, entityId: base.entityId,
        operation: .upsert, version: base.version,
        payloadSchemaVersion: base.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(payload),
        deviceId: "local-projection")
    }
    let zulu = try taskEnvelope(byReplacingTitle: canonical, with: "Zulu")
    let middle = try taskEnvelope(byReplacingTitle: canonical, with: "Middle")
    let expected = try SyncMutationSemantics.deterministicWinner(
      try SyncMutationSemantics.deterministicWinner(canonical, zulu), middle)
    guard case .object(let expectedObject)? = JSONValue.parse(expected.payload),
      case .string(let expectedTitle)? = expectedObject["title"]
    else {
      return XCTFail("expected contender payload must contain a title")
    }

    let report = try service.applyInbound([zulu, middle], undecodable: 0)

    XCTAssertEqual(
      report.applied, 2,
      "each grouped-register contender changes the canonical joined task row")
    XCTAssertEqual(report.appliedEntityTypes, [.task])
    XCTAssertEqual(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [base.entityId])
      },
      expectedTitle)
    let successor = try XCTUnwrap(
      try service.pendingOutbound().first { pending in
        pending.envelope.entityType == .task && pending.envelope.entityId == base.entityId
      })
    XCTAssertGreaterThan(successor.envelope.version, base.version)
    XCTAssertEqual(
      try SyncMutationSemantics.key(for: successor.envelope).canonicalPayload,
      try SyncMutationSemantics.key(
        for: SyncMutationSemantics.restamp(
          expected, version: successor.envelope.version,
          deviceId: successor.envelope.deviceId)
      ).canonicalPayload)
  }

  func testOutboundEqualVersionCollisionReplacesExactOldRowWithStrictSuccessor() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Local clone", notes: "")
    let old = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == task.id })
    let server = try taskEnvelope(
      byReplacingTitle: old.envelope, with: "Divergent server clone")

    let report = try service.reconcileOutbound(
      OutboundReconciliationRequest(collisions: [
        OutboundCollisionRecord(
          outboxId: old.outboxId, kind: .equalVersion(serverEnvelope: server))
      ]))

    let replacement = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == task.id })
    XCTAssertNotEqual(replacement.outboxId, old.outboxId)
    XCTAssertGreaterThan(replacement.envelope.version, old.envelope.version)
    XCTAssertEqual(report.inbound.appliedEntityTypes, [.task])
    XCTAssertEqual(report.reconciledCollisionOutboxIds, [old.outboxId])
    XCTAssertNil(
      try service.read { db in
        try Int64.fetchOne(db, sql: "SELECT id FROM sync_outbox WHERE id = ?", arguments: [old.outboxId])
      })
  }

  func testOutboundCalendarRegisterCollisionJoinsBothArrivalOrdersAndAuthorsSuccessor()
    throws
  {
    let eventId = "01966a3f-7c8b-7d4e-8f3a-00000000ca11"
    let base = try Hlc.parse("1711234567100_0000_a1b2c3d4a1b2c3d4")
    let contentWinnerVersion = try Hlc.parse("1711234567200_0000_a1b2c3d4a1b2c3d4")
    let topologyWinnerVersion = try Hlc.parse("1711234567300_0000_b1c2d3e4b1c2d3e4")
    let contentWinner = try calendarBaseEnvelope(
      id: eventId, title: "Winning content", startDate: "2026-07-20",
      contentVersion: contentWinnerVersion, topologyVersion: base,
      rowVersion: contentWinnerVersion, deviceId: "content-device")
    let topologyWinner = try calendarBaseEnvelope(
      id: eventId, title: "Stale content", startDate: "2026-08-20",
      contentVersion: base, topologyVersion: topologyWinnerVersion,
      rowVersion: topologyWinnerVersion, deviceId: "topology-device")

    for (local, server) in [
      (contentWinner, topologyWinner),
      (topologyWinner, contentWinner),
    ] {
      let service = try makeService()
      XCTAssertEqual(try service.applyInbound([local], undecodable: 0).applied, 1)
      try service.write { db in
        guard let payload = JSONValue.parse(local.payload) else {
          return XCTFail("calendar payload must parse")
        }
        try OutboxEnqueue.enqueuePayloadUpsert(
          db, entityType: local.entityType.asString, entityId: local.entityId,
          payload: payload,
          context: OutboxWriteContext(
            version: local.version.description, deviceId: local.deviceId))
      }
      let old = try XCTUnwrap(
        try service.pendingOutbound().first {
          $0.envelope.entityType == .calendarEvent && $0.envelope.entityId == eventId
        })

      let report = try service.reconcileOutbound(
        OutboundReconciliationRequest(collisions: [
          OutboundCollisionRecord(
            outboxId: old.outboxId,
            kind: .semanticMerge(kind: .calendarBaseRegisters, serverEnvelope: server))
        ]))

      let state = try service.read { db in
        (
          try String.fetchOne(
            db, sql: "SELECT title FROM calendar_events WHERE id = ?", arguments: [eventId]),
          try String.fetchOne(
            db, sql: "SELECT start_date FROM calendar_events WHERE id = ?", arguments: [eventId]),
          try String.fetchOne(
            db, sql: "SELECT content_version FROM calendar_events WHERE id = ?",
            arguments: [eventId]),
          try String.fetchOne(
            db, sql: "SELECT recurrence_topology_version FROM calendar_events WHERE id = ?",
            arguments: [eventId]),
          try String.fetchOne(
            db, sql: "SELECT version FROM calendar_events WHERE id = ?", arguments: [eventId])
        )
      }
      XCTAssertEqual(state.0, "Winning content")
      XCTAssertEqual(state.1, "2026-08-20")
      XCTAssertEqual(state.2, contentWinnerVersion.description)
      XCTAssertEqual(state.3, topologyWinnerVersion.description)
      let successorVersion = try Hlc.parse(XCTUnwrap(state.4))
      XCTAssertGreaterThan(successorVersion, contentWinnerVersion)
      XCTAssertGreaterThan(successorVersion, topologyWinnerVersion)

      let successor = try XCTUnwrap(
        try service.pendingOutbound().first {
          $0.envelope.entityType == .calendarEvent && $0.envelope.entityId == eventId
        })
      XCTAssertNotEqual(successor.outboxId, old.outboxId)
      XCTAssertEqual(successor.envelope.version, successorVersion)
      XCTAssertEqual(report.reconciledCollisionOutboxIds, [old.outboxId])
      XCTAssertEqual(report.inbound.appliedEntityTypes, [.calendarEvent])
      XCTAssertNil(
        try service.read { db in
          try Int64.fetchOne(
            db, sql: "SELECT id FROM sync_outbox WHERE id = ?", arguments: [old.outboxId])
        })
    }
  }

  func testOutboundTaskRegisterCollisionPreservesLocalIntentAndJoinsRemoteSchedule()
    throws
  {
    let service = try makeService()
    let taskId = "01966a3f-7c8b-7d4e-8f3a-00000000ca31"
    let base = taskUpsertEnvelope(
      id: taskId, title: "Base title", listId: try seededListId(service))
    let serverVersion = try Hlc.parse("1711234567950_0000_b1c2d3e4b1c2d3e4")
    let localVersion = try Hlc.parse("1711234567990_0000_a1b2c3d4a1b2c3d4")
    guard case .object(var localObject)? = JSONValue.parse(base.payload),
      case .object(var serverObject)? = JSONValue.parse(base.payload)
    else { return XCTFail("task payload must be an object") }

    // The local outer HLC wins, but only its content register changed. The
    // server carries a newer schedule register under an older outer HLC. A
    // transport-level whole-row LWW decision would silently lose the due date.
    localObject["title"] = .string("Local content winner")
    localObject["content_version"] = .string(localVersion.description)
    localObject["version"] = .string(localVersion.description)
    serverObject["due_date"] = .string("2026-08-21")
    serverObject["schedule_version"] = .string(serverVersion.description)
    serverObject["version"] = .string(serverVersion.description)
    let localPayload = JSONValue.object(localObject)
    let local = SyncEnvelope(
      entityType: .task, entityId: taskId, operation: .upsert,
      version: localVersion, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(localPayload),
      deviceId: "local-content-device")
    let server = SyncEnvelope(
      entityType: .task, entityId: taskId, operation: .upsert,
      version: serverVersion, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(serverObject)),
      deviceId: "remote-schedule-device")

    XCTAssertEqual(try service.applyInbound([local], undecodable: 0).applied, 1)
    try service.write { db in
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: EntityKind.task.asString, entityId: taskId,
        payload: localPayload,
        context: OutboxWriteContext(
          version: localVersion.description, deviceId: local.deviceId,
          registerIntent: .task(.content)))
    }
    let old = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == taskId })

    let report = try service.reconcileOutbound(
      OutboundReconciliationRequest(collisions: [
        OutboundCollisionRecord(
          outboxId: old.outboxId,
          kind: .semanticMerge(kind: .taskRegisters, serverEnvelope: server))
      ]))

    let state = try service.read { db in
      (
        try Row.fetchOne(
          db,
          sql: "SELECT title, due_date, content_version, schedule_version, version "
            + "FROM tasks WHERE id = ?",
          arguments: [taskId]),
        try Row.fetchOne(
          db,
          sql: "SELECT id, version, register_intent FROM sync_outbox "
            + "WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL",
          arguments: [EntityKind.task.asString, taskId])
      )
    }
    let taskRow = try XCTUnwrap(state.0)
    XCTAssertEqual(taskRow["title"] as String, "Local content winner")
    XCTAssertEqual(taskRow["due_date"] as String?, "2026-08-21")
    XCTAssertEqual(taskRow["content_version"] as String, localVersion.description)
    XCTAssertEqual(taskRow["schedule_version"] as String, serverVersion.description)
    let successorVersion = try Hlc.parseCanonical(taskRow["version"] as String)
    XCTAssertGreaterThan(successorVersion, localVersion)

    let outboxRow = try XCTUnwrap(state.1)
    XCTAssertNotEqual(outboxRow["id"] as Int64, old.outboxId)
    XCTAssertEqual(outboxRow["version"] as String, successorVersion.description)
    XCTAssertEqual(
      outboxRow["register_intent"] as Int64,
      EntityRegisterIntent.task(.content).rawValue,
      "the convergence snapshot must retain only the still-winning local content intent")
    XCTAssertEqual(report.reconciledCollisionOutboxIds, [old.outboxId])
    XCTAssertEqual(report.inbound.appliedEntityTypes, [.task])
  }

  func testOutboundFutureTaskClientPreservesShadowWhileJoiningCurrentServerSchedule()
    throws
  {
    let service = try makeService()
    let taskId = "01966a3f-7c8b-7d4e-8f3a-00000000ca32"
    let base = taskUpsertEnvelope(
      id: taskId, title: "Base title", listId: try seededListId(service))
    let serverVersion = try Hlc.parse("1711234567950_0000_b1c2d3e4b1c2d3e4")
    let localVersion = try Hlc.parse("1711234567990_0000_a1b2c3d4a1b2c3d4")
    guard case .object(var localObject)? = JSONValue.parse(base.payload),
      case .object(var serverObject)? = JSONValue.parse(base.payload)
    else { return XCTFail("task payload must be an object") }
    localObject["title"] = .string("Local future content")
    localObject["content_version"] = .string(localVersion.description)
    localObject["version"] = .string(localVersion.description)
    let local = try forwardCompatibleClient(SyncEnvelope(
      entityType: .task, entityId: taskId, operation: .upsert,
      version: localVersion, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(localObject)),
      deviceId: "future-local-device"))
    serverObject["due_date"] = .string("2026-08-21")
    serverObject["schedule_version"] = .string(serverVersion.description)
    serverObject["version"] = .string(serverVersion.description)
    let server = SyncEnvelope(
      entityType: .task, entityId: taskId, operation: .upsert,
      version: serverVersion, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(serverObject)),
      deviceId: "current-server-device")

    XCTAssertEqual(try service.applyInbound([local], undecodable: 0).applied, 1)
    try service.write { db in
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: local.entityType.asString, entityId: taskId,
        payload: try XCTUnwrap(JSONValue.parse(local.payload)),
        context: OutboxWriteContext(
          version: local.version.description, deviceId: local.deviceId,
          registerIntent: .task(.content)))
    }
    let old = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == taskId })

    let report = try service.reconcileOutbound(
      OutboundReconciliationRequest(collisions: [
        OutboundCollisionRecord(
          outboxId: old.outboxId,
          kind: .semanticMerge(kind: .taskRegisters, serverEnvelope: server))
      ]))

    let successor = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == taskId })
    guard case .object(let successorObject)? = JSONValue.parse(successor.envelope.payload) else {
      return XCTFail("successor payload must be an object")
    }
    XCTAssertEqual(successorObject["future_probe"], .string("preserve-me"))
    XCTAssertEqual(successorObject["title"], .string("Local future content"))
    XCTAssertEqual(successorObject["due_date"], .string("2026-08-21"))
    XCTAssertEqual(
      successor.envelope.payloadSchemaVersion, LorvexVersion.payloadSchemaVersion + 1)
    XCTAssertGreaterThan(successor.envelope.version, localVersion)
    XCTAssertNotEqual(successor.outboxId, old.outboxId)
    XCTAssertEqual(report.reconciledCollisionOutboxIds, [old.outboxId])
  }

  func testOutboundFutureCalendarClientPreservesShadowWhileJoiningCurrentServerTopology()
    throws
  {
    let service = try makeService()
    let eventId = "01966a3f-7c8b-7d4e-8f3a-00000000ca33"
    let base = try Hlc.parse("1711234567900_0000_c1c2d3e4c1c2d3e4")
    let topologyVersion = try Hlc.parse("1711234567950_0000_b1c2d3e4b1c2d3e4")
    let contentVersion = try Hlc.parse("1711234567990_0000_a1b2c3d4a1b2c3d4")
    let local = try forwardCompatibleClient(calendarBaseEnvelope(
      id: eventId, title: "Local future content", startDate: "2026-07-20",
      contentVersion: contentVersion, topologyVersion: base,
      rowVersion: contentVersion, deviceId: "future-local-device"))
    let server = try calendarBaseEnvelope(
      id: eventId, title: "Stale server content", startDate: "2026-08-20",
      contentVersion: base, topologyVersion: topologyVersion,
      rowVersion: topologyVersion, deviceId: "current-server-device")

    XCTAssertEqual(try service.applyInbound([local], undecodable: 0).applied, 1)
    try service.write { db in
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: local.entityType.asString, entityId: eventId,
        payload: try XCTUnwrap(JSONValue.parse(local.payload)),
        context: OutboxWriteContext(
          version: local.version.description, deviceId: local.deviceId,
          registerIntent: .calendar(.content)))
    }
    let old = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == eventId })

    let report = try service.reconcileOutbound(
      OutboundReconciliationRequest(collisions: [
        OutboundCollisionRecord(
          outboxId: old.outboxId,
          kind: .semanticMerge(kind: .calendarBaseRegisters, serverEnvelope: server))
      ]))

    let successor = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == eventId })
    guard case .object(let successorObject)? = JSONValue.parse(successor.envelope.payload) else {
      return XCTFail("successor payload must be an object")
    }
    XCTAssertEqual(successorObject["future_probe"], .string("preserve-me"))
    XCTAssertEqual(successorObject["title"], .string("Local future content"))
    XCTAssertEqual(successorObject["start_date"], .string("2026-08-20"))
    XCTAssertEqual(
      successor.envelope.payloadSchemaVersion, LorvexVersion.payloadSchemaVersion + 1)
    XCTAssertGreaterThan(successor.envelope.version, contentVersion)
    XCTAssertNotEqual(successor.outboxId, old.outboxId)
    XCTAssertEqual(report.reconciledCollisionOutboxIds, [old.outboxId])
  }

  func testOutboundCutoverCollisionKeepsDeletedAbsorbingDespiteOlderOuterHlc()
    throws
  {
    let service = try makeService()
    let lineageRootId = "01966a3f-7c8b-7d4e-8f3a-00000000ca41"
    let date = "2026-08-24"
    let remoteDeletedVersion = try Hlc.parse(
      "1711234567950_0000_b1c2d3e4b1c2d3e4")
    let localActiveVersion = try Hlc.parse(
      "1711234567990_0000_a1b2c3d4a1b2c3d4")
    let local = try calendarCutoverEnvelope(
      lineageRootId: lineageRootId, date: date, state: .active,
      version: localActiveVersion, deviceId: "local-active-device")
    let server = try calendarCutoverEnvelope(
      lineageRootId: lineageRootId, date: date, state: .deleted,
      version: remoteDeletedVersion, deviceId: "remote-delete-device")

    XCTAssertEqual(try service.applyInbound([local], undecodable: 0).applied, 1)
    try service.write { db in
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: local.entityType.asString, entityId: local.entityId,
        payload: try XCTUnwrap(JSONValue.parse(local.payload)),
        context: OutboxWriteContext(
          version: local.version.description, deviceId: local.deviceId))
    }
    let old = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == local.entityId })

    let report = try service.reconcileOutbound(
      OutboundReconciliationRequest(collisions: [
        OutboundCollisionRecord(
          outboxId: old.outboxId,
          kind: .semanticMerge(kind: .calendarSeriesCutover, serverEnvelope: server))
      ]))

    let stored = try service.read { db in
      try Row.fetchOne(
        db,
        sql: "SELECT state, version FROM calendar_series_cutovers WHERE id = ?",
        arguments: [local.entityId])
    }
    let row = try XCTUnwrap(stored)
    XCTAssertEqual(row["state"] as String, CalendarSeriesCutoverState.deleted.rawValue)
    let joinedVersion = try Hlc.parseCanonical(row["version"] as String)
    XCTAssertGreaterThan(joinedVersion, localActiveVersion)
    let successor = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == local.entityId })
    XCTAssertNotEqual(successor.outboxId, old.outboxId)
    XCTAssertEqual(successor.envelope.version, joinedVersion)
    XCTAssertEqual(report.reconciledCollisionOutboxIds, [old.outboxId])
    XCTAssertEqual(report.inbound.appliedEntityTypes, [.calendarSeriesCutover])
  }

  func testOutboundFutureCutoverClientPreservesShadowAndCurrentServerDeleteRemainsAbsorbing()
    throws
  {
    let service = try makeService()
    let lineageRootId = "01966a3f-7c8b-7d4e-8f3a-00000000ca42"
    let serverVersion = try Hlc.parse("1711234567950_0000_b1c2d3e4b1c2d3e4")
    let localVersion = try Hlc.parse("1711234567990_0000_a1b2c3d4a1b2c3d4")
    let local = try forwardCompatibleClient(calendarCutoverEnvelope(
      lineageRootId: lineageRootId, date: "2026-08-24", state: .active,
      version: localVersion, deviceId: "future-local-device"))
    let server = try calendarCutoverEnvelope(
      lineageRootId: lineageRootId, date: "2026-08-24", state: .deleted,
      version: serverVersion, deviceId: "current-server-device")

    XCTAssertEqual(try service.applyInbound([local], undecodable: 0).applied, 1)
    let old = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == local.entityId })
    XCTAssertEqual(
      old.envelope.payloadSchemaVersion, LorvexVersion.payloadSchemaVersion + 1)

    let report = try service.reconcileOutbound(
      OutboundReconciliationRequest(collisions: [
        OutboundCollisionRecord(
          outboxId: old.outboxId,
          kind: .semanticMerge(kind: .calendarSeriesCutover, serverEnvelope: server))
      ]))

    let successor = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == local.entityId })
    guard case .object(let successorObject)? = JSONValue.parse(successor.envelope.payload) else {
      return XCTFail("successor payload must be an object")
    }
    XCTAssertEqual(successorObject["future_probe"], .string("preserve-me"))
    XCTAssertEqual(successorObject["state"], .string(CalendarSeriesCutoverState.deleted.rawValue))
    XCTAssertEqual(
      successor.envelope.payloadSchemaVersion, LorvexVersion.payloadSchemaVersion + 1)
    XCTAssertGreaterThan(successor.envelope.version, localVersion)
    XCTAssertNotEqual(successor.outboxId, old.outboxId)
    XCTAssertEqual(report.reconciledCollisionOutboxIds, [old.outboxId])
  }

  func testOutboundRedirectCollisionUnionsTerminalAggregatesAndReportsTheirDomain()
    throws
  {
    let service = try makeService()
    let targetA = "00000000-0000-7000-8000-000000000001"
    let targetB = "22222222-2222-7222-8222-222222222222"
    let source = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let baseVersion = try Hlc.parse("1711234567900_0000_1111222233334444")
    let serverVersion = try Hlc.parse("1711234567950_0000_b1c2d3e4b1c2d3e4")
    let localVersion = try Hlc.parse("1711234567990_0000_a1b2c3d4a1b2c3d4")
    let local = try redirectEnvelope(
      sourceType: .tag, sourceId: source, targetId: targetB,
      version: localVersion, deviceId: "local-redirect-device")
    let server = try redirectEnvelope(
      sourceType: .tag, sourceId: source, targetId: targetA,
      version: serverVersion, deviceId: "remote-redirect-device")

    try service.write { db in
      for (id, name, lookup) in [
        (targetA, "Alpha", "alpha"),
        (targetB, "Bravo", "bravo"),
      ] {
        try db.execute(
          sql: """
            INSERT INTO tags
              (id, display_name, lookup_key, version, created_at, updated_at)
            VALUES (?, ?, ?, ?,
                    '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
            """,
          arguments: [id, name, lookup, baseVersion.description])
      }
      try db.execute(
        sql: """
          INSERT INTO sync_entity_redirects
            (source_type, source_id, target_id, version, created_at)
          VALUES (?, ?, ?, ?, '2026-07-15T00:00:00.000Z')
          """,
        arguments: [EntityKind.tag.asString, source, targetB, localVersion.description])
      _ = try Outbox.enqueueCoalesced(db, local)
    }
    let old = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == local.entityId })

    let report = try service.reconcileOutbound(
      OutboundReconciliationRequest(collisions: [
        OutboundCollisionRecord(
          outboxId: old.outboxId,
          kind: .semanticMerge(kind: .entityRedirect, serverEnvelope: server))
      ]))

    let state = try service.read { db in
      (
        try EntityRedirect.get(
          db, sourceType: EntityKind.tag.asString, sourceId: source),
        try EntityRedirect.get(
          db, sourceType: EntityKind.tag.asString, sourceId: targetB),
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tags WHERE id = ?", arguments: [targetA]) ?? 0,
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tags WHERE id = ?", arguments: [targetB]) ?? 0
      )
    }
    XCTAssertEqual(state.0?.targetId, targetA)
    XCTAssertEqual(state.1?.targetId, targetA)
    XCTAssertEqual(state.2, 1)
    XCTAssertEqual(state.3, 0)
    let successor = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == local.entityId })
    XCTAssertNotEqual(successor.outboxId, old.outboxId)
    XCTAssertGreaterThan(successor.envelope.version, localVersion)
    XCTAssertEqual(report.reconciledCollisionOutboxIds, [old.outboxId])
    XCTAssertEqual(report.inbound.appliedEntityTypes, [.entityRedirect, .tag])
  }

  func testOutboundRedirectLogicalDeleteIsReassertedAtStrictSuccessor() throws {
    let service = try makeService()
    let target = "00000000-0000-7000-8000-000000000001"
    let source = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let localVersion = try Hlc.parse("1711234567950_0000_a1b2c3d4a1b2c3d4")
    let serverDeleteVersion = try Hlc.parse("1711234567990_0000_b1c2d3e4b1c2d3e4")
    let local = try redirectEnvelope(
      sourceType: .tag, sourceId: source, targetId: target,
      version: localVersion, deviceId: "local-redirect-device")
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO tags
            (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES (?, 'Target', 'target', ?,
                  '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
          """,
        arguments: [target, localVersion.description])
      try db.execute(
        sql: """
          INSERT INTO sync_entity_redirects
            (source_type, source_id, target_id, version, created_at)
          VALUES (?, ?, ?, ?, '2026-07-15T00:00:00.000Z')
          """,
        arguments: [EntityKind.tag.asString, source, target, localVersion.description])
      _ = try Outbox.enqueueCoalesced(db, local)
    }
    let old = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == local.entityId })

    let report = try service.reconcileOutbound(
      OutboundReconciliationRequest(collisions: [
        OutboundCollisionRecord(
          outboxId: old.outboxId,
          kind: .entityRedirectDelete(serverEnvelope: SyncEnvelope(
            entityType: .entityRedirect, entityId: local.entityId, operation: .delete,
            version: serverDeleteVersion,
            payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
            payload: "{}", deviceId: "invalid-delete-device")))
      ]))

    let successor = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == local.entityId })
    XCTAssertNotEqual(successor.outboxId, old.outboxId)
    XCTAssertGreaterThan(successor.envelope.version, serverDeleteVersion)
    XCTAssertEqual(
      try service.read { db in
        try EntityRedirect.get(
          db, sourceType: EntityKind.tag.asString, sourceId: source)?.targetId
      },
      target)
    XCTAssertEqual(report.reconciledCollisionOutboxIds, [old.outboxId])
    XCTAssertEqual(report.inbound.appliedEntityTypes, [.entityRedirect])
  }

  func testOutboundRedirectLogicalDeleteWithoutSuccessorHeadroomIsHeld() throws {
    let service = try makeService()
    let target = "00000000-0000-7000-8000-000000000001"
    let source = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let localVersion = try Hlc.parse("1711234567950_0000_a1b2c3d4a1b2c3d4")
    let serverDeleteVersion = try Hlc(
      physicalMs: Hlc.maxPhysicalMs, counter: Hlc.maxCounter,
      deviceSuffix: "b1c2d3e4b1c2d3e4")
    let local = try redirectEnvelope(
      sourceType: .tag, sourceId: source, targetId: target,
      version: localVersion, deviceId: "local-redirect-device")
    let server = SyncEnvelope(
      entityType: .entityRedirect, entityId: local.entityId, operation: .delete,
      version: serverDeleteVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{}", deviceId: "invalid-delete-device")
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO tags
            (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES (?, 'Target', 'target', ?,
                  '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
          """,
        arguments: [target, localVersion.description])
      try db.execute(
        sql: """
          INSERT INTO sync_entity_redirects
            (source_type, source_id, target_id, version, created_at)
          VALUES (?, ?, ?, ?, '2026-07-15T00:00:00.000Z')
          """,
        arguments: [EntityKind.tag.asString, source, target, localVersion.description])
      _ = try Outbox.enqueueCoalesced(db, local)
    }
    let old = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == local.entityId })

    let report = try service.reconcileOutbound(
      OutboundReconciliationRequest(collisions: [
        OutboundCollisionRecord(
          outboxId: old.outboxId,
          kind: .entityRedirectDelete(serverEnvelope: server))
      ]))

    XCTAssertTrue(report.reconciledCollisionOutboxIds.isEmpty)
    XCTAssertTrue(report.inbound.appliedEntityTypes.isEmpty)
    XCTAssertEqual(try service.unresolvedFutureRecordCount(), 1)
    XCTAssertTrue(try service.pendingOutbound().isEmpty)
    let held = try service.read { db in
      try Row.fetchOne(
        db,
        sql: "SELECT id, disposition, future_record_version FROM sync_outbox WHERE id = ?",
        arguments: [old.outboxId])
    }
    let heldRow = try XCTUnwrap(held)
    XCTAssertEqual(heldRow["disposition"] as String?, "future_record_hold")
    XCTAssertEqual(
      heldRow["future_record_version"] as String?, serverDeleteVersion.description)
    XCTAssertEqual(
      try service.read { db in
        try EntityRedirect.get(
          db, sourceType: EntityKind.tag.asString, sourceId: source)?.targetId
      },
      target)
  }

  func testDirectInboundRedirectReportsRedirectAndUnderlyingAggregateDomains() throws {
    let service = try makeService()
    let target = "00000000-0000-7000-8000-000000000001"
    let source = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let version = try Hlc.parse("1711234567950_0000_b1c2d3e4b1c2d3e4")
    let redirect = try redirectEnvelope(
      sourceType: .tag, sourceId: source, targetId: target,
      version: version, deviceId: "remote-redirect-device")
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO tags
            (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES (?, 'Target', 'target', ?,
                  '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
          """,
        arguments: [target, version.description])
    }

    let report = try service.applyInbound([redirect], undecodable: 0)

    XCTAssertEqual(report.applied, 1)
    XCTAssertEqual(report.appliedEntityTypes, [.entityRedirect, .tag])
  }

  func testPendingRedirectReplayReportsRedirectAndUnderlyingAggregateDomains() throws {
    let service = try makeService()
    let target = "00000000-0000-7000-8000-000000000001"
    let source = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let version = try Hlc.parse("1711234567950_0000_b1c2d3e4b1c2d3e4")
    let redirect = try redirectEnvelope(
      sourceType: .tag, sourceId: source, targetId: target,
      version: version, deviceId: "remote-redirect-device")

    let deferred = try service.applyInbound([redirect], undecodable: 0)
    XCTAssertEqual(deferred.deferred, 1)
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO tags
            (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES (?, 'Target', 'target', ?,
                  '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
          """,
        arguments: [target, version.description])
    }

    let replay = try service.applyInbound([], undecodable: 0)

    XCTAssertEqual(replay.drainReplayed, 1)
    XCTAssertEqual(replay.appliedEntityTypes, [.entityRedirect, .tag])
  }

  func testOutboundCalendarRegisterCollisionWithoutLegalSuccessorNeverConfirmsOldOutbox()
    throws
  {
    let service = try makeService()
    let eventId = "01966a3f-7c8b-7d4e-8f3a-00000000ca12"
    let localVersion = try Hlc.parse("1711234567200_0000_a1b2c3d4a1b2c3d4")
    let serverVersion = try Hlc(
      physicalMs: Hlc.maxPhysicalMs, counter: 0,
      deviceSuffix: "b1c2d3e4b1c2d3e4")
    let local = try calendarBaseEnvelope(
      id: eventId, title: "Local content", startDate: "2026-07-20",
      contentVersion: localVersion, topologyVersion: localVersion,
      rowVersion: localVersion, deviceId: "local-device")
    let server = try calendarBaseEnvelope(
      id: eventId, title: "Remote future", startDate: "2026-08-20",
      contentVersion: localVersion, topologyVersion: serverVersion,
      rowVersion: serverVersion, deviceId: "future-device")

    XCTAssertEqual(try service.applyInbound([local], undecodable: 0).applied, 1)
    let localPayload = try XCTUnwrap(JSONValue.parse(local.payload))
    try service.write { db in
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: local.entityType.asString, entityId: local.entityId,
        payload: localPayload,
        context: OutboxWriteContext(
          version: local.version.description, deviceId: local.deviceId))
    }
    let old = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == eventId })

    let report = try service.reconcileOutbound(
      OutboundReconciliationRequest(collisions: [
        OutboundCollisionRecord(
          outboxId: old.outboxId,
          kind: .semanticMerge(kind: .calendarBaseRegisters, serverEnvelope: server))
      ]))

    XCTAssertTrue(report.reconciledCollisionOutboxIds.isEmpty)
    let state = try service.read { db in
      (
        try Row.fetchOne(
          db,
          sql: "SELECT synced_at, disposition, future_record_version "
            + "FROM sync_outbox WHERE id = ?",
          arguments: [old.outboxId]),
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_pending_inbox "
            + "WHERE envelope_entity_type = ? AND envelope_entity_id = ?",
          arguments: [EntityKind.calendarEvent.asString, eventId]) ?? 0,
        try String.fetchOne(
          db, sql: "SELECT title FROM calendar_events WHERE id = ?", arguments: [eventId])
      )
    }
    let oldRow = try XCTUnwrap(state.0)
    XCTAssertNil(oldRow["synced_at"] as String?)
    XCTAssertEqual(oldRow["disposition"] as String?, "future_record_hold")
    XCTAssertEqual(oldRow["future_record_version"] as String?, serverVersion.description)
    XCTAssertEqual(state.1, 1)
    XCTAssertEqual(state.2, "Local content")
  }

  func testOutboundCollisionBatchRollsBackEarlierRepairWhenLaterCapabilityIsInvalid()
    async throws
  {
    let service = try makeService()
    let firstTask = try await service.createTask(title: "First local", notes: "")
    let secondTask = try await service.createTask(title: "Second local", notes: "")
    let pending = try service.pendingOutbound()
    let first = try XCTUnwrap(pending.first { $0.envelope.entityId == firstTask.id })
    let second = try XCTUnwrap(pending.first { $0.envelope.entityId == secondTask.id })
    let firstServer = try taskEnvelope(
      byReplacingTitle: first.envelope, with: "First divergent server")
    let mismatchedVersion = try Hlc(
      physicalMs: second.envelope.version.physicalMs + 1, counter: 0,
      deviceSuffix: second.envelope.version.deviceSuffix)
    let invalidSecondServer = try taskEnvelope(
      byReplacingTitle: second.envelope, with: "Invalid second server",
      version: mismatchedVersion)

    XCTAssertThrowsError(
      try service.reconcileOutbound(
        OutboundReconciliationRequest(collisions: [
          OutboundCollisionRecord(
            outboxId: first.outboxId,
            kind: .equalVersion(serverEnvelope: firstServer)),
          OutboundCollisionRecord(
            outboxId: second.outboxId,
            kind: .equalVersion(serverEnvelope: invalidSecondServer)),
        ]))) { error in
          XCTAssertEqual(
            error as? SwiftLorvexCoreService.OutboundCollisionReconciliationError,
            .mismatchedVersion(outboxId: second.outboxId))
        }

    let after = try service.pendingOutbound()
    let firstAfter = try XCTUnwrap(after.first { $0.envelope.entityId == firstTask.id })
    let secondAfter = try XCTUnwrap(after.first { $0.envelope.entityId == secondTask.id })
    XCTAssertEqual(firstAfter.outboxId, first.outboxId)
    XCTAssertEqual(firstAfter.envelope, first.envelope)
    XCTAssertEqual(secondAfter.outboxId, second.outboxId)
    XCTAssertEqual(secondAfter.envelope, second.envelope)
    XCTAssertEqual(
      try service.read { db in
        try String.fetchOne(db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [firstTask.id])
      }, "First local")
  }

  func testOutboundCollisionForCoalescedOldCapabilityIsIgnoredAndNotReceipted()
    async throws
  {
    let service = try makeService()
    let task = try await service.createTask(title: "In-flight old intent", notes: "")
    let old = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == task.id })

    _ = try await service.updateTask(
      id: task.id, title: "New local intent", notes: "", priority: .p2,
      estimatedMinutes: nil, plannedDate: nil, tags: [], dependsOn: [])
    let replacementBefore = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == task.id })
    XCTAssertNotEqual(replacementBefore.outboxId, old.outboxId)

    let higherServerFloor = try Hlc(
      physicalMs: replacementBefore.envelope.version.physicalMs + 1,
      counter: 0, deviceSuffix: "eeeeeeeeeeeeeeee")
    let report = try service.reconcileOutbound(
      OutboundReconciliationRequest(collisions: [
        OutboundCollisionRecord(
          outboxId: old.outboxId,
          kind: .corruptServerSlot(serverVersionFloor: higherServerFloor))
      ]))

    XCTAssertTrue(report.reconciledCollisionOutboxIds.isEmpty)
    let replacementAfter = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == task.id })
    XCTAssertEqual(replacementAfter, replacementBefore)
    let loaded = try await service.loadTask(id: task.id)
    XCTAssertEqual(loaded.title, "New local intent")
  }

  func testOutboundAuditCollisionReplacesImmutableProjectionAndEnqueuesSuccessor()
    async throws
  {
    let service = try makeService()
    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: "audit-collision-account",
      zoneName: "LorvexData-e1-audit-collision")
    _ = try await service.createTask(title: "Audited local write", notes: "")
    let local = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityType == .aiChangelog })
    guard case .object(var serverObject)? = JSONValue.parse(local.envelope.payload) else {
      return XCTFail("local audit payload must be an object")
    }
    serverObject["summary"] = .string("Divergent cloned audit summary")
    let server = SyncEnvelope(
      entityType: local.envelope.entityType,
      entityId: local.envelope.entityId,
      operation: local.envelope.operation,
      version: local.envelope.version,
      payloadSchemaVersion: local.envelope.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(serverObject)),
      deviceId: "cloned-peer")
    let expected = try SyncMutationSemantics.deterministicWinner(
      local.envelope, server)
    guard case .object(let expectedObject)? = JSONValue.parse(expected.payload),
      case .string(let expectedSummary)? = expectedObject["summary"]
    else { return XCTFail("deterministic audit winner must carry a summary") }

    let report = try service.reconcileOutbound(
      OutboundReconciliationRequest(collisions: [
        OutboundCollisionRecord(
          outboxId: local.outboxId,
          kind: .equalVersion(serverEnvelope: server))
      ]))

    let replacement = try XCTUnwrap(
      try service.pendingOutbound().first {
        $0.envelope.entityType == .aiChangelog
          && $0.envelope.entityId == local.envelope.entityId
      })
    XCTAssertNotEqual(replacement.outboxId, local.outboxId)
    XCTAssertGreaterThan(replacement.envelope.version, local.envelope.version)
    XCTAssertEqual(report.reconciledCollisionOutboxIds, [local.outboxId])
    XCTAssertEqual(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT summary FROM ai_changelog WHERE id = ?",
          arguments: [local.envelope.entityId])
      },
      expectedSummary)
  }

  func testOutboundAuditImmutableConflictChoosesVersionIndependentContent()
    async throws
  {
    let service = try makeService()
    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: "audit-immutable-account",
      zoneName: "LorvexData-e1-audit-immutable")
    _ = try await service.createTask(title: "Audited immutable write", notes: "")
    let local = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityType == .aiChangelog })
    guard case .object(var serverObject)? = JSONValue.parse(local.envelope.payload) else {
      return XCTFail("local audit payload must be an object")
    }
    serverObject["summary"] = .string("Higher-HLC server audit summary")
    let serverVersion = try Hlc(
      physicalMs: local.envelope.version.physicalMs + 1, counter: 0,
      deviceSuffix: "eeeeeeeeeeeeeeee")
    serverObject["version"] = .string(serverVersion.description)
    let server = SyncEnvelope(
      entityType: local.envelope.entityType,
      entityId: local.envelope.entityId,
      operation: local.envelope.operation,
      version: serverVersion,
      payloadSchemaVersion: local.envelope.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(serverObject)),
      deviceId: "newer-peer")
    let expected = try SyncMutationSemantics.deterministicWinnerIgnoringVersion(
      local.envelope, server)
    guard case .object(let expectedObject)? = JSONValue.parse(expected.payload),
      case .string(let expectedSummary)? = expectedObject["summary"]
    else { return XCTFail("deterministic audit winner must carry a summary") }

    let report = try service.reconcileOutbound(
      OutboundReconciliationRequest(collisions: [
        OutboundCollisionRecord(
          outboxId: local.outboxId,
          kind: .immutableIdentity(serverEnvelope: server))
      ]))

    let replacement = try XCTUnwrap(
      try service.pendingOutbound().first {
        $0.envelope.entityType == .aiChangelog
          && $0.envelope.entityId == local.envelope.entityId
      })
    XCTAssertGreaterThan(replacement.envelope.version, serverVersion)
    XCTAssertEqual(report.reconciledCollisionOutboxIds, [local.outboxId])
    XCTAssertEqual(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT summary FROM ai_changelog WHERE id = ?",
          arguments: [local.envelope.entityId])
      },
      expectedSummary)
  }

  /// SY2: a PERSISTENT per-row failure still escalates through the same-error
  /// heuristic and, on crossing maxRetries, enters durable retry wait with a
  /// surfaced diagnostic and an automatic future recovery time.
  func testPersistentOutboundFailureEntersRetryWaitAndLogs() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Poison payload", notes: "")
    let id = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == task.id }?.outboxId)

    // Three identical persistent errors escalate to maxRetries (fast-fail).
    let persistentError = "CloudKit rejected record: payload too large"
    for _ in 0..<3 {
      try service.recordOutboundFailure(outboxId: id, error: persistentError, kind: .perRecord)
    }

    XCTAssertFalse(
      try service.pendingOutbound().contains { $0.outboxId == id },
      "a persistent per-row error must pause until its retry due time")
    let state = try service.read { db in
      try Row.fetchOne(
        db,
        sql: "SELECT retry_count, disposition, next_retry_at FROM sync_outbox WHERE id = ?",
        arguments: [id])
    }
    let row = try XCTUnwrap(state)
    XCTAssertEqual(row["retry_count"] as Int64, Outbox.maxRetries)
    XCTAssertEqual(
      row["disposition"] as String?,
      Outbox.Disposition.retryWait.rawValue)
    XCTAssertNotNil(row["next_retry_at"] as String?)
    let retryWaitLogs = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.outbox.retry_wait'") ?? 0
    }
    XCTAssertGreaterThanOrEqual(retryWaitLogs, 1, "retry wait must be surfaced to error_logs")
  }

  /// Runtime/MCP diagnostics report ordinary retry wait as a failed outbound
  /// item, but not an intentional authoritative-adoption fence.
  func testSyncDiagnosticsDistinguishRetryWaitFromAuthoritativeAdoption() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Diagnostic retry", notes: "")
    let id = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == task.id }?.outboxId)
    let pendingBefore = try await service.loadRuntimeDiagnostics().sync.pendingCount
    for _ in 0..<3 {
      try service.recordOutboundFailure(
        outboxId: id, error: "CloudKit rejected record", kind: .perRecord)
    }

    let waiting = try await service.loadRuntimeDiagnostics().sync
    XCTAssertEqual(waiting.failedCount, 1)
    XCTAssertEqual(waiting.pendingCount, pendingBefore - 1)

    _ = try beginAuthoritativeSnapshot(
      service, accountIdentifier: "diagnostics-test-account")
    let adopted = try await service.loadRuntimeDiagnostics().sync
    XCTAssertEqual(adopted.failedCount, 0)
    XCTAssertEqual(adopted.pendingCount, 0)
  }

  /// The facade must release only the canceled snapshot's discard fences, not
  /// revive their stale payloads. A later local-authoritative rebuild then
  /// re-enqueues the current DB snapshot through the ordinary full-resync path.
  func testCancelAuthoritativeSnapshotReleasesFenceForLaterFullResync() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Local rebuild winner", notes: "")
    let originalVersion = try service.read { db in
      try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [task.id])
    }

    _ = try beginAuthoritativeSnapshot(
      service, accountIdentifier: "cancel-test-account")
    XCTAssertTrue(try service.pendingOutbound().isEmpty)

    try service.cancelAuthoritativeSnapshot()
    XCTAssertTrue(
      try service.pendingOutbound().isEmpty,
      "cancel discards the old queue instead of re-arming pre-adoption writes")
    let remainingFences = try service.read { db in
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM sync_outbox
          WHERE disposition = 'authoritative_adoption'
          """) ?? -1
    }
    XCTAssertEqual(remainingFences, 0)

    let report = try service.enqueueFullResyncBackfill()
    XCTAssertGreaterThan(report.emitted, 0)
    let rebuilt = try XCTUnwrap(
      try service.pendingOutbound().map(\.envelope).first {
        $0.entityType == .task && $0.entityId == task.id
      })
    XCTAssertEqual(rebuilt.version.description, originalVersion)
  }

  /// End-to-end through `EnvelopeSyncServicing`: successful remote-authoritative
  /// finalization must discard a fenced newer local payload, then leave the
  /// unique slot free for a later lower-HLC full-resync enqueue.
  func testFinalizeAuthoritativeSnapshotReleasesFenceForLowerHlcFullResync() async throws {
    let service = try makeService()
    let inboxId = try seededListId(service)
    let local = try await service.createTask(title: "Newer stale local", notes: "")
    let remote = taskUpsertEnvelope(
      id: local.id, title: "Adopted lower-HLC remote", listId: inboxId)
    let inboxEnvelope = try service.read { db -> SyncEnvelope in
      let snapshot = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.list, entityId: inboxId)
      guard case .object(var fields) = snapshot else {
        throw XCTSkip("seeded inbox payload must be an object")
      }
      fields["version"] = .string(remote.version.description)
      return SyncEnvelope(
        entityType: .list, entityId: inboxId, operation: .upsert,
        version: remote.version,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(.object(fields)),
        deviceId: "remote-device")
    }
    let staged: (SyncEnvelope) -> AuthoritativeSnapshotRemoteRecord = { envelope in
      AuthoritativeSnapshotRemoteRecord(
        recordName: SyncRecordName.opaque(
          entityType: envelope.entityType.asString, entityId: envelope.entityId),
        state: .decoded, envelope: envelope)
    }

    let session = try beginAuthoritativeSnapshot(
      service, accountIdentifier: "finalize-test-account")
    try service.markAuthoritativeSnapshotReady(sessionToken: session.sessionToken)
    try service.stageAuthoritativeSnapshotPage(
      records: [staged(inboxEnvelope), staged(remote)], deletedRecordNames: [],
      sessionToken: session.sessionToken)

    _ = try service.finalizeAuthoritativeSnapshot(
      sessionToken: session.sessionToken, accountIdentifier: session.accountIdentifier,
      zoneName: session.zoneName, enrolledZoneEpoch: nil)
    let adopted = try service.read { db in
      try Row.fetchOne(
        db, sql: "SELECT title, version FROM tasks WHERE id = ?", arguments: [local.id])
    }
    let adoptedRow = try XCTUnwrap(adopted)
    XCTAssertEqual(adoptedRow["title"] as String, "Adopted lower-HLC remote")
    XCTAssertEqual(adoptedRow["version"] as String, remote.version.description)
    XCTAssertFalse(
      try service.pendingOutbound().contains {
        $0.envelope.entityType == .task && $0.envelope.entityId == local.id
      },
      "the stale pre-adoption task payload must not survive finalization")
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE disposition = 'authoritative_adoption'")
          ?? -1
      },
      0)

    let report = try service.enqueueFullResyncBackfill()
    let rebuilt = try XCTUnwrap(
      try service.pendingOutbound().map(\.envelope).first {
        $0.entityType == .task && $0.entityId == local.id
      })
    XCTAssertGreaterThan(report.emitted, 0)
    XCTAssertEqual(rebuilt.version, remote.version)
  }

  /// A WHOLESALE chunk failure stamps the identical error on every row each
  /// cycle — the exact shape the same-error heuristic reads as a poisoned row —
  /// but it is chunk-level, not per-record, evidence. Reported `.wholesale`, it
  /// advances `retry_count` linearly (a genuinely persistent failure still
  /// enters retry wait at `maxRetries`) and never fast-forwards early.
  func testWholesaleOutboundFailureDoesNotFastForwardToRetryWait() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Chunk-failure edit", notes: "")
    let id = try XCTUnwrap(
      try service.pendingOutbound().first { $0.envelope.entityId == task.id }?.outboxId)

    let wholesaleError = "push chunk failed: The operation couldn't be completed."
    for _ in 0..<5 {
      try service.recordOutboundFailure(outboxId: id, error: wholesaleError, kind: .wholesale)
    }

    XCTAssertTrue(
      try service.pendingOutbound().contains { $0.outboxId == id },
      "a wholesale failure must not park the row after three identical repeats")
    let retryCount = try service.read { db in
      try Int64.fetchOne(db, sql: "SELECT retry_count FROM sync_outbox WHERE id = ?", arguments: [id])
    }
    XCTAssertEqual(retryCount, 5, "retry_count advances linearly, no fast-forward")
    let retryWaitLogs = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.outbox.retry_wait'") ?? -1
    }
    XCTAssertEqual(retryWaitLogs, 0, "no retry wait is logged before wholesale exhaustion")
  }

  /// `applyInbound` routes an upsert envelope through `Apply.applyEnvelope` and
  /// materializes the entity — proving the inbound path uses the engine (not a
  /// reimplemented applier) and that conflict resolution / FK gating run.
  func testApplyInboundUpsertsTaskThroughEngine() async throws {
    let service = try makeService()
    let envelope = taskUpsertEnvelope(listId: try seededListId(service))

    let report = try service.applyInbound([envelope], undecodable: 0)

    XCTAssertEqual(report.applied, 1)
    XCTAssertEqual(report.skipped + report.deferred + report.remapped, 0)
    XCTAssertEqual(report.undecodable, 0)

    let exists = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?",
        arguments: [envelope.entityId]) ?? 0
    }
    XCTAssertEqual(exists, 1)
  }

  /// `applyInbound` reports the distinct entity kinds it actually CHANGED, so a
  /// store can reload only the affected surfaces. An applied upsert's kind is
  /// present; an envelope that fails to apply (here a bad-JSON habit, dropped as
  /// undecodable) contributes nothing — proving the set never over-claims a kind
  /// whose rows never changed.
  func testApplyInboundReportsAppliedEntityKinds() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let task = taskUpsertEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-000000000091",
      title: "Applied task",
      listId: listId)
    let badHabit = SyncEnvelope(
      entityType: .habit,
      entityId: "01966a3f-7c8b-7d4e-8f3a-000000000092",
      operation: .upsert,
      version: try Hlc.parse("1711234567899_0000_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{ invalid json",
      deviceId: "device-remote")

    let report = try service.applyInbound([task, badHabit], undecodable: 0)

    XCTAssertEqual(report.applied, 1)
    XCTAssertEqual(report.undecodable, 1)
    XCTAssertEqual(report.appliedEntityTypes, [.task])
  }

  /// A payload-level bad envelope must not roll back valid siblings in the same
  /// inbound batch. The invalid row is reported as undecodable and the already
  /// applied envelope remains committed.
  func testApplyInboundInvalidPayloadDoesNotRollbackValidEnvelope() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let valid = taskUpsertEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-000000000011",
      title: "Inbound valid sibling",
      listId: listId)
    let invalid = SyncEnvelope(
      entityType: .task,
      entityId: "01966a3f-7c8b-7d4e-8f3a-000000000012",
      operation: .upsert,
      version: try Hlc.parse("1711234567891_0000_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{ invalid json",
      deviceId: "device-remote")

    let report = try service.applyInbound([valid, invalid], undecodable: 0)

    XCTAssertEqual(report.applied, 1)
    XCTAssertEqual(report.undecodable, 1)
    let existingIds = try service.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT id FROM tasks WHERE id IN (?, ?) ORDER BY id",
        arguments: [valid.entityId, invalid.entityId])
    }
    XCTAssertEqual(existingIds, [valid.entityId])
  }

  /// FND-APPLY-2: a single malformed-payload record that DEFERS to the pending
  /// inbox must be DROPPED, never wedge the whole inbound batch. The pending-inbox
  /// enqueue rejects a malformed payload with `EnqueueError.malformedPayload` — a
  /// type distinct from `ApplyError` — so it escaped the batch loop's
  /// `catch ... as ApplyError`, aborted `applyInbound`, and left the CloudKit
  /// change token unsaved; the poison page then re-fetched and re-failed forever (a
  /// permanent inbound-sync wedge on one crafted record). A schema-too-new envelope
  /// defers BEFORE its payload is parsed by the apply pipeline, so a payload that is
  /// not valid JSON reaches the enqueue and trips the malformed-payload rejection.
  func testApplyInboundMalformedDeferredRecordDroppedNotWedged() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let poison = SyncEnvelope(
      entityType: .task,
      entityId: "01966a3f-7c8b-7d4e-8f3a-0000000000f1",
      operation: .upsert,
      version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 2,  // deferToPendingInbox
      payload: "not valid json",
      deviceId: "device-remote")
    let valid = taskUpsertEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-0000000000f2", title: "Valid sibling", listId: listId)

    // Poison ordered FIRST so a wrongful batch-abort would starve the sibling and
    // never advance the change token.
    let report = try service.applyInbound([poison, valid], undecodable: 0)

    XCTAssertEqual(
      report.applied, 1, "valid sibling must apply — the malformed record must not wedge the batch")
    XCTAssertEqual(report.undecodable, 1, "the malformed-payload record is dropped, not retained")
    XCTAssertEqual(report.deferred, 0, "a malformed record cannot be parked — it is dropped")
    let ids = try service.read { db in
      try String.fetchAll(
        db, sql: "SELECT id FROM tasks WHERE id IN (?, ?) ORDER BY id",
        arguments: [poison.entityId, valid.entityId])
    }
    XCTAssertEqual(ids, [valid.entityId], "the malformed record must not have landed")
    XCTAssertGreaterThanOrEqual(
      try droppedInvalidLogCount(service), 1, "the drop must be observable in error_logs")
  }

  // MARK: - D4 trust-boundary CHECK validation + constraint drop-not-wedge

  /// Build a `task` upsert envelope with arbitrary payload overrides on top of
  /// the schema-valid minimum, at the current schema version.
  private func taskEnvelope(
    id: String, version: String, listId: String, overrides: [String: JSONValue]
  ) -> SyncEnvelope {
    var obj: [String: JSONValue] = [
      "title": .string("Inbound"),
      "status": .string("open"),
      "list_id": .string(listId),
      "created_at": .string("2026-04-01T00:00:00.000Z"),
      "updated_at": .string("2026-04-01T00:00:00.000Z"),
    ]
    for (k, v) in overrides { obj[k] = v }
    return SyncEnvelope(
      entityType: .task, entityId: id, operation: .upsert,
      version: try! Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: (try? SyncCanonicalize.canonicalizeJSON(.object(obj))) ?? "{}",
      deviceId: "device-remote")
  }

  private func droppedInvalidLogCount(_ service: SwiftLorvexCoreService) throws -> Int {
    try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.inbound_invalid'")
        ?? 0
    }
  }

  /// A task carrying a malformed `recurrence` rule drops at the trust boundary
  /// (the normalizer rejects it) and the batch continues.
  func testApplyInboundTaskMalformedRecurrenceDroppedNotWedged() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let bad = taskEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-0000000000d3",
      version: "1711234567890_0000_a1b2c3d4a1b2c3d4", listId: listId,
      overrides: [
        "recurrence": .string("{\"FREQ\":\"HOURLY\"}"),
        "due_date": .string("2026-05-01"),
        "recurrence_group_id": .string("grp-1"),
        "canonical_occurrence_date": .string("2026-05-01"),
      ])
    let valid = taskUpsertEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-0000000000d4", title: "Valid sibling", listId: listId)

    let report = try service.applyInbound([bad, valid], undecodable: 0)

    XCTAssertEqual(report.applied, 1)
    XCTAssertEqual(report.undecodable, 1)
    let ids = try service.read { db in
      try String.fetchAll(
        db, sql: "SELECT id FROM tasks WHERE id IN (?, ?) ORDER BY id",
        arguments: [bad.entityId, valid.entityId])
    }
    XCTAssertEqual(ids, [valid.entityId])
  }

  /// An honest recurring task (canonical rule + all companion fields) applies
  /// through the batch unchanged — the new validation must not reject valid data.
  func testApplyInboundValidRecurringTaskApplies() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let recurring = try CurrentSyncEnvelopeTestSupport.complete(
      taskEnvelope(
        id: "01966a3f-7c8b-7d4e-8f3a-0000000000d5",
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4", listId: listId,
        overrides: [
          "recurrence": .string("{\"FREQ\":\"WEEKLY\",\"INTERVAL\":1}"),
          "due_date": .string("2026-05-01"),
          "recurrence_group_id": .string("01966a3f-7c8b-7d4e-8f3a-0000000000d5"),
          "canonical_occurrence_date": .string("2026-05-01"),
        ]))

    let report = try service.applyInbound([recurring], undecodable: 0)

    XCTAssertEqual(report.applied, 1)
    XCTAssertEqual(report.undecodable, 0)
    let stored = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT recurrence FROM tasks WHERE id = ?", arguments: [recurring.entityId])
    }
    XCTAssertEqual(stored, "{\"FREQ\":\"WEEKLY\",\"INTERVAL\":1}")
  }

  /// A `daily_review` with `mood = 9` violates `CHECK (mood BETWEEN 1 AND 5)`.
  /// The trust-boundary validator drops it and a valid task sibling still applies.
  func testApplyInboundDayReviewMoodOutOfRangeDroppedNotWedged() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let badReview = SyncEnvelope(
      entityType: .dailyReview, entityId: "2026-04-01", operation: .upsert,
      version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: (try? SyncCanonicalize.canonicalizeJSON(
        .object([
          "summary": .string("bad mood value"), "mood": .int(9),
          "created_at": .string("2026-04-01T00:00:00Z"),
          "updated_at": .string("2026-04-01T00:00:00Z"),
        ]))) ?? "{}",
      deviceId: "device-remote")
    let valid = taskUpsertEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-0000000000d6", title: "Valid sibling", listId: listId)

    let report = try service.applyInbound([badReview, valid], undecodable: 0)

    XCTAssertEqual(report.applied, 1)
    XCTAssertEqual(report.undecodable, 1)
    XCTAssertEqual(report.deferred, 0)
    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM daily_reviews WHERE date = ?", arguments: ["2026-04-01"])
          ?? -1, 0, "the out-of-range review must not have landed")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [valid.entityId]) ?? -1,
        1)
    }
  }

  /// Defense-in-depth (D4 Layer 2): a DETERMINISTIC SQLITE_CONSTRAINT that
  /// ESCAPES the trust-boundary validators must still degrade to a single dropped
  /// envelope, not a batch-fatal wedge. A `focus_schedule` block typed `task`
  /// with a null `task_id` trips the `(block_type, task_id, event_id)`
  /// consistency CHECK inside the applier — a constraint the day-scoped validators
  /// do not pre-empt. The classifier maps it to `.dbConstraint` (non-fatal), so a
  /// valid task sibling ordered after it still applies.
  func testApplyInboundDeterministicConstraintDroppedNotWedged() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let badSchedule = SyncEnvelope(
      entityType: .focusSchedule, entityId: "2026-04-01", operation: .upsert,
      version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: (try? SyncCanonicalize.canonicalizeJSON(
        .object([
          "created_at": .string("2026-04-01T00:00:00Z"),
          "updated_at": .string("2026-04-01T00:00:00Z"),
          "blocks": .array([
            // block_type "task" REQUIRES a non-null task_id; omitting it trips
            // the schema CHECK the day-scoped applier does not pre-validate.
            .object([
              "block_type": .string("task"), "start_minutes": .int(540), "end_minutes": .int(570),
              "event_source": .null,
            ])
          ]),
        ]))) ?? "{}",
      deviceId: "device-remote")
    let valid = taskUpsertEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-0000000000d7", title: "Valid sibling", listId: listId)

    // Constraint-violating envelope FIRST: before the classifier fix this
    // re-aborted the whole page (batch-fatal); now it drops and the batch drains.
    let report = try service.applyInbound([badSchedule, valid], undecodable: 0)

    XCTAssertEqual(
      report.applied, 1, "valid sibling must apply — a deterministic constraint must not wedge")
    XCTAssertEqual(report.undecodable, 1, "the constraint-tripping envelope is dropped")
    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule WHERE date = ?", arguments: ["2026-04-01"])
          ?? -1, 0, "the whole envelope savepoint rolled back — no partial focus_schedule row")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [valid.entityId]) ?? -1,
        1)
    }
  }

  /// Build a `calendar_event` upsert envelope. When `attendees` is nil the key is
  /// OMITTED entirely (an older/partial peer); otherwise it is carried verbatim.
  private func calendarEventEnvelope(
    id: String, version: String, attendees: JSONValue?
  ) throws -> SyncEnvelope {
    var obj: [String: JSONValue] = [
      "title": .string("Standup"),
      "start_date": .string("2026-04-20"),
      "start_time": .string("09:00"),
      "all_day": .bool(false),
      "event_type": .string("event"),
      "created_at": .string("2026-04-20T09:00:00.000Z"),
      "updated_at": .string("2026-04-20T09:00:00.000Z"),
    ]
    if let attendees { obj["attendees"] = attendees }
    return try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .calendarEvent, entityId: id, operation: .upsert,
        version: try Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(.object(obj)),
        deviceId: "device-remote"))
  }

  private func attendeesColumn(_ service: SwiftLorvexCoreService, eventId: String) throws -> String? {
    try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT attendees FROM calendar_events WHERE id = ?", arguments: [eventId])
    }
  }

  /// `attendees` is a plain last-writer-wins JSON column: an inbound envelope
  /// carrying it stores it verbatim, and a later (strictly newer) envelope that
  /// OMITS it clears the column — no absence-preserve, no re-emit.
  func testInboundAttendeesColumnIsPlainLastWriterWins() async throws {
    let eventId = "01966a3f-7c8b-7d4e-8f3a-0000000000c1"
    let v1 = "1711234567890_0000_a1b2c3d4a1b2c3d4"
    let v2 = "1711234567891_0000_a1b2c3d4a1b2c3d4"
    let alice: JSONValue = .array([.object(["email": .string("alice@example.com")])])

    let service = try makeService()
    _ = try service.applyInbound(
      [calendarEventEnvelope(id: eventId, version: v1, attendees: alice)], undecodable: 0)
    XCTAssertEqual(
      JSONValue.parse(try XCTUnwrap(attendeesColumn(service, eventId: eventId))), alice,
      "inbound attendees are stored verbatim in the column")

    _ = try service.applyInbound(
      [calendarEventEnvelope(id: eventId, version: v2, attendees: nil)], undecodable: 0)
    XCTAssertNil(
      try attendeesColumn(service, eventId: eventId),
      "a later envelope omitting attendees clears the column (plain LWW, no preserve)")
  }

  /// VERIFY-APPLY resolveListId: a `task` upsert whose payload names a `list_id`
  /// this device has ordinarily tombstoned rehomes to inbox via the per-device
  /// fallback. That leaves the task in a different list than the envelope named, so
  /// a peer that still holds the list would keep the task there under the same
  /// version. The fallback must re-emit a fresh-HLC upsert of the resolved snapshot
  /// (list_id = inbox) so peers converge.
  func testTaskListFallbackRehomeReemitsResolvedList() async throws {
    let service = try makeService()
    let inboxId = try seededListId(service)
    let deadListId = "01966a3f-7c8b-7d4e-8f3a-0000000000a1"
    // An ordinary tombstone for a list this device has deleted.
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
          VALUES ('list', ?, ?, '2026-04-01T00:00:00.000Z')
          """,
        arguments: [deadListId, "1711234567000_0000_a1b2c3d4a1b2c3d4"])
    }
    let taskId = "01966a3f-7c8b-7d4e-8f3a-0000000000a2"
    let envVersion = "1711234567890_0000_a1b2c3d4a1b2c3d4"
    let env = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .task, entityId: taskId, operation: .upsert,
        version: try Hlc.parse(envVersion),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "title": .string("Rehomed"), "status": .string("open"),
            "list_id": .string(deadListId),
            "created_at": .string("2026-04-01T00:00:00.000Z"),
            "updated_at": .string("2026-04-01T00:00:00.000Z"),
          ])),
        deviceId: "device-remote"))

    let report = try service.applyInbound([env], undecodable: 0)
    XCTAssertEqual(report.applied, 1, "the task applies (rehomed), not deferred")

    let landedList = try service.read { db in
      try String.fetchOne(db, sql: "SELECT list_id FROM tasks WHERE id = ?", arguments: [taskId])
    }
    XCTAssertEqual(landedList, inboxId, "the task rehomes to inbox, not the tombstoned list")

    let reemits = try service.pendingOutbound().map { $0.envelope }.filter {
      $0.entityType == .task && $0.entityId == taskId
    }
    let reemit = try XCTUnwrap(
      reemits.first, "the fallback rehome must re-emit the resolved snapshot")
    XCTAssertGreaterThan(
      reemit.version, try Hlc.parse(envVersion), "the re-emit must carry a dominating HLC")
    guard case let .object(obj)? = JSONValue.parse(reemit.payload),
      case let .string(reemitListId)? = obj["list_id"]
    else {
      return XCTFail("re-emit payload must carry a string list_id")
    }
    XCTAssertEqual(reemitListId, inboxId, "the re-emit propagates the resolved (inbox) list_id")
  }

  /// DE-3: a forward-compat envelope carrying an additive unknown top-level field
  /// on the natural `+1` `payload_schema_version` applies its known projection,
  /// retains the unknown field in a payload shadow, and does not abort a valid
  /// sibling ordered after it.
  func testApplyInboundForwardCompatEnvelopeAppliesKnownFieldsAndShadowsUnknownKey()
    async throws
  {
    let service = try makeService()
    let listId = try seededListId(service)
    let forwardCompat = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .focusSchedule,
        entityId: "2026-04-01",
        operation: .upsert,
        version: try Hlc.parse("1711234567893_0000_a1b2c3d4a1b2c3d4"),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "created_at": .string("2026-04-01T00:00:00Z"),
            "updated_at": .string("2026-04-01T00:00:00Z"),
            "future_metadata": .object(["planner": .string("v2")]),
          ])),
        deviceId: "device-remote"))
    let valid = taskUpsertEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-000000000031",
      title: "Valid sibling after forward-compat apply",
      listId: listId)

    // Forward-compat envelope ordered FIRST so a wrongful batch-abort would
    // starve the valid sibling.
    let report = try service.applyInbound([forwardCompat, valid], undecodable: 0)

    XCTAssertEqual(report.deferred, 0)
    XCTAssertEqual(
      report.applied, 2, "the known projection and valid sibling must both apply")
    XCTAssertEqual(report.undecodable, 0, "an additive future field is not corruption")

    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [valid.entityId])
          ?? 0, 1)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule WHERE date = ?", arguments: ["2026-04-01"])
          ?? 0, 1)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_pending_inbox WHERE envelope_entity_type = ?",
          arguments: ["focus_schedule"]) ?? 0, 0)
      let rawShadow = try XCTUnwrap(
        try String.fetchOne(
          db,
          sql: """
            SELECT raw_payload_json FROM sync_payload_shadow
            WHERE entity_type = ? AND entity_id = ?
            """,
          arguments: [EntityName.focusSchedule, "2026-04-01"]))
      guard case .object(let shadow)? = JSONValue.parse(rawShadow) else {
        return XCTFail("forward-compat payload shadow must be an object")
      }
      XCTAssertEqual(
        shadow["future_metadata"], .object(["planner": .string("v2")]))
    }
  }

  func testApplyInboundInvalidOperationDoesNotRollbackValidEnvelope() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let valid = taskUpsertEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-000000000021",
      title: "Inbound valid before invalid operation",
      listId: listId)
    let invalid = SyncEnvelope(
      entityType: .aiChangelog,
      entityId: "01966a3f-7c8b-7d4e-8f3a-000000000022",
      operation: .delete,
      version: try Hlc.parse("1711234567892_0000_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{}",
      deviceId: "device-remote")

    let report = try service.applyInbound([valid, invalid], undecodable: 0)

    XCTAssertEqual(report.applied, 1)
    XCTAssertEqual(report.undecodable, 1)
    let validExists = try service.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [valid.entityId])
        ?? 0
    }
    XCTAssertEqual(validExists, 1)
    let logged = try service.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.inbound_invalid' "
          + "AND message LIKE '%delete is not supported for ai_changelog%'") ?? 0
    }
    XCTAssertGreaterThanOrEqual(logged, 1)
  }

  func testApplyInboundInvalidEntityRedirectDoesNotRollbackValidEnvelope() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let valid = taskUpsertEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-000000000031",
      title: "Inbound valid before invalid redirect",
      listId: listId)
    let redirectVersion = try Hlc.parse("1711234567892_0000_a1b2c3d4a1b2c3d4")
    let sourceId = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let targetId = "00000000-0000-7000-8000-000000000033"
    let invalidPayload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "source_type": .string(EntityName.list),
        "source_id": .string(sourceId),
        "target_id": .string(targetId),
        "version": .string(redirectVersion.description),
      ]))
    let invalid = SyncEnvelope(
      entityType: .entityRedirect,
      entityId: SyncRecordName.opaque(entityType: EntityName.list, entityId: sourceId),
      operation: .upsert, version: redirectVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: invalidPayload, deviceId: "device-remote")

    let report = try service.applyInbound([valid, invalid], undecodable: 0)

    XCTAssertEqual(report.applied, 1)
    XCTAssertEqual(report.undecodable, 1)
    let existingIds = try service.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT id FROM tasks WHERE id = ? ORDER BY id",
        arguments: [valid.entityId])
    }
    XCTAssertEqual(existingIds, [valid.entityId])
    let logged = try service.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.inbound_invalid' "
          + "AND message LIKE '%invalid payload%'") ?? 0
    }
    XCTAssertGreaterThanOrEqual(logged, 1)
  }

  func testApplyInboundDependencyCycleRejectionLogsConflictAndContinuesIdempotently()
    async throws
  {
    let service = try makeService()
    let taskA = "01966a3f-7c8b-7d4e-8f3a-000000000041"
    let taskB = "01966a3f-7c8b-7d4e-8f3a-000000000042"
    let validSibling = taskUpsertEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-000000000043",
      title: "Applied after rejected dependency",
      listId: try seededListId(service))
    let existingVersion = "7000000000000_0000_a1b2c3d4a1b2c3d4"
    let losingVersion = "6000000000000_0000_b1b2c3d4a1b2c3d4"
    let losingEdge = try taskDependencyEnvelope(
      taskId: taskB, dependsOn: taskA, version: losingVersion)

    try service.write { db in
      for (id, title) in [(taskA, "Dependency source"), (taskB, "Dependency target")] {
        try db.execute(
          sql: """
            INSERT INTO tasks (id, title, status, version, created_at, updated_at)
            VALUES (?, ?, 'open', ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
            """,
          arguments: [id, title, Hlc.testVersion])
      }
      try db.execute(
        sql: """
          INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
          VALUES (?, ?, ?, '2026-04-01T00:00:00.000Z')
          """,
        arguments: [taskA, taskB, existingVersion])
    }

    let report = try service.applyInbound([losingEdge, validSibling], undecodable: 0)

    XCTAssertEqual(report.applied, 1)
    XCTAssertEqual(report.undecodable, 1)
    let siblingApplied = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [validSibling.entityId])
        ?? 0
    }
    XCTAssertEqual(siblingApplied, 1)

    let conflict = try service.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT entity_type, entity_id, winner_version, loser_version, loser_device_id,
                 loser_payload, resolution_type
          FROM sync_conflict_log
          WHERE entity_type = ? AND entity_id = ? AND resolution_type = ?
          """,
        arguments: [EdgeName.taskDependency, "\(taskB):\(taskA)", ResolutionName.cycleBreak])
    }
    let row = try XCTUnwrap(conflict)
    XCTAssertEqual(row["entity_type"] as String, EdgeName.taskDependency)
    XCTAssertEqual(row["entity_id"] as String, "\(taskB):\(taskA)")
    XCTAssertEqual(row["winner_version"] as String, "")
    XCTAssertEqual(row["loser_version"] as String, losingVersion)
    XCTAssertEqual(row["loser_device_id"] as String, try Hlc.parse(losingVersion).deviceSuffix)
    XCTAssertNil(row["loser_payload"] as String?)
    XCTAssertEqual(row["resolution_type"] as String, ResolutionName.cycleBreak)

    _ = try service.applyInbound([losingEdge], undecodable: 0)
    let conflictCount = try service.read { db in
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM sync_conflict_log
          WHERE entity_type = ? AND entity_id = ? AND resolution_type = ?
          """,
        arguments: [EdgeName.taskDependency, "\(taskB):\(taskA)", ResolutionName.cycleBreak])
        ?? 0
    }
    XCTAssertEqual(conflictCount, 1)
  }

  /// S-02: `applyInbound` feeds each remote version into the HLC clock, so a later
  /// local edit of a remote-touched row mints a dominating HLC and succeeds —
  /// instead of failing `versionSuperseded` against a peer's future-relative clock
  /// and rolling the whole transaction back.
  func testApplyInboundObservesRemoteVersionSoLaterLocalEditSucceeds() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let taskId = "01966a3f-7c8b-7d4e-8f3a-000000000099"

    // A legitimate peer whose clock is slightly ahead — but WITHIN the S-1 inbound
    // drift bound — upserts the task at a version above this device's natural mint.
    // applyInbound must observe it so the later local edit mints ABOVE it and wins
    // LWW rather than losing versionSuperseded. (A far-FUTURE peer beyond the bound
    // is deliberately clamped and would correctly out-rank the local edit — see
    // testApplyInboundDoesNotLetFarFuturePeerInflateLocalClock.)
    let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
    let futureVersion = try Hlc(
      physicalMs: nowMs &+ 60_000, counter: 0, deviceSuffix: "ffffffffffffffff")
    let payload =
      (try? SyncCanonicalize.canonicalizeJSON(
        .object([
          "title": .string("Remote title"),
          "status": .string("open"),
          "list_id": .string(listId),
          "created_at": .string("2026-04-01T00:00:00.000Z"),
          "updated_at": .string("2026-04-01T00:00:00.000Z"),
        ]))) ?? "{}"
    let envelope = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .task, entityId: taskId, operation: .upsert,
        version: futureVersion, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "device-remote"))

    XCTAssertEqual(try service.applyInbound([envelope], undecodable: 0).applied, 1)

    // Without the clock observing `futureVersion`, this local mutation would mint
    // an HLC below it and roll back with versionSuperseded.
    _ = try await service.completeTask(id: taskId)

    let status = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = ?", arguments: [taskId])
    }
    XCTAssertNotEqual(status, "open")
  }

  /// S-1: a FAR-future peer (beyond the inbound drift bound) is clamped, so merely
  /// OBSERVING it must not drag this device's clock up to its year-2286 physical
  /// time. The proof is a SEPARATE, locally-created task the peer never touched: it
  /// still mints a now-era HLC.
  ///
  /// The clamp is passive-observation hygiene only. An EXPLICIT local edit of the
  /// future-stamped row IS deliberately allowed to supersede it (SYNC-HIGH-1) via a
  /// one-shot unbounded clock advance — covered by
  /// `testLocalCompleteOfFutureStampedRowSupersedesAndSucceeds`. This test pins the
  /// complementary invariant: the passive advance stays clamped.
  func testApplyInboundDoesNotLetFarFuturePeerInflateLocalClock() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let taskId = "01966a3f-7c8b-7d4e-8f3a-0000000000aa"

    let farFutureVersion = try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs, counter: 0,
      deviceSuffix: "ffffffffffffffff")
    let payload =
      (try? SyncCanonicalize.canonicalizeJSON(
        .object([
          "title": .string("Remote title"),
          "status": .string("open"),
          "list_id": .string(listId),
          "created_at": .string("2026-04-01T00:00:00.000Z"),
          "updated_at": .string("2026-04-01T00:00:00.000Z"),
        ]))) ?? "{}"
    let envelope = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .task, entityId: taskId, operation: .upsert,
        version: farFutureVersion, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "device-remote"))
    XCTAssertEqual(try service.applyInbound([envelope], undecodable: 0).applied, 1)

    // A brand-new local task the far-future peer never touched: its minted HLC must
    // stay near wall-clock, proving the passive observation left the clock clamped
    // (not inflated to the peer's year-2286 physical time).
    let localTask = try await service.createTask(title: "Untouched local", notes: "")
    let localVersionString = try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [localTask.id])
      })
    let localVersion = try Hlc.parse(localVersionString)
    let nowCeiling =
      UInt64(Date().timeIntervalSince1970 * 1000) &+ HlcState.maxInboundForwardDriftMs
    XCTAssertLessThanOrEqual(
      localVersion.physicalMs, nowCeiling,
      "passive observation of a far-future peer must not drag the local clock forward")
    XCTAssertLessThan(
      localVersion.physicalMs, farFutureVersion.physicalMs,
      "the untouched local task must mint a now-era HLC, not the peer's year-2286 physical time")
  }

  func testReservedHlcHeadroomIsParkedBeforeCanonicalStateOrClockMutation() throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let (_, clock) = try service.writeState()
    let checkpointBefore = try service.read { db in
      (
        try SyncCheckpoints.get(db, key: clock.normalHighWaterKey),
        try SyncCheckpoints.get(db, key: clock.detachedHighWaterKey)
      )
    }
    let unsafeVersions = [
      try Hlc(
        physicalMs: Hlc.maxOperationalWirePhysicalMs + 1, counter: 0,
        deviceSuffix: "eeeeeeeeeeeeeeee"),
      try Hlc(
        physicalMs: Hlc.maxPhysicalMs, counter: Hlc.maxCounter,
        deviceSuffix: "ffffffffffffffff"),
    ]
    let envelopes = unsafeVersions.enumerated().map { index, version in
      var envelope = taskUpsertEnvelope(
        id: String(format: "01966a3f-7c8b-7d4e-8f3a-%012d", 800 + index),
        title: "Reserved headroom", listId: listId)
      envelope.version = version
      return envelope
    }

    let report = try service.applyInbound(envelopes, undecodable: 0)
    XCTAssertEqual(report.applied, 0)
    XCTAssertEqual(report.deferred, unsafeVersions.count)
    XCTAssertTrue(try service.pendingOutbound().isEmpty)
    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id IN (?, ?)",
          arguments: [envelopes[0].entityId, envelopes[1].entityId]) ?? -1,
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_pending_inbox WHERE reason LIKE ?",
          arguments: ["\(DeferralReason.operationallyUnusableHlcReasonMarker)%"]) ?? -1,
        unsafeVersions.count)
      XCTAssertEqual(
        try SyncCheckpoints.get(db, key: clock.normalHighWaterKey), checkpointBefore.0)
      XCTAssertEqual(
        try SyncCheckpoints.get(db, key: clock.detachedHighWaterKey), checkpointBefore.1)
    }
  }

  func testWireTerminalRecordIsHeldBeforeCanonicalStateOnBothPeers() async throws {
    let peerA = try makeService()
    let peerB = try makeService()
    let taskId = "01966a3f-7c8b-7d4e-8f3a-0000000008ff"
    var boundary = taskUpsertEnvelope(
      id: taskId, title: "Shared boundary", listId: try seededListId(peerA))
    boundary.version = try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs,
      counter: Hlc.maxCounter, deviceSuffix: "ffffffffffffffff")

    let reportA = try peerA.applyInbound([boundary], undecodable: 0)
    let reportB = try peerB.applyInbound([boundary], undecodable: 0)
    XCTAssertEqual(reportA.applied, 0)
    XCTAssertEqual(reportA.deferred, 1)
    XCTAssertEqual(reportB.applied, 0)
    XCTAssertEqual(reportB.deferred, 1)
    XCTAssertTrue(Hlc.isOperationallyAcceptableWire(boundary.version))
    XCTAssertFalse(Hlc.hasOperationalWireSuccessor(after: boundary.version))

    try peerA.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [taskId]),
        0, "an uneditable terminal record must never enter canonical state")
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?",
          arguments: [taskId]),
        0, "the held remote record must not create outbound work")
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_pending_inbox
            WHERE envelope_entity_type = 'task' AND envelope_entity_id = ?
              AND reason LIKE ?
            """,
          arguments: [taskId, "\(DeferralReason.operationallyUnusableHlcReasonMarker)%"]),
        1, "the exact terminal record remains durable for a newer build")
    }
  }

  func testEverySuccessfulLocalTaskEnvelopeIsAcceptedByAnotherPeer() async throws {
    let author = try makeService()
    let receiver = try makeService()
    let task = try await author.createTask(title: "Wire-safe local edit", notes: "")
    let envelope = try XCTUnwrap(
      try author.pendingOutbound().first {
        $0.envelope.entityType == .task && $0.envelope.entityId == task.id
      }?.envelope)

    XCTAssertTrue(Hlc.isOperationallyAcceptableWire(envelope.version))
    let report = try receiver.applyInbound([envelope], undecodable: 0)
    XCTAssertEqual(report.applied, 1)
    XCTAssertEqual(
      try receiver.read { db in
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [task.id])
      },
      "Wire-safe local edit")
  }

  // MARK: - SYNC18-MED-1: a merge-minted HLC respects the S-1 clock bound

  /// Build a `tag` upsert envelope. The applier re-derives `lookup_key` from
  /// `display_name`, so two envelopes whose names canonicalize to the same key
  /// collapse through the aggregate merge on the second apply.
  private func tagEnvelope(id: String, displayName: String, version: Hlc) throws -> SyncEnvelope {
    try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .tag, entityId: id, operation: .upsert, version: version,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "display_name": .string(displayName),
            "lookup_key": .string(displayName.lowercased()),
            "color": .null,
            "created_at": .string("2026-01-01T00:00:00.000Z"),
            "updated_at": .string("2026-01-01T00:00:00.000Z"),
          ])),
        deviceId: "device-remote"))
  }

  /// SYNC18-MED-1: a duplicate-key merge mints its merge HLC as the successor of
  /// the cluster's highest participant version — attacker-controllable wire data.
  /// A crafted colliding tag stamped ~9.9y in the future is injected directly at
  /// the in-process apply seam (CloudKit would reject it at 30 days). It makes
  /// that future time the cluster `maxHlc`. Feeding
  /// the minted merge HLC into the local clock UNBOUNDED would passively pin the
  /// process clock ~9.9y forward for the whole session, so every honest peer edit
  /// then loses LWW fleet-wide with no user action. The clock advance must be
  /// bounded to `now + maxInboundForwardDriftMs` exactly like the inbound
  /// peer-observe path (S-1); the winner-row / tombstone STAMP still carries the
  /// future merge version (the aggregate-root invariant needs the stamp, and a
  /// later genuine edit re-converges through the unbounded explicit-authorship
  /// path).
  func testMergeMintedHlcDoesNotPinLocalClockForward() throws {
    let service = try makeService()
    let (_, clock) = try service.writeState()

    let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
    // ~9.9 years ahead — valid HLC syntax, injected below the CloudKit boundary.
    let futureMs = nowMs &+ UInt64(9.9 * 365.25 * 24 * 60 * 60 * 1000)
    let attackerVersion = try Hlc(
      physicalMs: futureMs, counter: 0, deviceSuffix: "ffffffffffffffff")
    let honest = try tagEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-000000000a01", displayName: "work",
      version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"))
    let attacker = try tagEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-000000000a02", displayName: "Work",
      version: attackerVersion)

    // The service binds deterministic merge events to this exact transaction's
    // clock/high-water; no process-global last-installer routing is involved.
    _ = try service.applyInbound([honest, attacker], undecodable: 0)

    // The merge collapsed the two tags to one, whose stamp is the future merge
    // version — the aggregate-root invariant leaves the stamp untouched.
    let winnerVersion = try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(db, sql: "SELECT version FROM tags WHERE lookup_key = 'work'")
      })
    XCTAssertGreaterThanOrEqual(
      try Hlc.parse(winnerVersion).physicalMs, futureMs,
      "the surviving winner row must keep the future merge stamp")

    // But the local clock must NOT have been dragged to that future time: a fresh
    // mint stays near wall-clock + bounded drift.
    let minted = clock.generate()
    let ceiling = UInt64(Date().timeIntervalSince1970 * 1000) &+ HlcState.maxInboundForwardDriftMs
    XCTAssertLessThanOrEqual(
      minted.physicalMs, ceiling,
      "a merge-minted HLC must not drag the local clock past wall-clock + bounded drift")
    XCTAssertLessThan(
      minted.physicalMs, futureMs,
      "the local clock must stay near wall-clock, not the forged future merge time")
  }

  // MARK: - SYNC-HIGH-1: explicit local edits supersede a future-stamped row

  /// Apply an inbound task upsert stamped with a FUTURE HLC beyond the S-1 drift
  /// bound (near `Hlc.maxPhysicalMs`, with counter headroom for the advance). LWW
  /// accepts it, so the local row keeps the future `version` while the clock stays
  /// clamped. Returns the future version for the caller's domination asserts.
  @discardableResult
  private func applyFutureStampedTask(
    _ service: SwiftLorvexCoreService, id: String, listId: String,
    version suppliedVersion: Hlc? = nil
  ) throws -> Hlc {
    let futureVersion = try suppliedVersion
      ?? Hlc.parse("9999913599990_0000_ffffffffffffffff")
    let payload =
      (try? SyncCanonicalize.canonicalizeJSON(
        .object([
          "title": .string("Remote future"),
          "status": .string("open"),
          "list_id": .string(listId),
          "created_at": .string("2026-04-01T00:00:00.000Z"),
          "updated_at": .string("2026-04-01T00:00:00.000Z"),
        ]))) ?? "{}"
    let envelope = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .task, entityId: id, operation: .upsert, version: futureVersion,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion, payload: payload,
        deviceId: "device-remote"))
    XCTAssertEqual(try service.applyInbound([envelope], undecodable: 0).applied, 1)
    return futureVersion
  }

  func testDetachedRepairOrdersLaterExceptionalEditWithoutPinningNormalWrites() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let extremeId = "01966a3f-7c8b-7d4e-8f3a-0000000000c1"
    let modestId = "01966a3f-7c8b-7d4e-8f3a-0000000000c2"
    let extremeFloor = try Hlc.parse("9999913599900_0000_eeeeeeeeeeeeeeee")
    let now = UInt64(Date().timeIntervalSince1970 * 1000)
    let modestFloor = try Hlc(
      physicalMs: now + 10 * 60 * 1000, counter: 0,
      deviceSuffix: "dddddddddddddddd")
    try applyFutureStampedTask(
      service, id: extremeId, listId: listId, version: extremeFloor)
    try applyFutureStampedTask(
      service, id: modestId, listId: listId, version: modestFloor)

    _ = try await service.updateTask(
      id: extremeId, title: "Extreme repaired", notes: "", priority: .p2,
      estimatedMinutes: nil, plannedDate: nil, tags: [], dependsOn: [])
    _ = try await service.updateTask(
      id: modestId, title: "Modest repaired", notes: "", priority: .p2,
      estimatedMinutes: nil, plannedDate: nil, tags: [], dependsOn: [])

    let modestVersion = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [modestId])
    }
    let parsed = try Hlc.parse(try XCTUnwrap(modestVersion))
    XCTAssertGreaterThan(parsed, modestFloor)
    XCTAssertGreaterThan(
      parsed, extremeFloor,
      "exceptional edits share a durable lane so their HLCs stay globally unique")

    let ordinary = try await service.createTask(title: "Normal lane remains bounded", notes: "")
    let ordinaryVersion = try Hlc.parse(
      try XCTUnwrap(
        try service.read { db in
          try String.fetchOne(
            db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [ordinary.id])
        }))
    XCTAssertLessThan(ordinaryVersion, extremeFloor)
  }

  /// SYNC-HIGH-1 (a): a peer stamps a task with a FUTURE HLC beyond the S-1 drift
  /// bound. Pre-fix a local `completeTask` mints below the row `version`, loses the
  /// workflow LWW gate (`StoreError.staleVersion`), and rolls the whole mutation
  /// back — the task stays "open", un-editable until wall-clock passes the stamp
  /// (never, for this near-`Hlc.maxPhysicalMs` stamp). The fix advances the local
  /// clock UNBOUNDED past the row version and retries once, so the completion lands
  /// and both the row version AND the outbound upsert dominate the peer's version.
  func testLocalCompleteOfFutureStampedRowSupersedesAndSucceeds() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let taskId = "01966a3f-7c8b-7d4e-8f3a-0000000000b1"
    let futureVersion = try applyFutureStampedTask(service, id: taskId, listId: listId)

    // Pre-fix: throws StoreError.staleVersion and rolls back. Post-fix: succeeds.
    _ = try await service.completeTask(id: taskId)

    let (status, versionStr) = try service.read { db -> (String?, String?) in
      let row = try Row.fetchOne(
        db, sql: "SELECT status, version FROM tasks WHERE id = ?", arguments: [taskId])
      return (row?["status"], row?["version"])
    }
    XCTAssertNotEqual(status, "open", "the local completion must land on the future-stamped row")
    let newVersion = try Hlc.parse(try XCTUnwrap(versionStr))
    XCTAssertGreaterThan(
      newVersion, futureVersion,
      "the local edit must supersede the peer's future version, not sit below it")

    // The outbound task upsert must also dominate the future version so it wins LWW
    // on push instead of being rejected as stale.
    let taskEnvelope = try XCTUnwrap(try pending(service, kind: .task, id: taskId).last)
    XCTAssertEqual(taskEnvelope.operation, .upsert)
    XCTAssertGreaterThan(taskEnvelope.version, futureVersion)

    // The repair used a transaction-scoped detached lane. A later unrelated
    // write must return to the normal wall-time lane instead of inheriting the
    // peer's near-ceiling timestamp process-wide.
    let unrelated = try await service.createTask(title: "Unrelated normal write", notes: "")
    let unrelatedVersion = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [unrelated.id])
    }
    let parsedUnrelated = try Hlc.parse(try XCTUnwrap(unrelatedVersion))
    let now = UInt64(Date().timeIntervalSince1970 * 1000)
    XCTAssertLessThan(parsedUnrelated, futureVersion)
    XCTAssertLessThanOrEqual(
      parsedUnrelated.physicalMs, now + HlcState.maxInboundForwardDriftMs,
      "dominating one row must not pin unrelated writes to the detached future lane")
  }

  func testBatchMutationSupersedesHeterogeneousFutureFloorsAtomically() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let firstId = "01966a3f-7c8b-7d4e-8f3a-0000000000d1"
    let secondId = "01966a3f-7c8b-7d4e-8f3a-0000000000d2"
    let now = UInt64(Date().timeIntervalSince1970 * 1000)
    let firstFloor = try Hlc(
      physicalMs: now + 10 * 60 * 1000, counter: 0,
      deviceSuffix: "aaaaaaaaaaaaaaaa")
    let secondFloor = try Hlc(
      physicalMs: now + 20 * 60 * 1000, counter: 0,
      deviceSuffix: "bbbbbbbbbbbbbbbb")
    try applyFutureStampedTask(
      service, id: firstId, listId: listId, version: firstFloor)
    try applyFutureStampedTask(
      service, id: secondId, listId: listId, version: secondFloor)

    let result = try await service.batchCompleteTasks(ids: [firstId, secondId])

    XCTAssertEqual(Set(result.changedIDs), Set([firstId, secondId]))
    let rows = try service.read { db in
      try Row.fetchAll(
        db,
        sql: "SELECT id, status, version FROM tasks WHERE id IN (?, ?) ORDER BY id",
        arguments: [firstId, secondId])
    }
    XCTAssertEqual(rows.count, 2)
    for row in rows {
      let id: String = row["id"]
      let status: String = row["status"]
      let version: String = row["version"]
      XCTAssertNotEqual(status, "open")
      XCTAssertGreaterThan(
        try Hlc.parse(version), id == firstId ? firstFloor : secondFloor)
    }
  }

  func testInboundMutationBumpsLocalChangeSequenceExactlyOnceButSkippedReplayDoesNot() throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let envelope = taskUpsertEnvelope(
      id: "01966a3f-7c8b-7d4e-8f3a-0000000000aa", listId: listId)

    let before = try service.read { db in try LocalChangeSeq.read(db) }
    XCTAssertEqual(try service.applyInbound([envelope], undecodable: 0).applied, 1)
    let afterApply = try service.read { db in try LocalChangeSeq.read(db) }
    XCTAssertEqual(afterApply, before + 1)

    let replay = try service.applyInbound([envelope], undecodable: 0)
    XCTAssertEqual(replay.applied, 0)
    let afterReplay = try service.read { db in try LocalChangeSeq.read(db) }
    XCTAssertEqual(
      afterReplay, afterApply,
      "a pure LWW-skipped replay must not manufacture a canonical change signal")
  }

  /// SYNC-HIGH-1 (a, content edit): a content `updateTask` of a future-stamped row
  /// takes the same LWW-loss-then-advance-and-retry path, landing the new title with
  /// a version that dominates the peer's future version.
  func testLocalUpdateOfFutureStampedRowSucceeds() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let taskId = "01966a3f-7c8b-7d4e-8f3a-0000000000b2"
    let futureVersion = try applyFutureStampedTask(service, id: taskId, listId: listId)

    _ = try await service.updateTask(
      id: taskId, title: "Edited locally", notes: "", priority: .p2, estimatedMinutes: nil,
      plannedDate: nil, tags: [], dependsOn: [])

    let (title, versionStr) = try service.read { db -> (String?, String?) in
      let row = try Row.fetchOne(
        db, sql: "SELECT title, version FROM tasks WHERE id = ?", arguments: [taskId])
      return (row?["title"], row?["version"])
    }
    XCTAssertEqual(title, "Edited locally")
    XCTAssertGreaterThan(try Hlc.parse(try XCTUnwrap(versionStr)), futureVersion)
  }

  /// SYNC-HIGH-1 (b): a local delete of a future-stamped row. Pre-fix the LWW-gated
  /// `hardDeleteTaskLww` loses to the future `version` and rolls back; even a delete
  /// that landed would ship an envelope BELOW the future version, so on push
  /// CloudKit reports `serverRecordChanged`, the server's upsert wins, and the
  /// deleted task RESURRECTS. The fix advances the clock past the row version and
  /// retries, so the delete lands locally AND the delete envelope's version
  /// dominates the future version — the delete wins on push, no resurrection.
  func testLocalDeleteOfFutureStampedRowStampsDominatingDeleteEnvelope() async throws {
    let service = try makeService()
    let listId = try seededListId(service)
    let taskId = "01966a3f-7c8b-7d4e-8f3a-0000000000b3"
    let futureVersion = try applyFutureStampedTask(service, id: taskId, listId: listId)

    // Permanent delete requires the row archived first (two-step Trash flow).
    try service.write { db in
      try db.execute(
        sql: "UPDATE tasks SET archived_at = '2026-06-01T00:00:00.000Z' WHERE id = ?",
        arguments: [taskId])
    }

    // Pre-fix: throws StoreError.staleVersion and rolls back. Post-fix: succeeds.
    try await service.deleteTask(id: taskId)

    let remaining = try service.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [taskId]) ?? -1
    }
    XCTAssertEqual(remaining, 0, "the future-stamped row must be deleted locally")

    let deleteEnvelope = try XCTUnwrap(try pending(service, kind: .task, id: taskId).last)
    XCTAssertEqual(deleteEnvelope.operation, .delete)
    XCTAssertGreaterThan(
      deleteEnvelope.version, futureVersion,
      "the delete envelope must out-rank the peer's future version so it wins on push "
        + "and the row does not resurrect")
  }

  // MARK: - SYNC17-HIGH-2: hard-delete of a future-stamped row supersedes

  /// A future HLC beyond the S-1 inbound drift bound (so the local clock stays
  /// clamped and a fresh local mint sits below it), but within honest dead-RTC
  /// skew — the stamp a peer with a fast clock legitimately authors. Distinct from
  /// the near-`Hlc.maxPhysicalMs` ceiling, which is a corrupt physical time.
  private func honestFutureVersion(counter: UInt32 = 0) -> Hlc {
    let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
    return try! Hlc(
      physicalMs: nowMs &+ 90 * 24 * 60 * 60 * 1000, counter: counter,
      deviceSuffix: "ffffffffffffffff")
  }

  private func tombstoneVersion(
    _ service: SwiftLorvexCoreService, entityType: String, entityId: String
  ) throws -> Hlc? {
    let raw = try service.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT version FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
        arguments: [entityType, entityId])
    }
    return try raw.map { try Hlc.parse($0) }
  }

  /// SYNC17-HIGH-2 (a, calendar_event): a peer stamps a calendar event with a
  /// future HLC. The whole-event delete uses a bare `DELETE` then `enqueueDelete` —
  /// no LWW-gated write throws, so pre-fix the delete envelope + tombstone mint
  /// BELOW the future version; on push CloudKit reports `serverRecordChanged`, the
  /// server's upsert wins, and the event RESURRECTS. The fix detects the losing
  /// delete in the enqueue arm (the pre-delete snapshot carries the row version),
  /// advances the clock, and re-runs, so both dominate the future version.
  func testLocalDeleteOfFutureStampedCalendarEventStampsDominatingDeleteEnvelope() async throws {
    let service = try makeService()
    let eventId = "01966a3f-7c8b-7d4e-8f3a-0000000000c9"
    let futureVersion = honestFutureVersion()
    let upsert = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .calendarEvent, entityId: eventId, operation: .upsert,
        version: futureVersion,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "title": .string("Standup"),
            "start_date": .string("2026-04-20"),
            "start_time": .null,
            "all_day": .bool(true),
            "event_type": .string("event"),
            "created_at": .string("2026-04-20T09:00:00.000Z"),
            "updated_at": .string("2026-04-20T09:00:00.000Z"),
          ])),
        deviceId: "device-remote"))
    XCTAssertEqual(try service.applyInbound([upsert], undecodable: 0).applied, 1)

    _ = try await service.deleteCalendarEvent(id: eventId)

    let remaining = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM calendar_events WHERE id = ?", arguments: [eventId]) ?? -1
    }
    XCTAssertEqual(remaining, 0, "the future-stamped event must be deleted locally")

    let deleteEnvelope = try XCTUnwrap(try pending(service, kind: .calendarEvent, id: eventId).last)
    XCTAssertEqual(deleteEnvelope.operation, .delete)
    XCTAssertGreaterThan(
      deleteEnvelope.version, futureVersion,
      "the delete envelope must out-rank the peer's future version so it wins on push")
    let tomb = try XCTUnwrap(
      try tombstoneVersion(service, entityType: EntityName.calendarEvent, entityId: eventId))
    XCTAssertGreaterThan(
      tomb, futureVersion, "the tombstone must dominate the future version, not sit below it")
  }

  func testLocalClearOfFutureStampedCurrentFocusStampsDominatingDeleteEnvelope() async throws {
    let service = try makeService()
    let date = "2026-04-21"
    let futureVersion = honestFutureVersion()
    let upsert = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .currentFocus, entityId: date, operation: .upsert,
        version: futureVersion,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "briefing": .string("Future focus"),
            "timezone": .string("UTC"),
            "task_ids": .array([]),
            "created_at": .string("2026-04-21T00:00:00.000Z"),
            "updated_at": .string("2026-04-21T00:00:00.000Z"),
          ])),
        deviceId: "device-remote"))
    XCTAssertEqual(try service.applyInbound([upsert], undecodable: 0).applied, 1)

    _ = try await service.clearCurrentFocus(date: date)

    let remaining = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM current_focus WHERE date = ?", arguments: [date]) ?? -1
    }
    XCTAssertEqual(remaining, 0)
    let deleteEnvelope = try XCTUnwrap(
      try pending(service, kind: .currentFocus, id: date).last)
    XCTAssertEqual(deleteEnvelope.operation, .delete)
    XCTAssertGreaterThan(deleteEnvelope.version, futureVersion)
    let tomb = try XCTUnwrap(
      try tombstoneVersion(service, entityType: EntityName.currentFocus, entityId: date))
    XCTAssertGreaterThan(tomb, futureVersion)
  }

  func testLocalClearOfFutureStampedFocusScheduleStampsDominatingDeleteEnvelope() async throws {
    let service = try makeService()
    let date = "2026-04-22"
    let futureVersion = honestFutureVersion(counter: 1)
    let upsert = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .focusSchedule, entityId: date, operation: .upsert,
        version: futureVersion,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "rationale": .string("Future schedule"),
            "timezone": .string("UTC"),
            "blocks": .array([]),
            "created_at": .string("2026-04-22T00:00:00.000Z"),
            "updated_at": .string("2026-04-22T00:00:00.000Z"),
          ])),
        deviceId: "device-remote"))
    XCTAssertEqual(try service.applyInbound([upsert], undecodable: 0).applied, 1)

    try await service.clearFocusSchedule(date: date)

    let remaining = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM focus_schedule WHERE date = ?", arguments: [date]) ?? -1
    }
    XCTAssertEqual(remaining, 0)
    let deleteEnvelope = try XCTUnwrap(
      try pending(service, kind: .focusSchedule, id: date).last)
    XCTAssertEqual(deleteEnvelope.operation, .delete)
    XCTAssertGreaterThan(deleteEnvelope.version, futureVersion)
    let tomb = try XCTUnwrap(
      try tombstoneVersion(service, entityType: EntityName.focusSchedule, entityId: date))
    XCTAssertGreaterThan(tomb, futureVersion)
  }

  /// SYNC17-HIGH-2 (a, list): a peer stamps a list with a future HLC.
  /// `ListRepo.deleteList` runs an unconditional `DELETE`, so pre-fix the delete
  /// envelope + tombstone mint below the future version and the list resurrects on
  /// push. The fix advances the clock so both dominate.
  func testLocalDeleteOfFutureStampedListStampsDominatingDeleteEnvelope() async throws {
    let service = try makeService()
    let listId = "01966a3f-7c8b-7d4e-8f3a-0000000000ca"
    let futureVersion = honestFutureVersion()
    let upsert = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .list, entityId: listId, operation: .upsert,
        version: futureVersion,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "name": .string("Future list"),
            "created_at": .string("2026-04-01T00:00:00.000Z"),
            "updated_at": .string("2026-04-01T00:00:00.000Z"),
          ])),
        deviceId: "device-remote"))
    XCTAssertEqual(try service.applyInbound([upsert], undecodable: 0).applied, 1)

    // inbox + the future list = two lists, and no task is assigned to it, so the
    // delete guards pass.
    try await service.deleteList(id: listId)

    let remaining = try service.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM lists WHERE id = ?", arguments: [listId]) ?? -1
    }
    XCTAssertEqual(remaining, 0, "the future-stamped list must be deleted locally")

    let deleteEnvelope = try XCTUnwrap(try pending(service, kind: .list, id: listId).last)
    XCTAssertEqual(deleteEnvelope.operation, .delete)
    XCTAssertGreaterThan(deleteEnvelope.version, futureVersion)
    let tomb = try XCTUnwrap(
      try tombstoneVersion(service, entityType: EntityName.list, entityId: listId))
    XCTAssertGreaterThan(tomb, futureVersion)
  }

  /// SYNC17-HIGH-2 (b, memory): a peer stamps a memory with a future HLC. The
  /// memory delete is LWW-gated at the store (`DELETE ... AND version < ?`), so
  /// pre-fix it returns nil (refused) and the surface maps that to `false` — the
  /// memory is un-deletable until wall-clock passes the stamp. The fix makes
  /// `deleteMemoryEntry` throw `staleVersion` on a gate refusal (distinct from a
  /// missing row), so the write-surface retry advances the clock and the delete
  /// lands.
  func testLocalDeleteOfFutureStampedMemorySucceeds() async throws {
    let service = try makeService()
    let memoryId = "01966a3f-7c8b-7d4e-8f3a-0000000000cb"
    let key = "future-memory"
    let futureVersion = honestFutureVersion()
    let upsert = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .memory, entityId: memoryId, operation: .upsert,
        version: futureVersion,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "key": .string(key), "content": .string("remember this"),
            "updated_at": .string("2026-04-01T00:00:00.000Z"),
          ])),
        deviceId: "device-remote"))
    XCTAssertEqual(try service.applyInbound([upsert], undecodable: 0).applied, 1)

    // Pre-fix: refused (returns false) — un-deletable. Post-fix: the retry advances
    // the clock past the future version and the delete lands.
    let deleted = try await service.deleteMemory(key: key)
    XCTAssertTrue(deleted, "the future-stamped memory must be deletable, not refused")

    let remaining = try service.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memories WHERE key = ?", arguments: [key]) ?? -1
    }
    XCTAssertEqual(remaining, 0, "the memory row must be gone")
  }

  /// SYNC17-HIGH-2 (c, preference): a peer stamps a synced preference with a
  /// future HLC. `PreferenceRepo.clearPreference` is LWW-gated
  /// (`DELETE ... AND ? > version`) and the surface guards its delete-envelope
  /// enqueue behind `deleted > 0`, so pre-fix a gate refusal silently no-ops:
  /// no throw, no write-surface clock-advance retry, no delete envelope — the
  /// future-stamped preference is un-deletable and never converges. The fix
  /// routes `clearPreference` through `LwwOps.executeDeleteById`, which throws
  /// `staleVersion` on a present-but-refused row (distinct from an absent key),
  /// so the retry advances the clock and the delete lands with a dominating
  /// envelope.
  func testLocalDeleteOfFutureStampedPreferenceStampsDominatingDeleteEnvelope() async throws {
    let service = try makeService()
    let key = PreferenceKeys.prefWorkingHours
    let futureVersion = honestFutureVersion()
    let upsert = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .preference, entityId: key, operation: .upsert,
        version: futureVersion,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "key": .string(key),
            "value": .object(["start": .string("09:00"), "end": .string("17:00")]),
            "updated_at": .string("2026-04-01T00:00:00.000Z"),
          ])),
        deviceId: "device-remote"))
    XCTAssertEqual(try service.applyInbound([upsert], undecodable: 0).applied, 1)

    // Pre-fix: the LWW gate refuses, `clearPreference` returns 0, the enqueue is
    // skipped, and nothing throws — so the row survives and no envelope ships.
    try await service.deletePreference(key: key)

    let remaining = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM preferences WHERE key = ?", arguments: [key]) ?? -1
    }
    XCTAssertEqual(remaining, 0, "the future-stamped preference must be deleted locally")

    let deleteEnvelope = try XCTUnwrap(try pending(service, kind: .preference, id: key).last)
    XCTAssertEqual(deleteEnvelope.operation, .delete)
    XCTAssertGreaterThan(
      deleteEnvelope.version, futureVersion,
      "the delete envelope must out-rank the peer's future version so it wins on push")
  }

  /// A peer DELETES a natural-key entity (a synced preference) at a future HLC,
  /// so this device holds a tombstone whose death version DOMINATES its clamped
  /// clock (S-1 keeps the passive receive-path advance below the peer's future
  /// stamp). The user then RE-CREATES the same key locally. Pre-fix the enqueue's
  /// unconditional tombstone removal destroys the dominating tombstone and ships
  /// the upsert BELOW it, so on push CloudKit reports `serverRecordChanged`, the
  /// server's delete wins, and the re-create reverts locally and never reaches the
  /// peer. The fix surfaces the supersession from the enqueue arm, so the
  /// write-surface retry advances the clock and the re-created upsert dominates the
  /// tombstone, which is then legitimately cleared.
  func testLocalRecreateOverFutureDeleteTombstoneStampsDominatingUpsert() async throws {
    let service = try makeService()
    let key = PreferenceKeys.prefWorkingHours
    let futureVersion = honestFutureVersion()

    // The peer's future-stamped DELETE lands first. The key never existed locally,
    // so the delete no-ops the row and records only the dominating tombstone.
    let delete = SyncEnvelope(
      entityType: .preference, entityId: key, operation: .delete, version: futureVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: (try? SyncCanonicalize.canonicalizeJSON(
        .object([
          "key": .string(key),
          "value": .object(["start": .string("09:00"), "end": .string("17:00")]),
          "updated_at": .string("2026-04-01T00:00:00.000Z"),
          "version": .string(futureVersion.description),
        ]))) ?? "{}",
      deviceId: "device-remote")
    XCTAssertEqual(try service.applyInbound([delete], undecodable: 0).applied, 1)
    XCTAssertNotNil(
      try tombstoneVersion(service, entityType: EntityName.preference, entityId: key),
      "the peer delete must plant a tombstone")

    // The user re-creates the key locally.
    _ = try await service.setPreference(key: key, value: #"{"start":"08:00","end":"16:00"}"#)

    let stored = try service.read { db in
      try String.fetchOne(db, sql: "SELECT value FROM preferences WHERE key = ?", arguments: [key])
    }
    XCTAssertNotNil(stored, "the re-created preference row must exist locally")

    let upsertEnvelope = try XCTUnwrap(try pending(service, kind: .preference, id: key).last)
    XCTAssertEqual(upsertEnvelope.operation, .upsert)
    XCTAssertGreaterThan(
      upsertEnvelope.version, futureVersion,
      "the re-created upsert must out-rank the peer's future delete so it wins on push "
        + "instead of reverting")
    XCTAssertNil(
      try tombstoneVersion(service, entityType: EntityName.preference, entityId: key),
      "once the upsert dominates, the tombstone is legitimately cleared")
  }

  /// A second apply of the same envelope is idempotent: the engine's LWW gate
  /// skips the equal-or-older version rather than re-applying.
  func testApplyInboundIsIdempotent() async throws {
    let service = try makeService()
    let envelope = taskUpsertEnvelope(listId: try seededListId(service))

    _ = try service.applyInbound([envelope], undecodable: 0)
    let beforeReplay = try service.read { db in
      (
        try LocalChangeSeq.read(db),
        try String.fetchOne(
          db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [envelope.entityId]),
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?",
          arguments: [envelope.entityId]) ?? -1
      )
    }
    let second = try service.applyInbound([envelope], undecodable: 0)
    let afterReplay = try service.read { db in
      (
        try LocalChangeSeq.read(db),
        try String.fetchOne(
          db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [envelope.entityId]),
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?",
          arguments: [envelope.entityId]) ?? -1
      )
    }

    XCTAssertEqual(second.applied, 0)
    XCTAssertEqual(second.skipped, 1)
    XCTAssertEqual(afterReplay.0, beforeReplay.0)
    XCTAssertEqual(afterReplay.1, beforeReplay.1)
    XCTAssertEqual(afterReplay.2, beforeReplay.2)
  }

  /// The transport-supplied undecodable count is threaded straight into the
  /// report alongside the engine outcomes.
  func testApplyInboundThreadsUndecodableCount() async throws {
    let service = try makeService()
    let envelope = taskUpsertEnvelope(listId: try seededListId(service))
    let report = try service.applyInbound([envelope], undecodable: 3)
    XCTAssertEqual(report.undecodable, 3)
    XCTAssertEqual(report.applied, 1)
  }

  // MARK: - S-2 full-resync backfill

  /// The bug S-2 closes, end to end through the facade: a task that was already
  /// pushed (its outbox row confirmed, then GC'd past the 7-day window) is
  /// otherwise never re-pushed to a recreated zone. `enqueueFullResyncBackfill`
  /// re-enqueues it at its EXISTING stored version — not a fresh HLC — and a
  /// second call adds no duplicate unsynced row.
  func testFullResyncBackfillReenqueuesPreviouslySyncedTaskAtStoredVersion() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Synced long ago", notes: "")
    let storedVersion = try service.read { db in
      try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [task.id])
    }

    // Simulate a successful prior push followed by the outbox GC: confirm every
    // pending row, then drop the synced rows. Nothing is now pending, so the task
    // would never reach a recreated zone without the backfill.
    try service.markOutboundSynced(outboxIds: try service.pendingOutbound().map(\.outboxId))
    try service.write { db in
      try db.execute(sql: "DELETE FROM sync_outbox WHERE synced_at IS NOT NULL")
    }
    XCTAssertTrue(try service.pendingOutbound().isEmpty)

    let report = try service.enqueueFullResyncBackfill()
    XCTAssertGreaterThanOrEqual(report.emitted, 1)
    XCTAssertEqual(report.skipped, 0)

    let reenqueued = try service.pendingOutbound().map(\.envelope)
      .first { $0.entityType == .task && $0.entityId == task.id }
    let envelope = try XCTUnwrap(reenqueued, "previously-synced task must be re-enqueued")
    XCTAssertEqual(envelope.operation, .upsert)
    XCTAssertEqual(
      envelope.version.description, storedVersion,
      "re-enqueue must carry the stored version, not a fresh HLC")

    // The stored row version is untouched (no LWW inflation).
    let afterVersion = try service.read { db in
      try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [task.id])
    }
    XCTAssertEqual(afterVersion, storedVersion)

    // Idempotent: a second backfill leaves exactly one unsynced row for the task.
    _ = try service.enqueueFullResyncBackfill()
    let unsynced = try service.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ? "
          + "AND synced_at IS NULL",
        arguments: [task.id]) ?? -1
    }
    XCTAssertEqual(unsynced, 1)
  }

  /// M1 surface: the coordinator polls `isReseedRequired()` at cycle start to
  /// decide whether to run the automatic reseed recovery. It reads the durable
  /// `reseed_required` checkpoint, and a complete backfill pass clears it.
  func testIsReseedRequiredReadsCheckpointAndCompleteBackfillClearsIt() async throws {
    let service = try makeService()
    XCTAssertFalse(try service.isReseedRequired())

    try service.write { db in
      try db.execute(
        sql: "INSERT INTO sync_checkpoints (key, value) VALUES ('reseed_required', 'true') "
          + "ON CONFLICT(key) DO UPDATE SET value = excluded.value")
    }
    XCTAssertTrue(try service.isReseedRequired())

    let report = try service.enqueueFullResyncBackfill()
    XCTAssertEqual(report.skipped, 0)
    XCTAssertFalse(
      try service.isReseedRequired(), "a complete backfill pass clears the marker")
  }

  /// Local enrollment is a fail-closed gate, not a best-effort hint.
  /// Corruption must throw instead of being folded to "not enrolled".
  func testMalformedZoneEpochEnrollmentFailsClosed() throws {
    let service = try makeService()
    let account = "account-A"

    try service.write { db in
      try db.execute(
        sql: "INSERT INTO sync_checkpoints (key, value) VALUES (?1, 'not-an-epoch')",
        arguments: [SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: account)])
    }
    XCTAssertThrowsError(try service.enrolledZoneEpoch(forAccountIdentifier: account)) { error in
      XCTAssertEqual(error as? ZoneEpochCheckpointStateError, .invalidEnrollment)
    }
  }

  // MARK: - Outbound enqueue coverage across write surfaces

  /// Filter the pending outbox to envelopes for one `(kind, id)`, asserting the
  /// HLC version is non-empty on each (every enqueue mints a fresh version).
  private func pending(
    _ service: SwiftLorvexCoreService, kind: EntityKind, id: String
  ) throws -> [SyncEnvelope] {
    let matches = try service.pendingOutbound()
      .map(\.envelope)
      .filter { $0.entityType == kind && $0.entityId == id }
    for envelope in matches {
      XCTAssertFalse(envelope.version.description.isEmpty)
    }
    return matches
  }

  /// `updateTask` with a new tag enqueues both the primary `task` upsert and the
  /// `task_tag` edge upsert (the tag string is auto-created and linked).
  func testUpdateTaskWithTagEnqueuesTaskAndEdge() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Tag me", notes: "")
    _ = try await service.updateTask(
      id: task.id, title: "Tag me", notes: "", priority: .p2, estimatedMinutes: nil,
      plannedDate: nil, tags: ["focus"], dependsOn: [])

    let tagId = try service.read { db in
      try String.fetchOne(db, sql: "SELECT id FROM tags WHERE display_name = 'focus'")
    }
    let edgeId = "\(task.id):\(try XCTUnwrap(tagId))"
    XCTAssertEqual(try pending(service, kind: .task, id: task.id).last?.operation, .upsert)
    let edge = try pending(service, kind: .taskTag, id: edgeId)
    XCTAssertEqual(edge.last?.operation, .upsert)
  }

  /// `completeTask` enqueues a `task` upsert reflecting the new status.
  func testCompleteTaskEnqueuesTaskUpsert() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Finish me", notes: "")
    _ = try await service.completeTask(id: task.id)

    let envelopes = try pending(service, kind: .task, id: task.id)
    XCTAssertEqual(envelopes.last?.operation, .upsert)
  }

  /// `deleteTask` enqueues a `task` Delete plus a `task_tag` child tombstone for
  /// the edge the task carried (cascade children are tombstoned pre-delete).
  func testDeleteTaskEnqueuesDeleteAndChildTombstone() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Delete me", notes: "")
    _ = try await service.updateTask(
      id: task.id, title: "Delete me", notes: "", priority: .p2, estimatedMinutes: nil,
      plannedDate: nil, tags: ["doomed"], dependsOn: [])
    let tagId = try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(db, sql: "SELECT id FROM tags WHERE display_name = 'doomed'")
      })

    // Permanent delete requires the task to be archived first (two-step Trash
    // flow). Archive the row directly so the test exercises the delete path.
    try service.write { db in
      try db.execute(
        sql: "UPDATE tasks SET archived_at = '2026-06-01T00:00:00.000Z' WHERE id = ?",
        arguments: [task.id])
    }

    _ = try await service.deleteTask(id: task.id)

    XCTAssertEqual(try pending(service, kind: .task, id: task.id).last?.operation, .delete)
    let edge = try pending(service, kind: .taskTag, id: "\(task.id):\(tagId)")
    XCTAssertEqual(edge.last?.operation, .delete)
  }

  /// `createList` enqueues a `list` upsert for the new list id.
  func testCreateListEnqueuesListUpsert() async throws {
    let service = try makeService()
    let list = try await service.createList(name: "Projects", description: nil)
    XCTAssertEqual(try pending(service, kind: .list, id: list.id).last?.operation, .upsert)
  }

  /// `createCalendarEvent` enqueues a `calendar_event` aggregate upsert.
  func testCreateCalendarEventEnqueuesUpsert() async throws {
    let service = try makeService()
    let event = try await service.createCalendarEvent(
      title: "Standup", startDate: "2026-06-01", endDate: nil, startTime: "09:00", endTime: "09:30",
      allDay: false, location: nil, notes: nil)
    XCTAssertEqual(
      try pending(service, kind: .calendarEvent, id: event.id).last?.operation, .upsert)
  }

  /// Creating a habit and completing it enqueues a `habit` upsert and a
  /// `habit_completion` edge upsert (composite id `{habit}:{date}`).
  func testHabitCreateAndCompleteEnqueueHabitAndCompletion() async throws {
    let service = try makeService()
    let habit = try await service.createHabit(name: "Stretch", cue: nil, targetCount: 1)
    _ = try await service.completeHabit(id: habit.id, date: "2026-06-01")

    XCTAssertEqual(try pending(service, kind: .habit, id: habit.id).last?.operation, .upsert)
    let completion = try pending(service, kind: .habitCompletion, id: "\(habit.id):2026-06-01")
    XCTAssertEqual(completion.last?.operation, .upsert)
  }

  /// The privacy fix, end to end: `upsertMemory` enqueues the `memory` upsert
  /// routed on the row's OPAQUE `id` — NEVER the human `key`, which becomes the
  /// plaintext CloudKit `entity_id`. A potentially-identifying memory title must
  /// not cross the wire as routing metadata; it rides inside the payload (which
  /// the CloudKit envelope encrypts).
  func testUpsertMemoryEnqueuesMemoryRoutedOnOpaqueIdNotKey() async throws {
    let service = try makeService()
    _ = try await service.upsertMemory(key: "north_star", content: "Ship the port")

    let memoryId = try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM memories WHERE key = ?", arguments: ["north_star"])
      })
    XCTAssertNotEqual(
      memoryId, "north_star", "the memory row id must be a synthesized opaque id, not the key")

    let allOutbound = try service.pendingOutbound().map(\.envelope)
    XCTAssertFalse(
      allOutbound.contains { $0.entityId == "north_star" },
      "the human memory key must NEVER be an outbound routing entity_id")

    let memory = try pending(service, kind: .memory, id: memoryId)
    XCTAssertEqual(memory.last?.operation, .upsert)
    // The key is preserved — inside the payload (encrypted on the wire), not as
    // the plaintext routing identity.
    guard case let .object(payload) = try XCTUnwrap(JSONValue.parse(try XCTUnwrap(memory.last?.payload)))
    else { return XCTFail("memory payload must be a JSON object") }
    XCTAssertEqual(payload["key"], .string("north_star"))
    XCTAssertEqual(payload["id"], .string(memoryId))
    XCTAssertEqual(payload["content"], .string("Ship the port"))
  }

  /// Round-trip: a memory written by key is read back by key with identical
  /// content — the `id` indirection is invisible to callers.
  func testUpsertMemoryRoundTripsByKey() async throws {
    let service = try makeService()
    _ = try await service.upsertMemory(key: "alex_prefs", content: "likes tea")
    let reloaded = try await service.loadMemory()
    let entry = try XCTUnwrap(reloaded.entries.first { $0.key == "alex_prefs" })
    XCTAssertEqual(entry.content, "likes tea")
    // A second edit keeps the same opaque id (stable CloudKit identity).
    let firstId = try service.read { db in
      try String.fetchOne(db, sql: "SELECT id FROM memories WHERE key = ?", arguments: ["alex_prefs"])
    }
    _ = try await service.upsertMemory(key: "alex_prefs", content: "likes coffee")
    let secondId = try service.read { db in
      try String.fetchOne(db, sql: "SELECT id FROM memories WHERE key = ?", arguments: ["alex_prefs"])
    }
    XCTAssertEqual(secondId, firstId)
  }

  /// Setting a SYNCED preference key enqueues a `preference` upsert.
  func testSetSyncedPreferenceEnqueuesUpsert() async throws {
    let service = try makeService()
    _ = try await service.setPreference(
      key: PreferenceKeys.prefWorkingHours, value: #"{"start":"09:00","end":"17:00"}"#)
    XCTAssertEqual(
      try pending(service, kind: .preference, id: PreferenceKeys.prefWorkingHours).last?.operation,
      .upsert)
  }

  func testSetPreferenceSameStoredValueNoOpDoesNotEnqueueOrLog() async throws {
    let service = try makeService()
    _ = try await service.setPreference(
      key: PreferenceKeys.prefWorkingHours, value: #"{"start":"09:00","end":"17:00"}"#)
    let beforeSynced = try mutationCounts(service)

    _ = try await service.setPreference(
      key: PreferenceKeys.prefWorkingHours, value: #"{"start":"09:00","end":"17:00"}"#)
    let afterSynced = try mutationCounts(service)

    XCTAssertEqual(afterSynced.outbox, beforeSynced.outbox)
    XCTAssertEqual(afterSynced.changelog, beforeSynced.changelog)

    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode, value: CalendarAiAccessMode.fullDetails.asString)
    let beforeDeviceState = try mutationCounts(service)

    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode, value: CalendarAiAccessMode.fullDetails.asString)
    let afterDeviceState = try mutationCounts(service)

    XCTAssertEqual(afterDeviceState.outbox, beforeDeviceState.outbox)
    XCTAssertEqual(afterDeviceState.changelog, beforeDeviceState.changelog)
  }

  // MARK: - Negative: local-only writes never enqueue

  /// Setting a LOCAL-ONLY preference never enqueues a `preference` envelope: the
  /// preference value must not cross the sync boundary. The append-only
  /// `ai_changelog` audit of the action itself DOES ride (ACF-14 cross-device
  /// audit sync), so the only envelope a local-only write may add is that audit
  /// row — never a `preference` envelope for the local-only key.
  func testLocalOnlyWritesDoNotEnqueue() async throws {
    let service = try makeService()
    let before = try service.pendingOutbound().map(\.envelope)

    _ = try await service.setPreference(key: PreferenceKeys.prefTheme, value: "dark")

    let after = try service.pendingOutbound().map(\.envelope)
    // The local-only preference itself never crosses the sync boundary.
    XCTAssertFalse(
      after.contains {
        $0.entityType == .preference && $0.entityId == PreferenceKeys.prefTheme
      })
    // The write enqueues no NON-audit envelope. The only thing that may ride is
    // the append-only ai_changelog audit of the action (ACF-14 cross-device
    // audit sync), which is not a `preference` envelope.
    let addedNonAudit =
      after.filter { $0.entityType != .aiChangelog }.count
      - before.filter { $0.entityType != .aiChangelog }.count
    XCTAssertEqual(
      addedNonAudit, 0, "a local-only preference write must not enqueue a syncable entity")
  }

  // MARK: - SYNC-MED-2: habit archive-interleaving winner re-emit

  private func habitUpsertEnvelope(
    id: String, version: String, archived: Bool, name: String = "gym"
  ) throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "name": .string(name),
      "frequency_type": .string("daily"),
      "target_count": .int(1),
      "archived": .bool(archived),
      "created_at": .string("2026-04-01T00:00:00.000Z"),
      "updated_at": .string("2026-04-01T00:00:00.000Z"),
    ]))
    return try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .habit, entityId: id, operation: .upsert, version: try Hlc.parse(version),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion, payload: payload,
        deviceId: "device-remote"))
  }

  private func habitArchivedFlag(_ service: SwiftLorvexCoreService, _ id: String) throws -> Int64? {
    try service.read { db in
      try Int64.fetchOne(db, sql: "SELECT archived FROM habits WHERE id = ?", arguments: [id])
    }
  }

  /// A habit's UNIQUE index is partial (`WHERE archived = 0`), so the merge is
  /// non-confluent under an archive interleaving: device X pulls the loser ACTIVE
  /// (merges it into the winner), then pulls it ARCHIVED (the archived record
  /// redirect-remaps onto the winner and flips it to archived); device Y pulls only
  /// the archived loser, sees no collision, and leaves the winner ACTIVE. Without a
  /// re-emit the fleet is terminally divergent (winner archived-and-hidden on X vs
  /// active on Y). The fix re-emits the merged winner at a fresh HLC so both
  /// converge on archived.
  func testArchiveInterleavingRemapReemitsWinnerAndConverges() throws {
    // Smaller id wins `min(id)`; both share lookup_key "gym".
    let winnerId = "00000000-0000-7000-8000-000000000001"
    let loserId = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let winnerV = "1752000000000_0000_a0a0a0a0a0a0a0a0"
    let loserActiveV = "1752000001000_0000_b0b0b0b0b0b0b0b0"
    let loserArchivedV = "1752000002000_0000_b0b0b0b0b0b0b0b0"

    // Device X: winner active, then loser active (merges loser→winner), then loser
    // archived (remaps onto winner, flipping it to archived).
    let deviceX = try makeService()
    _ = try deviceX.applyInbound(
      [habitUpsertEnvelope(id: winnerId, version: winnerV, archived: false)], undecodable: 0)
    _ = try deviceX.applyInbound(
      [habitUpsertEnvelope(id: loserId, version: loserActiveV, archived: false)], undecodable: 0)
    let xReport = try deviceX.applyInbound(
      [habitUpsertEnvelope(id: loserId, version: loserArchivedV, archived: true)], undecodable: 0)

    XCTAssertEqual(xReport.remapped, 1, "the archived loser record redirect-remapped onto the winner")
    XCTAssertEqual(
      try habitArchivedFlag(deviceX, winnerId), 1, "X's winner flipped to archived via the remap")

    // The fix: X re-emitted the merged winner snapshot at a fresh HLC.
    let reemits = try deviceX.pendingOutbound().filter {
      $0.envelope.entityType == .habit && $0.envelope.entityId == winnerId
        && $0.envelope.operation == .upsert
    }
    XCTAssertEqual(
      reemits.count, 1, "the winner-changing remap re-emits exactly one fresh winner snapshot")
    let reemit = try XCTUnwrap(reemits.first?.envelope)
    XCTAssertTrue(
      reemit.payload.contains("\"archived\":true"),
      "the re-emit carries the merged (archived) winner state; got \(reemit.payload)")

    // Device Y pulled ONLY the archived loser — no collision, no merge — so its
    // winner stays ACTIVE. This is the terminal divergence.
    let deviceY = try makeService()
    _ = try deviceY.applyInbound(
      [habitUpsertEnvelope(id: winnerId, version: winnerV, archived: false)], undecodable: 0)
    _ = try deviceY.applyInbound(
      [habitUpsertEnvelope(id: loserId, version: loserArchivedV, archived: true)], undecodable: 0)
    XCTAssertEqual(
      try habitArchivedFlag(deviceY, winnerId), 0, "pre-re-emit, Y's winner is still active (diverged)")

    // Applying X's re-emit converges Y: the winner flips to archived on both.
    _ = try deviceY.applyInbound([reemit], undecodable: 0)
    XCTAssertEqual(
      try habitArchivedFlag(deviceY, winnerId), 1, "the winner re-emit converges Y to archived")
  }
}
