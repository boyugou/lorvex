import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Manual display-order persistence for the lists catalog and habits board.
///
/// `position` is an ordinary synced column on the `lists` / `habits` rows (LWW
/// like every other field), so reordering on one device converges on peers
/// through the normal outbox → apply path.
///
/// A reorder is a full-permutation operation: `orderedIDs` must be exactly the
/// current reorderable set (the active, non-archived rows) — every id present,
/// none extra, none duplicated. The whole permutation is validated and then
/// applied inside a single `withWrite` transaction, so the rewritten positions
/// stay dense (`0…n-1`, no collisions, no gaps) and either commit as one new
/// ordering or roll back entirely. Only the rows whose position actually
/// changes are version-stamped + enqueued, so a no-op drag syncs nothing.
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
  /// partly-failed reorder can never leave positions half-applied, collided, or
  /// gapped. On acceptance each id's synced `position` is rewritten to its index
  /// (`0…n-1`, dense), touching only the rows whose position actually changes.
  /// Every changed row is version-stamped + enqueued through the standard LWW
  /// upsert path so its new order syncs like any other column, and a single
  /// changelog row summarizes the reorder. `table` and `scopeWhere` are
  /// caller-supplied literals (`lists` / `habits`), never user input.
  static func applyReorder(
    _ db: Database, hlc: HlcSession, deviceId: String, service: SwiftLorvexCoreService,
    table: String, scopeWhere: String, kind: EntityKind, entityType: String,
    orderedIDs: [String], summaryNoun: String
  ) throws {
    try validateReorderPermutation(
      db, table: table, scopeWhere: scopeWhere, orderedIDs: orderedIDs, summaryNoun: summaryNoun)

    let now = SyncTimestampFormat.syncTimestampNow()
    var changed: [String] = []
    for (index, id) in orderedIDs.enumerated() {
      let position = Int64(index)
      // The permutation check guarantees the row exists and is in scope.
      guard
        let current = try Int64.fetchOne(
          db, sql: "SELECT position FROM \(table) WHERE id = ?", arguments: [id])
      else { continue }
      if current == position { continue }
      try db.execute(
        sql: "UPDATE \(table) SET position = ?, updated_at = ? WHERE id = ?",
        arguments: [position, now, id])
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
