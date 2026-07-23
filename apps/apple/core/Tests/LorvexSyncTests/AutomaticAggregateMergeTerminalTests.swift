import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Terminal convergence checks for automatic aggregate merges. These focus on
/// state that is easy to make locally correct while emitting different bytes on
/// different peers: carried display order, re-pointed edge provenance, authored
/// timestamps, and the parent FK captured in an outbox snapshot.
final class AutomaticAggregateMergeTerminalTests: XCTestCase {
  private let winnerId = "00000000-0000-7000-8000-000000000001"
  private let loserId = "ffffffff-ffff-7fff-8fff-ffffffffffff"
  private let taskId = "11111111-1111-7111-8111-111111111111"
  private let earlier = "1800000000100_0000_1111222233334444"
  private let later = "1800000000200_0000_5555666677778888"
  private let rootEarlier = "1800000000300_0000_1111222233334444"
  private let rootLater = "1800000000400_0000_5555666677778888"
  private let ts1 = "2026-07-18T01:00:00.000Z"
  private let ts2 = "2026-07-18T02:00:00.000Z"

  private func insertHabit(
    _ db: Database, id: String, name: String, lookupKey: String, position: Int64,
    version: String, archived: Int64 = 0
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO habits
          (id, name, frequency_type, target_count, archived, lookup_key, position,
           version, created_at, updated_at)
        VALUES (?, ?, 'daily', 1, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [id, name, archived, lookupKey, position, version, ts1, ts1])
  }

  private func insertTag(_ db: Database, id: String, version: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
        VALUES (?, 'Shared', 'shared', ?, ?, ?)
        """,
      arguments: [id, version, ts1, ts1])
  }

  private func insertTask(_ db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, version, created_at, updated_at)
        VALUES (?, 'Task', 'open', ?, ?, ?)
        """,
      arguments: [taskId, earlier, ts1, ts1])
  }

  private func canonical(_ payload: JSONValue?) throws -> String {
    try SyncCanonicalize.canonicalizeJSON(try XCTUnwrap(payload))
  }

  func testHabitMergeCarriesPositionIntoWinnerAndOutbox() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertHabit(
        db, id: self.winnerId, name: "Shared", lookupKey: "shared", position: 1,
        version: self.rootEarlier)
      // Staged outside the active lookup-key index, matching the production
      // insert-collision path immediately before the aggregate merge.
      try self.insertHabit(
        db, id: self.loserId, name: "Shared", lookupKey: "shared", position: 9,
        version: self.rootLater, archived: 1)

      XCTAssertEqual(
        try ApplyHabitMerge.mergeKnownDuplicateHabits(
          db, rows: [(self.winnerId, self.rootEarlier), (self.loserId, self.rootLater)],
          triggeringVersion: self.rootLater, applyTs: self.ts2),
        self.winnerId)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT position FROM habits WHERE id = ?", arguments: [self.winnerId]),
        9)

      let queued = try XCTUnwrap(
        try String.fetchOne(
          db,
          sql: """
            SELECT payload FROM sync_outbox
             WHERE entity_type = ? AND entity_id = ? AND operation = 'upsert'
                   AND synced_at IS NULL
            """,
          arguments: [EntityName.habit, self.winnerId]))
      guard case .object(let object)? = JSONValue.parse(queued) else {
        return XCTFail("habit winner outbox payload must be an object")
      }
      XCTAssertEqual(object["position"], .int(9))
    }
  }

  func testTagEdgeRepointConvergesWithLateLoserEdgeAndDifferentApplyTimes() throws {
    let run: (_ bothEdgesPresentAtMerge: Bool, _ applyTs: String) throws -> String = {
      bothEdgesPresentAtMerge, applyTs in
      let store = try SyncTestSupport.freshStore()
      var result = ""
      try store.writer.write { db in
        try self.insertTask(db)
        try self.insertTag(db, id: self.winnerId, version: self.rootEarlier)
        try self.insertTag(db, id: self.loserId, version: self.rootLater)
        try db.execute(
          sql: "INSERT INTO task_tags (task_id, tag_id, version, created_at) VALUES (?, ?, ?, ?)",
          arguments: [self.taskId, self.winnerId, self.earlier, self.ts1])
        if bothEdgesPresentAtMerge {
          try db.execute(
            sql: "INSERT INTO task_tags (task_id, tag_id, version, created_at) VALUES (?, ?, ?, ?)",
            arguments: [self.taskId, self.loserId, self.later, self.ts2])
        }

        _ = try ApplyTagMerge.merger.mergeKnownDuplicate(
          db, rows: [(self.winnerId, self.rootEarlier), (self.loserId, self.rootLater)],
          triggeringVersion: self.rootLater, applyTs: applyTs)

        if !bothEdgesPresentAtMerge {
          let edgePayload = try SyncCanonicalize.canonicalizeJSON(
            .object([
              "task_id": .string(self.taskId), "tag_id": .string(self.loserId),
              "created_at": .string(self.ts2),
            ]))
          let envelope = try SyncTestSupport.completeEnvelope(
            entityType: .taskTag, entityId: "\(self.taskId):\(self.loserId)",
            operation: .upsert, version: try Hlc.parse(self.later),
            payloadSchemaVersion: LorvexVersion.payloadSchemaVersion, payload: edgePayload,
            deviceId: "remote-device")
          _ = try Apply.applyEnvelope(
            db,
            registry: EntityApplierRegistry(
              appliers: EntityApplierRegistry.defaultEntityAppliers()),
            envelope: envelope)
        }
        result = try self.canonical(
          PayloadLoaders.loadTaskTagSyncPayload(
            db, taskId: self.taskId, tagId: self.winnerId))
      }
      return result
    }

    let edgePresent = try run(true, ts1)
    let edgeLate = try run(false, ts2)
    XCTAssertEqual(edgePresent, edgeLate)
    guard case .object(let payload)? = JSONValue.parse(edgePresent) else {
      return XCTFail("task-tag payload must be an object")
    }
    XCTAssertEqual(payload["version"], .string(later))
    XCTAssertEqual(payload["created_at"], .string(ts2))
  }

  func testCompletionNoCollisionPreservesAuthoredTimestampsAcrossApplyTimes() throws {
    let run: (String) throws -> String = { applyTs in
      let store = try SyncTestSupport.freshStore()
      var result = ""
      try store.writer.write { db in
        try self.insertHabit(
          db, id: self.winnerId, name: "Winner", lookupKey: "winner", position: 0,
          version: self.rootEarlier)
        try self.insertHabit(
          db, id: self.loserId, name: "Loser", lookupKey: "loser", position: 0,
          version: self.rootLater)
        try db.execute(
          sql: """
            INSERT INTO habit_completions
              (habit_id, completed_date, value, note, version, created_at, updated_at)
            VALUES (?, '2026-07-17', 2, 'authored', ?, ?, ?)
            """,
          arguments: [self.loserId, self.later, self.ts1, self.ts2])
        try ApplyHabitCompletionMerge.mergeHabitCompletions(
          db, winnerId: self.winnerId, loserId: self.loserId,
          mergeVersion: self.rootLater, applyTs: applyTs)
        result = try self.canonical(
          PayloadLoaders.loadHabitCompletionSyncPayload(
            db, habitId: self.winnerId, completedDate: "2026-07-17"))
      }
      return result
    }

    let first = try run(ts1)
    let second = try run("2026-07-18T09:00:00.000Z")
    XCTAssertEqual(first, second)
    guard case .object(let payload)? = JSONValue.parse(first) else {
      return XCTFail("habit-completion payload must be an object")
    }
    XCTAssertEqual(payload["created_at"], .string(ts1))
    XCTAssertEqual(payload["updated_at"], .string(ts2))
  }

  func testCompletionCollisionCarriesAllTimestampsFromMaxHlcContentWinner() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertHabit(
        db, id: self.winnerId, name: "Winner", lookupKey: "winner", position: 0,
        version: self.rootEarlier)
      try self.insertHabit(
        db, id: self.loserId, name: "Loser", lookupKey: "loser", position: 0,
        version: self.rootLater)
      try db.execute(
        sql: """
          INSERT INTO habit_completions
            (habit_id, completed_date, value, note, version, created_at, updated_at)
          VALUES (?, '2026-07-17', 1, 'older', ?, '2026-07-01T00:00:00.000Z',
                  '2026-07-02T00:00:00.000Z'),
                 (?, '2026-07-17', 3, 'newer', ?, '2026-07-03T00:00:00.000Z',
                  '2026-07-04T00:00:00.000Z')
          """,
        arguments: [self.winnerId, self.earlier, self.loserId, self.later])

      try ApplyHabitCompletionMerge.mergeHabitCompletions(
        db, winnerId: self.winnerId, loserId: self.loserId,
        mergeVersion: self.rootLater, applyTs: self.ts2)
      let payload = try XCTUnwrap(
        try PayloadLoaders.loadHabitCompletionSyncPayload(
          db, habitId: self.winnerId, completedDate: "2026-07-17"))
      guard case .object(let object) = payload else {
        return XCTFail("habit-completion payload must be an object")
      }
      XCTAssertEqual(object["value"], .int(3))
      XCTAssertEqual(object["created_at"], .string("2026-07-03T00:00:00.000Z"))
      XCTAssertEqual(object["updated_at"], .string("2026-07-04T00:00:00.000Z"))
    }
  }

  func testNestedPolicyMergeEnqueuesWinnerAfterParentRepoint() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertHabit(
        db, id: self.winnerId, name: "Winner", lookupKey: "winner", position: 0,
        version: self.rootEarlier)
      try self.insertHabit(
        db, id: self.loserId, name: "Loser", lookupKey: "loser", position: 0,
        version: self.rootLater)
      let survivingPolicy = "00000000-0000-7000-8000-000000000010"
      let deletedPolicy = "ffffffff-ffff-7fff-8fff-fffffffffff0"
      try db.execute(
        sql: """
          INSERT INTO habit_reminder_policies
            (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
          VALUES (?, ?, '09:00', 0, ?, ?, ?), (?, ?, '09:00', 1, ?, ?, ?)
          """,
        arguments: [
          survivingPolicy, self.loserId, self.later, self.ts1, self.ts2,
          deletedPolicy, self.winnerId, self.earlier, self.ts1, self.ts1,
        ])

      XCTAssertEqual(
        try ApplyHabitReminderPolicyMerge.mergePoliciesDuringHabitMerge(
          db, firstPolicyId: survivingPolicy, secondPolicyId: deletedPolicy,
          winnerHabitId: self.winnerId, applyTs: self.ts2),
        survivingPolicy)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT habit_id FROM habit_reminder_policies WHERE id = ?",
          arguments: [survivingPolicy]),
        self.winnerId)

      let queued = try XCTUnwrap(
        try String.fetchOne(
          db,
          sql: """
            SELECT payload FROM sync_outbox
             WHERE entity_type = ? AND entity_id = ? AND operation = 'upsert'
                   AND synced_at IS NULL
            """,
          arguments: [EntityName.habitReminderPolicy, survivingPolicy]))
      guard case .object(let object)? = JSONValue.parse(queued) else {
        return XCTFail("policy winner outbox payload must be an object")
      }
      XCTAssertEqual(object["habit_id"], .string(winnerId))
    }
  }
}
