import GRDB
import LorvexDomain

/// Canonical-row pruning for state proven absent by an authoritative CloudKit
/// observation. This deliberately bypasses the ordinary Delete applier: remote
/// absence must not synthesize a tombstone or outbound Delete that could recreate
/// the physically absent CloudKit record.
enum AuthoritativeAbsence {
  /// The amount of remote inventory required before a physical CloudKit delete
  /// may change canonical state for one identity.
  ///
  /// A single deleted record proves only that exact CloudKit slot is absent. It
  /// does not prove that independently-synced children, edges, or referring
  /// aggregates are absent too. Aggregate roots therefore require a complete
  /// inventory pass; otherwise SQLite FK triggers could silently cascade rows or
  /// re-home tasks without producing typed outbound repairs. Independent leaves
  /// can be pruned exactly, while permanent local invariants are re-emitted.
  enum IncrementalPhysicalDeletionPolicy: Sendable, Equatable {
    case exactPrune
    case reassertInvariant
    case requireCompleteInventory
  }

  enum PruneResult: Sendable, Equatable {
    case unchanged
    case removed(EntityKind)
    /// The canonical inbox is a permanent relational invariant. Its remote
    /// record may be absent, but its local row must instead be re-emitted.
    case requiredInboxNeedsReassertion
    /// The product timezone is the shared calendar-day authority. Physical
    /// CloudKit absence must preserve the local row and re-author it at a fresh
    /// dominating HLC rather than making each peer fall back to its device zone.
    case requiredTimezoneNeedsReassertion
  }

  static func incrementalPhysicalDeletionPolicy(
    entityType: String, entityId: String
  ) throws -> IncrementalPhysicalDeletionPolicy {
    guard let kind = EntityKind.parse(entityType), kind.isSyncableKind else {
      throw FutureRecordHoldError.invalidPreservedIntent
    }
    if kind == .list && entityId == "inbox" {
      return .reassertInvariant
    }
    if kind == .preference && entityId == PreferenceKeys.prefTimezone {
      return .reassertInvariant
    }
    switch kind {
    case .task, .list, .habit, .tag, .calendarEvent:
      return .requireCompleteInventory
    case .calendarSeriesCutover, .entityRedirect:
      return .reassertInvariant
    case .preference, .memory, .dailyReview, .currentFocus, .focusSchedule,
      .taskReminder, .taskChecklistItem, .habitReminderPolicy, .aiChangelog,
      .taskTag, .taskDependency, .taskCalendarEventLink,
      .habitCompletion:
      return .exactPrune
    case .deviceState, .importSession:
      throw FutureRecordHoldError.invalidPreservedIntent
    }
  }

  /// Permanent redirects and their terminal rows form one relational
  /// invariant. A physical CloudKit deletion of the target must therefore
  /// re-author the live target instead of pruning it or waiting for a complete
  /// inventory; keeping the alias while removing its target would make every
  /// later source mutation impossible to resolve.
  static func isPermanentRedirectTarget(
    _ db: Database, entityType: String, entityId: String
  ) throws -> Bool {
    guard let kind = EntityKind.parse(entityType), kind.isSyncableKind else {
      throw FutureRecordHoldError.invalidPreservedIntent
    }
    switch kind {
    case .tag, .habit, .memory, .habitReminderPolicy:
      return try Bool.fetchOne(
        db,
        sql: """
          SELECT EXISTS(
            SELECT 1 FROM sync_entity_redirects
            WHERE source_type = ? AND target_id = ?
          )
          """,
        arguments: [kind.asString, entityId]) ?? false
    default:
      return false
    }
  }

  static func prune(
    _ db: Database, entityType: String, entityId: String
  ) throws -> PruneResult {
    guard let kind = EntityKind.parse(entityType), kind.isSyncableKind else {
      throw FutureRecordHoldError.invalidPreservedIntent
    }

    if kind == .list, entityId == "inbox" {
      try clearIdentityMetadata(db, entityType: entityType, entityId: entityId)
      return .requiredInboxNeedsReassertion
    }
    if kind == .preference, entityId == PreferenceKeys.prefTimezone {
      try clearIdentityMetadata(db, entityType: entityType, entityId: entityId)
      return .requiredTimezoneNeedsReassertion
    }

    let removed: Bool
    if let (table, primaryKey) = kind.tablePk {
      ValidationSQL.assertSafeSQLIdentifier(table)
      ValidationSQL.assertSafeSQLIdentifier(primaryKey)
      try db.execute(
        sql: "DELETE FROM \(table) WHERE \(primaryKey) = ?",
        arguments: [entityId])
      removed = db.changesCount > 0
    } else {
      removed = try pruneNonSimpleIdentity(
        db, kind: kind, entityId: entityId)
    }

    try clearIdentityMetadata(db, entityType: entityType, entityId: entityId)
    return removed ? .removed(kind) : .unchanged
  }

  private static func pruneNonSimpleIdentity(
    _ db: Database, kind: EntityKind, entityId: String
  ) throws -> Bool {
    if kind == .aiChangelog {
      try db.execute(
        sql: "DELETE FROM ai_changelog WHERE id = ?", arguments: [entityId])
      return db.changesCount > 0
    }
    if kind == .entityRedirect {
      guard let redirect = try EntityRedirect.get(db, wireEntityId: entityId) else {
        return false
      }
      try db.execute(
        sql: "DELETE FROM sync_entity_redirects WHERE source_type = ? AND source_id = ?",
        arguments: [redirect.sourceType.asString, redirect.sourceId])
      return db.changesCount > 0
    }

    guard case .success((let left, let right)) =
      CompositeEdge.splitCompositeEdgeId(entityId)
    else {
      throw FutureRecordHoldError.invalidPreservedIntent
    }
    let storage: (table: String, left: String, right: String)
    switch kind {
    case .taskTag:
      storage = ("task_tags", "task_id", "tag_id")
    case .taskDependency:
      storage = ("task_dependencies", "task_id", "depends_on_task_id")
    case .taskCalendarEventLink:
      storage = ("task_calendar_event_links", "task_id", "calendar_event_id")
    case .habitCompletion:
      storage = ("habit_completions", "habit_id", "completed_date")
    default:
      throw FutureRecordHoldError.invalidPreservedIntent
    }
    try db.execute(
      sql: "DELETE FROM \(storage.table) WHERE \(storage.left) = ? AND \(storage.right) = ?",
      arguments: [left, right])
    return db.changesCount > 0
  }

  static func clearIdentityMetadata(
    _ db: Database, entityType: String, entityId: String
  ) throws {
    try clearContradictoryDeathMetadata(
      db, entityType: entityType, entityId: entityId)
    try db.execute(
      sql: "DELETE FROM sync_payload_shadow WHERE entity_type = ? AND entity_id = ?",
      arguments: [entityType, entityId])
  }

  /// Remove only metadata that contradicts a live row. Reasserting a local
  /// winner must retain its payload shadow: those bytes are the sole copy of
  /// forward-schema fields and are overlaid by the normal outbox writer.
  static func clearContradictoryDeathMetadata(
    _ db: Database, entityType: String, entityId: String
  ) throws {
    try db.execute(
      sql: "DELETE FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
      arguments: [entityType, entityId])
  }
}
