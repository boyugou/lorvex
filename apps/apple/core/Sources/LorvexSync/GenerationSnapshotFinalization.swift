import GRDB
import LorvexDomain
import LorvexStore

private enum PersistedGenerationSnapshotRetentionKind: String {
  case active
  case candidate
}

private struct PersistedGenerationSnapshotRetention {
  let kind: PersistedGenerationSnapshotRetentionKind
  let authorizationToken: String
  let sourceZoneName: String
  let frontier: AuditRetentionFrontierValue
  let policy: ChangelogRetentionPolicy
  let policyVersion: String

  func candidateAuthorization(
    binding: GenerationSnapshotBinding
  ) throws -> AuditRetentionCandidateAuthorization {
    guard kind == .candidate,
      sourceZoneName != binding.candidateZoneName
    else { throw GenerationSnapshotError.corruptStaging }
    return AuditRetentionCandidateAuthorization(
      token: authorizationToken,
      accountIdentifier: binding.accountIdentifier,
      sourceActiveZoneName: sourceZoneName,
      candidateZoneName: binding.candidateZoneName,
      frontier: frontier, policy: policy, policyVersion: policyVersion)
  }
}

extension GenerationSnapshot {
  /// Commit local ownership of a generation only after exact durable readback
  /// proves that the published zone equals the immutable staged manifest.
  /// Candidate routing activation and staging cleanup share this savepoint, so
  /// a crash cannot leave either half of the transition committed alone.
  public static func finalizePublished(
    _ db: Database, binding: GenerationSnapshotBinding
  ) throws {
    try db.inSavepoint {
      let staging = try requireStaging(db, binding: binding)
      guard staging.progress.readbackComplete,
        staging.remoteManifest == staging.manifest
      else { throw GenerationSnapshotError.manifestMismatch }

      let retention = try persistedRetention(db, binding: binding)
      switch retention.kind {
      case .candidate:
        let authorization = try retention.candidateAuthorization(binding: binding)
        _ = try AuditRetentionFrontier.activateCandidateGeneration(
          db, authorization: authorization)
      case .active:
        guard retention.sourceZoneName == binding.candidateZoneName,
          try AuditRetentionFrontier.activeAccountIdentifier(db)
            == binding.accountIdentifier,
          try AuditRetentionFrontier.activeZoneName(db)
            == binding.candidateZoneName
        else { throw GenerationSnapshotError.bindingMismatch }
      }

      // The durable candidate readback is also this physical database's exact
      // enrollment proof for the generation it just published. Record that
      // proof in the same savepoint as retention-route activation and staging
      // deletion. Otherwise a crash after the remote ready CAS but before a
      // separate enrollment write makes the publisher look like an old peer;
      // the over-window gate could then authoritatively discard valid local
      // writes that were intentionally left pending after immutable capture.
      try SyncCheckpoints.set(
        db,
        key: SyncCheckpoints.keyEnrolledZoneEpoch(
          accountIdentifier: binding.accountIdentifier),
        value: String(binding.generation))

      // Candidate saves become fleet-visible only after the remote ready CAS.
      // Promote their exact server receipts now, in the same savepoint as local
      // route activation and staging cleanup. An abandoned candidate never
      // reaches this branch and its receipts disappear by cascade.
      let receiptRows = try Row.fetchAll(
        db,
        sql: """
          SELECT entity_type, entity_id, version, server_modified_at
          FROM sync_generation_snapshot_tombstone_receipts
          WHERE lease_identifier = ?
          """,
        arguments: [binding.leaseIdentifier])
      for row in receiptRows {
        _ = try Tombstone.confirmCloudPresence(
          db,
          confirmation: Tombstone.CloudConfirmation(
            entityType: row["entity_type"], entityId: row["entity_id"],
            version: row["version"], confirmedAt: row["server_modified_at"]))
      }

      // Reclaim only the exact old, CloudKit-confirmed tombstones this immutable
      // generation deliberately omitted. The version + confirmation match makes
      // a late finalize harmless after a newer local delete refreshed the row;
      // the shared redirect-target predicate also rechecks current topology so
      // an alias created after capture cannot lose its newly-required closure.
      try db.execute(
        sql: """
          DELETE FROM sync_outbox
          WHERE operation = 'delete'
            AND EXISTS (
              SELECT 1
              FROM sync_generation_snapshot_compacted_tombstones AS omitted
              JOIN sync_tombstones AS tombstone
                ON tombstone.entity_type = omitted.entity_type
               AND tombstone.entity_id = omitted.entity_id
               AND tombstone.version = omitted.version
               AND tombstone.cloud_confirmed_at <= omitted.cloud_confirmed_at
              WHERE omitted.lease_identifier = ?
                AND omitted.entity_type = sync_outbox.entity_type
                AND omitted.entity_id = sync_outbox.entity_id
                AND omitted.version = sync_outbox.version
                AND NOT (\(TombstoneCompactionPolicy.isPermanentRedirectTargetSQL))
            )
          """,
        arguments: [binding.leaseIdentifier])
      try db.execute(
        sql: """
          DELETE FROM sync_tombstones AS tombstone
          WHERE EXISTS (
            SELECT 1
            FROM sync_generation_snapshot_compacted_tombstones AS omitted
            WHERE omitted.lease_identifier = ?
              AND omitted.entity_type = tombstone.entity_type
              AND omitted.entity_id = tombstone.entity_id
              AND omitted.version = tombstone.version
              AND tombstone.cloud_confirmed_at <= omitted.cloud_confirmed_at
          )
            AND NOT (\(TombstoneCompactionPolicy.isPermanentRedirectTargetSQL))
          """,
        arguments: [binding.leaseIdentifier])

      try deleteExactStaging(db, binding: binding)
      return .commit
    }
  }

  /// Discard one exact local generation lease. Candidate authorization cleanup
  /// is idempotent so this also repairs the crash state where authorization was
  /// already revoked but its staging row survived. Active authorization and
  /// active routing are never revoked by this operation.
  public static func discard(
    _ db: Database, binding: GenerationSnapshotBinding
  ) throws {
    try db.inSavepoint {
      _ = try requireStaging(db, binding: binding)
      let retention = try persistedRetention(db, binding: binding)
      switch retention.kind {
      case .candidate:
        try AuditRetentionFrontier.revokeCandidateGeneration(
          db, authorization: retention.candidateAuthorization(binding: binding))
      case .active:
        guard retention.sourceZoneName == binding.candidateZoneName else {
          throw GenerationSnapshotError.corruptStaging
        }
      }
      try deleteExactStaging(db, binding: binding)
      return .commit
    }
  }

  private static func persistedRetention(
    _ db: Database, binding: GenerationSnapshotBinding
  ) throws -> PersistedGenerationSnapshotRetention {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT retention_kind, retention_authorization_token,
                 retention_source_zone_name, retention_frontier_epoch,
                 retention_cutoff_timestamp, retention_cutoff_entity_id,
                 retention_policy_value, retention_policy_version
          FROM sync_generation_snapshot_staging
          WHERE lease_identifier = ? AND account_identifier = ?
            AND database_instance_id = ? AND candidate_zone_name = ?
            AND generation = ? AND generation_identifier = ?
            AND lease_owner_identifier = ?
          """,
        arguments: exactBindingArguments(binding))
    else { throw GenerationSnapshotError.bindingMismatch }

    let rawKind: String = row["retention_kind"]
    let token: String = row["retention_authorization_token"]
    let sourceZoneName: String = row["retention_source_zone_name"]
    let epoch: Int64 = row["retention_frontier_epoch"]
    let cutoffTimestamp: String = row["retention_cutoff_timestamp"]
    let cutoffEntityID: String = row["retention_cutoff_entity_id"]
    let rawPolicy: String = row["retention_policy_value"]
    let policyVersion: String = row["retention_policy_version"]
    guard let kind = PersistedGenerationSnapshotRetentionKind(rawValue: rawKind),
      GenerationSnapshotBinding.validPrintableASCII(token, maximumBytes: 128),
      GenerationSnapshotBinding.validBounded(sourceZoneName, maximumBytes: 255)
    else { throw GenerationSnapshotError.corruptStaging }

    let frontier = AuditRetentionFrontierValue(
      epoch: epoch, minimumRetainedTimestamp: cutoffTimestamp,
      minimumRetainedEntityId: cutoffEntityID)
    do {
      try AuditRetentionFrontier.validateFrontier(frontier)
    } catch {
      throw GenerationSnapshotError.corruptStaging
    }
    let policy = ChangelogRetentionPolicy.parse(rawPolicy)
    guard policy.wireValue == rawPolicy else {
      throw GenerationSnapshotError.corruptStaging
    }
    if !policyVersion.isEmpty {
      guard let parsed = try? Hlc.parseCanonical(policyVersion),
        parsed.description == policyVersion
      else { throw GenerationSnapshotError.corruptStaging }
    }
    return PersistedGenerationSnapshotRetention(
      kind: kind, authorizationToken: token,
      sourceZoneName: sourceZoneName, frontier: frontier,
      policy: policy, policyVersion: policyVersion)
  }

  private static func deleteExactStaging(
    _ db: Database, binding: GenerationSnapshotBinding
  ) throws {
    try db.execute(
      sql: """
        DELETE FROM sync_generation_snapshot_staging
        WHERE lease_identifier = ? AND account_identifier = ?
          AND database_instance_id = ? AND candidate_zone_name = ?
          AND generation = ? AND generation_identifier = ?
          AND lease_owner_identifier = ?
        """,
      arguments: exactBindingArguments(binding))
    guard db.changesCount == 1 else {
      throw GenerationSnapshotError.bindingMismatch
    }
  }

  private static func exactBindingArguments(
    _ binding: GenerationSnapshotBinding
  ) -> StatementArguments {
    [
      binding.leaseIdentifier, binding.accountIdentifier,
      binding.databaseInstanceIdentifier, binding.candidateZoneName,
      binding.generation, binding.generationIdentifier,
      binding.leaseOwnerIdentifier,
    ]
  }
}
