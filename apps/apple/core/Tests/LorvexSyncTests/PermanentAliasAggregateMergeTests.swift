import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// A permanent alias is an already-authored identity union, not a fresh
/// natural-key collision. These composition tests apply the same source content
/// before versus after the alias and require the canonical current-state payload
/// to be byte-identical.
final class PermanentAliasAggregateMergeTests: XCTestCase {
  private let targetId = "00000000-0000-7000-8000-000000000001"
  private let sourceId = "ffffffff-ffff-7fff-8fff-ffffffffffff"
  private let parentA = "11111111-1111-7111-8111-111111111111"
  private let parentB = "22222222-2222-7222-8222-222222222222"
  private let targetVersion = "1800000000100_0000_1111222233334444"
  private let aliasVersion = "1800000000200_0000_2222333344445555"
  private let sourceVersion = "1800000000300_0000_5555666677778888"
  private let targetCreatedAt = "2026-07-01T00:00:00.000Z"
  private let sourceCreatedAt = "2026-07-02T00:00:00.000Z"
  private let sourceUpdatedAt = "2026-07-03T00:00:00.000Z"
  private let registry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())

  private func aliasEnvelope(_ kind: EntityKind) throws -> SyncEnvelope {
    try EntityRedirect.makeEnvelope(
      record: EntityRedirect.Record(
        sourceType: kind, sourceId: sourceId, targetId: targetId,
        version: aliasVersion, createdAt: targetCreatedAt),
      deviceId: "remote-device")
  }

  private func canonicalSnapshot(
    _ db: Database, entityType: String, entityId: String
  ) throws -> String {
    try SyncCanonicalize.canonicalizeJSON(
      try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: entityType, entityId: entityId))
  }

  private func insertHabit(
    _ db: Database, id: String, name: String, lookupKey: String,
    position: Int64, version: String, createdAt: String, updatedAt: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO habits
          (id, name, frequency_type, target_count, archived, lookup_key, position,
           version, created_at, updated_at)
        VALUES (?, ?, 'daily', 1, 0, ?, ?, ?, ?, ?)
        """,
      arguments: [id, name, lookupKey, position, version, createdAt, updatedAt])
  }

  private func habitEnvelope() throws -> SyncEnvelope {
    let supplied = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "name": .string("Renamed Source"), "frequency_type": .string("daily"),
        "target_count": .int(1), "archived": .bool(false), "position": .int(9),
        "icon": .null, "color": .null, "cue": .null, "milestone_target": .null,
        "created_at": .string(sourceCreatedAt), "updated_at": .string(sourceUpdatedAt),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .habit, entityId: sourceId, operation: .upsert,
      version: try Hlc.parse(sourceVersion),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: supplied, deviceId: "remote-device")
  }

  func testHabitAliasFirstAndAliasLateConvergeOnFullPayloadAndDerivedKey() throws {
    let run:
      (Bool) throws -> (
        payload: String, lookupKey: String, redirectVersion: String, tombstoneVersion: String
      ) = { aliasFirst in
        let store = try SyncTestSupport.freshStore()
        var result: (String, String, String, String)?
        try store.writer.write { db in
          try self.insertHabit(
            db, id: self.targetId, name: "Original Target", lookupKey: "original target",
            position: 1, version: self.targetVersion, createdAt: self.targetCreatedAt,
            updatedAt: self.targetCreatedAt)
          if !aliasFirst {
            try self.insertHabit(
              db, id: self.sourceId, name: "Renamed Source", lookupKey: "stale-source-key",
              position: 9, version: self.sourceVersion, createdAt: self.sourceCreatedAt,
              updatedAt: self.sourceUpdatedAt)
          }
          _ = try Apply.applyEnvelope(
            db, registry: self.registry, envelope: try self.aliasEnvelope(.habit))
          if aliasFirst {
            _ = try Apply.applyEnvelope(
              db, registry: self.registry, envelope: try self.habitEnvelope())
          }
          result = (
            try self.canonicalSnapshot(
              db, entityType: EntityName.habit, entityId: self.targetId),
            try XCTUnwrap(
              String.fetchOne(
                db, sql: "SELECT lookup_key FROM habits WHERE id = ?",
                arguments: [self.targetId])),
            try XCTUnwrap(
              EntityRedirect.get(
                db, sourceType: EntityName.habit, sourceId: self.sourceId)?.version),
            try XCTUnwrap(
              Tombstone.getTombstone(
                db, entityType: EntityName.habit, entityId: self.sourceId)?.version)
          )
        }
        return try XCTUnwrap(result)
      }

    let aliasFirst = try run(true)
    let aliasLate = try run(false)
    XCTAssertEqual(aliasFirst.payload, aliasLate.payload)
    XCTAssertEqual(aliasLate.lookupKey, normalizeLookupKey("Renamed Source"))
    XCTAssertEqual(aliasFirst.lookupKey, aliasLate.lookupKey)
    XCTAssertEqual(aliasFirst.redirectVersion, aliasLate.redirectVersion)
    XCTAssertEqual(aliasFirst.tombstoneVersion, aliasLate.tombstoneVersion)
    XCTAssertEqual(aliasLate.redirectVersion, aliasVersion)
    guard case .object(let payload)? = JSONValue.parse(aliasLate.payload) else {
      return XCTFail("habit payload must be an object")
    }
    XCTAssertEqual(payload["version"], .string(sourceVersion))
    XCTAssertEqual(payload["created_at"], .string(targetCreatedAt))
    XCTAssertEqual(payload["position"], .int(9))
  }

  private func insertParentHabits(_ db: Database) throws {
    try insertHabit(
      db, id: parentA, name: "A", lookupKey: "a", position: 0,
      version: targetVersion, createdAt: targetCreatedAt, updatedAt: targetCreatedAt)
    try insertHabit(
      db, id: parentB, name: "B", lookupKey: "b", position: 0,
      version: targetVersion, createdAt: targetCreatedAt, updatedAt: targetCreatedAt)
  }

  private func insertPolicy(
    _ db: Database, id: String, habitId: String, time: String, enabled: Int64,
    version: String, createdAt: String, updatedAt: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO habit_reminder_policies
          (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [id, habitId, time, enabled, version, createdAt, updatedAt])
  }

  private func policyEnvelope() throws -> SyncEnvelope {
    let supplied = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "id": .string(sourceId), "habit_id": .string(parentB),
        "reminder_time": .string("18:30"), "enabled": .bool(false),
        "created_at": .string(sourceCreatedAt), "updated_at": .string(sourceUpdatedAt),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .habitReminderPolicy, entityId: sourceId, operation: .upsert,
      version: try Hlc.parse(sourceVersion),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: supplied, deviceId: "remote-device")
  }

  func testPolicyAliasFirstAndAliasLateConvergeAcrossParentAndTimeChange() throws {
    let run: (Bool) throws -> String = { aliasFirst in
      let store = try SyncTestSupport.freshStore()
      var result = ""
      try store.writer.write { db in
        try self.insertParentHabits(db)
        try self.insertPolicy(
          db, id: self.targetId, habitId: self.parentA, time: "08:00", enabled: 1,
          version: self.targetVersion, createdAt: self.targetCreatedAt,
          updatedAt: self.targetCreatedAt)
        if !aliasFirst {
          try self.insertPolicy(
            db, id: self.sourceId, habitId: self.parentB, time: "18:30", enabled: 0,
            version: self.sourceVersion, createdAt: self.sourceCreatedAt,
            updatedAt: self.sourceUpdatedAt)
        }
        _ = try Apply.applyEnvelope(
          db, registry: self.registry,
          envelope: try self.aliasEnvelope(.habitReminderPolicy))
        if aliasFirst {
          _ = try Apply.applyEnvelope(
            db, registry: self.registry, envelope: try self.policyEnvelope())
        }
        result = try self.canonicalSnapshot(
          db, entityType: EntityName.habitReminderPolicy, entityId: self.targetId)
      }
      return result
    }

    let aliasFirst = try run(true)
    let aliasLate = try run(false)
    XCTAssertEqual(aliasFirst, aliasLate)
    guard case .object(let payload)? = JSONValue.parse(aliasLate) else {
      return XCTFail("habit reminder policy payload must be an object")
    }
    XCTAssertEqual(payload["habit_id"], .string(parentB))
    XCTAssertEqual(payload["reminder_time"], .string("18:30"))
    XCTAssertEqual(payload["version"], .string(sourceVersion))
    XCTAssertEqual(payload["created_at"], .string(targetCreatedAt))
  }

  func testTagAliasLateRederivesLookupKeyFromCarriedDisplayName() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES (?, 'Target', 'target', ?, ?, ?),
                 (?, 'Renamed Source', 'stale-source-key', ?, ?, ?)
          """,
        arguments: [
          self.targetId, self.targetVersion, self.targetCreatedAt, self.targetCreatedAt,
          self.sourceId, self.sourceVersion, self.sourceCreatedAt, self.sourceUpdatedAt,
        ])
      _ = try Apply.applyEnvelope(
        db, registry: self.registry, envelope: try self.aliasEnvelope(.tag))
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT lookup_key FROM tags WHERE id = ?", arguments: [self.targetId]),
        normalizeLookupKey("Renamed Source"))
    }
  }

  func testMemoryAliasFirstAndAliasLateConvergeAcrossKeyRename() throws {
    let sourcePayload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "id": .string(sourceId), "key": .string("renamed-memory"),
        "content": .string("new content"), "updated_at": .string(sourceUpdatedAt),
      ]))
    let sourceEnvelope = try SyncTestSupport.completeEnvelope(
      entityType: .memory, entityId: sourceId, operation: .upsert,
      version: try Hlc.parse(sourceVersion),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: sourcePayload, deviceId: "remote-device")
    let run: (Bool) throws -> String = { aliasFirst in
      let store = try SyncTestSupport.freshStore()
      var result = ""
      try store.writer.write { db in
        try db.execute(
          sql: """
            INSERT INTO memories (id, key, content, version, updated_at)
            VALUES (?, 'target-memory', 'old content', ?, ?)
            """,
          arguments: [self.targetId, self.targetVersion, self.targetCreatedAt])
        if !aliasFirst {
          try db.execute(
            sql: """
              INSERT INTO memories (id, key, content, version, updated_at)
              VALUES (?, 'renamed-memory', 'new content', ?, ?)
              """,
            arguments: [self.sourceId, self.sourceVersion, self.sourceUpdatedAt])
        }
        _ = try Apply.applyEnvelope(
          db, registry: self.registry, envelope: try self.aliasEnvelope(.memory))
        if aliasFirst {
          _ = try Apply.applyEnvelope(
            db, registry: self.registry, envelope: sourceEnvelope)
        }
        result = try self.canonicalSnapshot(
          db, entityType: EntityName.memory, entityId: self.targetId)
      }
      return result
    }

    let aliasFirst = try run(true)
    let aliasLate = try run(false)
    XCTAssertEqual(aliasFirst, aliasLate)
    guard case .object(let payload)? = JSONValue.parse(aliasLate) else {
      return XCTFail("memory payload must be an object")
    }
    XCTAssertEqual(payload["key"], .string("renamed-memory"))
    XCTAssertEqual(payload["content"], .string("new content"))
    XCTAssertEqual(payload["version"], .string(sourceVersion))
  }
}
