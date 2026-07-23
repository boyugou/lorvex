import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Cross-peer convergence coverage for the sync-applied list-delete task
/// re-home (SA1).
///
/// The schema trigger `trg_lists_before_delete` re-homes a deleted non-inbox
/// list's tasks to `inbox` without a version bump or outbox row, so a bare
/// sync-apply of a peer's list delete moves a task locally that never
/// propagates — the fleet diverges on that task's `list_id`. The driver
/// (`SwiftLorvexCoreService.applyInbound`) closes the gap by capturing the
/// re-home candidates before the delete applies and re-enqueuing them after,
/// via ``ListDeleteRehome``. These tests exercise that orchestration end-to-end
/// over two independent stores exchanging real outbox envelopes.
///
/// Each ``Device`` mirrors the driver's per-envelope inbound sequence exactly:
/// observe the peer version into the local clock, capture the re-home
/// candidates, apply the envelope, then (on `.applied`) re-enqueue the re-homed
/// tasks with a freshly minted local HLC.
final class ListDeleteRehomeConvergenceTests: XCTestCase {

  /// Canonical UUIDs — the outbox/envelope layer rejects non-UUID entity ids.
  private let listL = "01966a3f-7c8b-7d4e-8f3a-00000000c001"
  private let taskT = "01966a3f-7c8b-7d4e-8f3a-00000000c002"

  /// One simulated peer: an in-memory store, a monotone HLC clock, and a device
  /// identity, wired to apply inbound envelopes with the driver's re-home
  /// re-enqueue and to ship its outbox.
  private final class Device {
    let store: LorvexStore
    let hlc: HlcState
    let deviceId: String
    let suffix: String
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())

    init(suffix: String, deviceId: String, file: StaticString = #filePath) throws {
      self.store = try SyncTestSupport.freshStore(file: file)
      self.hlc = try HlcState(deviceSuffix: suffix)
      self.deviceId = deviceId
      self.suffix = suffix
    }

    private static func nowMs() -> UInt64 {
      let t = Date().timeIntervalSince1970
      return t < 0 ? 0 : UInt64(t * 1000)
    }

    // MARK: Seeding

    func seedList(_ id: String) throws {
      try store.writer.write { db in
        try db.execute(
          sql: """
            INSERT INTO lists (id, name, version, created_at, updated_at)
            VALUES (?, 'L', '0000000000000_0000_0000000000000000',
                    '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z')
            """,
          arguments: [id])
      }
    }

    func seedTaskInList(_ id: String, listId: String) throws {
      try store.writer.write { db in
        try db.execute(
          sql: """
            INSERT INTO tasks (id, list_id, title, status, version, created_at, updated_at,
                               defer_count)
            VALUES (?, ?, 'T', 'open', '0000000000000_0000_0000000000000000',
                    '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z', 0)
            """,
          arguments: [id, listId])
      }
    }

    // MARK: Local mutations (produce outbound envelopes)

    /// Version-stamp `(kind, id)` and enqueue an Upsert — the "author created /
    /// edited this row" path: read the snapshot, mint a fresh HLC, and route
    /// through `enqueuePayloadUpsert` (the production write-surface pattern).
    func enqueueUpsert(kind: EntityKind, id: String) throws {
      try store.writer.write { db in
        let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: kind.asString, entityId: id)
        try OutboxEnqueue.enqueuePayloadUpsert(
          db, entityType: kind.asString, entityId: id, payload: payload,
          context: OutboxWriteContext(version: hlc.generate().description, deviceId: deviceId))
      }
    }

    /// Delete a row locally: read its pre-delete snapshot, remove the row (a
    /// list delete fires the re-home trigger), then enqueue the Delete envelope
    /// + tombstone. Mirrors the driver's `deleteList` / task delete ordering.
    func localDelete(kind: EntityKind, id: String) throws {
      try store.writer.write { db in
        let snapshot = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: kind.asString, entityId: id)
        let table = kind == .list ? "lists" : "tasks"
        try db.execute(sql: "DELETE FROM \(table) WHERE id = ?", arguments: [id])
        try OutboxEnqueue.enqueuePayloadDelete(
          db, entityType: kind.asString, entityId: id, payload: snapshot,
          context: OutboxWriteContext(
            version: hlc.generate().description, deviceId: deviceId))
      }
    }

    // MARK: Inbound apply (mirrors driver applyInbound re-home orchestration)

    @discardableResult
    func applyInboundWithRehome(_ envelope: SyncEnvelope) throws -> ApplyResult {
      try store.writer.write { db in
        // Advance the local clock past the peer version, exactly as the driver's
        // `clock.observePeerEnvelope` does before apply.
        hlc.updateOnReceive(
          remote: envelope.version, physicalMs: Self.nowMs(),
          maxForwardDriftMs: HlcState.maxInboundForwardDriftMs)
        let candidates = try ListDeleteRehome.captureRehomeCandidates(db, envelope: envelope)
        let outcome = try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
        if case .applied = outcome, !candidates.isEmpty {
          try ListDeleteRehome.reenqueueRehomed(
            db, taskIds: candidates,
            mintVersion: { floor in
              if let floor {
                self.hlc.updateOnReceive(remote: floor, physicalMs: Self.nowMs())
              }
              return self.hlc.generate().description
            },
            deviceId: deviceId)
        }
        return outcome
      }
    }

    // MARK: Transport

    /// Drain every pending outbox envelope and mark it synced (one CloudKit
    /// push cycle). Returns the envelopes in FIFO order.
    func shipOutbound() throws -> [SyncEnvelope] {
      try store.writer.write { db in
        let entries = try Outbox.getPending(db)
        try Outbox.markManySynced(
          db, outboxIds: entries.map { $0.id }, syncedAt: "2026-04-19T09:00:00.000Z")
        return entries.map { $0.envelope }
      }
    }

    // MARK: Read helpers

    func taskListId(_ id: String) throws -> String? {
      try store.writer.read { db in
        try String.fetchOne(db, sql: "SELECT list_id FROM tasks WHERE id = ?", arguments: [id])
      }
    }

    func taskVersion(_ id: String) throws -> String? {
      try store.writer.read { db in
        try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [id])
      }
    }

    func taskExists(_ id: String) throws -> Bool {
      try store.writer.read { db in
        (try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [id]) ?? 0) > 0
      }
    }

    func listExists(_ id: String) throws -> Bool {
      try store.writer.read { db in
        (try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM lists WHERE id = ?", arguments: [id]) ?? 0) > 0
      }
    }

    func isTombstoned(_ kind: EntityKind, _ id: String) throws -> Bool {
      try store.writer.read { db in
        try Tombstone.isTombstoned(db, entityType: kind.asString, entityId: id)
      }
    }

    /// Count of task-upsert rows for `id` in the outbox, across synced and
    /// unsynced rows — proves whether a re-home enqueue ever fired.
    func taskUpsertOutboxCount(_ id: String) throws -> Int64 {
      try store.writer.read { db in
        try Int64.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND operation = 'upsert'
            """,
          arguments: [id]) ?? -1
      }
    }
  }

  private func makeDevices(file: StaticString = #filePath) throws -> (Device, Device) {
    let a = try Device(suffix: "aaaaaaaaaaaaaaaa", deviceId: "device-a", file: file)
    let b = try Device(suffix: "bbbbbbbbbbbbbbbb", deviceId: "device-b", file: file)
    return (a, b)
  }

  // MARK: - Convergence

  /// Device A deletes list L; device B holds a task T in L that A never saw.
  /// Exchanging both directions converges BOTH devices on T present in inbox —
  /// the re-home now propagates instead of stranding T on B.
  func testListDeleteRehomeConvergesAcrossPeers() throws {
    let (a, b) = try makeDevices()

    // Converged catalog: both hold list L. B independently adds task T to L.
    try a.seedList(listL)
    try b.seedList(listL)
    try b.seedTaskInList(taskT, listId: listL)
    try b.enqueueUpsert(kind: .task, id: taskT)

    // A deletes L (empty on A) — nothing to re-home on A's own side.
    try a.localDelete(kind: .list, id: listL)

    // A → B: B applies the list delete; the trigger re-homes T to inbox and the
    // driver re-enqueues it.
    let aOut = try a.shipOutbound()
    XCTAssertEqual(aOut.count, 1, "A ships only the list-delete envelope")
    for env in aOut {
      XCTAssertEqual(try b.applyInboundWithRehome(env), .applied)
    }
    XCTAssertEqual(try b.taskListId(taskT), "inbox", "B re-homes T to inbox")
    XCTAssertFalse(try b.listExists(listL), "L deleted on B")

    // B → A: the re-home upsert (coalesced over B's original create) carries the
    // inbox move to A, which never held T before.
    let bOut = try b.shipOutbound()
    let tUpsert = try XCTUnwrap(
      bOut.first { $0.entityType == .task && $0.entityId == taskT && $0.operation == .upsert },
      "B ships a task upsert propagating the re-home")
    XCTAssertTrue(
      tUpsert.payload.contains("\"list_id\":\"inbox\""),
      "the propagated upsert carries list_id=inbox; got \(tUpsert.payload)")
    for env in bOut {
      _ = try a.applyInboundWithRehome(env)
    }

    // Both devices agree: T exists, list_id = inbox.
    XCTAssertEqual(try a.taskListId(taskT), "inbox", "A converges on T in inbox")
    XCTAssertEqual(try b.taskListId(taskT), "inbox")
    XCTAssertEqual(
      try a.taskVersion(taskT), try b.taskVersion(taskT),
      "both devices agree on the re-home version")
  }

  // MARK: - No resurrection (concurrent delete via the capture guard)

  /// Device A deletes task T then deletes list L; device B concurrently deletes
  /// task T. When B applies A's list-delete, T is already gone locally, so it is
  /// NOT captured and NOT re-enqueued — the re-home never resurrects a
  /// concurrently-deleted task. T converges to DELETED on both devices.
  func testConcurrentTaskDeleteIsNotResurrectedByRehome() throws {
    let (a, b) = try makeDevices()

    // Converged start: both hold L and T-in-L.
    try a.seedList(listL)
    try a.seedTaskInList(taskT, listId: listL)
    try b.seedList(listL)
    try b.seedTaskInList(taskT, listId: listL)

    // A deletes T, then deletes L (now empty on A). B independently deletes T.
    try a.localDelete(kind: .task, id: taskT)
    try a.localDelete(kind: .list, id: listL)
    try b.localDelete(kind: .task, id: taskT)

    // A → B: the task-delete lands first (FIFO), then the list-delete finds no
    // live task in L to re-home.
    let aOut = try a.shipOutbound()
    for env in aOut {
      _ = try b.applyInboundWithRehome(env)
    }
    XCTAssertFalse(try b.listExists(listL), "L deleted on B")

    // B → A: B's task-delete reaches A (already deleted there).
    let bOut = try b.shipOutbound()
    for env in bOut {
      _ = try a.applyInboundWithRehome(env)
    }

    // T stays DELETED on both, and NO task upsert was ever minted by the
    // re-home path on either device.
    XCTAssertFalse(try a.taskExists(taskT), "A: T stays deleted")
    XCTAssertFalse(try b.taskExists(taskT), "B: T stays deleted")
    XCTAssertTrue(try a.isTombstoned(.task, taskT), "A: T tombstoned")
    XCTAssertTrue(try b.isTombstoned(.task, taskT), "B: T tombstoned")
    XCTAssertEqual(
      try a.taskUpsertOutboxCount(taskT), 0, "A never enqueued a re-home upsert for a deleted task")
    XCTAssertEqual(
      try b.taskUpsertOutboxCount(taskT), 0, "B never enqueued a re-home upsert for a deleted task")
  }

  /// The re-home is an ordinary live-task edit, not an immortality grant: once
  /// B has re-homed T to inbox and propagated it to A, a delete with a strictly
  /// greater HLC (minted after the re-home on the same monotone clock) removes T
  /// on both devices. The re-home upsert does NOT win LWW against a dominating
  /// delete.
  func testRehomeLosesToDominatingLaterDelete() throws {
    let (a, b) = try makeDevices()

    try a.seedList(listL)
    try b.seedList(listL)
    try b.seedTaskInList(taskT, listId: listL)
    try b.enqueueUpsert(kind: .task, id: taskT)
    try a.localDelete(kind: .list, id: listL)

    // B applies A's list-delete → re-homes T and enqueues the inbox upsert.
    for env in try a.shipOutbound() {
      _ = try b.applyInboundWithRehome(env)
    }
    XCTAssertEqual(try b.taskListId(taskT), "inbox")

    // Ship the re-home upsert to A first, so A holds T alive in inbox.
    for env in try b.shipOutbound() {
      _ = try a.applyInboundWithRehome(env)
    }
    XCTAssertEqual(try a.taskListId(taskT), "inbox", "A sees the re-home before any delete")

    // A dominating delete: B deletes T locally now, minting a strictly greater
    // HLC than the re-home version (same monotone clock, later mint).
    let rehomeVersion = try XCTUnwrap(try b.taskVersion(taskT))
    try b.localDelete(kind: .task, id: taskT)
    let deleteVersion = try XCTUnwrap(
      try b.store.writer.read { db in
        try String.fetchOne(
          db,
          sql: """
            SELECT version FROM sync_tombstones
            WHERE entity_type = 'task' AND entity_id = ?
            """,
          arguments: [taskT])
      })
    XCTAssertGreaterThan(
      try Hlc.parse(deleteVersion), try Hlc.parse(rehomeVersion),
      "the later delete dominates the re-home version")

    // The delete propagates to A, which had T alive from the re-home.
    for env in try b.shipOutbound() {
      _ = try a.applyInboundWithRehome(env)
    }

    XCTAssertFalse(try b.taskExists(taskT), "B: dominating delete removes T")
    XCTAssertFalse(
      try a.taskExists(taskT), "A: the re-home upsert did NOT resurrect T against the later delete")
    XCTAssertTrue(try a.isTombstoned(.task, taskT))
  }

  // MARK: - Idempotent re-apply

  /// Re-applying the same list-delete envelope re-homes nothing the second time
  /// (the tasks already carry list_id=inbox), so no extra re-home upsert is
  /// minted and the task's version is unchanged.
  func testReapplyingListDeleteDoesNotReenqueueRehomeAgain() throws {
    let (a, b) = try makeDevices()

    try a.seedList(listL)
    try b.seedList(listL)
    try b.seedTaskInList(taskT, listId: listL)
    try b.enqueueUpsert(kind: .task, id: taskT)
    try a.localDelete(kind: .list, id: listL)

    let listDelete = try XCTUnwrap(try a.shipOutbound().first)

    // First apply: re-homes T and re-enqueues it.
    XCTAssertEqual(try b.applyInboundWithRehome(listDelete), .applied)
    XCTAssertEqual(try b.taskListId(taskT), "inbox")
    let versionAfterFirst = try XCTUnwrap(try b.taskVersion(taskT))
    let upsertsAfterFirst = try b.taskUpsertOutboxCount(taskT)

    // Second apply of the identical envelope: the list is already tombstoned and
    // T already lives in inbox, so nothing is captured or re-enqueued.
    _ = try b.applyInboundWithRehome(listDelete)
    XCTAssertEqual(
      try b.taskVersion(taskT), versionAfterFirst,
      "no second re-home mint bumps the task version")
    XCTAssertEqual(
      try b.taskUpsertOutboxCount(taskT), upsertsAfterFirst,
      "re-applying the list-delete adds no extra re-home upsert")
    XCTAssertEqual(try b.taskListId(taskT), "inbox")
  }
}
