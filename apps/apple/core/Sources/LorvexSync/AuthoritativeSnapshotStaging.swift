import Foundation
import GRDB
import LorvexDomain

extension AuthoritativeSnapshot {
  static let maximumRecordCount = GenerationSnapshot.maximumRecordCount
  static let maximumTotalEncodedBytes = GenerationSnapshot.maximumTotalEncodedBytes
  static let maximumEncodedEnvelopeBytes = GenerationSnapshot.maximumEncodedEnvelopeBytes

  /// A typed record can still be unsafe to apply as authoritative state when
  /// its payload contract is newer or its HLC has no legal local successor.
  /// Treat every newer typed payload conservatively here: ordinary incremental
  /// sync can preserve manifest-valid additive top-level fields in payload
  /// shadow, but a complete truth-adoption pass must not erase local state
  /// before an upgraded build has interpreted the future contract as a whole.
  static func futureDeferralReason(
    for envelope: SyncEnvelope
  ) -> DeferralReason? {
    if let clockReason = FutureRecordHold.clockDeferralReason(for: envelope.version) {
      return clockReason
    }
    guard envelope.payloadSchemaVersion > LorvexVersion.payloadSchemaVersion else {
      return nil
    }
    return .schemaTooNew(
      remoteVersion: envelope.payloadSchemaVersion,
      localVersion: LorvexVersion.payloadSchemaVersion)
  }

  /// Promote every future-authored staged envelope into the durable pending
  /// inbox before a snapshot session, restart, or boundary replacement drops
  /// its page inventory. The outbox fence alone is not sufficient provenance:
  /// a later build needs these exact remote bytes to release or replay it.
  static func preserveStagedFutureProvenance(
    _ db: Database, sessionToken: String
  ) throws {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT record_name, state, envelope
        FROM sync_authoritative_snapshot_records
        WHERE session_id = ?
        ORDER BY record_name
        """,
      arguments: [sessionToken])
    let decoder = JSONDecoder()
    for row in rows {
      let stateRaw: String = row["state"]
      guard let state = AuthoritativeSnapshotRecordState(rawValue: stateRaw) else {
        throw AuthoritativeSnapshotError.malformedStagedEnvelope(
          recordName: row["record_name"])
      }
      switch state {
      case .corrupt:
        continue
      case .unknown:
        guard let json: String = row["envelope"],
          let data = json.data(using: .utf8),
          let raw = try? decoder.decode(RawEnvelopeFields.self, from: data),
          case .success = raw.validate(),
          SyncRecordName.opaque(entityType: raw.entityType, entityId: raw.entityId)
            == (row["record_name"] as String)
        else {
          throw AuthoritativeSnapshotError.malformedStagedEnvelope(
            recordName: row["record_name"])
        }
        try PendingInboxDrain.holdUnknownTypeRecord(db, raw: raw)
        try FutureRecordHold.replaceAuthoritativeFutureProvenance(
          db, entityType: raw.entityType, entityId: raw.entityId,
          heldVersion: raw.version)
      case .decoded:
        guard let json: String = row["envelope"],
          let data = json.data(using: .utf8),
          let envelope = try? decoder.decode(SyncEnvelope.self, from: data),
          case .success = envelope.validate(),
          SyncRecordName.opaque(
            entityType: envelope.entityType.asString, entityId: envelope.entityId)
            == (row["record_name"] as String)
        else {
          throw AuthoritativeSnapshotError.malformedStagedEnvelope(
            recordName: row["record_name"])
        }
        if let reason = futureDeferralReason(for: envelope) {
          try PendingInboxDrain.enqueueDeferred(
            db, envelope: envelope, reason: reason)
          try FutureRecordHold.replaceAuthoritativeFutureProvenance(
            db, entityType: envelope.entityType.asString,
            entityId: envelope.entityId,
            heldVersion: envelope.version.description)
        }
      }
    }
  }

  /// Release only fences that lost their sole staging provenance. Every valid
  /// permanent future hold has an identity-matched pending row after the
  /// promotion above; a fence without one would otherwise block writes forever.
  static func releaseOrphanedStagingFutureFences(_ db: Database) throws {
    try db.execute(
      sql: """
        UPDATE sync_outbox
        SET retry_count = 0, last_retry_at = NULL, last_error = NULL,
            consecutive_error_count = 0, disposition = NULL,
            future_record_version = NULL, future_record_resolution = NULL,
            next_retry_at = NULL, recovery_round = 0
        WHERE synced_at IS NULL AND disposition = ?
          AND NOT EXISTS (
            SELECT 1 FROM sync_pending_inbox AS pending
            WHERE pending.envelope_entity_type = sync_outbox.entity_type
              AND pending.envelope_entity_id = sync_outbox.entity_id
              AND pending.envelope_version = sync_outbox.future_record_version
              AND (
                \(PendingInboxDrain.futureRecordReasonSQL(column: "pending.reason"))
              )
          )
        """,
      arguments: [Outbox.Disposition.futureRecordHold.rawValue])
  }

  static func requireBoundDatabase(
    _ db: Database, accountIdentifier: String, databaseInstanceId: String
  ) throws {
    guard let binding = try CloudTraversalWitness.accountBinding(db),
      binding.accountIdentifier == accountIdentifier
    else { throw AuthoritativeSnapshotError.sessionBoundaryMismatch }
    guard binding.databaseInstanceIdentifier == databaseInstanceId else {
      throw AuthoritativeSnapshotError.databaseInstanceMismatch
    }
  }

  static func stagePageInsideSavepointBounded(
    _ db: Database, records: [AuthoritativeSnapshotRemoteRecord],
    deletedRecordNames: [String], sessionToken: String
  ) throws {
    guard let session = try activeSession(db) else {
      throw AuthoritativeSnapshotError.noActiveSession
    }
    guard session.sessionToken == sessionToken else {
      throw AuthoritativeSnapshotError.sessionTokenMismatch
    }
    guard session.phase == .ready || session.phase == .pulling else {
      throw AuthoritativeSnapshotError.wrongPhase(expected: .ready, actual: session.phase)
    }
    try requireBoundDatabase(
      db, accountIdentifier: session.accountIdentifier,
      databaseInstanceId: session.databaseInstanceId)

    guard
      let accounting = try Row.fetchOne(
        db,
        sql: """
          SELECT staged_record_count, staged_encoded_bytes
          FROM sync_authoritative_snapshot WHERE session_token = ?
          """,
        arguments: [session.sessionToken])
    else { throw AuthoritativeSnapshotError.noActiveSession }
    let originalCount: Int64 = accounting["staged_record_count"]
    let originalBytes: Int64 = accounting["staged_encoded_bytes"]
    var count = originalCount
    var encodedBytes = originalBytes

    if session.phase == .ready {
      try db.execute(
        sql: "UPDATE sync_authoritative_snapshot SET phase = ? WHERE session_token = ?",
        arguments: [AuthoritativeSnapshotPhase.pulling.rawValue, session.sessionToken])
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    for record in records {
      try validateRecordName(record.recordName)
      if let serverModifiedAt = record.serverModifiedAt {
        guard let parsed = SyncTimestamp.parse(serverModifiedAt),
          parsed.asString == serverModifiedAt
        else {
          throw AuthoritativeSnapshotError.malformedStagedEnvelope(
            recordName: record.recordName)
        }
      }
      let envelopeJSON: String?
      switch record.state {
      case .decoded:
        guard let envelope = record.envelope, record.rawEnvelope == nil,
          SyncRecordName.opaque(
            entityType: envelope.entityType.asString, entityId: envelope.entityId)
            == record.recordName,
          case .success = envelope.validate()
        else {
          throw AuthoritativeSnapshotError.malformedStagedEnvelope(recordName: record.recordName)
        }
        envelopeJSON = String(decoding: try encoder.encode(envelope), as: UTF8.self)
      case .unknown:
        guard record.envelope == nil, let raw = record.rawEnvelope,
          case .success = raw.validate(),
          SyncRecordName.opaque(entityType: raw.entityType, entityId: raw.entityId)
            == record.recordName
        else {
          throw AuthoritativeSnapshotError.malformedStagedEnvelope(recordName: record.recordName)
        }
        envelopeJSON = try raw.envelopeWireJSON()
      case .corrupt:
        guard record.envelope == nil, record.rawEnvelope == nil else {
          throw AuthoritativeSnapshotError.malformedStagedEnvelope(recordName: record.recordName)
        }
        envelopeJSON = nil
      }

      let newBytes = Int64(envelopeJSON?.utf8.count ?? 0)
      guard newBytes <= Int64(maximumEncodedEnvelopeBytes) else {
        throw AuthoritativeSnapshotError.byteLimitExceeded(
          limit: Int64(maximumEncodedEnvelopeBytes), observedAtLeast: newBytes)
      }
      let previous = try Row.fetchOne(
        db,
        sql: """
          SELECT COALESCE(length(CAST(envelope AS BLOB)), 0) AS encoded_bytes
          FROM sync_authoritative_snapshot_records
          WHERE session_id = ? AND record_name = ?
          """,
        arguments: [session.sessionToken, record.recordName])
      let previousBytes: Int64 = previous?["encoded_bytes"] ?? 0
      if previous == nil { count += 1 }
      encodedBytes = encodedBytes - previousBytes + newBytes
      try validateBounds(recordCount: count, encodedBytes: encodedBytes)

      try db.execute(
        sql: """
          INSERT INTO sync_authoritative_snapshot_records
              (session_id, record_name, state, envelope, server_modified_at)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(session_id, record_name) DO UPDATE SET
              state = excluded.state,
              envelope = excluded.envelope,
              server_modified_at = excluded.server_modified_at
          """,
        arguments: [
          session.sessionToken, record.recordName, record.state.rawValue,
          envelopeJSON, record.serverModifiedAt,
        ])

      switch record.state {
      case .unknown:
        if let raw = record.rawEnvelope {
          try FutureRecordHold.replaceAuthoritativeFutureProvenance(
            db, entityType: raw.entityType, entityId: raw.entityId, heldVersion: raw.version)
        }
      case .decoded:
        if let envelope = record.envelope,
          envelope.payloadSchemaVersion > LorvexVersion.payloadSchemaVersion
            || FutureRecordHold.clockDeferralReason(for: envelope.version) != nil
        {
          try FutureRecordHold.replaceAuthoritativeFutureProvenance(
            db, entityType: envelope.entityType.asString, entityId: envelope.entityId,
            heldVersion: envelope.version.description)
        }
      case .corrupt:
        break
      }
    }

    for recordName in deletedRecordNames {
      try validateRecordName(recordName)
      let previous = try Row.fetchOne(
        db,
        sql: """
          SELECT COALESCE(length(CAST(envelope AS BLOB)), 0) AS encoded_bytes
          FROM sync_authoritative_snapshot_records
          WHERE session_id = ? AND record_name = ?
          """,
        arguments: [session.sessionToken, recordName])
      if let previous {
        count -= 1
        encodedBytes -= previous["encoded_bytes"] as Int64
      }
      try db.execute(
        sql: """
          DELETE FROM sync_authoritative_snapshot_records
          WHERE session_id = ? AND record_name = ?
          """,
        arguments: [session.sessionToken, recordName])
    }

    try db.execute(
      sql: """
        UPDATE sync_authoritative_snapshot
        SET staged_record_count = ?, staged_encoded_bytes = ?
        WHERE session_token = ?
          AND staged_record_count = ? AND staged_encoded_bytes = ?
        """,
      arguments: [
        count, encodedBytes, session.sessionToken, originalCount, originalBytes,
      ])
    guard db.changesCount == 1 else {
      throw AuthoritativeSnapshotError.malformedStagingAccounting
    }
  }

  static func validateStagingAccounting(
    _ db: Database, sessionToken: String, rows: [Row]
  ) throws {
    guard
      let accounting = try Row.fetchOne(
        db,
        sql: """
          SELECT staged_record_count, staged_encoded_bytes
          FROM sync_authoritative_snapshot WHERE session_token = ?
          """,
        arguments: [sessionToken])
    else { throw AuthoritativeSnapshotError.noActiveSession }
    let expectedCount: Int64 = accounting["staged_record_count"]
    let expectedBytes: Int64 = accounting["staged_encoded_bytes"]
    let observedBytes = rows.reduce(Int64(0)) { result, row in
      let envelope: String? = row["envelope"]
      return result + Int64(envelope?.utf8.count ?? 0)
    }
    guard expectedCount == Int64(rows.count), expectedBytes == observedBytes else {
      throw AuthoritativeSnapshotError.malformedStagingAccounting
    }
  }

  private static func validateBounds(recordCount: Int64, encodedBytes: Int64) throws {
    guard recordCount <= Int64(maximumRecordCount) else {
      throw AuthoritativeSnapshotError.recordLimitExceeded(
        limit: maximumRecordCount, observedAtLeast: Int(recordCount))
    }
    guard encodedBytes <= maximumTotalEncodedBytes else {
      throw AuthoritativeSnapshotError.byteLimitExceeded(
        limit: maximumTotalEncodedBytes, observedAtLeast: encodedBytes)
    }
  }
}
