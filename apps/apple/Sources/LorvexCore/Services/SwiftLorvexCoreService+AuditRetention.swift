import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  /// Audit-retention transitions can change the virtual preference or
  /// physically remove canonical changelog rows. Keep the cross-process change
  /// sequence honest even when the caller does not otherwise mutate a
  /// user-facing aggregate.
  private func withAuditRetentionMutation<T: Sendable>(
    _ body: @Sendable (Database) throws -> T
  ) throws -> T {
    try write { db in
      let policyBefore = try AuditRetentionFrontier.currentPolicy(db)
      let auditCountBefore =
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
      let result = try body(db)
      let policyAfter = try AuditRetentionFrontier.currentPolicy(db)
      let auditCountAfter =
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
      if policyAfter != policyBefore || auditCountAfter < auditCountBefore {
        try LocalChangeSeq.bump(db)
        Overview.invalidateStreakCache(db)
      }
      return result
    }
  }

  public func activateAuditRetentionAccount(
    accountIdentifier: String, zoneName: String
  ) throws -> AuditRetentionAccountActivation {
    try write { db in
      let priorAccount = try AuditRetentionFrontier.activeAccountIdentifier(db)
      let activation = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: accountIdentifier, zoneName: zoneName)
      if let priorAccount, priorAccount != accountIdentifier {
        try LocalChangeSeq.bump(db)
        Overview.invalidateStreakCache(db)
      }
      return activation
    }
  }

  public func auditRetentionState(
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState? {
    try read { db in
      try AuditRetentionFrontier.state(db, accountIdentifier: accountIdentifier)
    }
  }

  public func auditRetentionActiveZoneName() throws -> String? {
    try read { db in try AuditRetentionFrontier.activeZoneName(db) }
  }

  public func initializeAuditRetentionForVerifiedEmptyAccount(
    accountIdentifier: String
  ) throws -> AuditRetentionAccountState {
    try write { db in
      try AuditRetentionFrontier.initializePolicyForVerifiedEmptyAccount(
        db, accountIdentifier: accountIdentifier)
    }
  }

  public func joinAuditRetentionFrontier(
    _ frontier: AuditRetentionFrontierValue,
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState {
    try write { db in
      try AuditRetentionFrontier.joinRemoteFrontier(
        db, accountIdentifier: accountIdentifier, frontier: frontier)
    }
  }

  public func adoptAuditRetentionPolicy(
    _ policy: ChangelogRetentionPolicy, policyVersion: String,
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState {
    try withAuditRetentionMutation { db in
      _ = try AuditRetentionFrontier.adoptPolicyForActiveAccount(
        db, accountIdentifier: accountIdentifier, policy: policy,
        policyVersion: policyVersion)
      try AuditRetention.enforcePolicyForAccount(
        db, accountIdentifier: accountIdentifier)
      guard
        let state = try AuditRetentionFrontier.state(
          db, accountIdentifier: accountIdentifier)
      else { throw AuditRetentionStateError.malformedAccountState(accountIdentifier) }
      return state
    }
  }

  public func authorizeAuditRetentionOutbound(
    verifiedRemoteFrontier: AuditRetentionFrontierValue,
    forAccountIdentifier accountIdentifier: String, zoneName: String
  ) throws -> AuditRetentionOutboundAuthorization {
    try withAuditRetentionMutation { db in
      try AuditRetentionFrontier.authorizeOutboundAuditPush(
        db, accountIdentifier: accountIdentifier,
        zoneName: zoneName,
        verifiedRemoteFrontier: verifiedRemoteFrontier)
    }
  }

  public func authorizeAuditRetentionOutboundAfterExactRemoteConfirmation(
    verifiedRemoteFrontier: AuditRetentionFrontierValue,
    verifiedRemotePolicy: ChangelogRetentionPolicy,
    verifiedRemotePolicyVersion: String,
    forAccountIdentifier accountIdentifier: String, zoneName: String
  ) throws -> AuditRetentionOutboundAuthorization {
    try withAuditRetentionMutation { db in
      try AuditRetentionFrontier
        .authorizeOutboundAuditPushAfterExactRemoteConfirmation(
          db, accountIdentifier: accountIdentifier, zoneName: zoneName,
          verifiedRemoteFrontier: verifiedRemoteFrontier,
          verifiedRemotePolicy: verifiedRemotePolicy,
          verifiedRemotePolicyVersion: verifiedRemotePolicyVersion)
    }
  }

  public func authorizeAuditRetentionCandidateGeneration(
    forAccountIdentifier accountIdentifier: String, candidateZoneName: String
  ) throws -> AuditRetentionCandidateAuthorization {
    try withAuditRetentionMutation { db in
      try AuditRetentionFrontier.authorizeCandidateGeneration(
        db, accountIdentifier: accountIdentifier,
        candidateZoneName: candidateZoneName)
    }
  }

  public func validateAuditRetentionCandidateGeneration(
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionAccountState {
    try read { db in
      try AuditRetentionFrontier.validateCandidateAuthorization(
        db, authorization: authorization)
    }
  }

  public func activateAuditRetentionCandidateGeneration(
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionAccountState {
    try write { db in
      try AuditRetentionFrontier.activateCandidateGeneration(
        db, authorization: authorization)
    }
  }

  public func revokeAuditRetentionCandidateGeneration(
    authorization: AuditRetentionCandidateAuthorization
  ) throws {
    try write { db in
      try AuditRetentionFrontier.revokeCandidateGeneration(
        db, authorization: authorization)
    }
  }

  public func confirmAuditRetentionFrontier(
    _ frontier: AuditRetentionFrontierValue,
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState {
    try write { db in
      try AuditRetentionFrontier.confirmRemoteFrontier(
        db, accountIdentifier: accountIdentifier,
        confirmedFrontier: frontier)
    }
  }

  public func markAuditCloudPresencePossible(
    outboxId: Int64, authorization: AuditRetentionOutboundAuthorization
  ) throws -> AuditRetentionCloudPresenceMarkResult {
    try withAuditRetentionMutation { db in
      try AuditRetentionFrontier.markCloudPresencePossible(
        db, outboxId: outboxId, authorization: authorization)
    }
  }

  public func markAuditGenerationSnapshotCloudPresencePossible(
    envelope: SyncEnvelope, authorization: AuditRetentionOutboundAuthorization
  ) throws -> AuditRetentionCloudPresenceMarkResult {
    try withAuditRetentionMutation { db in
      try AuditRetentionFrontier.markGenerationSnapshotCloudPresencePossible(
        db, envelope: envelope, authorization: authorization)
    }
  }

  public func markAuditCandidateGenerationSnapshotCloudPresencePossible(
    envelope: SyncEnvelope,
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionCloudPresenceMarkResult {
    try withAuditRetentionMutation { db in
      try AuditRetentionFrontier.markGenerationSnapshotCloudPresencePossible(
        db, envelope: envelope, candidateAuthorization: authorization)
    }
  }

  public func markAuditGenerationSnapshotBatchCloudPresencePossible(
    envelopes: [SyncEnvelope], authorization: AuditRetentionOutboundAuthorization
  ) throws -> [AuditRetentionCloudPresenceMarkResult] {
    try withAuditRetentionMutation { db in
      try AuditRetentionFrontier.markGenerationSnapshotCloudPresencePossible(
        db, envelopes: envelopes, authorization: authorization)
    }
  }

  public func markAuditCandidateGenerationSnapshotBatchCloudPresencePossible(
    envelopes: [SyncEnvelope], authorization: AuditRetentionCandidateAuthorization
  ) throws -> [AuditRetentionCloudPresenceMarkResult] {
    try withAuditRetentionMutation { db in
      try AuditRetentionFrontier.markGenerationSnapshotCloudPresencePossible(
        db, envelopes: envelopes, candidateAuthorization: authorization)
    }
  }

  public func pendingAuditRetentionPurges(
    forAccountIdentifier accountIdentifier: String, zoneName: String, limit: Int
  ) throws -> [AuditRetentionPurgeItem] {
    try read { db in
      try AuditRetentionFrontier.pendingPurges(
        db, accountIdentifier: accountIdentifier, zoneName: zoneName, limit: limit)
    }
  }

  public func acknowledgeAuditRetentionPurges(
    forAccountIdentifier accountIdentifier: String, zoneName: String,
    entityIds: [String]
  ) throws {
    try write { db in
      try AuditRetentionFrontier.acknowledgePurges(
        db, accountIdentifier: accountIdentifier, zoneName: zoneName,
        entityIds: entityIds)
    }
  }

  public func acknowledgeAuditRetentionZoneDeletion(
    forAccountIdentifier accountIdentifier: String, zoneName: String
  ) throws {
    try write { db in
      try AuditRetentionFrontier.acknowledgeZoneDeletion(
        db, accountIdentifier: accountIdentifier, zoneName: zoneName)
      try CloudInboundCompleteness.clearForDeletedZone(
        db, accountIdentifier: accountIdentifier, zoneIdentifier: zoneName)
    }
  }

  public func recordAuditRetentionPurgeFailure(
    forAccountIdentifier accountIdentifier: String, zoneName: String,
    entityId: String, error: String
  ) throws {
    try write { db in
      try AuditRetentionFrontier.recordPurgeFailure(
        db, accountIdentifier: accountIdentifier, zoneName: zoneName,
        entityId: entityId, error: error)
    }
  }
}
