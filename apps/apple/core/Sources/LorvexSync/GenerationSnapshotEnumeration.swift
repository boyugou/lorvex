import GRDB
import LorvexDomain
import LorvexStore

extension GenerationSnapshot {
  /// Cheap upper-bound gate performed before any entity payload is loaded.
  /// The count is exact for the current transaction, but capture still relies
  /// on the child-table uniqueness constraint and final inserted count.
  static func preflightDomainRecordCount(
    _ db: Database, tombstoneCompactionCutoff: String?
  ) throws -> Int {
    var count: Int64 = 0
    let kinds = EntityKind.topologicalEntityOrder.compactMap(EntityKind.parse)
      .filter { $0 != .aiChangelog }
    for kind in kinds {
      if kind == .entityRedirect {
        count += try countRows(db, table: "sync_entity_redirects")
      } else if kind.isEdge {
        let table: String
        switch kind {
        case .taskTag: table = "task_tags"
        case .taskDependency: table = "task_dependencies"
        case .taskCalendarEventLink: table = "task_calendar_event_links"
        case .habitCompletion: table = "habit_completions"
        default: continue
        }
        count += try countRows(db, table: table)
      } else if let (table, pk) = kind.tablePk {
        ValidationSQL.assertSafeSQLIdentifier(table)
        ValidationSQL.assertSafeSQLIdentifier(pk)
        if kind == .preference {
          let ids = try String.fetchAll(db, sql: "SELECT \(pk) FROM \(table)")
          count += Int64(
            ids.lazy.filter { !PreferenceKeys.isExcludedFromPreferenceEntitySync($0) }.count)
        } else {
          count += try countRows(db, table: table)
        }
      }
      if count > Int64(maximumRecordCount) { return Int(count) }
    }

    for kind in kinds where kind.isSyncableKind && kind != .entityRedirect
      && kind != .calendarSeriesCutover
    {
      if kind == .preference {
        let ids = try String.fetchAll(
          db,
          sql: """
            SELECT tombstone.entity_id FROM sync_tombstones AS tombstone
            WHERE tombstone.entity_type = ?
              AND (
                ? IS NULL
                OR tombstone.cloud_confirmed_at IS NULL
                OR tombstone.cloud_confirmed_at > ?
                OR \(TombstoneCompactionPolicy.isPermanentRedirectTargetSQL)
              )
            """,
          arguments: [kind.asString, tombstoneCompactionCutoff, tombstoneCompactionCutoff])
        count += Int64(
          ids.lazy.filter { !PreferenceKeys.isExcludedFromPreferenceEntitySync($0) }.count)
      } else {
        count += try Int64.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_tombstones AS tombstone
            WHERE tombstone.entity_type = ?
              AND (
                ? IS NULL
                OR tombstone.cloud_confirmed_at IS NULL
                OR tombstone.cloud_confirmed_at > ?
                OR \(TombstoneCompactionPolicy.isPermanentRedirectTargetSQL)
              )
            """,
          arguments: [kind.asString, tombstoneCompactionCutoff, tombstoneCompactionCutoff]) ?? 0
      }
      if count > Int64(maximumRecordCount) { return Int(count) }
    }
    return Int(count)
  }

  /// Deterministic, payload-streaming enumeration. At most one canonical
  /// envelope is live in the caller at a time; no `[SyncEnvelope]` inventory is
  /// built for durable staging.
  static func forEachDomainEnvelope(
    _ db: Database, tombstoneCompactionCutoff: String?,
    _ consume: (SyncEnvelope) throws -> Void
  ) throws {
    let deviceId = try SyncCheckpoints.getOrCreateDeviceId(db)
    let kinds = EntityKind.topologicalEntityOrder.compactMap(EntityKind.parse)
      .filter { $0 != .aiChangelog }
      .sorted { $0.asString < $1.asString }
    for kind in kinds {
      if kind == .entityRedirect {
        try forEachRedirectEnvelope(db, deviceId: deviceId, consume)
      } else if kind.isEdge {
        try forEachEdgeEnvelope(db, kind: kind, deviceId: deviceId, consume)
      } else {
        try forEachSimpleEnvelope(db, kind: kind, deviceId: deviceId, consume)
      }
    }
    try forEachTombstoneEnvelope(
      db, kinds: kinds, deviceId: deviceId,
      tombstoneCompactionCutoff: tombstoneCompactionCutoff, consume)
  }

  private static func countRows(_ db: Database, table: String) throws -> Int64 {
    ValidationSQL.assertSafeSQLIdentifier(table)
    return try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
  }

  private static func forEachSimpleEnvelope(
    _ db: Database, kind: EntityKind, deviceId: String,
    _ consume: (SyncEnvelope) throws -> Void
  ) throws {
    guard let (table, pk) = kind.tablePk else { return }
    ValidationSQL.assertSafeSQLIdentifier(table)
    ValidationSQL.assertSafeSQLIdentifier(pk)
    let cursor = try Row.fetchCursor(
      db, sql: "SELECT \(pk) AS entity_id, version FROM \(table) ORDER BY \(pk) ASC")
    while let row = try cursor.next() {
      let entityId: String = row["entity_id"]
      if kind == .preference,
        PreferenceKeys.isExcludedFromPreferenceEntitySync(entityId)
      {
        continue
      }
      let version: String = row["version"]
      let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: kind.asString, entityId: entityId)
      try consume(
        makeLiveEnvelope(
          db, kind: kind, entityId: entityId, version: version,
          payload: payload, deviceId: deviceId))
    }
  }

  private static func forEachEdgeEnvelope(
    _ db: Database, kind: EntityKind, deviceId: String,
    _ consume: (SyncEnvelope) throws -> Void
  ) throws {
    let sql: String
    switch kind {
    case .taskTag:
      sql = "SELECT task_id AS a, tag_id AS b, version FROM task_tags ORDER BY a, b"
    case .taskDependency:
      sql =
        "SELECT task_id AS a, depends_on_task_id AS b, version, created_at "
        + "FROM task_dependencies ORDER BY a, b"
    case .taskCalendarEventLink:
      sql =
        "SELECT task_id AS a, calendar_event_id AS b, version "
        + "FROM task_calendar_event_links ORDER BY a, b"
    case .habitCompletion:
      sql =
        "SELECT habit_id AS a, completed_date AS b, version "
        + "FROM habit_completions ORDER BY a, b"
    default:
      return
    }

    let cursor = try Row.fetchCursor(db, sql: sql)
    while let row = try cursor.next() {
      let a: String = row["a"]
      let b: String = row["b"]
      let entityId = "\(a):\(b)"
      let payload: JSONValue?
      switch kind {
      case .taskTag:
        payload = try PayloadLoaders.loadTaskTagSyncPayload(db, taskId: a, tagId: b)
      case .taskDependency:
        payload = PayloadLoaders.taskDependencyPayload(
          taskId: a, dependsOnTaskId: b, version: row["version"],
          createdAt: row["created_at"])
      case .taskCalendarEventLink:
        payload = try PayloadLoaders.loadTaskCalendarEventLinkSyncPayload(
          db, taskId: a, calendarEventId: b)
      case .habitCompletion:
        payload = try PayloadLoaders.loadHabitCompletionSyncPayload(
          db, habitId: a, completedDate: b)
      default:
        payload = nil
      }
      guard let payload else {
        throw GenerationSnapshotError.missingPayload(
          entityType: kind.asString, entityId: entityId)
      }
      try consume(
        makeLiveEnvelope(
          db, kind: kind, entityId: entityId, version: row["version"],
          payload: payload, deviceId: deviceId))
    }
  }

  private static func forEachRedirectEnvelope(
    _ db: Database, deviceId: String,
    _ consume: (SyncEnvelope) throws -> Void
  ) throws {
    let cursor = try Row.fetchCursor(
      db,
      sql: """
        SELECT source_type, source_id, target_id, version, created_at
        FROM sync_entity_redirects
        ORDER BY source_type, source_id COLLATE BINARY
        """)
    while let row = try cursor.next() {
      let sourceTypeRaw: String = row["source_type"]
      guard let sourceType = EntityKind.parse(sourceTypeRaw) else {
        throw GenerationSnapshotError.missingPayload(
          entityType: EntityName.entityRedirect, entityId: row["source_id"])
      }
      let sourceId: String = row["source_id"]
      let versionRaw: String = row["version"]
      guard let version = try? Hlc.parseCanonical(versionRaw),
        Hlc.isOperationallyAcceptableWire(version)
      else {
        throw GenerationSnapshotError.invalidStoredVersion(
          entityType: EntityName.entityRedirect, entityId: sourceId,
          version: versionRaw)
      }
      try consume(
        EntityRedirect.makeEnvelope(
          record: EntityRedirect.Record(
            sourceType: sourceType, sourceId: sourceId, targetId: row["target_id"],
            version: versionRaw, createdAt: row["created_at"]),
          deviceId: deviceId))
    }
  }

  private static func forEachTombstoneEnvelope(
    _ db: Database, kinds: [EntityKind], deviceId: String,
    tombstoneCompactionCutoff: String?,
    _ consume: (SyncEnvelope) throws -> Void
  ) throws {
    let allowed = Set(
      kinds.filter {
        $0.isSyncableKind && $0 != .entityRedirect && $0 != .calendarSeriesCutover
      })
    let cursor = try Row.fetchCursor(
      db,
      sql: """
        SELECT tombstone.entity_type, tombstone.entity_id, tombstone.version
        FROM sync_tombstones AS tombstone
        WHERE ? IS NULL
          OR tombstone.cloud_confirmed_at IS NULL
          OR tombstone.cloud_confirmed_at > ?
          OR \(TombstoneCompactionPolicy.isPermanentRedirectTargetSQL)
        ORDER BY tombstone.entity_type, tombstone.entity_id
        """,
      arguments: [tombstoneCompactionCutoff, tombstoneCompactionCutoff])
    while let row = try cursor.next() {
      let entityType: String = row["entity_type"]
      let entityId: String = row["entity_id"]
      let version: String = row["version"]
      guard let kind = EntityKind.parse(entityType), allowed.contains(kind) else { continue }
      if kind == .preference,
        PreferenceKeys.isExcludedFromPreferenceEntitySync(entityId)
      {
        continue
      }
      guard let hlc = try? Hlc.parseCanonical(version),
        Hlc.isOperationallyAcceptableWire(hlc)
      else {
        throw GenerationSnapshotError.invalidStoredVersion(
          entityType: entityType, entityId: entityId, version: version)
      }
      try consume(
        SyncEnvelope(
          entityType: kind, entityId: entityId, operation: .delete,
          version: hlc, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
          payload: try SyncCanonicalize.canonicalizeJSON(
            .object(["version": .string(version)])),
          deviceId: deviceId))
    }
  }
}
