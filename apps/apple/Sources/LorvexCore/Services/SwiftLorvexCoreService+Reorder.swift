import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Manual display-order persistence for the lists catalog and habits board.
///
/// `position` is an ordinary synced column on the `lists` / `habits` rows, so
/// reordering on one device converges on peers through the normal outbox →
/// apply path. A row syncs whole, the newer copy replacing the older, so a
/// reorder touches as few rows as it can (``ReorderPositions``): a rewritten
/// row would replace whatever another device changed in it meanwhile.
///
/// A reorder is a full-permutation operation: `orderedIDs` must be exactly the
/// current reorderable set (the active, non-archived rows) — every id present,
/// none extra, none duplicated. The whole permutation is validated and then
/// applied inside a single `withWrite` transaction, so the rewritten positions
/// either commit as one new ordering or roll back entirely. Only the rows whose
/// position changes are version-stamped + enqueued, so a no-op drag syncs
/// nothing and a one-row drag syncs one row.
extension SwiftLorvexCoreService {
  public func reorderLists(orderedIDs: [LorvexList.ID]) async throws -> ListCatalogSnapshot {
    try withWrite { db, hlc, deviceId in
      try Self.applyReorder(
        db, hlc: hlc, deviceId: deviceId, service: self,
        table: "lists", scopeWhere: "archived_at IS NULL",
        kind: .list, entityType: EntityName.list,
        orderedIDs: orderedIDs, summaryNoun: "list")
      let rows = try ListRepo.getAllListsWithCounts(db)
      return ListCatalogSnapshot(lists: rows.map(SwiftLorvexListDeserializers.list))
    }
  }

  public func reorderHabits(orderedIDs: [LorvexHabit.ID], date: String) async throws
    -> HabitCatalogSnapshot
  {
    try withWrite { db, hlc, deviceId in
      try Self.applyReorder(
        db, hlc: hlc, deviceId: deviceId, service: self,
        table: "habits", scopeWhere: "archived = 0",
        kind: .habit, entityType: EntityName.habit,
        orderedIDs: orderedIDs, summaryNoun: "habit")
      return try Self.loadHabitsSnapshot(db, date: date)
    }
  }

  /// Persist `orderedIDs` as the complete new display order of the reorderable
  /// set, atomically.
  ///
  /// `orderedIDs` must be a genuine permutation of the ids currently in scope —
  /// the rows matching `scopeWhere` (`lists` where `archived_at IS NULL`,
  /// `habits` where `archived = 0`). A duplicate id, an id outside the scope, or
  /// a missing id is rejected with `LorvexCoreError.unsupportedOperation` and no
  /// row is touched; the enclosing transaction rolls back, so a rejected or
  /// partly-failed reorder can never leave positions half-applied. On
  /// acceptance the rows take the positions ``ReorderPositions/assign(_:)``
  /// gives them: strictly increasing in the new order, with every row that can
  /// keep its position keeping it. Every changed row is version-stamped +
  /// enqueued through the standard LWW upsert path so its new order syncs like
  /// any other column, and a single changelog row summarizes the reorder.
  /// `table` and `scopeWhere` are caller-supplied literals (`lists` / `habits`),
  /// never user input.
  static func applyReorder(
    _ db: Database, hlc: HlcSession, deviceId: String, service: SwiftLorvexCoreService,
    table: String, scopeWhere: String, kind: EntityKind, entityType: String,
    orderedIDs: [String], summaryNoun: String
  ) throws {
    try validateReorderPermutation(
      db, table: table, scopeWhere: scopeWhere, orderedIDs: orderedIDs, summaryNoun: summaryNoun)

    // The permutation check guarantees every row exists and is in scope.
    let current = try orderedIDs.map { id in
      try Int64.fetchOne(db, sql: "SELECT position FROM \(table) WHERE id = ?", arguments: [id])
        ?? 0
    }
    let target = ReorderPositions.assign(current)

    let now = SyncTimestampFormat.syncTimestampNow()
    var changed: [String] = []
    for (index, id) in orderedIDs.enumerated() where current[index] != target[index] {
      try db.execute(
        sql: "UPDATE \(table) SET position = ?, updated_at = ? WHERE id = ?",
        arguments: [target[index], now, id])
      // `enqueueUpsert` re-reads the row (new position), mints the canonical HLC
      // version, LWW-stamps the row, and queues the envelope — so `position`
      // rides the same path as any edited field.
      try service.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: kind, entityId: id)
      changed.append(id)
    }
    guard !changed.isEmpty else { return }
    try service.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: "reorder", entityType: entityType, entityIds: changed,
        summary: "Reordered \(changed.count) \(summaryNoun)(s)"),
      deviceId: deviceId)
  }

  /// The position a row created now takes in `table`'s set (`scopeWhere`).
  ///
  /// A set the user has ordered by hand holds positions above zero, and a new
  /// row goes after its last one. A set no one has ordered keeps every row at
  /// zero, where the reads fall back to their own order (creation for lists,
  /// name for habits), and a new row joins it there.
  static func positionForNewRow(
    _ db: Database, table: String, scopeWhere: String
  ) throws -> Int64 {
    let last =
      try Int64.fetchOne(db, sql: "SELECT MAX(position) FROM \(table) WHERE \(scopeWhere)") ?? 0
    guard last > 0, last <= Int64.max - ReorderPositions.spacing else { return 0 }
    return last + ReorderPositions.spacing
  }

  /// Reject `orderedIDs` unless it is a genuine permutation of the ids currently
  /// matching `scopeWhere` in `table`: no duplicate, no id outside the set, and
  /// every in-scope id present exactly once. Messages report only counts (never
  /// raw ids) so they surface as clean validation errors.
  private static func validateReorderPermutation(
    _ db: Database, table: String, scopeWhere: String, orderedIDs: [String], summaryNoun: String
  ) throws {
    let requested = Set(orderedIDs)
    guard requested.count == orderedIDs.count else {
      throw LorvexCoreError.validation(
        field: nil,
        message:
          "Reorder received a duplicate \(summaryNoun) id; each \(summaryNoun) may appear at most once.")
    }

    let currentIDs = try String.fetchAll(
      db, sql: "SELECT id FROM \(table) WHERE \(scopeWhere)")
    let current = Set(currentIDs)

    let extra = requested.subtracting(current).count
    let missing = current.subtracting(requested).count
    guard extra == 0, missing == 0 else {
      throw LorvexCoreError.validation(
        field: nil,
        message: "Reorder must list every current \(summaryNoun) exactly once "
          + "(the set has \(current.count) \(summaryNoun)(s); received \(orderedIDs.count), "
          + "with \(missing) missing and \(extra) not part of the set).")
    }
  }
}
