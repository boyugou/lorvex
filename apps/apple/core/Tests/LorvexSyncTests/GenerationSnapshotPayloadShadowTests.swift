import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class GenerationSnapshotPayloadShadowTests: XCTestCase {
  private let entityID = "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa"
  private let older = "1711234567000_0001_a1b2c3d4a1b2c3d4"
  private let newer = "1711234567001_0001_a1b2c3d4a1b2c3d4"

  private func payload() -> JSONValue {
    .object([
      "id": .string(entityID),
      "title": .string("Live task"),
      "status": .string("open"),
      "list_id": .string("inbox"),
    ])
  }

  private func seedShadow(_ db: Database, version: String) throws {
    try PayloadShadow.restoreShadow(
      db,
      row: PayloadShadow.Row(
        entityType: .task, entityID: entityID, baseVersion: version,
        payloadSchemaVersion: 2,
        rawPayloadJSON: #"{"future_field":"preserved"}"#,
        sourceDeviceID: "device-remote", updatedAt: "2026-01-01T00:00:00Z"))
  }

  func testShadowBehindLiveFailsClosedAndIsRetained() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedShadow(db, version: older)

      XCTAssertThrowsError(
        try GenerationSnapshot.makeLiveEnvelope(
          db, kind: .task, entityId: entityID, version: newer,
          payload: payload(), deviceId: "device-local")
      ) { error in
        XCTAssertEqual(
          error as? GenerationSnapshotError,
          .payloadShadowVersionMismatch(
            entityType: EntityName.task, entityId: self.entityID,
            liveVersion: self.newer, shadowVersion: self.older))
      }
      XCTAssertNotNil(
        try PayloadShadow.getShadow(db, entityType: EntityName.task, entityID: entityID))
    }
  }

  func testShadowAheadOfLiveFailsClosedAndIsRetained() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedShadow(db, version: newer)

      XCTAssertThrowsError(
        try GenerationSnapshot.makeLiveEnvelope(
          db, kind: .task, entityId: entityID, version: older,
          payload: payload(), deviceId: "device-local")
      ) { error in
        XCTAssertEqual(
          error as? GenerationSnapshotError,
          .payloadShadowVersionMismatch(
            entityType: EntityName.task, entityId: self.entityID,
            liveVersion: self.older, shadowVersion: self.newer))
      }
      XCTAssertNotNil(
        try PayloadShadow.getShadow(db, entityType: EntityName.task, entityID: entityID))
    }
  }

  func testEqualVersionShadowIsPublishedAtFutureSchema() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedShadow(db, version: newer)

      let envelope = try GenerationSnapshot.makeLiveEnvelope(
        db, kind: .task, entityId: entityID, version: newer,
        payload: payload(), deviceId: "device-local")

      guard case .object(let published)? = JSONValue.parse(envelope.payload) else {
        return XCTFail("generation payload must be an object")
      }
      XCTAssertEqual(published["future_field"], .string("preserved"))
      XCTAssertEqual(envelope.payloadSchemaVersion, 2)
    }
  }

  func testInvalidStoredSchemaVersionFailsClosedWithoutClamping() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(sql: "PRAGMA ignore_check_constraints = ON")
      try db.execute(
        sql: """
          INSERT INTO sync_payload_shadow
            (entity_type, entity_id, base_version, payload_schema_version,
             raw_payload_json, source_device_id, updated_at)
          VALUES ('task', ?, ?, 0, '{"future_field":"preserved"}',
                  'device-remote', '2026-01-01T00:00:00.000Z')
          """,
        arguments: [entityID, newer])
      try db.execute(sql: "PRAGMA ignore_check_constraints = OFF")

      XCTAssertThrowsError(
        try GenerationSnapshot.makeLiveEnvelope(
          db, kind: .task, entityId: entityID, version: newer,
          payload: payload(), deviceId: "device-local")
      ) { error in
        XCTAssertEqual(
          error as? GenerationSnapshotError,
          .invalidPayloadShadowSchemaVersion(
            entityType: EntityName.task, entityId: self.entityID, storedVersion: 0))
      }
      XCTAssertNotNil(
        try PayloadShadow.getShadow(db, entityType: EntityName.task, entityID: entityID))
    }
  }
}
