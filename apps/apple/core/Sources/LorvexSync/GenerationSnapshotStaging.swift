import Foundation
import GRDB
import LorvexDomain
import LorvexStore

private enum GenerationSnapshotRetentionKind: String {
  case active
  case candidate
}

private struct GenerationSnapshotRetentionScope {
  let kind: GenerationSnapshotRetentionKind
  let token: String
  let accountIdentifier: String
  let sourceZoneName: String
  let candidateZoneName: String
  let frontier: AuditRetentionFrontierValue
  let policyValue: String
  let policyVersion: String
}

extension GenerationSnapshot {
  /// Atomically capture an initial/bootstrap generation whose audit routing is
  /// already active in the candidate zone. An exact existing lease resumes.
  public static func capture(
    _ db: Database, binding: GenerationSnapshotBinding,
    authorization: AuditRetentionOutboundAuthorization,
    sourceLocalChangeSequence: UInt64,
    tombstoneCompactionCutoff: String? = nil,
    limits: GenerationSnapshotCaptureLimits = .production
  ) throws -> GenerationSnapshotStaging {
    var captured: GenerationSnapshotStaging?
    try db.inSavepoint {
      let state = try AuditRetentionFrontier.validateOutboundAuthorization(
        db, authorization: authorization)
      let scope = GenerationSnapshotRetentionScope(
        kind: .active, token: authorization.token,
        accountIdentifier: authorization.accountIdentifier,
        sourceZoneName: authorization.zoneName,
        candidateZoneName: authorization.zoneName,
        frontier: authorization.frontier,
        policyValue: state.policy.wireValue, policyVersion: state.policyVersion)
      captured = try capture(
        db, binding: binding, scope: scope,
        auditPreflightCount: {
          try AuditRetentionFrontier.generationSnapshotPreflightCount(
            db, authorization: authorization).count
        },
        sourceLocalChangeSequence: sourceLocalChangeSequence,
        tombstoneCompactionCutoff: tombstoneCompactionCutoff,
        limits: limits
      ) { consume in
        try AuditRetentionFrontier.forEachGenerationSnapshotEnvelope(
          db, authorization: authorization, consume)
      }
      return .commit
    }
    guard let captured else { throw GenerationSnapshotError.corruptStaging }
    return captured
  }

  /// Atomically capture a replacement generation under a staged audit-retention
  /// capability, without redirecting ordinary outbound from the source zone.
  public static func capture(
    _ db: Database, binding: GenerationSnapshotBinding,
    candidateAuthorization: AuditRetentionCandidateAuthorization,
    sourceLocalChangeSequence: UInt64,
    tombstoneCompactionCutoff: String? = nil,
    limits: GenerationSnapshotCaptureLimits = .production
  ) throws -> GenerationSnapshotStaging {
    var captured: GenerationSnapshotStaging?
    try db.inSavepoint {
      let state = try AuditRetentionFrontier.validateCandidateAuthorization(
        db, authorization: candidateAuthorization)
      let scope = GenerationSnapshotRetentionScope(
        kind: .candidate, token: candidateAuthorization.token,
        accountIdentifier: candidateAuthorization.accountIdentifier,
        sourceZoneName: candidateAuthorization.sourceActiveZoneName,
        candidateZoneName: candidateAuthorization.candidateZoneName,
        frontier: candidateAuthorization.frontier,
        policyValue: state.policy.wireValue, policyVersion: state.policyVersion)
      captured = try capture(
        db, binding: binding, scope: scope,
        auditPreflightCount: {
          try AuditRetentionFrontier.generationSnapshotPreflightCount(
            db, candidateAuthorization: candidateAuthorization).count
        },
        sourceLocalChangeSequence: sourceLocalChangeSequence,
        tombstoneCompactionCutoff: tombstoneCompactionCutoff,
        limits: limits
      ) { consume in
        try AuditRetentionFrontier.forEachGenerationSnapshotEnvelope(
          db, candidateAuthorization: candidateAuthorization, consume)
      }
      return .commit
    }
    guard let captured else { throw GenerationSnapshotError.corruptStaging }
    return captured
  }

  private static func capture(
    _ db: Database, binding: GenerationSnapshotBinding,
    scope: GenerationSnapshotRetentionScope,
    auditPreflightCount: () throws -> Int,
    sourceLocalChangeSequence: UInt64,
    tombstoneCompactionCutoff: String?,
    limits: GenerationSnapshotCaptureLimits,
    emitAudit: (_ consume: (SyncEnvelope) throws -> Void) throws -> Void
  ) throws -> GenerationSnapshotStaging {
    try requireDatabaseBinding(db, binding: binding)
    guard binding.accountIdentifier == scope.accountIdentifier,
      binding.candidateZoneName == scope.candidateZoneName
    else { throw GenerationSnapshotError.bindingMismatch }
    if let tombstoneCompactionCutoff {
      guard let parsed = SyncTimestamp.parse(tombstoneCompactionCutoff),
        parsed.asString == tombstoneCompactionCutoff
      else { throw GenerationSnapshotError.invalidBinding }
    }

    if try stagingMatches(
      db, binding: binding, scope: scope,
      tombstoneCompactionCutoff: tombstoneCompactionCutoff)
    {
      // The authorization token is a renewable capability for the same exact
      // retention frontier. Rebind it without touching immutable staged rows or
      // checking current local_change_seq: crash recovery resumes the capture.
      try db.execute(
        sql: """
          UPDATE sync_generation_snapshot_staging
          SET retention_authorization_token = ?
          WHERE lease_identifier = ?
          """,
        arguments: [scope.token, binding.leaseIdentifier])
      return try requireStaging(db, binding: binding)
    }

    let auditPreflightCount = try auditPreflightCount()
    let domainCount = try preflightDomainRecordCount(
      db, tombstoneCompactionCutoff: tombstoneCompactionCutoff)
    let observed = domainCount + auditPreflightCount
    guard observed <= limits.maximumRecordCount else {
      throw GenerationSnapshotError.recordLimitExceeded(
        limit: limits.maximumRecordCount, observedAtLeast: observed)
    }

    try db.execute(sql: "DELETE FROM sync_generation_snapshot_staging")
    guard sourceLocalChangeSequence <= UInt64(Int64.max) else {
      throw GenerationSnapshotError.corruptStaging
    }
    let emptyDigest = try digest(witnesses: [])
    let emptyAuditDigest = try digest(witnesses: [], auditOnly: true)
    let createdAt = SyncTimestampFormat.syncTimestampNow()
    try db.execute(
      sql: """
        INSERT INTO sync_generation_snapshot_staging (
          lease_identifier, account_identifier, database_instance_id,
          candidate_zone_name, generation, generation_identifier,
          lease_owner_identifier, retention_kind,
          retention_authorization_token, retention_source_zone_name,
          retention_frontier_epoch, retention_cutoff_timestamp,
          retention_cutoff_entity_id, retention_policy_value,
          retention_policy_version, tombstone_compaction_cutoff,
          source_local_change_seq, record_count,
          canonical_digest, audit_record_count, audit_witness_digest,
          total_encoded_bytes, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, 0, ?, 0, ?)
        """,
      arguments: [
        binding.leaseIdentifier, binding.accountIdentifier,
        binding.databaseInstanceIdentifier, binding.candidateZoneName,
        binding.generation, binding.generationIdentifier,
        binding.leaseOwnerIdentifier, scope.kind.rawValue, scope.token,
        scope.sourceZoneName, scope.frontier.epoch,
        scope.frontier.minimumRetainedTimestamp,
        scope.frontier.minimumRetainedEntityId, scope.policyValue,
        scope.policyVersion, tombstoneCompactionCutoff,
        Int64(sourceLocalChangeSequence), emptyDigest,
        emptyAuditDigest, createdAt,
      ])

    if let tombstoneCompactionCutoff {
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT tombstone.entity_type, tombstone.entity_id, tombstone.version,
                 tombstone.cloud_confirmed_at
          FROM sync_tombstones AS tombstone
          WHERE tombstone.cloud_confirmed_at IS NOT NULL
            AND tombstone.cloud_confirmed_at <= ?
            AND NOT (\(TombstoneCompactionPolicy.isPermanentRedirectTargetSQL))
          ORDER BY tombstone.entity_type, tombstone.entity_id
          """,
        arguments: [tombstoneCompactionCutoff])
      for row in rows {
        let entityType: String = row["entity_type"]
        let entityId: String = row["entity_id"]
        guard let kind = EntityKind.parse(entityType), kind.isSyncableKind,
          kind != .aiChangelog, kind != .entityRedirect,
          !(kind == .preference
            && PreferenceKeys.isExcludedFromPreferenceEntitySync(entityId))
        else { continue }
        try db.execute(
          sql: """
            INSERT INTO sync_generation_snapshot_compacted_tombstones
                (lease_identifier, entity_type, entity_id, version, cloud_confirmed_at)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            binding.leaseIdentifier, entityType, entityId,
            row["version"] as String, row["cloud_confirmed_at"] as String,
          ])
      }
    }

    let insert = try db.makeStatement(
      sql: """
        INSERT INTO sync_generation_snapshot_items (
          lease_identifier, ordinal, record_name, canonical_envelope,
          envelope_digest, encoded_byte_count, is_audit
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """)
    var ordinal = 0
    var totalBytes: Int64 = 0
    var auditCount = 0
    var seen = Set<String>()
    seen.reserveCapacity(observed)

    func stage(_ envelope: SyncEnvelope) throws {
      guard ordinal < limits.maximumRecordCount else {
        throw GenerationSnapshotError.recordLimitExceeded(
          limit: limits.maximumRecordCount, observedAtLeast: ordinal + 1)
      }
      guard Hlc.isOperationallyAcceptableWire(envelope.version) else {
        throw GenerationSnapshotError.invalidStoredVersion(
          entityType: envelope.entityType.asString, entityId: envelope.entityId,
          version: envelope.version.description)
      }
      let encoded = try canonicalEnvelopeData(envelope)
      guard encoded.count <= maximumEncodedEnvelopeBytes else {
        throw GenerationSnapshotError.byteLimitExceeded(
          limit: Int64(maximumEncodedEnvelopeBytes),
          observedAtLeast: Int64(encoded.count))
      }
      let byteCount = Int64(encoded.count)
      guard totalBytes <= limits.maximumTotalEncodedBytes - byteCount else {
        throw GenerationSnapshotError.byteLimitExceeded(
          limit: limits.maximumTotalEncodedBytes,
          observedAtLeast: totalBytes + byteCount)
      }
      let recordName = SyncRecordName.opaque(
        entityType: envelope.entityType.asString, entityId: envelope.entityId)
      guard seen.insert(recordName).inserted else {
        throw GenerationSnapshotError.duplicateIdentity(
          entityType: envelope.entityType.asString, entityId: envelope.entityId)
      }
      let isAudit = envelope.entityType == .aiChangelog
      try insert.execute(
        arguments: [
          binding.leaseIdentifier, ordinal, recordName, encoded,
          Sha256Checksum.hexDigest(encoded), byteCount, isAudit ? 1 : 0,
        ])
      ordinal += 1
      totalBytes += byteCount
      if isAudit { auditCount += 1 }
    }

    try forEachDomainEnvelope(
      db, tombstoneCompactionCutoff: tombstoneCompactionCutoff, stage)
    try emitAudit(stage)
    guard ordinal == observed, auditCount == auditPreflightCount else {
      throw GenerationSnapshotError.manifestMismatch
    }

    let canonicalDigest = try stagedDigest(
      db, leaseIdentifier: binding.leaseIdentifier, auditOnly: false)
    let auditDigest = try stagedDigest(
      db, leaseIdentifier: binding.leaseIdentifier, auditOnly: true)
    try db.execute(
      sql: """
        UPDATE sync_generation_snapshot_staging
        SET record_count = ?, canonical_digest = ?, audit_record_count = ?,
            audit_witness_digest = ?, total_encoded_bytes = ?
        WHERE lease_identifier = ?
        """,
      arguments: [
        ordinal, canonicalDigest, auditCount, auditDigest, totalBytes,
        binding.leaseIdentifier,
      ])
    guard db.changesCount == 1 else { throw GenerationSnapshotError.corruptStaging }
    return try requireStaging(db, binding: binding)
  }

  /// Read an immutable staged slice by ordinal, bounded by both item count and
  /// canonical encoded bytes. Mutable domain state is never consulted.
  public static func stagedPage(
    _ db: Database, binding: GenerationSnapshotBinding, offset: Int,
    limit: Int = maximumPageSize,
    maximumEncodedBytes: Int = maximumPageEncodedBytes
  ) throws -> GenerationSnapshotPage {
    let staging = try requireStaging(db, binding: binding)
    guard offset >= 0, limit > 0, limit <= maximumPageSize,
      maximumEncodedBytes > 0, maximumEncodedBytes <= maximumPageEncodedBytes
    else { throw GenerationSnapshotError.invalidPage(offset: offset, limit: limit) }
    guard offset < staging.manifest.recordCount else {
      return GenerationSnapshotPage(
        manifest: staging.manifest, envelopes: [], nextOffset: nil)
    }

    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT ordinal, record_name, canonical_envelope, envelope_digest,
               encoded_byte_count, is_audit
        FROM sync_generation_snapshot_items
        WHERE lease_identifier = ? AND ordinal >= ?
        ORDER BY ordinal ASC LIMIT ?
        """,
      arguments: [binding.leaseIdentifier, offset, limit])
    var envelopes: [SyncEnvelope] = []
    var pageBytes = 0
    for (index, row) in rows.enumerated() {
      let ordinal: Int = row["ordinal"]
      guard ordinal == offset + index else { throw GenerationSnapshotError.corruptStaging }
      let byteCount: Int = row["encoded_byte_count"]
      if !envelopes.isEmpty, pageBytes + byteCount > maximumEncodedBytes { break }
      guard pageBytes + byteCount <= maximumEncodedBytes,
        let encoded = row["canonical_envelope"] as Data?, encoded.count == byteCount,
        let envelope = try? JSONDecoder().decode(SyncEnvelope.self, from: encoded),
        case .success = envelope.validate(),
        Hlc.isOperationallyAcceptableWire(envelope.version),
        try canonicalEnvelopeData(envelope) == encoded,
        try witness(for: envelope)
          == GenerationSnapshotWitness(
            recordName: row["record_name"], envelopeDigest: row["envelope_digest"],
            encodedByteCount: Int64(byteCount), isAudit: row["is_audit"])
      else { throw GenerationSnapshotError.corruptStaging }
      envelopes.append(envelope)
      pageBytes += byteCount
    }
    guard !envelopes.isEmpty else { throw GenerationSnapshotError.corruptStaging }
    let next = offset + envelopes.count
    return GenerationSnapshotPage(
      manifest: staging.manifest, envelopes: envelopes,
      nextOffset: next < staging.manifest.recordCount ? next : nil)
  }

  /// Read the exact durable staging header, or nil when no capture exists.
  public static func staging(
    _ db: Database, binding: GenerationSnapshotBinding
  ) throws -> GenerationSnapshotStaging? {
    guard try stagingRow(db) != nil else { return nil }
    return try requireStaging(db, binding: binding)
  }

  /// Read the singleton staging header without an externally reconstructed
  /// binding. Used only to finish post-publication local cleanup after a crash;
  /// callers must still compare every lease/account/generation field with the
  /// authoritative remote descriptor before deleting it.
  public static func currentStaging(
    _ db: Database
  ) throws -> GenerationSnapshotStaging? {
    guard let row = try stagingRow(db) else { return nil }
    let result = try decodeStaging(row)
    try requireDatabaseBinding(db, binding: result.binding)
    return result
  }

  static func requireStaging(
    _ db: Database, binding: GenerationSnapshotBinding
  ) throws -> GenerationSnapshotStaging {
    try requireDatabaseBinding(db, binding: binding)
    guard let row = try stagingRow(db) else { throw GenerationSnapshotError.stagingNotFound }
    let result = try decodeStaging(row)
    guard result.binding == binding else { throw GenerationSnapshotError.bindingMismatch }
    return result
  }

  private static func stagingRow(_ db: Database) throws -> Row? {
    try Row.fetchOne(db, sql: "SELECT * FROM sync_generation_snapshot_staging")
  }

  private static func requireDatabaseBinding(
    _ db: Database, binding: GenerationSnapshotBinding
  ) throws {
    guard
      let databaseIdentifier = try SyncCheckpoints.get(
        db, key: SyncCheckpoints.keyDatabaseInstanceId),
      databaseIdentifier == binding.databaseInstanceIdentifier,
      try Int.fetchOne(
        db,
        sql: """
          SELECT 1 FROM sync_cloudkit_account_binding
          WHERE singleton = 1 AND account_identifier = ?
            AND database_instance_id = ?
          """,
        arguments: [
          binding.accountIdentifier, binding.databaseInstanceIdentifier,
        ]) == 1
    else { throw GenerationSnapshotError.bindingMismatch }
  }

  private static func stagingMatches(
    _ db: Database, binding: GenerationSnapshotBinding,
    scope: GenerationSnapshotRetentionScope,
    tombstoneCompactionCutoff: String?
  ) throws -> Bool {
    try Int.fetchOne(
      db,
      sql: """
        SELECT 1 FROM sync_generation_snapshot_staging
        WHERE lease_identifier = ? AND account_identifier = ?
          AND database_instance_id = ? AND candidate_zone_name = ?
          AND generation = ? AND generation_identifier = ?
          AND lease_owner_identifier = ? AND retention_kind = ?
          AND retention_source_zone_name = ? AND retention_frontier_epoch = ?
          AND retention_cutoff_timestamp = ? AND retention_cutoff_entity_id = ?
          AND retention_policy_value = ? AND retention_policy_version = ?
          AND tombstone_compaction_cutoff IS ?
        """,
      arguments: [
        binding.leaseIdentifier, binding.accountIdentifier,
        binding.databaseInstanceIdentifier, binding.candidateZoneName,
        binding.generation, binding.generationIdentifier,
        binding.leaseOwnerIdentifier, scope.kind.rawValue,
        scope.sourceZoneName, scope.frontier.epoch,
        scope.frontier.minimumRetainedTimestamp,
        scope.frontier.minimumRetainedEntityId, scope.policyValue,
        scope.policyVersion, tombstoneCompactionCutoff,
      ]) == 1
  }

  private static func stagedDigest(
    _ db: Database, leaseIdentifier: String, auditOnly: Bool
  ) throws -> String {
    let cursor = try Row.fetchCursor(
      db,
      sql: """
        SELECT record_name, envelope_digest, encoded_byte_count, is_audit
        FROM sync_generation_snapshot_items
        WHERE lease_identifier = ? \(auditOnly ? "AND is_audit = 1" : "")
        ORDER BY record_name ASC
        """,
      arguments: [leaseIdentifier])
    return try digest(cursor: cursor, auditOnly: auditOnly)
  }

  static func decodeStaging(_ row: Row) throws -> GenerationSnapshotStaging {
    let binding = try GenerationSnapshotBinding(
      accountIdentifier: row["account_identifier"],
      databaseInstanceIdentifier: row["database_instance_id"],
      candidateZoneName: row["candidate_zone_name"], generation: row["generation"],
      generationIdentifier: row["generation_identifier"],
      leaseIdentifier: row["lease_identifier"],
      leaseOwnerIdentifier: row["lease_owner_identifier"])
    let sourceSequence: Int64 = row["source_local_change_seq"]
    let manifest = GenerationSnapshotManifest(
      sourceLocalChangeSequence: UInt64(sourceSequence), recordCount: row["record_count"],
      canonicalDigest: row["canonical_digest"],
      auditRecordCount: row["audit_record_count"],
      auditWitnessDigest: row["audit_witness_digest"],
      totalEncodedBytes: row["total_encoded_bytes"])
    guard manifest.recordCount >= 0,
      manifest.auditRecordCount >= 0,
      manifest.auditRecordCount <= manifest.recordCount,
      manifest.totalEncodedBytes >= 0,
      isLowerHex(manifest.canonicalDigest, count: 64),
      isLowerHex(manifest.auditWitnessDigest, count: 64)
    else { throw GenerationSnapshotError.corruptStaging }
    let progress = GenerationSnapshotProgress(
      uploadNextOrdinal: row["upload_next_ordinal"],
      readbackPageIndex: row["readback_page_index"],
      readbackContinuationToken: row["readback_continuation_token"],
      readbackWitnessObserved: row["readback_witness_observed"],
      readbackComplete: row["readback_complete"])
    guard progress.uploadNextOrdinal >= 0,
      progress.uploadNextOrdinal <= manifest.recordCount,
      progress.readbackPageIndex >= 0
    else { throw GenerationSnapshotError.corruptStaging }

    let remote: GenerationSnapshotManifest?
    if progress.readbackComplete {
      guard let digest = row["remote_canonical_digest"] as String?,
        let auditDigest = row["remote_audit_witness_digest"] as String?
      else { throw GenerationSnapshotError.corruptStaging }
      remote = GenerationSnapshotManifest(
        sourceLocalChangeSequence: manifest.sourceLocalChangeSequence,
        recordCount: row["remote_record_count"], canonicalDigest: digest,
        auditRecordCount: row["remote_audit_record_count"],
        auditWitnessDigest: auditDigest,
        totalEncodedBytes: row["remote_total_encoded_bytes"])
    } else {
      remote = nil
    }
    return GenerationSnapshotStaging(
      binding: binding, manifest: manifest, progress: progress,
      remoteManifest: remote,
      tombstoneCompactionCutoff: row["tombstone_compaction_cutoff"],
      createdAt: row["created_at"])
  }
}
