import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ports the parity-relevant `#[test]` cases for the apply-pipeline FOUNDATION:
/// error/result vocabulary, the LWW gate + SQL builder, the conflict log
/// (dedup + PII scrub), device-identity collision, FK preflight, the redirect
/// chain walker, the `apply_envelope` entry-point flow against an injected stub
/// applier, and the ai_changelog applier. Per-entity applier bodies land with
/// their own slices.
final class ApplyFoundationTests: XCTestCase {

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: "account-a", zoneName: "LorvexZone-g1")
      try body(db)
    }
  }

  private let suffix = "a1b2c3d4a1b2c3d4"
  private func v(_ ms: UInt64, _ ctr: UInt32 = 0) -> String {
    "\(String(format: "%013d", ms))_\(String(format: "%04d", ctr))_\(suffix)"
  }

  // MARK: - ApplyError.lift SQLite result-code classification

  /// D4 defense-in-depth: `ApplyError.lift` must split a DETERMINISTIC
  /// SQLITE_CONSTRAINT trip (CHECK / NOT NULL / UNIQUE) into ``ApplyError/dbConstraint(_:)``
  /// — the class the inbound batch loop drops (single-envelope, non-fatal) —
  /// while a generic / IO failure stays ``ApplyError/db(_:)`` (batch-fatal,
  /// retry the whole page). The distinction is by the SQLite primary result
  /// code, so a future constraint that escapes an applier degrades to one
  /// dropped envelope instead of wedging the whole fetch loop forever.
  func testLiftClassifiesDeterministicConstraintTripsAsDbConstraint() throws {
    try withDB { db in
      try db.execute(
        sql: """
          CREATE TABLE _lift_probe (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            n INTEGER CHECK (n IS NULL OR (n >= 1 AND n <= 5))
          )
          """)

      func liftedError(_ sql: String) -> ApplyError? {
        do {
          try db.execute(sql: sql)
          return nil
        } catch let error as DatabaseError {
          return ApplyError.lift(error)
        } catch {
          return ApplyError.lift(error)
        }
      }

      // CHECK violation → SQLITE_CONSTRAINT → .dbConstraint
      guard
        case .dbConstraint = try XCTUnwrap(
          liftedError("INSERT INTO _lift_probe (id, name, n) VALUES ('a', 'x', 9)"))
      else { return XCTFail("CHECK trip must lift to .dbConstraint") }

      // NOT NULL violation → SQLITE_CONSTRAINT → .dbConstraint
      guard
        case .dbConstraint = try XCTUnwrap(
          liftedError("INSERT INTO _lift_probe (id, name, n) VALUES ('b', NULL, 1)"))
      else { return XCTFail("NOT NULL trip must lift to .dbConstraint") }

      // UNIQUE (PK) violation → SQLITE_CONSTRAINT → .dbConstraint
      try db.execute(sql: "INSERT INTO _lift_probe (id, name, n) VALUES ('c', 'y', 1)")
      guard
        case .dbConstraint = try XCTUnwrap(
          liftedError("INSERT INTO _lift_probe (id, name, n) VALUES ('c', 'z', 2)"))
      else { return XCTFail("UNIQUE/PK trip must lift to .dbConstraint") }
    }
  }

  /// A non-constraint SQLite failure (here a syntax / no-such-table error) must
  /// stay ``ApplyError/db(_:)`` — batch-fatal — so a genuine store fault still
  /// aborts and retries the page rather than being silently dropped.
  func testLiftClassifiesGenericSqliteErrorAsDb() throws {
    try withDB { db in
      do {
        try db.execute(sql: "INSERT INTO _no_such_table_ (x) VALUES (1)")
        XCTFail("expected a SQLite error")
      } catch let error as DatabaseError {
        guard case .db = ApplyError.lift(error) else {
          return XCTFail("a generic SQLite error must lift to .db, got \(ApplyError.lift(error))")
        }
      }
    }
  }

  // MARK: - LwwUpsertSpec.buildSQL

  func testBuildSQLEmitsStrictLwwClause() {
    let spec = LwwUpsertSpec(
      table: "preferences", columns: ["key", "value", "updated_at", "version"],
      conflict: ["key"], tieBreak: .rejectEqual)
    let sql = spec.buildSQL()
    XCTAssertTrue(sql.contains("INSERT INTO preferences (key, value, updated_at, version)"))
    XCTAssertTrue(sql.contains("VALUES (:key, :value, :updated_at, :version)"))
    XCTAssertTrue(sql.contains("ON CONFLICT(key) DO UPDATE SET"))
    XCTAssertFalse(sql.contains("key=excluded.key"))
    XCTAssertTrue(sql.contains("value=excluded.value"))
    XCTAssertTrue(sql.contains("version=excluded.version"))
    XCTAssertTrue(sql.contains("WHERE excluded.version > preferences.version"))
  }

  func testBuildSQLAllowEqualFlipsPredicate() {
    let spec = LwwUpsertSpec(
      table: "preferences", columns: ["key", "value", "updated_at", "version"],
      conflict: ["key"], tieBreak: .allowEqual)
    XCTAssertTrue(spec.buildSQL().contains("WHERE excluded.version >= preferences.version"))
  }

  func testBuildSQLSupportsCompositeConflictKeys() {
    let spec = LwwUpsertSpec(
      table: "task_tags", columns: ["task_id", "tag_id", "created_at", "version"],
      conflict: ["task_id", "tag_id"], tieBreak: .rejectEqual)
    let sql = spec.buildSQL()
    XCTAssertTrue(sql.contains("ON CONFLICT(task_id, tag_id) DO UPDATE SET"))
    XCTAssertFalse(sql.contains("task_id=excluded.task_id"))
    XCTAssertFalse(sql.contains("tag_id=excluded.tag_id"))
    XCTAssertTrue(sql.contains("created_at=excluded.created_at"))
    XCTAssertTrue(sql.contains("version=excluded.version"))
  }

  func testVersionCmpOperators() {
    XCTAssertEqual(LwwTieBreak.rejectEqual.sqlOp, ">")
    XCTAssertEqual(LwwTieBreak.allowEqual.sqlOp, ">=")
    XCTAssertEqual(LwwTieBreak(allowEqualVersions: true), .allowEqual)
    XCTAssertEqual(LwwTieBreak(allowEqualVersions: false), .rejectEqual)
  }

  // MARK: - lwwGatedDelete

  func testLwwGatedDeleteRemovesWhenIncomingStrictlyGreater() throws {
    try withDB { db in
      try db.execute(
        sql: "INSERT INTO tasks (id, list_id, title, status, version, created_at, updated_at) "
          + "VALUES ('33333333-3333-7333-8333-333333333333', 'inbox', 'x', 'open', ?, '2026-03-23T12:00:00.000Z', '2026-03-23T12:00:00.000Z')",
        arguments: [self.v(100)])
      let deleted = try ApplyLww.lwwGatedDelete(
        db, table: "tasks", pkColumns: ["id"], pkValues: ["33333333-3333-7333-8333-333333333333"],
        incomingVersion: self.v(200))
      XCTAssertEqual(deleted, 1)
    }
  }

  func testLwwGatedDeleteRefusesWhenIncomingOlder() throws {
    try withDB { db in
      try db.execute(
        sql: "INSERT INTO tasks (id, list_id, title, status, version, created_at, updated_at) "
          + "VALUES ('33333333-3333-7333-8333-333333333333', 'inbox', 'x', 'open', ?, '2026-03-23T12:00:00.000Z', '2026-03-23T12:00:00.000Z')",
        arguments: [self.v(200)])
      let deleted = try ApplyLww.lwwGatedDelete(
        db, table: "tasks", pkColumns: ["id"], pkValues: ["33333333-3333-7333-8333-333333333333"],
        incomingVersion: self.v(100))
      XCTAssertEqual(deleted, 0)
    }
  }

  func testLwwGatedDeleteNoopOnAbsentRow() throws {
    try withDB { db in
      let deleted = try ApplyLww.lwwGatedDelete(
        db, table: "tasks", pkColumns: ["id"], pkValues: ["missing"],
        incomingVersion: self.v(100))
      XCTAssertEqual(deleted, 0)
    }
  }

  // MARK: - Conflict log

  private func lwwEntry(_ entityId: String, resolvedAt: String) -> ConflictLog.Entry {
    ConflictLog.Entry(
      entityType: EntityName.task, entityId: entityId,
      winnerVersion: v(101), loserVersion: v(100), loserDeviceId: "device-002",
      loserPayload: nil, resolvedAt: resolvedAt, resolutionType: ResolutionName.lww)
  }

  func testLogConflictDedupesIdenticalEntry() throws {
    try withDB { db in
      let e = self.lwwEntry("task-001", resolvedAt: "2026-03-23T12:00:00.000Z")
      try ConflictLog.logConflict(db, e)
      try ConflictLog.logConflict(db, e)
      let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_conflict_log") ?? 0
      XCTAssertEqual(count, 1)
    }
  }

  func testGcConflictsPreservesUnexpired() throws {
    try withDB { db in
      try ConflictLog.logConflict(
        db, self.lwwEntry("task-001", resolvedAt: "2099-01-01T00:00:00.000Z"))
      let deleted = try ConflictLog.gcConflicts(db, retentionDays: 30)
      XCTAssertEqual(deleted, 0)
    }
  }

  func testLwwConflictPreservesEqualVersionPayloadShadow() throws {
    try withDB { db in
      let taskId = "77777777-7777-7777-8777-777777777777"
      let shadowVersion = self.v(101)
      try PayloadShadow.restoreShadow(
        db,
        row: PayloadShadow.Row(
          entityType: .task, entityID: taskId, baseVersion: shadowVersion,
          payloadSchemaVersion: Int(LorvexVersion.payloadSchemaVersion),
          rawPayloadJSON: #"{"future_key":"kept"}"#, sourceDeviceID: "device-shadow",
          updatedAt: "2026-01-01T00:00:00.000Z"))

      _ = try ApplyConflict.recordLwwConflictAndSkip(
        db, entityType: EntityName.task, entityId: taskId,
        localVersion: try Hlc.parse(shadowVersion),
        envelope: try self.envelope(.task, taskId, .upsert, 100),
        skipReason: "local newer than remote", applyTs: "2026-01-01T00:00:00.000Z")

      XCTAssertNotNil(
        try PayloadShadow.getShadow(db, entityType: EntityName.task, entityID: taskId))
    }
  }

  func testScrubLoserPayloadRedactsPiiKeys() {
    let raw =
      #"{"title":"Pregnancy test","notes":"follow up","url":"https://private.example/token","person_name":"Ada Lovelace","tags":["health"],"priority":1}"#
    let out = ConflictLog.scrubLoserPayload(raw)
    XCTAssertFalse(out.contains("Pregnancy test"))
    XCTAssertFalse(out.contains("follow up"))
    XCTAssertFalse(out.contains("private.example"))
    XCTAssertFalse(out.contains("Ada Lovelace"))
    XCTAssertTrue(out.contains("[REDACTED_PII]"))
    XCTAssertTrue(out.contains(#""priority":1"#))
  }

  func testScrubLoserPayloadRecursesIntoNestedObjects() {
    let raw = #"{"outer":{"notes":"secret","id":"abc"},"keep":true}"#
    let out = ConflictLog.scrubLoserPayload(raw)
    XCTAssertFalse(out.contains("secret"))
    XCTAssertTrue(out.contains("[REDACTED_PII]"))
    XCTAssertTrue(out.contains(#""id":"abc""#))
    XCTAssertTrue(out.contains(#""keep":true"#))
  }

  func testScrubLoserPayloadRedactsStringEncodedChangelogSnapshots() {
    let raw =
      #"{"before_json":"{\"title\":\"private before\"}","after_json":"{\"notes\":\"private after\"}","summary":"audit"}"#
    let out = ConflictLog.scrubLoserPayload(raw)
    XCTAssertFalse(out.contains("private before"))
    XCTAssertFalse(out.contains("private after"))
    XCTAssertTrue(out.contains("[REDACTED_PII]"))
  }

  func testScrubLoserPayloadRejectsNonJson() {
    XCTAssertEqual(
      ConflictLog.scrubLoserPayload("this is not json"), "<non-json payload suppressed>")
  }

  // MARK: - Redirect chain

  func testChaseRedirectChainNoTombstoneReturnsInitial() throws {
    try withDB { db in
      let result = try ApplyRedirect.chaseRedirectChain(
        db, initialEntityType: EntityName.tag,
        initialEntityId: "33333333-3333-7333-8333-333333333333")
      XCTAssertEqual(result.finalId, "33333333-3333-7333-8333-333333333333")
      XCTAssertTrue(result.hops.isEmpty)
    }
  }

  func testChaseRedirectChainFollowsSingleHop() throws {
    try withDB { db in
      let target = "22222222-2222-7222-8222-222222222222"
      try SyncTestSupport.seedEntityRedirect(
        db, sourceType: .tag,
        sourceId: "33333333-3333-7333-8333-333333333333", targetId: target,
        version: self.v(100))
      let result = try ApplyRedirect.chaseRedirectChain(
        db, initialEntityType: EntityName.tag,
        initialEntityId: "33333333-3333-7333-8333-333333333333")
      XCTAssertEqual(result.finalId, target)
      XCTAssertEqual(result.hops.count, 1)
      XCTAssertEqual(result.hops[0].fromEntityId, "33333333-3333-7333-8333-333333333333")
      XCTAssertEqual(result.hops[0].toEntityId, target)
    }
  }

  func testRemapEntityIdSimpleAndComposite() {
    XCTAssertEqual(
      ApplyRedirect.remapEntityId(originalId: "t1", oldPart: "t1", newPart: "t2", entityType: nil),
      "t2")
    XCTAssertEqual(
      ApplyRedirect.remapEntityId(
        originalId: "t1:tag9", oldPart: "t1", newPart: "t2", entityType: EdgeName.taskTag),
      "t2:tag9")
  }

  func testRemapPayloadIdentityFieldsRewritesId() {
    var payload: JSONValue = ["id": "t1", "title": "x"]
    let changed = ApplyRedirect.remapPayloadIdentityFields(
      entityType: EntityName.task, payload: &payload, originalId: "t1", targetId: "t2")
    XCTAssertTrue(changed)
    guard case .object(let map) = payload, case .string(let id)? = map["id"] else {
      return XCTFail("payload not an object")
    }
    XCTAssertEqual(id, "t2")
  }

  // MARK: - FK preflight

  func testFkPreflightDefersTaskWithMissingList() throws {
    try withDB { db in
      let payload =
        #"{"id":"33333333-3333-7333-8333-333333333333","list_id":"missing-list","title":"x"}"#
      let dep = try ApplyFk.checkFkDependencies(
        db, entityType: EntityName.task, entityId: "33333333-3333-7333-8333-333333333333",
        payload: payload)
      XCTAssertEqual(dep?.0, .list)
      XCTAssertEqual(dep?.1, "missing-list")
    }
  }

  func testFkPreflightPassesWhenListPresent() throws {
    try withDB { db in
      // The schema seeds an `inbox` list; reference it.
      let payload = #"{"id":"33333333-3333-7333-8333-333333333333","list_id":"inbox","title":"x"}"#
      let dep = try ApplyFk.checkFkDependencies(
        db, entityType: EntityName.task, entityId: "33333333-3333-7333-8333-333333333333",
        payload: payload)
      XCTAssertNil(dep)
    }
  }

  func testFkPreflightEdgeMismatchThrows() throws {
    try withDB { db in
      let payload = #"{"task_id":"WRONG","tag_id":"tag9"}"#
      XCTAssertThrowsError(
        try ApplyFk.checkFkDependencies(
          db, entityType: EdgeName.taskTag, entityId: "t1:tag9", payload: payload)
      ) { error in
        guard case .invalidPayload = error as? ApplyError else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
      }
    }
  }

  // MARK: - apply_envelope entry point

  /// Stub applier that records every dispatched envelope and returns a
  /// configurable outcome.
  private final class StubApplier: EntityApplier, @unchecked Sendable {
    let types: [String]
    let upsertOutcome: EntityApplyOutcome
    let deleteOutcome: EntityApplyOutcome
    var upserts: [SyncEnvelope] = []
    var deletes: [SyncEnvelope] = []
    init(
      types: [String], upsert: EntityApplyOutcome = .applied,
      delete: EntityApplyOutcome = .applied
    ) {
      self.types = types
      self.upsertOutcome = upsert
      self.deleteOutcome = delete
    }
    var handledEntityTypes: [String] { types }
    func applyUpsert(_ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String)
      throws -> EntityApplyOutcome
    {
      upserts.append(envelope)
      return upsertOutcome
    }
    func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
      -> EntityApplyOutcome
    {
      deletes.append(envelope)
      return deleteOutcome
    }
  }

  private func envelope(
    _ kind: EntityKind, _ id: String, _ op: SyncOperation, _ versionMs: UInt64,
    payload: String = "{}", schema: UInt32 = LorvexVersion.payloadSchemaVersion,
    device: String = "device-remote"
  ) throws -> SyncEnvelope {
    let version = try Hlc.parse(v(versionMs))
    if kind == .task {
      return try SyncTestSupport.completeEnvelope(
        entityType: kind, entityId: id, operation: op, version: version,
        payloadSchemaVersion: schema, payload: payload, deviceId: device)
    }
    let canonicalPayload: String
    if op == .delete {
      var object: [String: JSONValue] = ["version": .string(version.description)]
      if case .object(let supplied)? = JSONValue.parse(payload) {
        object.merge(supplied) { _, supplied in supplied }
        object["version"] = .string(version.description)
      }
      canonicalPayload = try SyncCanonicalize.canonicalizeJSON(.object(object))
    } else if kind.isSyncableKind,
      let golden = try SyncPayloadContractFixture.goldenEnvelopes()
        .first(where: { $0.entityType == kind }),
      case .object(var object)? = JSONValue.parse(golden.payload)
    {
      if case .object(let supplied)? = JSONValue.parse(payload) {
        object.merge(supplied) { _, supplied in supplied }
      }
      object["version"] = .string(version.description)
      switch kind {
      case .task, .list, .habit, .tag, .calendarEvent, .memory,
        .taskReminder, .taskChecklistItem, .habitReminderPolicy:
        object["id"] = .string(id)
      case .preference:
        object["key"] = .string(id)
      case .dailyReview, .currentFocus, .focusSchedule:
        object["date"] = .string(id)
      default:
        break
      }
      if kind == .task {
        object["list_id"] = .string(ListId.inboxSentinel)
      }
      canonicalPayload = try SyncCanonicalize.canonicalizeJSON(.object(object))
    } else {
      canonicalPayload = payload
    }
    return SyncEnvelope(
      entityType: kind, entityId: id, operation: op, version: version,
      payloadSchemaVersion: schema, payload: canonicalPayload, deviceId: device)
  }

  func testApplyEnvelopeDefersSchemaTooNew() throws {
    try withDB { db in
      let env = try self.envelope(
        .list, "22222222-2222-7222-8222-222222222222", .upsert, 100,
        schema: LorvexVersion.payloadSchemaVersion + 50)
      let result = try Apply.applyEnvelope(db, registry: EntityApplierRegistry(), envelope: env)
      guard case .deferred(let reason) = result, case .schemaTooNew = reason else {
        return XCTFail("expected schemaTooNew deferral, got \(result)")
      }
    }
  }

  func testApplyEnvelopeDefersForwardCompatChangelog() throws {
    try withDB { db in
      let env = try self.envelope(
        .aiChangelog, "11111111-1111-7111-8111-111111111111", .upsert, 100,
        schema: LorvexVersion.payloadSchemaVersion + 1)
      let result = try Apply.applyEnvelope(db, registry: EntityApplierRegistry(), envelope: env)
      guard case .deferred = result else { return XCTFail("expected deferral, got \(result)") }
      let rows = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? -1
      XCTAssertEqual(rows, 0)
      let shadows = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_payload_shadow") ?? -1
      XCTAssertEqual(shadows, 0)
    }
  }

  func testApplyEnvelopeUnknownEntityWhenRegistryEmpty() throws {
    try withDB { db in
      let env = try self.envelope(
        .list, "22222222-2222-7222-8222-222222222222", .upsert, 100,
        payload: #"{"id":"22222222-2222-7222-8222-222222222222"}"#)
      XCTAssertThrowsError(
        try Apply.applyEnvelope(db, registry: EntityApplierRegistry(), envelope: env)
      ) { error in
        guard case .unknownEntityType = error as? ApplyError else {
          return XCTFail("expected unknownEntityType, got \(error)")
        }
      }
    }
  }

  func testApplyEnvelopeDispatchesUpsertToRegisteredApplier() throws {
    try withDB { db in
      let stub = StubApplier(types: [EntityName.list])
      let registry = EntityApplierRegistry(appliers: [stub])
      let env = try self.envelope(
        .list, "22222222-2222-7222-8222-222222222222", .upsert, 100,
        payload: #"{"id":"22222222-2222-7222-8222-222222222222"}"#)
      let result = try Apply.applyEnvelope(db, registry: registry, envelope: env)
      XCTAssertEqual(result, .applied)
      XCTAssertEqual(stub.upserts.count, 1)
    }
  }

  func testApplyEnvelopeDeleteWritesTombstone() throws {
    try withDB { db in
      let stub = StubApplier(types: [EntityName.list])
      let registry = EntityApplierRegistry(appliers: [stub])
      let env = try self.envelope(
        .list, "22222222-2222-7222-8222-222222222222", .delete, 100,
        payload: #"{"id":"22222222-2222-7222-8222-222222222222"}"#)
      let result = try Apply.applyEnvelope(db, registry: registry, envelope: env)
      XCTAssertEqual(result, .applied)
      XCTAssertTrue(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.list, entityId: "22222222-2222-7222-8222-222222222222"))
    }
  }

  func testApplyEnvelopeDeleteSkippedByInvariantDefers() throws {
    try withDB { db in
      let stub = StubApplier(
        types: [EntityName.list], delete: .deleteSkippedByInvariant(invariant: "at_least_one_list"))
      let registry = EntityApplierRegistry(appliers: [stub])
      let env = try self.envelope(
        .list, "22222222-2222-7222-8222-222222222222", .delete, 100,
        payload: #"{"id":"22222222-2222-7222-8222-222222222222"}"#)
      let result = try Apply.applyEnvelope(db, registry: registry, envelope: env)
      guard case .deferred(let reason) = result,
        case .aggregateInvariantBlocked(_, _, let invariant) = reason
      else {
        return XCTFail("expected aggregateInvariantBlocked, got \(result)")
      }
      XCTAssertEqual(invariant, "at_least_one_list")
      XCTAssertFalse(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.list, entityId: "22222222-2222-7222-8222-222222222222"))
    }
  }

  func testApplyEnvelopeSkipsLocalOnlyKind() throws {
    try withDB { db in
      let env = SyncEnvelope(
        entityType: .deviceState, entityId: "ds1", operation: .upsert,
        version: try Hlc.parse(self.v(100)),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: "{}", deviceId: "d")
      let result = try Apply.applyEnvelope(db, registry: EntityApplierRegistry(), envelope: env)
      guard case .skipped(_, let winner) = result else {
        return XCTFail("expected skipped, got \(result)")
      }
      XCTAssertNil(winner)
    }
  }

  func testApplyEnvelopeLwwSkipsStaleUpsert() throws {
    try withDB { db in
      // Seed every independent task register at the high-water mark; a lower
      // whole-row upsert with no winning register must skip.
      try db.execute(
        sql: "INSERT INTO tasks (id, list_id, title, status, version, "
          + "content_version, schedule_version, lifecycle_version, archive_version, "
          + "created_at, updated_at) "
          + "VALUES ('33333333-3333-7333-8333-333333333333', 'inbox', 'x', 'open', "
          + "?1, ?1, ?1, ?1, ?1, '2026-03-23T12:00:00.000Z', "
          + "'2026-03-23T12:00:00.000Z')",
        arguments: [self.v(500)])
      let stub = StubApplier(types: [EntityName.task])
      let registry = EntityApplierRegistry(appliers: [stub])
      let env = try self.envelope(
        .task, "33333333-3333-7333-8333-333333333333", .upsert, 100,
        payload: #"{"id":"33333333-3333-7333-8333-333333333333"}"#)
      let result = try Apply.applyEnvelope(db, registry: registry, envelope: env)
      guard case .skipped(_, let winner) = result else {
        return XCTFail("expected skipped, got \(result)")
      }
      XCTAssertEqual(winner?.description, self.v(500))
      XCTAssertEqual(stub.upserts.count, 0)
      // Conflict-log row written.
      let n = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_conflict_log") ?? 0
      XCTAssertEqual(n, 1)
    }
  }

  func testApplyEnvelopeTombstoneWinsOverStaleUpsert() throws {
    try withDB { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "33333333-3333-7333-8333-333333333333",
        version: self.v(500),
        deletedAt: "2026-03-23T12:00:00.000Z")
      let stub = StubApplier(types: [EntityName.task])
      let registry = EntityApplierRegistry(appliers: [stub])
      let env = try self.envelope(
        .task, "33333333-3333-7333-8333-333333333333", .upsert, 100,
        payload: #"{"id":"33333333-3333-7333-8333-333333333333"}"#)
      let result = try Apply.applyEnvelope(db, registry: registry, envelope: env)
      guard case .skipped = result else { return XCTFail("expected skipped, got \(result)") }
      XCTAssertEqual(stub.upserts.count, 0)
    }
  }

  func testApplyEnvelopeUpsertWinsOverOlderTombstone() throws {
    try withDB { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "33333333-3333-7333-8333-333333333333",
        version: self.v(100),
        deletedAt: "2026-03-23T12:00:00.000Z")
      let stub = StubApplier(types: [EntityName.task])
      let registry = EntityApplierRegistry(appliers: [stub])
      let env = try self.envelope(
        .task, "33333333-3333-7333-8333-333333333333", .upsert, 500,
        payload: #"{"id":"33333333-3333-7333-8333-333333333333"}"#)
      let result = try Apply.applyEnvelope(db, registry: registry, envelope: env)
      XCTAssertEqual(result, .applied)
      XCTAssertEqual(stub.upserts.count, 1)
      XCTAssertFalse(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.task, entityId: "33333333-3333-7333-8333-333333333333"))
    }
  }

  // MARK: - ChangelogApplier

  private func changelogPayload(id: String) -> String {
    return """
      {"id":"\(id)","timestamp":"2026-03-23T12:00:00.000Z","operation":"create",\
      "entity_type":"task","entity_id":"task-1","summary":"Created a task",\
      "initiated_by":"ai","retention_epoch":0}
      """
  }

  func testChangelogDedupesById() throws {
    try withDB { db in
      let id = "11111111-1111-7111-8111-111111111111"
      let payload = self.changelogPayload(id: id)
      for _ in 0..<2 {
        try ChangelogApplier.applyChangelogEntry(
          db, entityId: id, payload: payload,
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion)
      }
      let n =
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?", arguments: [id])
        ?? 0
      XCTAssertEqual(n, 1)
    }
  }

  func testChangelogDeleteIsAlwaysRejectedAndPreservesTheAuditRow() throws {
    try withDB { db in
      let id = "11111111-1111-7111-8111-111111111111"
      try ChangelogApplier.applyChangelogEntry(
        db, entityId: id, payload: self.changelogPayload(id: id),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion)
      let envelope = try self.envelope(
        .aiChangelog, id, .delete, 100,
        payload: #"{"reset_all_data":true}"#)
      XCTAssertThrowsError(
        try ChangelogApplier().applyDelete(
          db, envelope: envelope, applyTs: "2026-03-23T12:00:00.000Z")
      ) { error in
        guard case .invalidOperation(let entityType, let operation) = error as? ApplyError else {
          return XCTFail("expected invalidOperation, got \(error)")
        }
        XCTAssertEqual(entityType, EntityName.aiChangelog)
        XCTAssertEqual(operation, "delete")
      }
      let n =
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?", arguments: [id])
        ?? -1
      XCTAssertEqual(n, 1)
    }
  }

  // MARK: - Device-identity collision

  func testGenerationRepackageDoesNotLogFalseDeviceCollision() throws {
    try withDB { db in
      ApplyCollision.resetGuardForTesting()
      // Seed a local device_id whose app-surface suffix we mint envelopes with.
      let localDeviceId = "device-local-aaaa"
      try db.execute(
        sql: "INSERT OR REPLACE INTO sync_checkpoints (key, value) VALUES ('device_id', ?)",
        arguments: [localDeviceId])
      let appSuffix = DeviceIdentity.deviceIdToHlcSuffix(localDeviceId, surface: .app)
      let ver = "1711234567890_0000_\(appSuffix)"
      let env = SyncEnvelope(
        entityType: .task, entityId: "33333333-3333-7333-8333-333333333333", operation: .upsert,
        version: try Hlc.parse(ver),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion, payload: "{}",
        deviceId: "DIFFERENT-device-id")
      ApplyCollision.checkDeviceIdentityCollision(db, envelope: env)
      let n =
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.device_collision'")
        ?? 0
      XCTAssertEqual(n, 0)
      XCTAssertFalse(
        ApplyCollision.shouldReportCollision(
          localDeviceId: localDeviceId, localSuffixes: [appSuffix],
          envelopeDeviceId: env.deviceId, envelopeSuffix: appSuffix,
          envelopeDerivedSuffixes: HlcSurface.allSurfaces.map {
            DeviceIdentity.deviceIdToHlcSuffix(env.deviceId, surface: $0)
          }))
      XCTAssertTrue(
        ApplyCollision.shouldReportCollision(
          localDeviceId: localDeviceId, localSuffixes: [appSuffix],
          envelopeDeviceId: env.deviceId, envelopeSuffix: appSuffix,
          envelopeDerivedSuffixes: [appSuffix]),
        "two distinct full ids that independently derive one suffix are a real collision")
      ApplyCollision.resetGuardForTesting()
    }
  }
}
