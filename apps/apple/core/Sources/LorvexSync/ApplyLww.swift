import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// LWW (last-writer-wins) machinery and FK preflight shared by every apply
/// handler.
///
/// The LWW tie-break enum, SQL comparator, upsert-spec SQL builder, merge-winner
/// version stamper, LWW-gated delete, and the foreign-key preflight + local-
/// version lookup live here so every per-entity applier picks up the same
/// comparison and the dispatcher shares one preflight.

/// LWW tie-break policy used by every apply handler.
///
/// At the SQL layer it picks the comparison operator (`>` vs `>=`); at the apply
/// layer it routes an envelope into the strict-LWW or replay path.
public enum LwwTieBreak: Sendable, Equatable {
  /// Strict LWW — the inbound version must be strictly greater than the local
  /// row's to win. Same-version envelopes are rejected as no-ops. Default for
  /// live envelope apply.
  case rejectEqual
  /// Allow same-version envelopes to land idempotently. Used by replay /
  /// repair paths whose payload is already expected to match local state.
  case allowEqual
  /// Shadow promotion has separately proven that the live row and shadow share
  /// one exact base version. Its reconstructed full payload is authoritative at
  /// that equal version because the live projection may have truncated fields
  /// this build only now understands. SQL semantics remain `>=`; grouped
  /// aggregates use the distinct case to repair equal-clock projection loss
  /// without weakening ordinary replay or live collision joins.
  case shadowPromotion

  /// SQL comparison operator for a `WHERE excluded.version <op> table.version`
  /// clause.
  public var sqlOp: String {
    switch self {
    case .rejectEqual: return ">"
    case .allowEqual, .shadowPromotion: return ">="
    }
  }

  public var allowsEqual: Bool { self != .rejectEqual }

  public init(allowEqualVersions: Bool) {
    self = allowEqualVersions ? .allowEqual : .rejectEqual
  }
}

/// Choose the `WHERE excluded.version <op> table.version` clause for the LWW
/// upsert. ``LwwTieBreak/allowEqual`` is used by re-emit / replay paths where an
/// identical envelope must be idempotent rather than rejected as a no-op.
func versionCmp(_ tieBreak: LwwTieBreak) -> String { tieBreak.sqlOp }

/// Spec for an LWW-gated `INSERT … ON CONFLICT DO UPDATE` against an apply-time
/// aggregate / edge / child / day-scoped table.
///
/// `columns` lists every column in the INSERT in declaration order; `version`
/// MUST be last. The DO UPDATE SET clause omits the conflict columns and writes
/// every other column as `col=excluded.col`. The placeholder names in the
/// VALUES clause are `:<col>` — callers bind named parameters matching.
///
/// `createdAtFloor` opts the table's `created_at` into the min-register
/// contract (see ``ApplyLww/foldCreatedAtFloor(_:table:pkValue:incomingCreatedAt:)``):
/// a winning payload folds `min(existing, incoming)` instead of overwriting, so
/// a payload remapped through a permanent alias can never raise the canonical
/// row's creation floor.
struct LwwUpsertSpec {
  let table: String
  /// Every column in the INSERT, in declaration order. `version` must be last.
  let columns: [String]
  /// One or more conflict columns matching a UNIQUE / PRIMARY KEY constraint.
  let conflict: [String]
  let tieBreak: LwwTieBreak
  /// When true, the DO UPDATE branch writes
  /// `created_at = min(<table>.created_at, excluded.created_at)`.
  var createdAtFloor: Bool = false

  /// Render the full LWW upsert SQL string.
  func buildSQL() -> String {
    precondition(columns.last == "version", "LwwUpsertSpec.columns must end with `version`")
    precondition(!conflict.isEmpty, "LwwUpsertSpec.conflict must name at least one column")
    precondition(
      !createdAtFloor || columns.contains("created_at"),
      "LwwUpsertSpec.createdAtFloor requires a created_at column")
    let cmp = versionCmp(tieBreak)
    var sql = "INSERT INTO "
    sql += table
    sql += " ("
    sql += columns.joined(separator: ", ")
    sql += ") VALUES ("
    sql += columns.map { ":\($0)" }.joined(separator: ", ")
    sql += ") ON CONFLICT("
    sql += conflict.joined(separator: ", ")
    sql += ") DO UPDATE SET "
    let conflictSet = Set(conflict)
    sql += columns.filter { !conflictSet.contains($0) }.map { column in
      if createdAtFloor && column == "created_at" {
        return "created_at=min(\(table).created_at, excluded.created_at)"
      }
      return "\(column)=excluded.\(column)"
    }
    .joined(separator: ", ")
    sql += " WHERE excluded.version "
    sql += cmp
    sql += " "
    sql += table
    sql += ".version"
    return sql
  }
}

enum ApplyLww {
  /// Stamp `mergeVersion` onto a merge-winner aggregate row iff `mergeVersion`
  /// strictly dominates the row's current version under the canonical-preferring
  /// LWW policy. Returns the number of rows updated (0 if missing or LWW-rejected).
  ///
  /// The taint policy is the shared ``canonicalPreferringDominates(incoming:existing:)``
  /// — the same tiebreak the tombstone monotonicity gate and SCC edge apply use:
  /// two canonical HLCs compare by their typed ordering; when exactly one side
  /// parses, the canonical side wins regardless of bytes (a canonical
  /// `mergeVersion` clears a tainted row; a tainted `mergeVersion` is refused
  /// against a canonical row); neither parsing falls back to a raw byte compare.
  ///
  /// `pkColumn` / `pkValue` come from an in-module closed set, so the
  /// interpolated SQL is safe.
  @discardableResult
  static func stampMergeWinnerVersion(
    _ db: Database, table: String, pkColumn: String, pkValue: String, mergeVersion: String
  ) throws -> Int {
    let existing: String?
    do {
      existing = try String.fetchOne(
        db, sql: "SELECT version FROM \(table) WHERE \(pkColumn) = ?", arguments: [pkValue])
    } catch { throw ApplyError.lift(error) }
    guard let existing else { return 0 }

    let shouldWrite = canonicalPreferringDominates(incoming: mergeVersion, existing: existing)
    if !shouldWrite { return 0 }
    do {
      try db.execute(
        sql: "UPDATE \(table) SET version = ? WHERE \(pkColumn) = ?",
        arguments: [mergeVersion, pkValue])
    } catch { throw ApplyError.lift(error) }
    return db.changesCount
  }

  /// The aggregate tables whose `created_at` is a min-register (`memories` has
  /// no `created_at` column and every other syncable table keeps plain LWW
  /// `created_at` semantics — only the alias-merge families can observe two
  /// different creation floors for one row identity).
  static func createdAtFloorTable(for kind: EntityKind) -> String? {
    switch kind {
    case .tag: return "tags"
    case .habit: return "habits"
    case .habitReminderPolicy: return "habit_reminder_policies"
    default: return nil
    }
  }

  /// Fold a version-skipped upsert's creation floor before the envelope is
  /// discarded. The pre-dispatch LWW gates (plain and redirect-remapped) are
  /// the only terminals where a stale payload would otherwise vanish without
  /// its `created_at` entering the min-register; a stale alias-remapped source
  /// payload can be the only witness of the canonical floor this peer ever
  /// receives. No-op for deletes, non-register kinds, and payloads without a
  /// string `created_at`.
  static func foldSkippedUpsertCreatedAtFloor(
    _ db: Database, envelope: SyncEnvelope
  ) throws {
    guard envelope.operation == .upsert,
      let table = createdAtFloorTable(for: envelope.entityType),
      case .object(let map)? = JSONValue.parse(envelope.payload),
      case .string(let createdAt)? = map["created_at"]
    else { return }
    try foldCreatedAtFloor(
      db, table: table, pkValue: envelope.entityId, incomingCreatedAt: createdAt)
  }

  /// Fold one observed `created_at` into an aggregate row's creation floor:
  /// `created_at := min(created_at, incoming)`, independent of the LWW version
  /// gate. `tags` / `habits` / `habit_reminder_policies` treat `created_at` as a
  /// min-register over every payload ever addressed to the row's identity —
  /// including payloads remapped onto it through a permanent alias, which carry
  /// the alias source's creation time. The min-lattice is commutative,
  /// idempotent, and needs only envelope-local information, so every arrival
  /// order (alias-first, alias-late, or no local collapse at all) converges to
  /// the same floor even when a peer has never materialized the row's original
  /// authored payload. A version-rejected envelope still folds: rejection means
  /// its CONTENT lost, but the creation floor it witnessed is identity metadata,
  /// not content.
  ///
  /// `table` comes from an in-module closed set, so the interpolated SQL is safe.
  static func foldCreatedAtFloor(
    _ db: Database, table: String, pkValue: String, incomingCreatedAt: String
  ) throws {
    do {
      try db.execute(
        sql: "UPDATE \(table) SET created_at = ? WHERE id = ? AND created_at > ?",
        arguments: [incomingCreatedAt, pkValue, incomingCreatedAt])
    } catch { throw ApplyError.lift(error) }
  }

  /// LWW-gated DELETE against an apply-time edge / child table. Routes the
  /// version comparison through ``compareVersionsWithFallback(_:_:)`` so
  /// parse-failure semantics align with the upsert path. Returns the number of
  /// rows deleted (0 if absent or LWW-rejected).
  @discardableResult
  static func lwwGatedDelete(
    _ db: Database, table: String, pkColumns: [String], pkValues: [String],
    incomingVersion: String
  ) throws -> Int {
    precondition(
      !pkColumns.isEmpty && pkColumns.count == pkValues.count,
      "lwwGatedDelete: pkColumns and pkValues must be non-empty and equal length")
    let whereClause = pkColumns.enumerated().map { "\($0.element) = ?" }.joined(separator: " AND ")
    let local: String?
    do {
      local = try String.fetchOne(
        db, sql: "SELECT version FROM \(table) WHERE \(whereClause)",
        arguments: StatementArguments(pkValues))
    } catch { throw ApplyError.lift(error) }
    guard let local else { return 0 }

    if compareVersionsWithFallback(incomingVersion, local) == .orderedAscending {
      // Local strictly newer (or canonical local vs tainted incoming): refuse.
      return 0
    }
    do {
      try db.execute(
        sql: "DELETE FROM \(table) WHERE \(whereClause)",
        arguments: StatementArguments(pkValues))
    } catch { throw ApplyError.lift(error) }
    return db.changesCount
  }

  // MARK: - Local-version lookup

  /// Canonical minimum HLC — physical_ms 0, counter 0, all-zero device suffix.
  /// Sorts strictly below every real HLC under both the typed and raw-byte
  /// orderings, so a row reset to it yields to any canonical inbound version.
  /// Matches the schema's seed version for the `inbox` list.
  static let zeroVersionHlc = "0000000000000_0000_0000000000000000"

  /// Current local version (HLC string) for an entity. `nil` if absent or for
  /// kinds with no `version` column (append-only / local-only).
  static func getLocalVersion(_ db: Database, entityType: String, entityId: String) throws
    -> String?
  {
    guard let loc = versionRowLocation(entityType: entityType, entityId: entityId) else {
      return nil
    }
    do {
      return try String.fetchOne(
        db, sql: "SELECT version FROM \(loc.table) WHERE \(loc.whereClause)",
        arguments: StatementArguments(loc.pkValues))
    } catch { throw ApplyError.lift(error) }
  }

  /// Reset an entity's corrupt (unparseable) local `version` to the zero HLC so a
  /// canonical inbound UPSERT wins the per-entity handler's in-SQL
  /// `:version <op> version` byte-compare gate. Returns `true` when a corrupt
  /// version was rewritten, `false` when the row is absent, versionless, or
  /// already canonical.
  ///
  /// The outer LWW gate treats an unparseable local version as "absent" and admits
  /// the envelope (a canonical version dominates a non-canonical one under the
  /// canonical-preferring policy). But every upsert handler RE-gates the write
  /// against the STORED bytes: a corrupt string that lex-sorts above canonical
  /// HLCs (letters sort above digits) makes the UPDATE match zero rows while apply
  /// still reports `.applied`, leaving the row permanently deaf to inbound sync.
  /// Rewriting the taint to the zero HLC — which sorts below every real HLC — lets
  /// the byte-compare gate admit the canonical envelope and re-stamp the row.
  ///
  /// Upsert-only: the delete path keeps its taint-refuses-delete safety in
  /// ``ApplyAggregate/evaluateDeleteLww(_:readVersionSQL:entityId:incomingVersion:tieBreak:)``,
  /// so this must never run before a delete handler.
  @discardableResult
  static func resetCorruptLocalVersion(_ db: Database, entityType: String, entityId: String) throws
    -> Bool
  {
    guard let local = try getLocalVersion(db, entityType: entityType, entityId: entityId) else {
      return false
    }
    if (try? Hlc.parseCanonical(local)) != nil { return false }
    guard let loc = versionRowLocation(entityType: entityType, entityId: entityId) else {
      return false
    }
    do {
      if EntityKind.parse(entityType) == .calendarEvent {
        // Calendar register clocks are constrained to the row high-water mark.
        // Clear the invalid row and group clocks together so the canonical
        // inbound snapshot can replace them without creating an intermediate
        // CHECK violation.
        try db.execute(
          sql: """
            UPDATE calendar_events
               SET version = ?,
                   recurrence_generation = CASE
                     WHEN recurrence_generation IS NULL THEN NULL ELSE ? END,
                   content_version = CASE WHEN series_id IS NULL THEN ? ELSE NULL END,
                   recurrence_topology_version = CASE
                     WHEN series_id IS NULL THEN ? ELSE NULL END
             WHERE id = ?
          """,
          arguments: [zeroVersionHlc, zeroVersionHlc, zeroVersionHlc, zeroVersionHlc, entityId])
      } else if EntityKind.parse(entityType) == .task {
        // Task register clocks and successor authorization clocks are likewise
        // bounded by the row high-water mark. Reset the entire clock vector in
        // one statement so no intermediate CHECK can fail.
        try db.execute(
          sql: """
            UPDATE tasks
               SET version = ?, content_version = ?, schedule_version = ?,
                   lifecycle_version = ?, archive_version = ?,
                   spawned_from_version = CASE
                     WHEN spawned_from_version IS NULL THEN NULL ELSE ? END
             WHERE id = ?
            """,
          arguments: [
            zeroVersionHlc, zeroVersionHlc, zeroVersionHlc, zeroVersionHlc,
            zeroVersionHlc, zeroVersionHlc, entityId,
          ])
      } else {
        try db.execute(
          sql: "UPDATE \(loc.table) SET version = ? WHERE \(loc.whereClause)",
          arguments: StatementArguments([zeroVersionHlc] + loc.pkValues))
      }
    } catch { throw ApplyError.lift(error) }
    ErrorLog.appendBestEffort(
      db, source: "sync.apply.upsert_corrupt_local_version_reset",
      message: "reset corrupt local version \(applyDebugQuoted(local)) to the zero HLC for "
        + "\(entityType):\(entityId) so a canonical inbound upsert can land",
      details: nil, level: "warning")
    return true
  }

  /// Reset one existing row below every canonical wire HLC before an explicitly
  /// authoritative snapshot is replayed.
  ///
  /// This is deliberately NOT part of ordinary inbound apply: normal sync is
  /// LWW and must preserve a newer local edit. An over-window device has instead
  /// chosen the complete CloudKit snapshot as truth. Replaying that snapshot
  /// through the same per-entity appliers still gives us all validation,
  /// FK/cascade, merge, and payload-shadow behavior. Grouped-register entities
  /// are removed outright because their group clocks are constrained below `version`; a
  /// partial zeroing would either violate that invariant or let a pre-adoption
  /// group clock defeat the authoritative row. The surrounding savepoint makes
  /// the remove-and-rebuild atomic.
  /// Returns false when the row is already absent or has no version column.
  @discardableResult
  static func resetVersionForAuthoritativeSnapshot(
    _ db: Database, entityType: String, entityId: String
  ) throws -> Bool {
    guard let loc = versionRowLocation(entityType: entityType, entityId: entityId) else {
      return false
    }
    do {
      if let kind = EntityKind.parse(entityType), kind == .calendarEvent || kind == .task {
        try db.execute(
          sql: "DELETE FROM \(loc.table) WHERE \(loc.whereClause)",
          arguments: StatementArguments(loc.pkValues))
      } else {
        try db.execute(
          sql: "UPDATE \(loc.table) SET version = ? WHERE \(loc.whereClause)",
          arguments: StatementArguments([zeroVersionHlc] + loc.pkValues))
      }
    } catch { throw ApplyError.lift(error) }
    return db.changesCount > 0
  }

  /// The `(table, whereClause, pkValues)` that locate an entity's row for version
  /// lookups / resets, or `nil` for kinds with no `version` column (append-only /
  /// local-only) or an edge whose composite `{a}:{b}` entity_id fails to split.
  /// Single-PK kinds map `entityId` onto their PK column; edges split it into the
  /// two-column primary key.
  private static func versionRowLocation(entityType: String, entityId: String)
    -> (table: String, whereClause: String, pkValues: [String])?
  {
    guard let kind = EntityKind.parse(entityType) else { return nil }
    func single(_ table: String, _ pkColumn: String)
      -> (table: String, whereClause: String, pkValues: [String])
    {
      (table, "\(pkColumn) = ?", [entityId])
    }
    func edge(_ table: String, _ leftColumn: String, _ rightColumn: String)
      -> (table: String, whereClause: String, pkValues: [String])?
    {
      guard case let .success((left, right)) = CompositeEdge.splitCompositeEdgeId(entityId) else {
        return nil
      }
      return (table, "\(leftColumn) = ? AND \(rightColumn) = ?", [left, right])
    }
    switch kind {
    case .task: return single("tasks", "id")
    case .list: return single("lists", "id")
    case .habit: return single("habits", "id")
    case .tag: return single("tags", "id")
    case .calendarEvent: return single("calendar_events", "id")
    case .calendarSeriesCutover: return single("calendar_series_cutovers", "id")
    case .preference: return single("preferences", "key")
    case .memory: return single("memories", "id")
    case .dailyReview: return single("daily_reviews", "date")
    case .currentFocus: return single("current_focus", "date")
    case .focusSchedule: return single("focus_schedule", "date")
    case .taskReminder: return single("task_reminders", "id")
    case .taskChecklistItem: return single("task_checklist_items", "id")
    case .habitReminderPolicy: return single("habit_reminder_policies", "id")
    case .taskTag: return edge("task_tags", "task_id", "tag_id")
    case .taskDependency: return edge("task_dependencies", "task_id", "depends_on_task_id")
    case .taskCalendarEventLink:
      return edge("task_calendar_event_links", "task_id", "calendar_event_id")
    case .habitCompletion: return edge("habit_completions", "habit_id", "completed_date")
    case .aiChangelog, .entityRedirect, .deviceState, .importSession: return nil
    }
  }
}

/// Foreign-key preflight for inbound envelope apply.
///
/// Edge FK preflight always derives FK targets from `entity_id` (canonical
/// `{a}:{b}`) and additionally requires the payload FK fields to agree with
/// `entity_id`. A deferral
/// returns the missing parent so the caller can park the envelope in the
/// pending inbox.
enum ApplyFk {
  /// Check FK dependencies before INSERT. Returns the missing parent
  /// `(kind, id)` when a required FK target does not exist locally; `nil` when
  /// all deps are present.
  static func checkFkDependencies(
    _ db: Database, entityType: String, entityId: String, payload: String
  ) throws -> (EntityKind, String)? {
    let envelopeKind = EntityKind.parse(entityType)
    for (dependencyKind, dependencyID) in try requiredDependencies(
      entityType: entityType, entityId: entityId, payload: payload)
    {
      if try dependencyExists(db, kind: dependencyKind, id: dependencyID) {
        continue
      }
      // A redirect target that is already ordinarily deleted is a satisfied
      // dependency: the alias remains permanent and causes every stale source
      // write to land on (and lose to) that target death barrier.
      if envelopeKind == .entityRedirect,
        try Tombstone.getTombstone(
          db, entityType: dependencyKind.asString, entityId: dependencyID) != nil
      {
        continue
      }
      // A task whose list has an active tombstone is deliberately
      // handled by ApplyTask's inbox fallback. Preserve that established
      // behavior instead of parking it on an impossible dependency.
      if envelopeKind == .task, dependencyKind == .list,
        try Tombstone.getTombstone(
          db, entityType: EntityName.list, entityId: dependencyID) != nil
      {
        continue
      }
      return (dependencyKind, dependencyID)
    }
    return nil
  }

  /// Return every hard FK dependency encoded by one upsert. This is the shared
  /// structural source for both inbound preflight and authoritative-snapshot
  /// local-intent dependency closure; keeping those paths together prevents a
  /// newly added child/edge kind from being accepted by ordinary sync but lost
  /// during remote-authoritative adoption.
  static func requiredDependencies(
    entityType: String, entityId: String, payload: String
  ) throws -> [(EntityKind, String)] {
    let obj = try ApplyJSON.parseObject(payload)
    guard let kind = EntityKind.parse(entityType) else { return [] }
    switch kind {
    case .entityRedirect:
      let redirect = try EntityRedirect.decodePayload(
        wireEntityId: entityId, payload: payload)
      return [(redirect.sourceType, redirect.targetId)]
    case .taskTag:
      let (taskId, tagId) = try splitEdgeId(entityType, entityId)
      try requireEdgeFieldMatches(entityType, obj, "task_id", taskId)
      try requireEdgeFieldMatches(entityType, obj, "tag_id", tagId)
      return [(.task, taskId), (.tag, tagId)]
    case .taskDependency:
      let (taskId, dep) = try splitEdgeId(entityType, entityId)
      try requireEdgeFieldMatches(entityType, obj, "task_id", taskId)
      try requireEdgeFieldMatches(entityType, obj, "depends_on_task_id", dep)
      return [(.task, taskId), (.task, dep)]
    case .taskCalendarEventLink:
      let (taskId, eventId) = try splitEdgeId(entityType, entityId)
      try requireEdgeFieldMatches(entityType, obj, "task_id", taskId)
      try requireEdgeFieldMatches(entityType, obj, "calendar_event_id", eventId)
      return [(.task, taskId), (.calendarEvent, eventId)]
    case .habitCompletion:
      let (habitId, date) = try splitEdgeId(entityType, entityId)
      try requireEdgeFieldMatches(entityType, obj, "habit_id", habitId)
      try requireEdgeFieldMatches(entityType, obj, "completed_date", date)
      return [(.habit, habitId)]
    case .taskReminder, .taskChecklistItem:
      let taskId = try requiredFkStr(obj, entityType, "task_id")
      return [(.task, taskId)]
    case .habitReminderPolicy:
      let habitId = try requiredFkStr(obj, entityType, "habit_id")
      return [(.habit, habitId)]
    case .task:
      // list_id FK if present (empty treated as missing — apply resolves the
      // fallback list in that case).
      if case let .string(listId)? = obj["list_id"], !listId.isEmpty {
        return [(.list, listId)]
      }
      return []
    case .calendarEvent:
      if case let .string(cutoverId)? = obj["series_cutover_id"] {
        return [(.calendarSeriesCutover, cutoverId)]
      }
      return []
    case .list, .tag, .habit, .calendarSeriesCutover, .preference, .memory,
      .dailyReview, .currentFocus, .focusSchedule,
      .aiChangelog, .deviceState,
      .importSession:
      return []
    }
  }

  private static func dependencyExists(
    _ db: Database, kind: EntityKind, id: String
  ) throws -> Bool {
    switch kind {
    case .task: return try rowExists(db, "tasks", "id", id)
    case .tag: return try rowExists(db, "tags", "id", id)
    case .habit: return try rowExists(db, "habits", "id", id)
    case .list: return try rowExists(db, "lists", "id", id)
    case .calendarEvent: return try rowExists(db, "calendar_events", "id", id)
    case .calendarSeriesCutover:
      return try rowExists(db, "calendar_series_cutovers", "id", id)
    case .memory: return try rowExists(db, "memories", "id", id)
    case .habitReminderPolicy:
      return try rowExists(db, "habit_reminder_policies", "id", id)
    default:
      throw ApplyError.db(
        "invalid FK dependency kind \(kind.asString) for \(id)")
    }
  }

  private static func splitEdgeId(_ entityType: String, _ entityId: String) throws -> (
    String, String
  ) {
    switch CompositeEdge.splitCompositeEdgeId(entityId) {
    case let .success(pair):
      return pair
    case let .failure(err):
      throw ApplyError.invalidPayload("edge \(entityType) entity_id invalid: \(err.description)")
    }
  }

  private static func requireEdgeFieldMatches(
    _ entityType: String, _ obj: [String: JSONValue], _ field: String, _ expected: String
  ) throws {
    if case let .string(actual)? = obj[field], actual != expected {
      throw ApplyError.invalidPayload(
        "edge \(entityType) payload.\(field) \(applyDebugQuoted(actual)) does not match "
          + "entity_id half \(applyDebugQuoted(expected)) — payload-vs-entity_id mismatch")
    }
  }

  private static func requiredFkStr(
    _ obj: [String: JSONValue], _ entityType: String, _ field: String
  ) throws -> String {
    guard case let .string(s)? = obj[field] else {
      throw ApplyError.invalidPayload(
        "invalid \(entityType) payload: missing string field \(field)")
    }
    return s
  }

  /// Existence check by PK against a closed set of (table, column) pairs.
  static func rowExists(_ db: Database, _ table: String, _ pkCol: String, _ pkVal: String) throws
    -> Bool
  {
    let sql: String
    switch (table, pkCol) {
    case ("tasks", "id"): sql = "SELECT 1 FROM tasks WHERE id = ?"
    case ("tags", "id"): sql = "SELECT 1 FROM tags WHERE id = ?"
    case ("habits", "id"): sql = "SELECT 1 FROM habits WHERE id = ?"
    case ("lists", "id"): sql = "SELECT 1 FROM lists WHERE id = ?"
    case ("calendar_events", "id"): sql = "SELECT 1 FROM calendar_events WHERE id = ?"
    case ("calendar_series_cutovers", "id"):
      sql = "SELECT 1 FROM calendar_series_cutovers WHERE id = ?"
    default:
      throw ApplyError.db("invalid FK preflight target (\(table), \(pkCol))")
    }
    do {
      return try Int.fetchOne(db, sql: sql, arguments: [pkVal]) != nil
    } catch { throw ApplyError.lift(error) }
  }
}

/// Render a string double-quoted with escapes (debug-style quoting) so FK
/// mismatch error wording is stable across surfaces.
func applyDebugQuoted(_ s: String) -> String {
  var out = "\""
  for scalar in s.unicodeScalars {
    switch scalar.value {
    case 0x22: out += "\\\""
    case 0x5C: out += "\\\\"
    case 0x0A: out += "\\n"
    case 0x0D: out += "\\r"
    case 0x09: out += "\\t"
    case let x where x < 0x20:
      out += String(format: "\\u{%x}", x)
    default:
      out.unicodeScalars.append(scalar)
    }
  }
  out += "\""
  return out
}
