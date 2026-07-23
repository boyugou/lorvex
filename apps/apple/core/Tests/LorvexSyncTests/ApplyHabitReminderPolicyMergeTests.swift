import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// W-1 sync-wedge regression: two devices that add a reminder for the SAME habit at
/// the SAME time offline each mint a distinct policy id but share one
/// `(habit_id, reminder_time)` pair. On inbound sync the second policy trips
/// `UNIQUE(habit_id, reminder_time)`, which historically escaped ``ApplyChild`` as
/// ``ApplyError/db`` — a batch-fatal error that aborts the whole inbound page and
/// wedges sync forever.
///
/// The fix mirrors ``ApplyTagMerge``: the collision
/// CONVERGES instead of wedging. `min(id)` wins, the loser is tombstoned with a
/// redirect, and the constraint never surfaces as ``ApplyError/db``.
final class ApplyHabitReminderPolicyMergeTests: XCTestCase {

  private let habitId = "00000000-0000-7000-8000-0000000000f0"
  private let smallerId = "00000000-0000-7000-8000-000000000001"
  private let largerId = "ffffffff-ffff-7fff-8fff-ffffffffffff"
  private let vEarlier = "1711234567000_0000_dec0000100000001"
  private let vLater = "1711234568000_0000_dec0000200000002"
  private let ts = "2026-04-01T00:00:00.000Z"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO habits (id, name, frequency_type, target_count, archived,
                              lookup_key, version, created_at, updated_at)
          VALUES (?, 'Read', 'daily', 1, 0, 'read', ?, ?, ?)
          """,
        arguments: [self.habitId, self.vEarlier, self.ts, self.ts])
      try body(db)
    }
  }

  private func policyPayload(reminderTime: String, enabled: Bool = true) throws -> String {
    try SyncCanonicalize.canonicalizeJSON(
      .object([
        "habit_id": .string(habitId), "reminder_time": .string(reminderTime),
        "enabled": .bool(enabled), "created_at": .string(ts), "updated_at": .string(ts),
      ]))
  }

  private func applyPolicy(
    _ db: Database, id: String, version: String, reminderTime: String = "09:00",
    enabled: Bool = true
  ) throws {
    try ApplyChild.applyHabitReminderPolicyUpsert(
      db, entityId: id, payload: try policyPayload(reminderTime: reminderTime, enabled: enabled),
      version: version, tieBreak: .rejectEqual, applyTs: ts)
  }

  private func alivePolicyIds(_ db: Database, reminderTime: String = "09:00") throws -> [String] {
    try String.fetchAll(
      db,
      sql: "SELECT id FROM habit_reminder_policies WHERE habit_id = ? AND reminder_time = ? ORDER BY id",
      arguments: [habitId, reminderTime])
  }

  private func tombstone(_ db: Database, _ id: String) throws -> Tombstone.Record? {
    try Tombstone.getTombstone(db, entityType: EntityName.habitReminderPolicy, entityId: id)
  }

  private func redirect(_ db: Database, _ id: String) throws -> EntityRedirect.Record? {
    try EntityRedirect.get(db, sourceType: EntityName.habitReminderPolicy, sourceId: id)
  }

  /// The incoming policy owns the SMALLER id, so it wins.
  func testIncomingSmallerIdWinsAndExistingIsTombstonedWithRedirect() throws {
    try withDB { db in
      try self.applyPolicy(db, id: self.largerId, version: self.vEarlier)
      do {
        try self.applyPolicy(db, id: self.smallerId, version: self.vLater)
      } catch {
        return XCTFail(
          "colliding policy must converge, not throw (got \(error)); the pre-fix bug surfaced "
            + "ApplyError.db and wedged the inbound batch")
      }

      XCTAssertEqual(try self.alivePolicyIds(db), [self.smallerId])
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT reminder_time FROM habit_reminder_policies WHERE id = ?",
          arguments: [self.smallerId]),
        "09:00", "winner keeps its real reminder_time after staging")

      XCTAssertNotNil(try self.tombstone(db, self.largerId))
      XCTAssertEqual(try self.redirect(db, self.largerId)?.targetId, self.smallerId)
      XCTAssertNil(try self.redirect(db, self.smallerId))
    }
  }

  /// The incoming policy owns the LARGER id but the LATER HLC, so it loses
  /// IDENTITY (min id wins) yet wins CONTENT: its `enabled` is carried onto the
  /// surviving smaller-id policy.
  func testIncomingLargerIdLosesIdentityButWinsEnabledContent() throws {
    try withDB { db in
      try self.applyPolicy(db, id: self.smallerId, version: self.vEarlier, enabled: true)
      do {
        try self.applyPolicy(db, id: self.largerId, version: self.vLater, enabled: false)
      } catch {
        return XCTFail("colliding policy must converge, not throw (got \(error))")
      }

      XCTAssertEqual(try self.alivePolicyIds(db), [self.smallerId])
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT enabled FROM habit_reminder_policies WHERE id = ?",
          arguments: [self.smallerId]),
        0, "the max-HLC `enabled` is carried onto the min-id winner")
      XCTAssertNotNil(try self.tombstone(db, self.largerId))
      XCTAssertEqual(try self.redirect(db, self.largerId)?.targetId, self.smallerId)
    }
  }

  /// Both convergence orders settle on the identical surviving policy id.
  func testBothArrivalOrdersConvergeToSameWinner() throws {
    var survivorA: [String] = []
    var survivorB: [String] = []
    try withDB { db in
      try self.applyPolicy(db, id: self.largerId, version: self.vEarlier)
      try self.applyPolicy(db, id: self.smallerId, version: self.vLater)
      survivorA = try self.alivePolicyIds(db)
    }
    try withDB { db in
      try self.applyPolicy(db, id: self.smallerId, version: self.vEarlier)
      try self.applyPolicy(db, id: self.largerId, version: self.vLater)
      survivorB = try self.alivePolicyIds(db)
    }
    XCTAssertEqual(survivorA, [self.smallerId])
    XCTAssertEqual(survivorA, survivorB)
  }

  /// The merged-away policy's device-local delivery-state row cascades away.
  func testMergeDropsLoserDeliveryStateAndLogsConflict() throws {
    try withDB { db in
      try self.applyPolicy(db, id: self.largerId, version: self.vEarlier)
      try db.execute(
        sql: """
          INSERT INTO habit_reminder_delivery_state (policy_id, updated_at)
          VALUES (?, ?)
          """,
        arguments: [self.largerId, self.ts])

      try self.applyPolicy(db, id: self.smallerId, version: self.vLater)

      XCTAssertEqual(try self.alivePolicyIds(db), [self.smallerId])
      XCTAssertEqual(
        try Int64.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM habit_reminder_delivery_state WHERE policy_id = ?",
          arguments: [self.largerId]),
        0, "loser policy's delivery-state row cascades away on delete")

      XCTAssertEqual(
        try Int64.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_conflict_log
             WHERE entity_type = ? AND entity_id = ? AND resolution_type = ?
            """,
          arguments: [
            EntityName.habitReminderPolicy, self.smallerId, ResolutionName.tagMerge,
          ]),
        1)
    }
  }

  /// Bug 2 (P1/P2 audit-trail gap): a dropped policy's diverging `enabled`
  /// content is captured as the conflict-log `loser_payload` instead of being
  /// silently discarded with `nil`.
  func testMergeLogsDivergentEnabledFieldAsLoserPayload() throws {
    try withDB { db in
      try self.applyPolicy(db, id: self.largerId, version: self.vEarlier, enabled: false)
      try self.applyPolicy(db, id: self.smallerId, version: self.vLater, enabled: true)

      let payload = try XCTUnwrap(
        try String.fetchOne(
          db,
          sql: """
            SELECT loser_payload FROM sync_conflict_log
             WHERE entity_type = ? AND entity_id = ? AND resolution_type = ?
            """,
          arguments: [EntityName.habitReminderPolicy, self.smallerId, ResolutionName.tagMerge]))
      let parsed = try XCTUnwrap(JSONValue.parse(payload).flatMap(ApplyJSON.object))
      XCTAssertEqual(parsed["enabled"], .bool(false))
    }
  }

  // MARK: - Full inbound batch (no wedge)

  private func policyEnvelope(id: String, version: String, reminderTime: String = "09:00") throws
    -> SyncEnvelope
  {
    try SyncTestSupport.completeEnvelope(
      entityType: .habitReminderPolicy, entityId: id, operation: .upsert,
      version: try Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try self.policyPayload(reminderTime: reminderTime), deviceId: "device-remote")
  }

  /// A full inbound page carrying the colliding policy alongside an unrelated valid
  /// policy must NOT abort.
  func testCollidingPolicyDoesNotWedgeInboundBatch() throws {
    let unrelatedId = "dddddddd-dddd-7ddd-8ddd-dddddddddddd"
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
    try withDB { db in
      let r1 = try Apply.applyEnvelope(
        db, registry: registry,
        envelope: try self.policyEnvelope(id: self.smallerId, version: self.vEarlier))
      XCTAssertEqual(r1, .applied)

      do {
        _ = try Apply.applyEnvelope(
          db, registry: registry,
          envelope: try self.policyEnvelope(id: self.largerId, version: self.vLater))
      } catch let error as ApplyError {
        if case .db = error {
          return XCTFail("collision still surfaced batch-fatal ApplyError.db — sync would wedge")
        }
        return XCTFail("collision threw an unexpected ApplyError: \(error)")
      }

      // The unrelated policy (a different reminder_time) still applies.
      let r3 = try Apply.applyEnvelope(
        db, registry: registry,
        envelope: try self.policyEnvelope(id: unrelatedId, version: self.vLater, reminderTime: "10:00"))
      XCTAssertEqual(r3, .applied)
      XCTAssertEqual(try self.alivePolicyIds(db, reminderTime: "10:00"), [unrelatedId])

      XCTAssertEqual(try self.alivePolicyIds(db), [self.smallerId])
      XCTAssertNotNil(try self.tombstone(db, self.largerId))
      XCTAssertEqual(try self.redirect(db, self.largerId)?.targetId, self.smallerId)
    }
  }

  // MARK: - max-HLC content convergence

  /// Both apply orders converge on the SAME `enabled` — the max-HLC participant's,
  /// carried onto the min-id winner regardless of arrival order.
  func testBothOrdersConvergeOnMaxHlcEnabled() throws {
    func run(_ apply: (Database) throws -> Void) throws -> Int64? {
      var enabled: Int64?
      try withDB { db in
        try apply(db)
        enabled = try Int64.fetchOne(
          db, sql: "SELECT enabled FROM habit_reminder_policies WHERE id = ?",
          arguments: [self.smallerId])
      }
      return enabled
    }
    let orderA = try run { db in
      try self.applyPolicy(db, id: self.smallerId, version: self.vEarlier, enabled: true)
      try self.applyPolicy(db, id: self.largerId, version: self.vLater, enabled: false)
    }
    let orderB = try run { db in
      try self.applyPolicy(db, id: self.largerId, version: self.vLater, enabled: false)
      try self.applyPolicy(db, id: self.smallerId, version: self.vEarlier, enabled: true)
    }
    XCTAssertEqual(orderA, 0, "the max-HLC `enabled` (false) survives")
    XCTAssertEqual(orderA, orderB, "content converges regardless of apply order")
  }

  /// Equal HLCs keep the min-id policy's own `enabled` (the tiebreak keeps the
  /// lower id, so nothing is carried).
  func testEqualHlcTiebreakKeepsMinIdEnabled() throws {
    try withDB { db in
      try self.applyPolicy(db, id: self.smallerId, version: self.vEarlier, enabled: true)
      try self.applyPolicy(db, id: self.largerId, version: self.vEarlier, enabled: false)
      XCTAssertEqual(try self.alivePolicyIds(db), [self.smallerId])
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT enabled FROM habit_reminder_policies WHERE id = ?",
          arguments: [self.smallerId]),
        1, "on an equal-HLC tie the min-id `enabled` survives")
    }
  }

  // MARK: - Bug 2: deterministic merge-stamp suffix (cross-peer version convergence)

  /// A 3-participant slot collision (`V_a=(t,0,sa)`, `V_b=(t,0,sb)` with `sb>sa`,
  /// `V_c=(t,1,sc)` dominating) mints a winner version `(t, 2, sc)` whose suffix is
  /// the dominating participant's own suffix, not the local device's, so two peers
  /// with DIFFERENT device ids converge on a byte-identical winner version and
  /// `enabled` content regardless of fold order. Distinct `reminder_time`s let the
  /// three policies coexist at rest, exactly the state the insert-collision path
  /// stages into.
  func testThreeWaySlotCollisionConvergesWinnerVersionAcrossPeers() throws {
    let idA = "00000000-0000-7000-8000-00000000000a"
    let idB = "00000000-0000-7000-8000-00000000000b"
    let idC = "00000000-0000-7000-8000-00000000000c"
    let vA = "1711234567000_0000_aaaa000000000001"
    let vB = "1711234567000_0000_bbbb000000000002"
    let vC = "1711234567000_0001_cccc000000000003"
    let expectedVersion = "1711234567000_0002_cccc000000000003"

    func run(deviceId: String, rowOrder: [(String, String)]) throws -> (Int64?, String?) {
      let store = try SyncTestSupport.freshStore()
      return try store.writer.write { db in
        try db.execute(
          sql: """
            INSERT INTO habits (id, name, frequency_type, target_count, archived,
                                lookup_key, version, created_at, updated_at)
            VALUES (?, 'Read', 'daily', 1, 0, 'read', ?, ?, ?)
            """,
          arguments: [self.habitId, self.vEarlier, self.ts, self.ts])
        try SyncCheckpoints.set(db, key: SyncCheckpoints.keyDeviceId, value: deviceId)
        try self.applyPolicy(db, id: idA, version: vA, reminderTime: "09:00", enabled: true)
        try self.applyPolicy(db, id: idB, version: vB, reminderTime: "09:30", enabled: true)
        // Dominating participant (V_c) carries `enabled = false` — the content that
        // survives on the min-id winner.
        try self.applyPolicy(db, id: idC, version: vC, reminderTime: "10:00", enabled: false)
        _ = try ApplyHabitReminderPolicyMerge.merger.mergeKnownDuplicate(
          db, rows: rowOrder, triggeringVersion: vC, applyTs: self.ts)
        let row = try Row.fetchOne(
          db, sql: "SELECT enabled, version FROM habit_reminder_policies WHERE id = ?",
          arguments: [idA])
        return (row?["enabled"] as Int64?, row?["version"] as String?)
      }
    }

    let peerOne = try run(deviceId: "device-one-1111", rowOrder: [(idA, vA), (idB, vB), (idC, vC)])
    let peerTwo = try run(deviceId: "device-two-2222", rowOrder: [(idC, vC), (idB, vB), (idA, vA)])

    XCTAssertEqual(peerOne.0, 0, "content = the dominating participant's `enabled` (false), carried onto min id")
    XCTAssertEqual(peerOne.1, expectedVersion, "winner version = (maxHlc.phys, counter+1, maxHlc.suffix)")
    XCTAssertEqual(peerOne.0, peerTwo.0, "content byte-identical across peers with different device ids")
    XCTAssertEqual(
      peerOne.1, peerTwo.1, "winner version byte-identical across peers (deterministic suffix)")
  }
}
