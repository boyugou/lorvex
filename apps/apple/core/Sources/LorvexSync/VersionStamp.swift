import Foundation
import GRDB
import LorvexDomain

/// Shared entity version stamping for sync consistency.
///
/// When a mutation is enqueued to the sync outbox, the entity's `version`
/// column must be advanced to the envelope version. Without it, the local LWW
/// check may use a stale version, letting remote changes incorrectly overwrite
/// local edits. The UPDATE is LWW-gated (`? > version`) so a slower transaction
/// with an older HLC cannot regress a faster concurrent writer's newer version.
public enum VersionStamp {
  /// Typed errors surfaced by ``stampEntityVersion(_:entityType:entityId:version:)``.
  public enum VersionStampError: Error, Equatable {
    case invalidCompositeEntityId(entityType: String, entityId: String)
    case unsupportedEntityType(String)
    /// The entity row was not found. Callers must not enqueue a sync envelope
    /// for an entity whose local version would remain stale.
    case entityNotFound(entityType: String, entityId: String)
    /// A concurrent writer already stamped a strictly newer version. The caller
    /// MUST NOT enqueue at the requested (now superseded) version — its payload
    /// reflects pre-superseding state, and the envelope would carry an HLC that
    /// disagrees with the row's `version` column.
    case superseded(entityType: String, entityId: String, existingVersion: String)

    public var message: String {
      switch self {
      case .invalidCompositeEntityId(let t, let id):
        return "invalid composite entity id for \(t): \(id)"
      case .unsupportedEntityType(let t):
        return "unsupported entity type for version stamping: \(t)"
      case .entityNotFound(let t, let id):
        return "entity not found for version stamping: \(t):\(id)"
      case .superseded(let t, let id, let existing):
        return
          "version stamping superseded for \(t):\(id) "
          + "(existing version \(existing) is newer than attempted stamp)"
      }
    }
  }

  /// Prepared LWW-guarded UPDATE + `version` read for a simple-PK entity.
  /// `?1` always binds version, `?2` the PK.
  private struct SimplePkSql {
    let update: String
    let readVersion: String
  }

  /// Per-EntityKind simple-PK SQL, computed once. Composite-PK kinds and
  /// non-syncable kinds are absent; they route through the composite path or
  /// surface `unsupportedEntityType`.
  private static let simplePkCache: [EntityKind: SimplePkSql] = {
    var map: [EntityKind: SimplePkSql] = [:]
    for et in EntityKind.allSyncableTypes {
      guard let kind = EntityKind.parse(et), let (table, pk) = kind.tablePk else {
        continue
      }
      ValidationSQL.assertSafeSQLIdentifier(table)
      ValidationSQL.assertSafeSQLIdentifier(pk)
      map[kind] = SimplePkSql(
        update: "UPDATE \(table) SET version = ?1 WHERE \(pk) = ?2 AND ?1 > version",
        readVersion: "SELECT version FROM \(table) WHERE \(pk) = ?1")
    }
    return map
  }()

  private static func simplePkSql(_ entityType: String) -> SimplePkSql? {
    guard let kind = EntityKind.parse(entityType) else { return nil }
    return simplePkCache[kind]
  }

  /// Test-only: does `entityType` map to a simple-PK SQL arm?
  static func simplePkSupported(_ entityType: String) -> Bool {
    simplePkSql(entityType) != nil
  }

  /// Stamp a fresh `version` on the entity row.
  ///
  /// Simple-PK entities (tasks, lists, …) take a direct LWW-gated UPDATE.
  /// Composite-PK edges (`a:b` ids like `task_tag`) split the id and route to
  /// the per-edge UPDATE. `ai_changelog` is exempt (append-only, no version
  /// column). When the UPDATE affects zero rows the row is re-read to classify
  /// the outcome: missing row → ``VersionStampError/entityNotFound``, strictly
  /// newer existing version → ``VersionStampError/superseded``, equal version →
  /// benign success.
  public static func stampEntityVersion(
    _ db: Database, entityType: String, entityId: String, version: String
  ) throws {
    if let sql = simplePkSql(entityType) {
      try db.execute(sql: sql.update, arguments: [version, entityId])
      if db.changesCount == 0 {
        let existing = try readExistingVersion(db, sql: sql.readVersion, key: [entityId])
        try classifyPostUpdate(existing, entityType: entityType, entityId: entityId, stamp: version)
      }
      return
    }
    try stampCompositeEntityVersion(
      db, entityType: entityType, entityId: entityId, version: version)
  }

  private static func stampCompositeEntityVersion(
    _ db: Database, entityType: String, entityId: String, version: String
  ) throws {
    if entityType == EntityName.aiChangelog {
      return
    }
    let a: String
    let b: String
    switch CompositeEdge.splitCompositeEdgeId(entityId) {
    case .success(let (left, right)):
      (a, b) = (left, right)
    case .failure:
      throw VersionStampError.invalidCompositeEntityId(entityType: entityType, entityId: entityId)
    }
    guard let kind = EntityKind.parse(entityType) else {
      throw VersionStampError.unsupportedEntityType(entityType)
    }
    let updateSql: String
    let readVersionSql: String
    switch kind {
    case .taskCalendarEventLink:
      updateSql =
        "UPDATE task_calendar_event_links SET version = ?1 "
        + "WHERE task_id = ?2 AND calendar_event_id = ?3 AND ?1 > version"
      readVersionSql =
        "SELECT version FROM task_calendar_event_links "
        + "WHERE task_id = ?1 AND calendar_event_id = ?2"
    case .habitCompletion:
      updateSql =
        "UPDATE habit_completions SET version = ?1 "
        + "WHERE habit_id = ?2 AND completed_date = ?3 AND ?1 > version"
      readVersionSql =
        "SELECT version FROM habit_completions WHERE habit_id = ?1 AND completed_date = ?2"
    case .taskTag:
      updateSql =
        "UPDATE task_tags SET version = ?1 WHERE task_id = ?2 AND tag_id = ?3 AND ?1 > version"
      readVersionSql = "SELECT version FROM task_tags WHERE task_id = ?1 AND tag_id = ?2"
    case .taskDependency:
      updateSql =
        "UPDATE task_dependencies SET version = ?1 "
        + "WHERE task_id = ?2 AND depends_on_task_id = ?3 AND ?1 > version"
      readVersionSql =
        "SELECT version FROM task_dependencies WHERE task_id = ?1 AND depends_on_task_id = ?2"
    default:
      throw VersionStampError.unsupportedEntityType(entityType)
    }

    try db.execute(sql: updateSql, arguments: [version, a, b])
    if db.changesCount == 0 {
      let existing = try readExistingVersion(db, sql: readVersionSql, key: [a, b])
      try classifyPostUpdate(existing, entityType: entityType, entityId: entityId, stamp: version)
    }
  }

  /// Three-state read: `.none` → row absent, `.some(nil)` → row with NULL
  /// version, `.some(.some)` → row with a version string.
  private static func readExistingVersion(
    _ db: Database, sql: String, key: [DatabaseValueConvertible]
  ) throws -> String??? {
    // Optional<Optional<String>>: outer nil = row absent, inner nil = NULL col.
    guard let row = try Row.fetchOne(db, sql: sql, arguments: StatementArguments(key)) else {
      return Optional<Optional<String>>.none
    }
    let v: String? = row[0]
    return Optional<Optional<String>>.some(v)
  }

  /// Classify the zero-rows-affected case into a typed error or benign success.
  private static func classifyPostUpdate(
    _ existing: String???, entityType: String, entityId: String, stamp: String
  ) throws {
    guard let outer = existing else {
      // Programmer-level Optional unwrap guard; never hit (the helper always
      // returns a concrete Optional<Optional<String>>).
      throw VersionStampError.entityNotFound(entityType: entityType, entityId: entityId)
    }
    switch outer {
    case .some(.some(let existingVersion)):
      if existingVersionDominates(existingVersion, stamp) {
        throw VersionStampError.superseded(
          entityType: staticEntityType(entityType), entityId: entityId,
          existingVersion: existingVersion)
      }
      // Reaching here means the SQL gate refused AND existing did not strictly
      // dominate — the only string satisfying both is existing == stamp (a
      // concurrent writer raced at the exact same HLC). Benign no-op.
      return
    case .some(.none):
      // Row exists with a NULL version. Unreachable for every composite entity
      // routed here — task_tags, task_dependencies, habit_completions, and
      // task_calendar_event_links all declare `version TEXT NOT NULL` — so this
      // is a defensive no-op, not a stamping path.
      return
    case .none:
      throw VersionStampError.entityNotFound(entityType: entityType, entityId: entityId)
    }
  }

  /// Whether the row's persisted `existingVersion` strictly dominates `stamp`.
  /// Routes through ``compareVersionsWithFallback(_:_:)`` — the single LWW
  /// ordering primitive — so the parse strictness and the byte-compare fallback
  /// match the SQL gate's binary-collation `>` exactly (a Swift `String >` here
  /// would use Unicode order, diverging from the gate on non-ASCII versions).
  /// Surfacing `superseded` on the byte-fallback path keeps a tainted row
  /// visible rather than papering over the gate refusal with a stale outbox
  /// enqueue.
  private static func existingVersionDominates(_ existingVersion: String, _ stamp: String) -> Bool {
    compareVersionsWithFallback(existingVersion, stamp) == .orderedDescending
  }

  /// Map a runtime entity-type string back to its canonical static form for the
  /// `superseded` error; unrecognized values fall through to `"unknown"`.
  private static func staticEntityType(_ entityType: String) -> String {
    EntityKind.parse(entityType)?.asString ?? "unknown"
  }
}
