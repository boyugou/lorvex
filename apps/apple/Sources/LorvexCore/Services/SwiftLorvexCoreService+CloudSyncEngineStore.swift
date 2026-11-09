import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync

extension SwiftLorvexCoreService: CloudSyncEngineStore {
  public func unsyncedOutboundRecordNames() throws -> Set<String> {
    try read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT DISTINCT entity_type, entity_id
          FROM sync_outbox
          WHERE synced_at IS NULL
            AND (disposition IS NULL OR disposition = 'retry_wait')
            AND entity_type <> ?
          """,
        arguments: [EntityName.aiChangelog])
      return Set(
        rows.map { row in
          SyncRecordName.opaque(entityType: row["entity_type"], entityId: row["entity_id"])
        })
    }
  }

  public func newestUnsyncedOutboundVersions() throws -> [String: Hlc] {
    try read { db in
      // The CHECK on `version` fixes its width and digit sets, so the text
      // maximum is the HLC maximum.
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT entity_type, entity_id, MAX(version) AS version
          FROM sync_outbox
          WHERE synced_at IS NULL
            AND (disposition IS NULL OR disposition = 'retry_wait')
            AND entity_type <> ?
          GROUP BY entity_type, entity_id
          """,
        arguments: [EntityName.aiChangelog])
      var versions: [String: Hlc] = [:]
      for row in rows {
        let version = try Hlc.parseCanonical(row["version"])
        versions[SyncRecordName.opaque(entityType: row["entity_type"], entityId: row["entity_id"])] =
          version
      }
      return versions
    }
  }

  public func unsyncedOutboxIdsHeldByServer(_ envelopes: [SyncEnvelope]) throws -> [Int64] {
    guard !envelopes.isEmpty else { return [] }
    return try read { db in
      var held: [Int64] = []
      for envelope in envelopes {
        let rows = try Row.fetchAll(
          db,
          sql: """
            SELECT id, version FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ?
              AND synced_at IS NULL
              AND (disposition IS NULL OR disposition = 'retry_wait')
            """,
          arguments: [envelope.entityType.asString, envelope.entityId])
        let versions = rows.map { $0["version"] as String }
        guard let newest = versions.max(), newest == envelope.version.description else { continue }
        held += rows.map { $0["id"] as Int64 }
      }
      return held
    }
  }

  public func applyFetchedRecords(
    _ envelopes: [SyncEnvelope], parking raws: [RawEnvelopeFields], undecodable: Int
  ) throws -> InboundApplyReport {
    try withStorageCutoverRetry {
      try self.applyInboundAttempt(
        envelopes, undecodable: undecodable, deferredUnknownTypeRecords: raws)
    }
  }

  /// Reading a checkpoint first resolves the install identity (memoized per
  /// storage epoch). The transport reads a checkpoint before it builds an
  /// engine, so a restored or cloned database rotates its device id and sets
  /// `reseed_required` before anything is fetched or sent, not at its first
  /// write.
  public func cloudSyncEngineCheckpoint(_ key: CloudSyncEngineCheckpoint) throws -> String? {
    _ = try writeState()
    return try read { db in try SyncCheckpoints.get(db, key: key.rawValue) }
  }

  public func setCloudSyncEngineCheckpoint(
    _ key: CloudSyncEngineCheckpoint, value: String?
  ) throws {
    try write { db in
      if let value {
        try SyncCheckpoints.set(db, key: key.rawValue, value: value)
      } else {
        try db.execute(
          sql: "DELETE FROM sync_checkpoints WHERE key = ?", arguments: [key.rawValue])
      }
    }
  }
}
