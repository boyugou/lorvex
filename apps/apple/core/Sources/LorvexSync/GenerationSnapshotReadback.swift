import Foundation
import GRDB
import LorvexDomain

extension GenerationSnapshot {
  /// Atomically stage candidate-zone delete receipts with the exact uploaded
  /// ordinal range and advance its progress. Receipts remain lease-scoped until
  /// ready publication; abandoning the candidate discards them by cascade.
  @discardableResult
  public static func recordUploadProgressAndReceipts(
    _ db: Database, binding: GenerationSnapshotBinding,
    expectedNextOrdinal: Int, nextOrdinal: Int,
    tombstoneConfirmations: [Tombstone.CloudConfirmation]
  ) throws -> GenerationSnapshotStaging {
    var result: GenerationSnapshotStaging?
    try db.inSavepoint {
      _ = try requireStaging(db, binding: binding)
      for confirmation in tombstoneConfirmations {
        guard let timestamp = SyncTimestamp.parse(confirmation.confirmedAt),
          timestamp.asString == confirmation.confirmedAt,
          let version = try? Hlc.parseCanonical(confirmation.version),
          version.description == confirmation.version
        else { throw TombstoneConfirmationError.invalidReceipt }
        let recordName = SyncRecordName.opaque(
          entityType: confirmation.entityType, entityId: confirmation.entityId)
        guard let encoded = try Data.fetchOne(
          db,
          sql: """
            SELECT canonical_envelope FROM sync_generation_snapshot_items
            WHERE lease_identifier = ? AND ordinal >= ? AND ordinal < ?
              AND record_name = ?
            """,
          arguments: [
            binding.leaseIdentifier, expectedNextOrdinal, nextOrdinal, recordName,
          ]),
          let envelope = try? JSONDecoder().decode(SyncEnvelope.self, from: encoded),
          envelope.entityType.asString == confirmation.entityType,
          envelope.entityId == confirmation.entityId,
          envelope.operation == .delete,
          envelope.version.description == confirmation.version
        else { throw TombstoneConfirmationError.invalidReceipt }
        try db.execute(
          sql: """
            INSERT INTO sync_generation_snapshot_tombstone_receipts
                (lease_identifier, entity_type, entity_id, version, server_modified_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(lease_identifier, entity_type, entity_id, version) DO UPDATE SET
              server_modified_at = MIN(
                sync_generation_snapshot_tombstone_receipts.server_modified_at,
                excluded.server_modified_at)
            """,
          arguments: [
            binding.leaseIdentifier, confirmation.entityType,
            confirmation.entityId, confirmation.version,
            confirmation.confirmedAt,
          ])
      }
      result = try advanceUploadProgress(
        db, binding: binding, expectedNextOrdinal: expectedNextOrdinal,
        nextOrdinal: nextOrdinal)
      return .commit
    }
    guard let result else { throw GenerationSnapshotError.corruptStaging }
    return result
  }

  /// Compare-and-swap the first staged ordinal not yet confirmed uploaded.
  @discardableResult
  public static func advanceUploadProgress(
    _ db: Database, binding: GenerationSnapshotBinding,
    expectedNextOrdinal: Int, nextOrdinal: Int
  ) throws -> GenerationSnapshotStaging {
    let staging = try requireStaging(db, binding: binding)
    let actual = staging.progress.uploadNextOrdinal
    guard actual == expectedNextOrdinal else {
      throw GenerationSnapshotError.progressMismatch(
        expected: expectedNextOrdinal, actual: actual)
    }
    guard nextOrdinal >= expectedNextOrdinal,
      nextOrdinal <= staging.manifest.recordCount
    else { throw GenerationSnapshotError.invalidBinding }
    if nextOrdinal != actual {
      try db.execute(
        sql: """
          UPDATE sync_generation_snapshot_staging
          SET upload_next_ordinal = ?
          WHERE lease_identifier = ? AND upload_next_ordinal = ?
          """,
        arguments: [nextOrdinal, binding.leaseIdentifier, expectedNextOrdinal])
      guard db.changesCount == 1 else {
        throw GenerationSnapshotError.progressMismatch(
          expected: expectedNextOrdinal,
          actual: try requireStaging(db, binding: binding).progress.uploadNextOrdinal)
      }
    }
    return try requireStaging(db, binding: binding)
  }

  /// Apply compact final-state readback observations without moving the page
  /// cursor. Repeating the same witness is idempotent; observing a new value for
  /// the same name overwrites it; a physical deletion removes it.
  @discardableResult
  public static func applyReadbackChanges(
    _ db: Database, binding: GenerationSnapshotBinding,
    witnesses: [GenerationSnapshotWitness], deletedRecordNames: [String]
  ) throws -> GenerationSnapshotStaging {
    var result: GenerationSnapshotStaging?
    try db.inSavepoint {
      let staging = try requireStaging(db, binding: binding)
      guard !staging.progress.readbackComplete else {
        throw GenerationSnapshotError.readbackAlreadyComplete
      }
      try applyReadbackItems(
        db, binding: binding, witnesses: witnesses,
        deletedRecordNames: deletedRecordNames)
      try refreshRemoteSummary(db, binding: binding, terminal: false)
      result = try requireStaging(db, binding: binding)
      return .commit
    }
    guard let result else { throw GenerationSnapshotError.corruptStaging }
    return result
  }

  /// Atomically persist one fetched CloudKit page and its continuation. The
  /// compact readback table represents final zone state across pages; terminal
  /// completion computes the same recordName+digest streaming proof as capture.
  /// Forget all compact remote observations and restart nil-token readback.
  @discardableResult
  public static func recordReadbackPage(
    _ db: Database, binding: GenerationSnapshotBinding,
    expectedPageIndex: Int, witnesses: [GenerationSnapshotWitness],
    deletedRecordNames: [String], continuationToken: Data,
    observedTraversalWitness: Bool, terminal: Bool
  ) throws -> GenerationSnapshotStaging {
    guard !continuationToken.isEmpty, continuationToken.count <= 262_144,
      expectedPageIndex >= 0, expectedPageIndex < 1_000_001,
      witnesses.count + deletedRecordNames.count <= maximumPageSize * 2
    else { throw GenerationSnapshotError.invalidBinding }
    var result: GenerationSnapshotStaging?
    try db.inSavepoint {
      let staging = try requireStaging(db, binding: binding)
      let actual = staging.progress.readbackPageIndex
      guard actual == expectedPageIndex else {
        throw GenerationSnapshotError.progressMismatch(
          expected: expectedPageIndex, actual: actual)
      }
      guard !staging.progress.readbackComplete else {
        throw GenerationSnapshotError.readbackAlreadyComplete
      }
      let witnessObserved =
        staging.progress.readbackWitnessObserved || observedTraversalWitness
      guard !terminal || witnessObserved else {
        throw GenerationSnapshotError.manifestMismatch
      }
      try applyReadbackItems(
        db, binding: binding, witnesses: witnesses,
        deletedRecordNames: deletedRecordNames)
      try db.execute(
        sql: """
          UPDATE sync_generation_snapshot_staging
          SET readback_page_index = ?, readback_continuation_token = ?,
              readback_witness_observed = ?
          WHERE lease_identifier = ? AND readback_page_index = ?
        """,
        arguments: [
          expectedPageIndex + 1, continuationToken, witnessObserved ? 1 : 0,
          binding.leaseIdentifier, expectedPageIndex,
        ])
      guard db.changesCount == 1 else {
        throw GenerationSnapshotError.progressMismatch(
          expected: expectedPageIndex,
          actual: try requireStaging(db, binding: binding).progress.readbackPageIndex)
      }
      // Persist the traversal witness before terminal completion. The staging
      // row invariant requires every complete readback to carry that witness;
      // both updates remain atomic inside this savepoint.
      try refreshRemoteSummary(db, binding: binding, terminal: terminal)
      result = try requireStaging(db, binding: binding)
      return .commit
    }
    guard let result else { throw GenerationSnapshotError.corruptStaging }
    return result
  }

  @discardableResult
  public static func resetReadbackProgress(
    _ db: Database, binding: GenerationSnapshotBinding
  ) throws -> GenerationSnapshotStaging {
    _ = try requireStaging(db, binding: binding)
    try db.execute(
      sql: "DELETE FROM sync_generation_snapshot_readback_items WHERE lease_identifier = ?",
      arguments: [binding.leaseIdentifier])
    try db.execute(
      sql: """
        UPDATE sync_generation_snapshot_staging
        SET readback_page_index = 0, readback_continuation_token = NULL,
            readback_witness_observed = 0, readback_complete = 0,
            remote_record_count = 0,
            remote_total_encoded_bytes = 0, remote_canonical_digest = NULL,
            remote_audit_record_count = 0,
            remote_audit_witness_digest = NULL
        WHERE lease_identifier = ?
        """,
      arguments: [binding.leaseIdentifier])
    guard db.changesCount == 1 else { throw GenerationSnapshotError.stagingNotFound }
    return try requireStaging(db, binding: binding)
  }

  private static func applyReadbackItems(
    _ db: Database, binding: GenerationSnapshotBinding,
    witnesses: [GenerationSnapshotWitness], deletedRecordNames: [String]
  ) throws {
    let upsert = try db.makeStatement(
      sql: """
        INSERT INTO sync_generation_snapshot_readback_items (
          lease_identifier, record_name, envelope_digest,
          encoded_byte_count, is_audit
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(lease_identifier, record_name) DO UPDATE SET
          envelope_digest = excluded.envelope_digest,
          encoded_byte_count = excluded.encoded_byte_count,
          is_audit = excluded.is_audit
        """)
    for witness in witnesses {
      try upsert.execute(
        arguments: [
          binding.leaseIdentifier, witness.recordName,
          witness.envelopeDigest, witness.encodedByteCount,
          witness.isAudit ? 1 : 0,
        ])
    }
    let delete = try db.makeStatement(
      sql: """
        DELETE FROM sync_generation_snapshot_readback_items
        WHERE lease_identifier = ? AND record_name = ?
        """)
    for name in deletedRecordNames {
      // A zone traversal also reports deletions for reserved/foreign record
      // names. Only opaque 64-hex LorvexEntity names can exist in this table.
      guard isLowerHex(name, count: 64) else { continue }
      try delete.execute(arguments: [binding.leaseIdentifier, name])
    }
  }

  private static func refreshRemoteSummary(
    _ db: Database, binding: GenerationSnapshotBinding, terminal: Bool
  ) throws {
    guard let row = try Row.fetchOne(
      db,
      sql: """
        SELECT COUNT(*) AS record_count,
               COALESCE(SUM(encoded_byte_count), 0) AS byte_count,
               COALESCE(SUM(CASE WHEN is_audit = 1 THEN 1 ELSE 0 END), 0)
                 AS audit_count
        FROM sync_generation_snapshot_readback_items
        WHERE lease_identifier = ?
        """,
      arguments: [binding.leaseIdentifier])
    else { throw GenerationSnapshotError.corruptStaging }
    let count: Int = row["record_count"]
    let bytes: Int64 = row["byte_count"]
    let auditCount: Int = row["audit_count"]
    guard count <= maximumRecordCount else {
      throw GenerationSnapshotError.recordLimitExceeded(
        limit: maximumRecordCount, observedAtLeast: count)
    }
    guard bytes <= maximumTotalEncodedBytes else {
      throw GenerationSnapshotError.byteLimitExceeded(
        limit: maximumTotalEncodedBytes, observedAtLeast: bytes)
    }

    let canonicalDigest: String?
    let auditDigest: String?
    if terminal {
      canonicalDigest = try readbackDigest(
        db, leaseIdentifier: binding.leaseIdentifier, auditOnly: false)
      auditDigest = try readbackDigest(
        db, leaseIdentifier: binding.leaseIdentifier, auditOnly: true)
    } else {
      canonicalDigest = nil
      auditDigest = nil
    }
    try db.execute(
      sql: """
        UPDATE sync_generation_snapshot_staging
        SET readback_complete = ?, remote_record_count = ?,
            remote_total_encoded_bytes = ?, remote_canonical_digest = ?,
            remote_audit_record_count = ?, remote_audit_witness_digest = ?
        WHERE lease_identifier = ?
        """,
      arguments: [
        terminal ? 1 : 0, count, bytes, canonicalDigest,
        auditCount, auditDigest, binding.leaseIdentifier,
      ])
    guard db.changesCount == 1 else { throw GenerationSnapshotError.stagingNotFound }
  }

  private static func readbackDigest(
    _ db: Database, leaseIdentifier: String, auditOnly: Bool
  ) throws -> String {
    let cursor = try Row.fetchCursor(
      db,
      sql: """
        SELECT record_name, envelope_digest, encoded_byte_count, is_audit
        FROM sync_generation_snapshot_readback_items
        WHERE lease_identifier = ? \(auditOnly ? "AND is_audit = 1" : "")
        ORDER BY record_name ASC
        """,
      arguments: [leaseIdentifier])
    return try digest(cursor: cursor, auditOnly: auditOnly)
  }
}
