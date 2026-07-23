import Foundation
import GRDB
import LorvexDomain

extension AuditRetentionFrontier {
  /// Mint a narrowly-scoped capability for copying retained audit rows into a
  /// fresh candidate generation. The active binding remains the source zone;
  /// ordinary outbox/purge APIs therefore continue to route only there.
  public static func authorizeCandidateGeneration(
    _ db: Database, accountIdentifier: String, candidateZoneName: String,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> AuditRetentionCandidateAuthorization {
    try requireActiveAccount(db, requested: accountIdentifier)
    try validateZoneName(candidateZoneName)
    guard let sourceZoneName = try activeZoneName(db),
      sourceZoneName != candidateZoneName
    else { throw AuditRetentionStateError.invalidOutboundAuthorization }

    try AuditRetention.enforcePolicyForAccount(
      db, accountIdentifier: accountIdentifier, now: now)
    guard let state = try state(db, accountIdentifier: accountIdentifier),
      state.isPolicyReady, state.policyAuthorizedEpoch == state.frontierEpoch
    else { throw AuditRetentionStateError.policyNotReady(accountIdentifier) }

    // Candidate construction is crash-resumable. Reopening the exact remote
    // lease must recover the same durable capability rather than invalidating
    // a staged snapshot by rotating its token. A row for any other candidate
    // is stale relative to the caller's exact control-plane lease; never reuse
    // it, and replace it with a fresh capability below.
    if let row = try Row.fetchOne(
      db,
      sql: """
        SELECT token, account_identifier, source_active_zone_name,
               candidate_zone_name, frontier_epoch,
               frontier_cutoff_timestamp, frontier_cutoff_entity_id,
               policy_value, policy_version
        FROM audit_retention_candidate_authorization WHERE singleton = 1
        """)
    {
      let storedAccount: String = row["account_identifier"]
      let storedSourceZone: String = row["source_active_zone_name"]
      let storedCandidateZone: String = row["candidate_zone_name"]
      let storedEpoch: Int64 = row["frontier_epoch"]
      let storedCutoffTimestamp: String = row["frontier_cutoff_timestamp"]
      let storedCutoffEntityID: String = row["frontier_cutoff_entity_id"]
      let storedPolicy: String = row["policy_value"]
      let storedPolicyVersion: String = row["policy_version"]
      let exact = [
        storedAccount == accountIdentifier,
        storedSourceZone == sourceZoneName,
        storedCandidateZone == candidateZoneName,
        storedEpoch == state.frontier.epoch,
        storedCutoffTimestamp == state.frontier.minimumRetainedTimestamp,
        storedCutoffEntityID == state.frontier.minimumRetainedEntityId,
        storedPolicy == state.policy.wireValue,
        storedPolicyVersion == state.policyVersion,
      ].allSatisfy { $0 }
      if exact {
        let token: String = row["token"]
        guard !token.isEmpty else {
          throw AuditRetentionStateError.invalidOutboundAuthorization
        }
        return AuditRetentionCandidateAuthorization(
          token: token, accountIdentifier: accountIdentifier,
          sourceActiveZoneName: sourceZoneName,
          candidateZoneName: candidateZoneName, frontier: state.frontier,
          policy: state.policy, policyVersion: state.policyVersion)
      }
    }

    let token = UUID().uuidString.lowercased()
    try db.execute(sql: "DELETE FROM audit_retention_candidate_authorization")
    try db.execute(
      sql: """
        INSERT INTO audit_retention_candidate_authorization (
          singleton, token, account_identifier, source_active_zone_name,
          candidate_zone_name, frontier_epoch, frontier_cutoff_timestamp,
          frontier_cutoff_entity_id, policy_value, policy_version, created_at
        ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [
        token, accountIdentifier, sourceZoneName, candidateZoneName,
        state.frontierEpoch, state.frontierCutoffTimestamp,
        state.frontierCutoffEntityId, state.policy.wireValue,
        state.policyVersion, now,
      ])
    return AuditRetentionCandidateAuthorization(
      token: token, accountIdentifier: accountIdentifier,
      sourceActiveZoneName: sourceZoneName,
      candidateZoneName: candidateZoneName, frontier: state.frontier,
      policy: state.policy, policyVersion: state.policyVersion)
  }

  /// Atomically move canonical routing to a successfully published candidate.
  /// Validation and the binding update share the caller's transaction, so a
  /// stale/failed candidate can never strand ordinary outbound in its zone.
  public static func activateCandidateGeneration(
    _ db: Database, authorization: AuditRetentionCandidateAuthorization,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> AuditRetentionAccountState {
    // Remote ready publication is the cross-system linearization point. A
    // local retention write may commit after the final pre-seal check but before
    // that CloudKit CAS; activation must preserve such monotonic state instead
    // of permanently wedging a remotely-ready generation on an exact snapshot.
    let state = try validatePublishedCandidateAuthorization(
      db, authorization: authorization)
    try db.execute(
      sql: """
        UPDATE audit_retention_binding
        SET active_zone_name = ?, updated_at = ?
        WHERE singleton = 1
          AND active_account_identifier = ?
          AND active_zone_name = ?
        """,
      arguments: [
        authorization.candidateZoneName, now,
        authorization.accountIdentifier, authorization.sourceActiveZoneName,
      ])
    guard db.changesCount == 1 else {
      throw AuditRetentionStateError.invalidOutboundAuthorization
    }
    // Pending audit inbox rows carry no source-zone witness and cannot cross a
    // generation activation. The ready generation will baseline them again.
    try dropAuditPendingInbox(db)
    try db.execute(sql: "DELETE FROM audit_retention_outbound_authorization")
    try db.execute(sql: "DELETE FROM audit_retention_candidate_authorization")
    return state
  }

  /// Revoke only the matching staged capability. This never touches active
  /// account/zone routing or the ordinary outbound authorization.
  public static func revokeCandidateGeneration(
    _ db: Database, authorization: AuditRetentionCandidateAuthorization
  ) throws {
    try db.execute(
      sql: """
        DELETE FROM audit_retention_candidate_authorization
        WHERE singleton = 1 AND token = ? AND account_identifier = ?
          AND source_active_zone_name = ? AND candidate_zone_name = ?
        """,
      arguments: [
        authorization.token, authorization.accountIdentifier,
        authorization.sourceActiveZoneName, authorization.candidateZoneName,
      ])
  }

  public static func validateCandidateAuthorization(
    _ db: Database, authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionAccountState {
    let state = try candidateAuthorizationStateAndIdentity(
      db, authorization: authorization)
    guard state.isPolicyReady,
      state.policyAuthorizedEpoch == state.frontierEpoch,
      state.frontier == authorization.frontier,
      state.policy == authorization.policy,
      state.policyVersion == authorization.policyVersion
    else { throw AuditRetentionStateError.invalidOutboundAuthorization }
    return state
  }

  static func validatePublishedCandidateAuthorization(
    _ db: Database, authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionAccountState {
    let state = try candidateAuthorizationStateAndIdentity(
      db, authorization: authorization)
    let policyOrdering = try comparePolicyVersion(
      incoming: state.policyVersion, stored: authorization.policyVersion,
      accountIdentifier: authorization.accountIdentifier)
    guard state.isPolicyReady,
      state.policyAuthorizedEpoch == state.frontierEpoch,
      state.frontier >= authorization.frontier,
      policyOrdering >= 0,
      policyOrdering != 0 || state.policy == authorization.policy
    else { throw AuditRetentionStateError.invalidOutboundAuthorization }
    return state
  }

  private static func candidateAuthorizationStateAndIdentity(
    _ db: Database, authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionAccountState {
    try requireActiveContext(
      db, requestedAccount: authorization.accountIdentifier,
      requestedZone: authorization.sourceActiveZoneName)
    try validateZoneName(authorization.candidateZoneName)
    guard authorization.candidateZoneName != authorization.sourceActiveZoneName,
      let state = try state(
        db, accountIdentifier: authorization.accountIdentifier),
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT token, account_identifier, source_active_zone_name,
                 candidate_zone_name, frontier_epoch,
                 frontier_cutoff_timestamp, frontier_cutoff_entity_id,
                 policy_value, policy_version
          FROM audit_retention_candidate_authorization WHERE singleton = 1
          """),
      row["token"] as String == authorization.token,
      row["account_identifier"] as String == authorization.accountIdentifier,
      row["source_active_zone_name"] as String == authorization.sourceActiveZoneName,
      row["candidate_zone_name"] as String == authorization.candidateZoneName,
      row["frontier_epoch"] as Int64 == authorization.frontier.epoch,
      row["frontier_cutoff_timestamp"] as String
        == authorization.frontier.minimumRetainedTimestamp,
      row["frontier_cutoff_entity_id"] as String
        == authorization.frontier.minimumRetainedEntityId,
      row["policy_value"] as String == authorization.policy.wireValue,
      row["policy_version"] as String == authorization.policyVersion
    else { throw AuditRetentionStateError.invalidOutboundAuthorization }
    return state
  }
}
