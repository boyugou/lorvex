import Foundation
import GRDB
import LorvexDomain

/// Folds the state of every composite edge that names a merged parent into the
/// edge addressed at the surviving parent.
///
/// Once a permanent alias `loser -> winner` is known, `(task, loser)` and
/// `(task, winner)` are one logical relationship. The inbound path already
/// treats them that way for every record that arrives after the alias
/// (``ApplyRedirect/remapCompositeEdgeThroughParentRedirects(_:envelope:)``).
/// Records that were applied before the alias became known sit under the loser
/// key — a live row, or the delete barrier a delete left behind — and the winner
/// key may hold its own row or barrier. Folding settles those two keys into one
/// register so the relationship ends in the same state in every arrival order.
///
/// A key's register is either a live row or a delete barrier, stamped with the
/// version of the operation that produced it. The higher version wins; at an
/// exact tie a delete barrier beats a live row (the same rule as the inbound
/// gates), and two live rows keep the earlier `created_at`. The winning register
/// is written to the winner key (a live row removes any barrier there, a barrier
/// removes any live row there) and the loser key is cleared. The fold is derived
/// state: every replica holds the same loser-side records and the same alias, so
/// it reaches the same register without emitting anything.
enum EdgeAliasFold {

  /// One edge key's state.
  private struct Register {
    /// `true` for a live row, `false` for a delete barrier.
    var isLive: Bool
    var version: String
    /// Creation time of a live row.
    var createdAt: String?
    /// Deletion time of a delete barrier.
    var deletedAt: String?
  }

  private static func join(_ lhs: Register, _ rhs: Register) -> Register {
    if canonicalPreferringDominates(incoming: lhs.version, existing: rhs.version) { return lhs }
    if canonicalPreferringDominates(incoming: rhs.version, existing: lhs.version) { return rhs }
    switch (lhs.isLive, rhs.isLive) {
    case (true, true):
      var earliest = lhs
      earliest.createdAt = min(lhs.createdAt ?? "", rhs.createdAt ?? "")
      return earliest
    case (false, _): return lhs
    case (true, false): return rhs
    }
  }

  /// Folds the edges of every kind that name `aliasSourceId` as a merged parent
  /// into the edges that name `targetId`. `targetId` must be a live row of
  /// `parentKind`; kinds without composite edges are left alone.
  static func fold(
    _ db: Database, parentKind: EntityKind, aliasSourceId: String, targetId: String
  ) throws {
    do {
      switch parentKind {
      case .tag:
        try foldTaskTags(db, loserId: aliasSourceId, winnerId: targetId)
      default:
        return
      }
    } catch { throw ApplyError.lift(error) }
  }

  private static func foldTaskTags(
    _ db: Database, loserId: String, winnerId: String
  ) throws {
    let edge = EdgeName.taskTag
    var loserRegisters: [String: Register] = [:]
    for row in try Row.fetchAll(
      db, sql: "SELECT task_id, created_at, version FROM task_tags WHERE tag_id = ?",
      arguments: [loserId])
    {
      loserRegisters[row["task_id"]] = Register(
        isLive: true, version: row["version"], createdAt: row["created_at"], deletedAt: nil)
    }
    let loserSuffix = ":" + loserId
    for row in try Row.fetchAll(
      db,
      sql: """
        SELECT entity_id, version, deleted_at FROM sync_tombstones
         WHERE entity_type = ?1 AND length(entity_id) > length(?2)
           AND substr(entity_id, length(entity_id) - length(?2) + 1) = ?2
        """,
      arguments: [edge, loserSuffix])
    {
      let entityId: String = row["entity_id"]
      guard case let .success(halves) = CompositeEdge.splitCompositeEdgeId(entityId),
        halves.1 == loserId
      else { continue }
      let barrier = Register(
        isLive: false, version: row["version"], createdAt: nil, deletedAt: row["deleted_at"])
      loserRegisters[halves.0] = loserRegisters[halves.0].map { join($0, barrier) } ?? barrier
    }
    guard !loserRegisters.isEmpty else { return }

    for (taskId, loserRegister) in loserRegisters.sorted(by: { $0.key < $1.key }) {
      let winnerKey = "\(taskId):\(winnerId)"
      var winnerRegister: Register?
      if let row = try Row.fetchOne(
        db, sql: "SELECT created_at, version FROM task_tags WHERE task_id = ? AND tag_id = ?",
        arguments: [taskId, winnerId])
      {
        winnerRegister = Register(
          isLive: true, version: row["version"], createdAt: row["created_at"], deletedAt: nil)
      }
      if let barrier = try Tombstone.getTombstone(db, entityType: edge, entityId: winnerKey) {
        let register = Register(
          isLive: false, version: barrier.version, createdAt: nil, deletedAt: barrier.deletedAt)
        winnerRegister = winnerRegister.map { join($0, register) } ?? register
      }

      let settled = winnerRegister.map { join($0, loserRegister) } ?? loserRegister
      if settled.isLive, let createdAt = settled.createdAt {
        try db.execute(
          sql: """
            INSERT INTO task_tags (task_id, tag_id, created_at, version) VALUES (?, ?, ?, ?)
            ON CONFLICT(task_id, tag_id) DO UPDATE SET
                created_at = excluded.created_at, version = excluded.version
            """,
          arguments: [taskId, winnerId, createdAt, settled.version])
        _ = try Tombstone.removeTombstone(db, entityType: edge, entityId: winnerKey)
      } else if let deletedAt = settled.deletedAt {
        try db.execute(
          sql: "DELETE FROM task_tags WHERE task_id = ? AND tag_id = ?",
          arguments: [taskId, winnerId])
        try Tombstone.createTombstone(
          db, entityType: edge, entityId: winnerKey, version: settled.version,
          deletedAt: deletedAt)
      }
      _ = try Tombstone.removeTombstone(
        db, entityType: edge, entityId: "\(taskId):\(loserId)")
    }
    try db.execute(sql: "DELETE FROM task_tags WHERE tag_id = ?", arguments: [loserId])
  }
}
