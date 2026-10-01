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
