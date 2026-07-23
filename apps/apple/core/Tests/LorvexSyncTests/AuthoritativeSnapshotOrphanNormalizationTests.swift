import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class AuthoritativeSnapshotOrphanNormalizationTests: XCTestCase {
  private static let account = "orphan-normalization-account"
  private static let zone = "LorvexZone"
  private static let databaseInstanceID = "orphan-normalization-database"
  private static let deviceID = "orphan-normalization-device"
  private static let taskID = "00000000-0000-7000-8000-000000000101"
  private static let secondTaskID = "00000000-0000-7000-8000-000000000102"
  private static let eventID = "00000000-0000-7000-8000-000000000201"
  private static let otherEventID = "00000000-0000-7000-8000-000000000202"
  private static let reminderID = "00000000-0000-7000-8000-000000000301"
  private static let futureListID = "00000000-0000-7000-8000-000000000401"
  private static let childVersion = "1760000000000_0000_aaaaaaaaaaaaaaaa"
  private static let parentDeleteVersion = "1760000001000_0000_bbbbbbbbbbbbbbbb"
  private static let postSessionVersion = "1760000002000_0000_cccccccccccccccc"
  private static let timestamp = "2026-10-01T00:00:00.000Z"

  private final class LockedHlcHandle: HlcDominatingStateHandle, @unchecked Sendable {
    private let lock = NSLock()
    private let state: HlcState

    init() throws {
      state = try HlcState(deviceSuffix: "dddddddddddddddd")
    }

    func generate() -> Hlc {
      lock.lock()
      defer { lock.unlock() }
      return state.generate(withPhysicalMs: 2_000_000_000_000)
    }

    func generate(dominating floor: Hlc?) -> Hlc {
      lock.lock()
      defer { lock.unlock() }
      if let floor {
        state.updateOnReceive(remote: floor, physicalMs: 2_000_000_000_000)
      }
      return state.generate(withPhysicalMs: 2_000_000_000_000)
    }
  }

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private func hlcSession() throws -> HlcSession {
    HlcSession(handle: try LockedHlcHandle())
  }

  private func startSnapshot(_ db: Database) throws -> AuthoritativeSnapshotSession {
    try SyncCheckpoints.set(
      db, key: SyncCheckpoints.keyDatabaseInstanceId,
      value: Self.databaseInstanceID)
    _ = try CloudTraversalWitness.claimAccount(
      db, accountIdentifier: Self.account)
    let session = try AuthoritativeSnapshot.begin(
      db,
      boundary: try SyncTestSupport.cloudTraversalBoundary(
        accountIdentifier: Self.account, zoneIdentifier: Self.zone),
      databaseInstanceId: Self.databaseInstanceID)
    try AuthoritativeSnapshot.markReady(db, sessionToken: session.sessionToken)
    return session
  }

  private func stage(
    _ db: Database, session: AuthoritativeSnapshotSession,
    records: [AuthoritativeSnapshotRemoteRecord]
  ) throws {
    try AuthoritativeSnapshot.stagePage(
      db, records: records, deletedRecordNames: [],
      sessionToken: session.sessionToken)
  }

  private func finalize(
    _ db: Database, session: AuthoritativeSnapshotSession, hlc: HlcSession
  ) throws -> AuthoritativeSnapshotReport {
    try AuthoritativeSnapshot.finalize(
      db, registry: registry, hlc: hlc, deviceId: Self.deviceID,
      sessionToken: session.sessionToken,
      databaseInstanceId: session.databaseInstanceId)
  }

  private func envelope(
    kind: EntityKind, id: String, operation: SyncOperation = .upsert,
    version: String = childVersion, fields: [String: JSONValue]
  ) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: kind, entityId: id, operation: operation,
      version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(fields)),
      deviceId: "remote-device")
  }

  private func staged(_ envelope: SyncEnvelope) -> AuthoritativeSnapshotRemoteRecord {
    AuthoritativeSnapshotRemoteRecord(
      recordName: SyncRecordName.opaque(
        entityType: envelope.entityType.asString, entityId: envelope.entityId),
      state: .decoded, envelope: envelope)
  }

  private func inboxEnvelope() throws -> SyncEnvelope {
    try envelope(
      kind: .list, id: "inbox",
      fields: [
        "name": .string("Inbox"),
        "created_at": .string(Self.timestamp),
        "updated_at": .string(Self.timestamp),
      ])
  }

  private func taskEnvelope(
    id: String = taskID, listID: String = "inbox"
  ) throws -> SyncEnvelope {
    try envelope(
      kind: .task, id: id,
      fields: [
        "list_id": .string(listID),
        "title": .string("Remote task"),
        "status": .string("open"),
        "created_at": .string(Self.timestamp),
        "updated_at": .string(Self.timestamp),
      ])
  }

  private func calendarEnvelope(
    version: String = childVersion, deviceID: String = "remote-device"
  ) throws -> SyncEnvelope {
    var result = try envelope(
      kind: .calendarEvent, id: Self.eventID, version: version,
      fields: [
        "title": .string("Remote event"),
        "start_date": .string("2026-10-01"),
        "start_time": .string("09:00"),
        "end_time": .string("09:30"),
        "all_day": .bool(false),
        "created_at": .string(Self.timestamp),
        "updated_at": .string(Self.timestamp),
      ])
    result.deviceId = deviceID
    return result
  }

  private func calendarDelete() throws -> SyncEnvelope {
    try envelope(
      kind: .calendarEvent, id: Self.eventID, operation: .delete,
      version: Self.parentDeleteVersion, fields: [:])
  }

  private func linkEnvelope() throws -> SyncEnvelope {
    try envelope(
      kind: .taskCalendarEventLink,
      id: "\(Self.taskID):\(Self.eventID)",
      fields: [
        "task_id": .string(Self.taskID),
        "calendar_event_id": .string(Self.eventID),
        "created_at": .string(Self.timestamp),
        "updated_at": .string(Self.timestamp),
      ])
  }

  private func reminderEnvelope() throws -> SyncEnvelope {
    try envelope(
      kind: .taskReminder, id: Self.reminderID,
      fields: [
        "task_id": .string(Self.taskID),
        "reminder_at": .string("2026-10-01T09:00:00.000Z"),
        "created_at": .string(Self.timestamp),
      ])
  }

  private func assertSyntheticDelete(
    _ db: Database, kind: EntityKind, id: String,
    dominates floors: [String], file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let tombstone = try XCTUnwrap(
      try Tombstone.getTombstone(
        db, entityType: kind.asString, entityId: id),
      file: file, line: line)
    let tombstoneVersion = try Hlc.parseCanonical(tombstone.version)
    for floor in floors {
      XCTAssertGreaterThan(
        tombstoneVersion, try Hlc.parseCanonical(floor), file: file, line: line)
    }
    let row = try XCTUnwrap(
      try Row.fetchOne(
        db,
        sql: """
          SELECT operation, version, payload FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [kind.asString, id]),
      file: file, line: line)
    XCTAssertEqual(row["operation"] as String, SyncNaming.opDelete, file: file, line: line)
    XCTAssertEqual(row["version"] as String, tombstone.version, file: file, line: line)
    guard case .object(let payload)? = JSONValue.parse(row["payload"] as String) else {
      return XCTFail("synthetic Delete payload must be an object", file: file, line: line)
    }
    XCTAssertEqual(payload["version"], .string(tombstone.version), file: file, line: line)
  }

  func testParentDeleteAndStaleCalendarLinkAuthorsDominatingDeleteAndReruns() throws {
    let store = try SyncTestSupport.freshStore()
    let hlc = try hlcSession()
    let linkID = "\(Self.taskID):\(Self.eventID)"
    let records = try [
      staged(inboxEnvelope()), staged(taskEnvelope()),
      staged(calendarDelete()), staged(linkEnvelope()),
    ]

    try store.writer.write { db in
      let session = try startSnapshot(db)
      try stage(db, session: session, records: records)
      _ = try finalize(db, session: session, hlc: hlc)

      XCTAssertNil(
        try Row.fetchOne(
          db,
          sql: """
            SELECT 1 FROM task_calendar_event_links
            WHERE task_id = ? AND calendar_event_id = ?
            """,
          arguments: [Self.taskID, Self.eventID]))
      try assertSyntheticDelete(
        db, kind: .taskCalendarEventLink, id: linkID,
        dominates: [Self.childVersion, Self.parentDeleteVersion])
      XCTAssertNil(try AuthoritativeSnapshot.activeSession(db))

      // CloudKit may present the same inconsistent complete inventory until the
      // locally-authored repair is pushed. Re-adoption must remain terminal and
      // leave exactly one active successor Delete, never a permanent retry loop.
      let rerun = try startSnapshot(db)
      try stage(db, session: rerun, records: records)
      _ = try finalize(db, session: rerun, hlc: hlc)
      try assertSyntheticDelete(
        db, kind: .taskCalendarEventLink, id: linkID,
        dominates: [Self.childVersion, Self.parentDeleteVersion])
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EdgeName.taskCalendarEventLink, linkID]),
        1)
      XCTAssertNil(try AuthoritativeSnapshot.activeSession(db))
    }
  }

  func testAbsentCalendarParentNormalizesStaleLink() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let session = try startSnapshot(db)
      try stage(
        db, session: session,
        records: try [staged(inboxEnvelope()), staged(taskEnvelope()), staged(linkEnvelope())])
      _ = try finalize(db, session: session, hlc: hlcSession())

      try assertSyntheticDelete(
        db, kind: .taskCalendarEventLink,
        id: "\(Self.taskID):\(Self.eventID)",
        dominates: [Self.childVersion])
    }
  }

  func testGenericHardChildNormalizationCoversTaskReminder() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let session = try startSnapshot(db)
      try stage(
        db, session: session,
        records: try [staged(inboxEnvelope()), staged(reminderEnvelope())])
      _ = try finalize(db, session: session, hlc: hlcSession())

      XCTAssertNil(
        try Row.fetchOne(
          db, sql: "SELECT 1 FROM task_reminders WHERE id = ?",
          arguments: [Self.reminderID]))
      try assertSyntheticDelete(
        db, kind: .taskReminder, id: Self.reminderID,
        dominates: [Self.childVersion])
    }
  }

  func testRemoteLiveParentsApplyCalendarLinkNormally() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let session = try startSnapshot(db)
      try stage(
        db, session: session,
        records: try [
          staged(inboxEnvelope()), staged(taskEnvelope()),
          staged(calendarEnvelope()), staged(linkEnvelope()),
        ])
      _ = try finalize(db, session: session, hlc: hlcSession())

      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM task_calendar_event_links
            WHERE task_id = ? AND calendar_event_id = ?
            """,
          arguments: [Self.taskID, Self.eventID]),
        1)
      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EdgeName.taskCalendarEventLink,
          entityId: "\(Self.taskID):\(Self.eventID)"))
    }
  }

  func testPostSessionParentUpsertProtectsAndMaterializesRemoteChild() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let session = try startSnapshot(db)

      let localParent = try calendarEnvelope(
        version: Self.postSessionVersion, deviceID: Self.deviceID)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: localParent),
        .applied)
      // This fixture bypasses the production service enqueue funnel. Model the
      // complete local parent creation explicitly so authoritative replay knows
      // both calendar registers are user-authored, rather than mistaking this
      // row for a zero-intent convergence re-emit.
      XCTAssertNotNil(
        try Outbox.enqueueCoalesced(
          db, localParent, registerIntent: .calendar(.all)))

      try stage(
        db, session: session,
        records: try [
          staged(inboxEnvelope()), staged(taskEnvelope()),
          staged(calendarDelete()), staged(linkEnvelope()),
        ])
      _ = try finalize(db, session: session, hlc: hlcSession())

      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM task_calendar_event_links
            WHERE task_id = ? AND calendar_event_id = ?
            """,
          arguments: [Self.taskID, Self.eventID]),
        1)
      let parentVersion = try XCTUnwrap(
        try String.fetchOne(
          db, sql: "SELECT version FROM calendar_events WHERE id = ?",
          arguments: [Self.eventID]))
      XCTAssertGreaterThan(
        try Hlc.parseCanonical(parentVersion),
        try Hlc.parseCanonical(Self.parentDeleteVersion))
      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EdgeName.taskCalendarEventLink,
          entityId: "\(Self.taskID):\(Self.eventID)"))
    }
  }

  func testFutureParentInventoryFailsClosedWithoutSyntheticDelete() throws {
    let store = try SyncTestSupport.freshStore()
    let futureParent = RawEnvelopeFields(
      entityType: EntityName.calendarEvent, entityId: Self.eventID,
      operation: "FutureCalendarOperation", version: Self.parentDeleteVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
      payload: #"{"future_calendar_shape":true}"#, deviceId: "future-device")

    try store.writer.write { db in
      let session = try startSnapshot(db)
      try stage(
        db, session: session,
        records: try [
          staged(inboxEnvelope()), staged(taskEnvelope()), staged(linkEnvelope()),
          AuthoritativeSnapshotRemoteRecord(
            recordName: SyncRecordName.opaque(
              entityType: EntityName.calendarEvent, entityId: Self.eventID),
            state: .unknown, envelope: nil, rawEnvelope: futureParent),
        ])
    }

    XCTAssertThrowsError(
      try store.writer.write { db in
        let session = try XCTUnwrap(try AuthoritativeSnapshot.activeSession(db))
        _ = try finalize(db, session: session, hlc: hlcSession())
      })
    try store.writer.read { db in
      XCTAssertNotNil(try AuthoritativeSnapshot.activeSession(db))
      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EdgeName.taskCalendarEventLink,
          entityId: "\(Self.taskID):\(Self.eventID)"))
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testFutureListInventoryDoesNotRehomeTaskAsIfListWereAbsent() throws {
    let store = try SyncTestSupport.freshStore()
    let futureList = RawEnvelopeFields(
      entityType: EntityName.list, entityId: Self.futureListID,
      operation: "FutureListOperation", version: Self.parentDeleteVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
      payload: #"{"future_list_shape":true}"#, deviceId: "future-device")

    try store.writer.write { db in
      let session = try startSnapshot(db)
      try stage(
        db, session: session,
        records: try [
          staged(inboxEnvelope()),
          staged(taskEnvelope(listID: Self.futureListID)),
          AuthoritativeSnapshotRemoteRecord(
            recordName: SyncRecordName.opaque(
              entityType: EntityName.list, entityId: Self.futureListID),
            state: .unknown, envelope: nil, rawEnvelope: futureList),
        ])
    }

    XCTAssertThrowsError(
      try store.writer.write { db in
        let session = try XCTUnwrap(try AuthoritativeSnapshot.activeSession(db))
        _ = try finalize(db, session: session, hlc: hlcSession())
      })
    try store.writer.read { db in
      XCTAssertNil(
        try Row.fetchOne(
          db, sql: "SELECT 1 FROM tasks WHERE id = ?", arguments: [Self.taskID]))
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
      XCTAssertNotNil(try AuthoritativeSnapshot.activeSession(db))
    }
  }

  func testInvalidEdgeIdentityFailsClosedWithoutOrphanRepair() throws {
    let store = try SyncTestSupport.freshStore()
    var invalid = try linkEnvelope()
    guard case .object(var payload)? = JSONValue.parse(invalid.payload) else {
      return XCTFail("link fixture must be an object")
    }
    payload["calendar_event_id"] = .string(Self.otherEventID)
    invalid.payload = try SyncCanonicalize.canonicalizeJSON(.object(payload))

    try store.writer.write { db in
      let session = try startSnapshot(db)
      try stage(
        db, session: session,
        records: try [staged(inboxEnvelope()), staged(taskEnvelope()), staged(invalid)])
    }
    XCTAssertThrowsError(
      try store.writer.write { db in
        let session = try XCTUnwrap(try AuthoritativeSnapshot.activeSession(db))
        _ = try finalize(db, session: session, hlc: hlcSession())
      }) { error in
        guard case .invalidPayload = error as? ApplyError else {
          return XCTFail("expected typed invalid payload, got \(error)")
        }
      }
    try store.writer.read { db in
      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EdgeName.taskCalendarEventLink,
          entityId: "\(Self.taskID):\(Self.eventID)"))
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testDependencyCycleFailsClosedWithoutSyntheticDelete() throws {
    let store = try SyncTestSupport.freshStore()
    let left = try envelope(
      kind: .taskDependency,
      id: "\(Self.taskID):\(Self.secondTaskID)",
      fields: [
        "task_id": .string(Self.taskID),
        "depends_on_task_id": .string(Self.secondTaskID),
        "created_at": .string(Self.timestamp),
      ])
    let right = try envelope(
      kind: .taskDependency,
      id: "\(Self.secondTaskID):\(Self.taskID)",
      fields: [
        "task_id": .string(Self.secondTaskID),
        "depends_on_task_id": .string(Self.taskID),
        "created_at": .string(Self.timestamp),
      ])

    try store.writer.write { db in
      let session = try startSnapshot(db)
      try stage(
        db, session: session,
        records: try [
          staged(inboxEnvelope()), staged(taskEnvelope()),
          staged(taskEnvelope(id: Self.secondTaskID)), staged(left), staged(right),
        ])
    }
    XCTAssertThrowsError(
      try store.writer.write { db in
        let session = try XCTUnwrap(try AuthoritativeSnapshot.activeSession(db))
        _ = try finalize(db, session: session, hlc: hlcSession())
      })
    try store.writer.read { db in
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_tombstones"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
      XCTAssertNotNil(try AuthoritativeSnapshot.activeSession(db))
    }
  }
}
