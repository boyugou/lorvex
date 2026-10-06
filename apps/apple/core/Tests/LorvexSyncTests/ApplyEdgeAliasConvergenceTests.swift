import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Order independence of a `task_tag` edge across a tag merge.
///
/// A merged tag keeps one logical edge per task: `(task, loser)` and
/// `(task, winner)` name the same relationship once the permanent alias is
/// known. Every operation on either key — upsert or delete — therefore competes
/// in one last-writer-wins register, and a delete wins an exact version tie.
/// These tests deliver the same set of records to a fresh replica in many
/// different orders (including orders where an edge record arrives before the
/// merge is known and orders where it arrives after) and require the same final
/// state each time, equal to what a replica computes from the highest-versioned
/// operation alone.
final class ApplyEdgeAliasConvergenceTests: XCTestCase {

  private let task = "01966a3f-7c8b-7d4e-8f3a-000000000001"
  // `winner` < `loser`, so the min-id merge keeps `winner`.
  private let winner = "01966a3f-7c8b-7d4e-8f3a-0000000000aa"
  private let loser = "01966a3f-7c8b-7d4e-8f3a-0000000000bb"

  private let winnerTagVersion = "1711234560000_0000_aaaaaaaaaaaaaaaa"
  private let loserTagVersion = "1711234561000_0000_bbbbbbbbbbbbbbbb"
  /// The merge version a replica mints for the pair: the smallest successor of
  /// the highest participant version.
  private let mergeVersion = "1711234561000_0001_bbbbbbbbbbbbbbbb"

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  // MARK: - Records

  private enum Delivery: String, CaseIterable {
    case winnerTag, loserTag
    case winnerEdgeUpsert, winnerEdgeDelete, loserEdgeUpsert, loserEdgeDelete
    case aliasRedirect, aliasWinnerTag, aliasLoserDelete

    var isEdge: Bool {
      switch self {
      case .winnerEdgeUpsert, .winnerEdgeDelete, .loserEdgeUpsert, .loserEdgeDelete: return true
      default: return false
      }
    }
  }

  /// The four edge operations ordered from oldest to newest by `rank`.
  private struct EdgeOperation {
    var record: Delivery
    var rank: Int
  }

  private func edgeVersion(rank: Int, suffix: String) -> String {
    "17112345\(70 + rank)000_0000_\(suffix)"
  }

  private func tagPayload() -> String {
    """
    {"display_name":"work","color":null,"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
    """
  }

  private func tagEnvelope(_ id: String, _ version: String) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .tag, entityId: id, operation: .upsert, version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion, payload: tagPayload(),
      deviceId: "device-remote")
  }

  private func edgeEnvelope(
    tag: String, operation: SyncOperation, version: String, createdAt: String
  ) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .taskTag, entityId: "\(task):\(tag)", operation: operation,
      version: try Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{\"task_id\":\"\(task)\",\"tag_id\":\"\(tag)\",\"created_at\":\"\(createdAt)\"}",
      deviceId: "device-remote")
  }

  private func createdAt(rank: Int) -> String { "2026-03-27T09:00:0\(rank).000Z" }

  private func envelope(for record: Delivery, operations: [Delivery: EdgeOperation]) throws
    -> SyncEnvelope
  {
    switch record {
    case .winnerTag: return try tagEnvelope(winner, winnerTagVersion)
    case .loserTag: return try tagEnvelope(loser, loserTagVersion)
    case .aliasWinnerTag: return try tagEnvelope(winner, mergeVersion)
    case .aliasRedirect:
      return try EntityRedirect.makeEnvelope(
        record: EntityRedirect.Record(
          sourceType: .tag, sourceId: loser, targetId: winner, version: mergeVersion,
          createdAt: "2026-03-27T09:00:00.000Z"),
        deviceId: "device-remote")
    case .aliasLoserDelete:
      return SyncEnvelope(
        entityType: .tag, entityId: loser, operation: .delete,
        version: try Hlc.parse(mergeVersion),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: "{\"version\":\"\(mergeVersion)\"}", deviceId: "device-remote")
    case .winnerEdgeUpsert, .winnerEdgeDelete, .loserEdgeUpsert, .loserEdgeDelete:
      guard let operation = operations[record] else {
        preconditionFailure("edge record \(record) has no operation")
      }
      let onLoser = record == .loserEdgeUpsert || record == .loserEdgeDelete
      let isUpsert = record == .winnerEdgeUpsert || record == .loserEdgeUpsert
      return try edgeEnvelope(
        tag: onLoser ? loser : winner, operation: isUpsert ? .upsert : .delete,
        version: edgeVersion(rank: operation.rank, suffix: onLoser ? "bbbbbbbbbbbbbbbb" : "aaaaaaaaaaaaaaaa"),
        createdAt: createdAt(rank: operation.rank))
    }
  }

  // MARK: - Replica

  private struct Outcome: Equatable, CustomStringConvertible {
    /// `task:tag version created_at` for every live edge.
    var liveEdges: [String] = []
    /// Live tag ids.
    var tags: [String] = []
    /// `source>target` for every tag redirect.
    var redirects: [String] = []
    /// Edge tombstones with the loser half rewritten to the winner and the
    /// highest version kept, `canonicalKey version`.
    var edgeTombstones: [String] = []
    /// State the engine must never produce.
    var invariantViolations: [String] = []

    var description: String {
      "edges=\(liveEdges) tags=\(tags) redirects=\(redirects) tombstones=\(edgeTombstones)"
        + (invariantViolations.isEmpty ? "" : " VIOLATIONS=\(invariantViolations)")
    }
  }

  /// Delivers the envelopes, in order, to a replica that holds only the task, and
  /// reads the resulting state. The replica's transaction is rolled back so one
  /// store serves every ordering.
  private func play(_ envelopes: [SyncEnvelope], on store: LorvexStore) throws -> Outcome {
    try store.writer.writeWithoutTransaction { db in
      var result = Outcome()
      try db.inTransaction {
        try db.execute(
          sql:
            "INSERT INTO tasks (id, title, status, version, created_at, updated_at) VALUES (?, 'T', 'open', '0000000000000_0000_0000000000000000', '', '')",
          arguments: [self.task])
        for envelope in envelopes {
          let applied = try Apply.applyEnvelope(db, registry: self.registry, envelope: envelope)
          if case let .deferred(reason) = applied {
            try PendingInboxDrain.enqueueDeferred(db, envelope: envelope, reason: reason)
          }
          _ = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
        }
        result = try self.outcome(db)
        return .rollback
      }
      return result
    }
  }

  private func outcome(_ db: Database) throws -> Outcome {
    var result = Outcome()
    result.liveEdges = try Row.fetchAll(
      db, sql: "SELECT task_id, tag_id, version, created_at FROM task_tags ORDER BY tag_id"
    ).map { "\($0[0] as String):\($0[1] as String) \($0[2] as String) \($0[3] as String)" }
    result.tags = try String.fetchAll(db, sql: "SELECT id FROM tags ORDER BY id")
    result.redirects = try Row.fetchAll(
      db,
      sql: "SELECT source_id, target_id FROM sync_entity_redirects WHERE source_type = 'tag'"
    ).map { "\($0[0] as String)>\($0[1] as String)" }
    var tombstones: [String: String] = [:]
    for row in try Row.fetchAll(
      db,
      sql: "SELECT entity_id, version FROM sync_tombstones WHERE entity_type = 'task_tag'")
    {
      let id: String = row[0]
      let version: String = row[1]
      let key = id.hasSuffix(":\(loser)") ? "\(task):\(winner)" : id
      if let existing = tombstones[key], existing >= version { continue }
      tombstones[key] = version
    }
    // A tombstone under a live edge's key is dominated by that edge and carries no
    // state.
    let liveKeys = Set(result.liveEdges.map { String($0.split(separator: " ")[0]) })
    result.edgeTombstones =
      tombstones.filter { !liveKeys.contains($0.key) }.map { "\($0.key) \($0.value)" }.sorted()

    for row in try Row.fetchAll(
      db,
      sql: """
        SELECT t.entity_id FROM sync_tombstones t
        JOIN task_tags e ON t.entity_id = e.task_id || ':' || e.tag_id
        WHERE t.entity_type = 'task_tag'
        """)
    {
      let id: String = row[0]
      result.invariantViolations.append("edge \(id) is both live and tombstoned")
    }
    let strandedLoserEdges =
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM task_tags WHERE tag_id = ?", arguments: [loser]) ?? 0
    if strandedLoserEdges != 0 {
      result.invariantViolations.append("\(strandedLoserEdges) live edge(s) still name the loser")
    }
    let pending =
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_pending_inbox") ?? 0
    if pending != 0 {
      result.invariantViolations.append("\(pending) record(s) still parked in the pending inbox")
    }
    return result
  }

  /// What one replica computes from the edge operations alone: the highest
  /// version wins, a delete wins an exact tie.
  private func expectedLiveEdge(operations: [Delivery: EdgeOperation]) -> String? {
    var best: (record: Delivery, version: String)?
    for (record, operation) in operations {
      let onLoser = record == .loserEdgeUpsert || record == .loserEdgeDelete
      let version = edgeVersion(
        rank: operation.rank, suffix: onLoser ? "bbbbbbbbbbbbbbbb" : "aaaaaaaaaaaaaaaa")
      guard let current = best else {
        best = (record, version)
        continue
      }
      if version > current.version { best = (record, version) }
    }
    guard let winning = best,
      winning.record == .winnerEdgeUpsert || winning.record == .loserEdgeUpsert,
      let operation = operations[winning.record]
    else { return nil }
    return "\(task):\(winner) \(winning.version) \(createdAt(rank: operation.rank))"
  }

  // MARK: - Enumeration

  private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  private func permutations<T>(_ items: [T]) -> [[T]] {
    if items.count <= 1 { return [items] }
    var result: [[T]] = []
    for index in items.indices {
      var rest = items
      let head = rest.remove(at: index)
      for tail in permutations(rest) { result.append([head] + tail) }
    }
    return result
  }

  /// Whether `order` lists every chain in `chains` in the chain's own order. A chain
  /// is the sequence one device emitted its records in; a replica reads one
  /// device's records in that order, while records of different devices interleave
  /// freely.
  private func respects(_ order: [Delivery], chains: [[Delivery]]) -> Bool {
    chains.allSatisfy { chain in
      let positions = chain.compactMap { order.firstIndex(of: $0) }
      return positions == positions.sorted()
    }
  }

  /// Every ordering of `records` that respects `chains`, or a seeded sample of up
  /// to `limit` such orderings when the full set is larger.
  private func orderings(
    of records: [Delivery], limit: Int, seed: UInt64, keeping chains: [[Delivery]] = []
  ) -> [[Delivery]] {
    let factorial = (1...max(records.count, 1)).reduce(1, *)
    if factorial <= limit {
      return permutations(records).filter { respects($0, chains: chains) }
    }
    var generator = SplitMix64(state: seed)
    var seen = Set<[Int]>()
    var result: [[Delivery]] = []
    var attempts = 0
    while result.count < limit && attempts < limit * 40 {
      attempts += 1
      let order = Array(records.indices).shuffled(using: &generator)
      let candidate = order.map { records[$0] }
      if respects(candidate, chains: chains), seen.insert(order).inserted {
        result.append(candidate)
      }
    }
    return result
  }

  private func assertConverges(
    records: [Delivery], operations: [Delivery: EdgeOperation], limit: Int, seed: UInt64,
    keeping chains: [[Delivery]] = [], file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let expected = expectedLiveEdge(operations: operations)
    var reference: (order: [Delivery], outcome: Outcome)?
    var failures: [String] = []
    let store = try SyncTestSupport.freshStore()
    for order in orderings(of: records, limit: limit, seed: seed, keeping: chains) {
      let outcome = try play(
        try order.map { try envelope(for: $0, operations: operations) }, on: store)
      var problems: [String] = []
      if !outcome.invariantViolations.isEmpty { problems.append("invariants violated") }
      let live = outcome.liveEdges.filter { $0.hasPrefix("\(task):\(winner) ") }
      if (live.first) != expected {
        problems.append("expected live edge \(expected ?? "none"), got \(live)")
      }
      if let reference {
        if outcome != reference.outcome {
          problems.append("differs from \(reference.order.map(\.rawValue)): \(reference.outcome)")
        }
      } else {
        reference = (order, outcome)
      }
      if !problems.isEmpty {
        failures.append("\(order.map(\.rawValue)): \(problems.joined(separator: "; ")) -> \(outcome)")
      }
      if failures.count >= 6 { break }
    }
    XCTAssertTrue(
      failures.isEmpty,
      "operations \(operations.mapValues(\.rank)):\n" + failures.joined(separator: "\n"),
      file: file, line: line)
  }

  /// Assigns the ranks `0..<n` to the given edge records in every possible order.
  private func rankAssignments(_ edgeRecords: [Delivery]) -> [[Delivery: EdgeOperation]] {
    permutations(Array(0..<edgeRecords.count)).map { ranks in
      Dictionary(
        uniqueKeysWithValues: zip(edgeRecords, ranks).map {
          ($0, EdgeOperation(record: $0, rank: $1))
        })
    }
  }

  // MARK: - Natural-key merge (the replica discovers the collision itself)

  /// A delete addressed at the loser edge arrives before or after the merge, and
  /// the winner holds an independently authored edge: whichever register entry
  /// has the higher version decides, in every arrival order.
  func testLoserEdgeDeleteAgainstWinnerEdgeUpsert() throws {
    let edgeRecords: [Delivery] = [.winnerEdgeUpsert, .loserEdgeDelete]
    for operations in rankAssignments(edgeRecords) {
      try assertConverges(
        records: [.winnerTag, .loserTag] + edgeRecords, operations: operations, limit: 60,
        seed: 1)
    }
  }

  /// A live loser edge meets a delete addressed at the winner edge.
  func testLoserEdgeUpsertAgainstWinnerEdgeDelete() throws {
    let edgeRecords: [Delivery] = [.loserEdgeUpsert, .winnerEdgeDelete]
    for operations in rankAssignments(edgeRecords) {
      try assertConverges(
        records: [.winnerTag, .loserTag] + edgeRecords, operations: operations, limit: 60,
        seed: 2)
    }
  }

  /// Both keys carry a delete and a later upsert lands on the winner key.
  func testDeleteOnBothKeysThenUpsert() throws {
    let edgeRecords: [Delivery] = [.winnerEdgeDelete, .loserEdgeDelete, .winnerEdgeUpsert]
    for operations in rankAssignments(edgeRecords) {
      try assertConverges(
        records: [.winnerTag, .loserTag] + edgeRecords, operations: operations, limit: 60,
        seed: 3)
    }
  }

  /// An upsert and a delete on the loser key against an upsert on the winner key.
  func testLoserUpsertAndDeleteAgainstWinnerUpsert() throws {
    let edgeRecords: [Delivery] = [.loserEdgeUpsert, .loserEdgeDelete, .winnerEdgeUpsert]
    for operations in rankAssignments(edgeRecords) {
      try assertConverges(
        records: [.winnerTag, .loserTag] + edgeRecords, operations: operations, limit: 60,
        seed: 4)
    }
  }

  // MARK: - Announced merge (the redirect, winner snapshot and loser delete arrive)

  func testAnnouncedMergeLoserEdgeDeleteAgainstWinnerEdgeUpsert() throws {
    let edgeRecords: [Delivery] = [.winnerEdgeUpsert, .loserEdgeDelete]
    for operations in rankAssignments(edgeRecords) {
      try assertConverges(
        records: [.winnerTag, .aliasRedirect, .aliasWinnerTag, .aliasLoserDelete] + edgeRecords,
        operations: operations, limit: 60, seed: 5)
    }
  }

  /// The replica already knows both tags when the merge is announced. The merging
  /// device emits the redirect, then the loser's delete, then the winner snapshot,
  /// and a replica reads those three in that order; the edge records interleave
  /// with them freely.
  func testAnnouncedMergeOnAReplicaThatKnowsBothTags() throws {
    let edgeRecords: [Delivery] = [.loserEdgeUpsert, .loserEdgeDelete, .winnerEdgeUpsert]
    for operations in rankAssignments(edgeRecords) {
      try assertConverges(
        records: [.winnerTag, .loserTag, .aliasRedirect, .aliasWinnerTag, .aliasLoserDelete]
          + edgeRecords,
        operations: operations, limit: 40, seed: 6,
        keeping: [
          [.aliasRedirect, .aliasLoserDelete, .aliasWinnerTag],
          [.winnerTag, .aliasRedirect], [.loserTag, .aliasRedirect],
        ])
    }
  }

  /// A replica that holds neither tag catches up on the zone: the loser's own
  /// upsert was replaced by its delete and the winner's by the winner snapshot, so
  /// the redirect waits for a winner that arrives after the loser's delete, while
  /// the edge records arrive before, between, or after the three merge records.
  func testCatchingUpAfterAnnouncedMergeWithNeitherTagKnown() throws {
    let edgeRecords: [Delivery] = [.loserEdgeUpsert, .loserEdgeDelete, .winnerEdgeUpsert]
    for operations in rankAssignments(edgeRecords) {
      try assertConverges(
        records: [.aliasRedirect, .aliasWinnerTag, .aliasLoserDelete] + edgeRecords,
        operations: operations, limit: 40, seed: 7,
        keeping: [[.aliasRedirect, .aliasLoserDelete, .aliasWinnerTag]])
    }
  }
}
