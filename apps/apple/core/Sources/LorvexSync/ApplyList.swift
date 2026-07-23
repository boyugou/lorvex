import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Per-entity apply handler for the `list` aggregate root.
///
/// Conforms to ``EntityApplier`` for `entity_type == "list"`. The upsert path
/// scrubs + validates the list name / description / ai_notes and runs the shared
/// LWW-gated upsert. The delete path threads two aggregate-level invariants
/// (`at_least_one_list`, `tasks_reference_list`) ahead of a defense-in-depth LWW
/// gate, surfacing each refusal as the typed dispatch outcome so
/// `applyEnvelope` can defer (the at-least-one-list invariant) or permanently
/// reject the required inbox without minting a tombstone.
public struct ListApplier: EntityApplier {
  public init() {}

  public var handledEntityTypes: [String] { [EntityKind.list.asString] }

  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyList.applyListUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak)
    return .applied
  }

  public func applyDelete(
    _ db: Database, envelope: SyncEnvelope, applyTs: String
  ) throws -> EntityApplyOutcome {
    switch try ApplyList.applyListDelete(
      db, entityId: envelope.entityId, version: envelope.version.description, applyTs: applyTs)
    {
    case .applied:
      return .applied
    case let .skippedByInvariant(invariant):
      return .deleteSkippedByInvariant(invariant: invariant)
    case .requiredInbox:
      return .requiredInboxDeleteRejected
    case let .lwwRejected(localVersion):
      return .lwwRejected(localVersion: localVersion)
    }
  }
}

enum ApplyList {
  /// Outcome of ``applyListDelete``.
  enum ListDeleteOutcome: Equatable {
    /// The SQL DELETE ran (or no-op'd against an already-deleted row); the
    /// caller writes the tombstone.
    case applied
    /// An aggregate-level invariant guard refused the DELETE while leaving the
    /// row alive. The caller defers the envelope to `sync_pending_inbox` and
    /// does NOT write a tombstone.
    case skippedByInvariant(invariant: String)
    /// The canonical inbox is a permanent synced invariant, not a dependency
    /// hold that could become deletable after later envelopes arrive.
    case requiredInbox
    /// The defense-in-depth LWW gate refused the DELETE because the local row's
    /// version strictly dominates the envelope's. The caller surfaces this as a
    /// skip and does NOT mint a tombstone; the dispatcher records the loss to
    /// `sync_conflict_log`.
    case lwwRejected(localVersion: String)
  }

  /// The "at least one list" invariant — deleting the row would leave the device
  /// with zero lists, breaking task creation.
  static let invariantAtLeastOneList = "at_least_one_list"
  static func applyListUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak
  ) throws {
    let val = try ApplyJSON.parseObject(payload)

    // Unicode hygiene: scrub free-text list fields at the sync apply boundary.
    let nameOwned = ApplyAggregate.scrub(try ApplyJSON.requiredStr(val, "name", entity: "list"))
    if nameOwned.isEmpty {
      throw ApplyError.invalidPayload("list \(entityId) name is empty")
    }
    let nameLen = nameOwned.count
    if nameLen > ValidationLimits.maxTitleLength {
      throw ApplyError.invalidPayload(
        "list \(entityId) name is too long (\(nameLen) chars; max "
          + "\(ValidationLimits.maxTitleLength))")
    }
    let color = try ApplyJSON.optionalStr(val, "color", entity: "list")
    let icon = try ApplyJSON.optionalStr(val, "icon", entity: "list")
    let description = ApplyAggregate.scrubOpt(
      try ApplyJSON.optionalStr(val, "description", entity: "list"))
    if let d = description {
      if case let .failure(e) = ValidationText.validateBody(d) {
        throw ApplyError.invalidPayload(
          "list \(entityId) description failed validation: \(e.description)")
      }
    }
    let aiNotes = ApplyAggregate.scrubOpt(try ApplyJSON.optionalStr(val, "ai_notes", entity: "list"))
    // Soft-archive timestamp (nullable): a peer archiving or unarchiving a whole
    // list rides the LWW-gated list upsert like any other owned column, so the
    // archive state converges across devices.
    let archivedAt = try ApplyJSON.optionalStr(val, "archived_at", entity: "list")
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "list")
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "list")
    // Synced manual display order. A peer that predates the column omits it; in
    // that case preserve this device's current position instead of resetting it
    // to 0 — a bare `?? 0` would let a position-less envelope clobber an order
    // already set here. A genuinely new row with no incoming position starts at 0.
    let position: Int64
    if let incomingPosition = try ApplyJSON.optionalInt64(val, "position", entity: "list") {
      position = incomingPosition
    } else {
      position = try Int64.fetchOne(
        db, sql: "SELECT position FROM lists WHERE id = ?", arguments: [entityId]) ?? 0
    }

    let sql = LwwUpsertSpec(
      table: "lists",
      columns: SyncEntityDescriptor.require(.list).plainColumns,
      conflict: ["id"], tieBreak: tieBreak
    ).buildSQL()
    do {
      try db.execute(
        sql: sql,
        arguments: [
          "id": entityId, "name": nameOwned, "color": color, "icon": icon,
          "description": description, "ai_notes": aiNotes, "archived_at": archivedAt,
          "created_at": createdAt, "updated_at": updatedAt, "position": position,
          "version": version,
        ])
    } catch { throw ApplyError.lift(error) }
  }

  /// Apply a peer's `Delete{list:id}` envelope.
  ///
  /// Branch order: required-inbox rejection → absent-row no-op →
  /// `at_least_one_list` → defense-in-depth LWW gate. The LWW-reject arm does
  /// NOT log a conflict — the dispatcher does once it surfaces `lwwRejected`.
  static func applyListDelete(
    _ db: Database, entityId: String, version: String, applyTs: String
  ) throws -> ListDeleteOutcome {
    // Inbox is the canonical task fallback and must exist even when it is empty.
    // Reject before the absent-row fast path so a malformed peer delete can
    // never mint a tombstone that suppresses the seeded inbox upsert.
    if entityId == "inbox" {
      return .requiredInbox
    }

    // Absent row first: deleting a list this device never materialized is an
    // idempotent no-op that still advances the delete frontier (the caller writes
    // the tombstone), exactly like every other absent-row delete. The aggregate
    // invariants below (`at_least_one_list`, inbox-with-tasks) guard a row that is
    // actually PRESENT; firing it for a never-held list would park a
    // steady-state delete of a long-deleted list forever as a budget-exempt
    // aggregate-invariant HOLD — re-applying on every drain pass indefinitely
    // (holds are exempt from the horizon reap). `inbox` was rejected above even
    // if corruption or a partial restore removed its local row.
    let rowExists: Int64
    do {
      rowExists = try Int64.fetchOne(
        db, sql: "SELECT EXISTS(SELECT 1 FROM lists WHERE id = ?)", arguments: [entityId]) ?? 0
    } catch { throw ApplyError.lift(error) }
    if rowExists == 0 {
      return .applied
    }

    // Prevent deleting the last list — at least one must exist for task creation.
    let totalLists: Int64
    do {
      totalLists = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM lists") ?? 0
    } catch { throw ApplyError.lift(error) }
    if totalLists <= 1 {
      return .skippedByInvariant(invariant: invariantAtLeastOneList)
    }

    // Defense-in-depth LWW guard, evaluated in Swift against parsed HLCs rather
    // than a `:version >= version` SQL byte compare. Reachable from the
    // shadow-promotion replay path (`>=` semantics), so route with `.allowEqual`.
    switch try ApplyAggregate.evaluateDeleteLww(
      db, readVersionSQL: "SELECT version FROM lists WHERE id = ?", entityId: entityId,
      incomingVersion: version, tieBreak: .allowEqual)
    {
    case .apply:
      do {
        try db.execute(sql: "DELETE FROM lists WHERE id = :id", arguments: ["id": entityId])
      } catch { throw ApplyError.lift(error) }
      return .applied
    case let .reject(localVersion, _):
      // The `lww` conflict-log row is written by the dispatcher's skip path once
      // it surfaces `lwwRejected`, so we MUST NOT log here too.
      return .lwwRejected(localVersion: localVersion)
    }
  }
}
