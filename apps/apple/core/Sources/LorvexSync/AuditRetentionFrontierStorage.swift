import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// SQL decoding, persistence, and validation support for
/// ``AuditRetentionFrontier``. State transitions remain in the primary file;
/// this file owns their durable representation and fail-closed shape checks.
extension AuditRetentionFrontier {
  struct BindingState {
    var activeAccountIdentifier: String?
    var activeZoneName: String?
    var everBound: Bool
    var unboundFrontierEpoch: Int64
    var unboundFrontierCutoffTimestamp: String
    var unboundFrontierCutoffEntityId: String
    var unboundPolicyAuthorizedEpoch: Int64
    var unboundPolicy: ChangelogRetentionPolicy
    var unboundPolicyVersion: String
    var unboundPolicyReady: Bool
  }

  static func readBinding(_ db: Database) throws -> BindingState {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT active_account_identifier, active_zone_name, ever_bound,
                 unbound_frontier_epoch, unbound_policy_authorized_epoch,
                 unbound_frontier_cutoff_timestamp,
                 unbound_frontier_cutoff_entity_id,
                 unbound_policy_value, unbound_policy_version,
                 unbound_policy_ready
          FROM audit_retention_binding WHERE singleton = 1
          """)
    else { throw AuditRetentionStateError.malformedBindingState }
    let active: String? = row["active_account_identifier"]
    let activeZone: String? = row["active_zone_name"]
    let everBoundRaw: Int64 = row["ever_bound"]
    let frontier: Int64 = row["unbound_frontier_epoch"]
    let cutoffTimestamp: String = row["unbound_frontier_cutoff_timestamp"]
    let cutoffEntityId: String = row["unbound_frontier_cutoff_entity_id"]
    let authorized: Int64 = row["unbound_policy_authorized_epoch"]
    let policyRaw: String = row["unbound_policy_value"]
    let version: String = row["unbound_policy_version"]
    let readyRaw: Int64 = row["unbound_policy_ready"]
    let bindingShapeIsValid =
      everBoundRaw == 0
      ? active == nil && activeZone == nil
      : active != nil && activeZone != nil
    guard everBoundRaw == 0 || everBoundRaw == 1,
      readyRaw == 0 || readyRaw == 1, frontier >= 0,
      authorized >= 0, authorized <= frontier,
      (readyRaw == 0 || authorized == frontier),
      bindingShapeIsValid,
      canonicalPolicy(raw: policyRaw) != nil
    else { throw AuditRetentionStateError.malformedBindingState }
    if let active { try validateAccountIdentifier(active) }
    if let activeZone { try validateZoneName(activeZone) }
    try validateFrontier(
      AuditRetentionFrontierValue(
        epoch: frontier, minimumRetainedTimestamp: cutoffTimestamp,
        minimumRetainedEntityId: cutoffEntityId))
    _ = try validatedPolicyVersion(version, accountIdentifier: "<unbound>")
    return BindingState(
      activeAccountIdentifier: active, activeZoneName: activeZone,
      everBound: everBoundRaw == 1,
      unboundFrontierEpoch: frontier,
      unboundFrontierCutoffTimestamp: cutoffTimestamp,
      unboundFrontierCutoffEntityId: cutoffEntityId,
      unboundPolicyAuthorizedEpoch: authorized,
      unboundPolicy: ChangelogRetentionPolicy.parse(policyRaw),
      unboundPolicyVersion: version, unboundPolicyReady: readyRaw == 1)
  }

  static func decodeAccountState(
    _ row: Row, expectedAccountIdentifier: String
  ) throws -> AuditRetentionAccountState {
    let account: String = row["account_identifier"]
    let frontier: Int64 = row["frontier_epoch"]
    let frontierCutoffTimestamp: String = row["frontier_cutoff_timestamp"]
    let frontierCutoffEntityId: String = row["frontier_cutoff_entity_id"]
    let confirmed: Int64 = row["confirmed_frontier_epoch"]
    let confirmedCutoffTimestamp: String = row["confirmed_cutoff_timestamp"]
    let confirmedCutoffEntityId: String = row["confirmed_cutoff_entity_id"]
    let authorized: Int64 = row["policy_authorized_epoch"]
    let policyRaw: String = row["policy_value"]
    let policyVersion: String = row["policy_version"]
    let readyRaw: Int64 = row["policy_ready"]
    let refresh: Int64? = row["refresh_required_epoch"]
    guard account == expectedAccountIdentifier,
      frontier >= 0, confirmed >= 0, confirmed <= frontier,
      authorized >= 0, authorized <= frontier,
      readyRaw == 0 || readyRaw == 1,
      (readyRaw == 0 || authorized == frontier),
      refresh.map({ $0 >= 0 }) ?? true,
      canonicalPolicy(raw: policyRaw) != nil
    else { throw AuditRetentionStateError.malformedAccountState(expectedAccountIdentifier) }
    _ = try validatedPolicyVersion(policyVersion, accountIdentifier: account)
    let frontierValue = AuditRetentionFrontierValue(
      epoch: frontier, minimumRetainedTimestamp: frontierCutoffTimestamp,
      minimumRetainedEntityId: frontierCutoffEntityId)
    let confirmedValue = AuditRetentionFrontierValue(
      epoch: confirmed, minimumRetainedTimestamp: confirmedCutoffTimestamp,
      minimumRetainedEntityId: confirmedCutoffEntityId)
    try validateFrontier(frontierValue)
    try validateFrontier(confirmedValue)
    guard confirmedValue <= frontierValue else {
      throw AuditRetentionStateError.malformedAccountState(expectedAccountIdentifier)
    }
    return AuditRetentionAccountState(
      accountIdentifier: account, frontierEpoch: frontier,
      frontierCutoffTimestamp: frontierCutoffTimestamp,
      frontierCutoffEntityId: frontierCutoffEntityId,
      confirmedFrontierEpoch: confirmed,
      confirmedCutoffTimestamp: confirmedCutoffTimestamp,
      confirmedCutoffEntityId: confirmedCutoffEntityId,
      policyAuthorizedEpoch: authorized,
      policy: ChangelogRetentionPolicy.parse(policyRaw), policyVersion: policyVersion,
      isPolicyReady: readyRaw == 1, refreshRequiredEpoch: refresh)
  }

  static func persist(
    _ state: AuditRetentionAccountState, db: Database, now: String
  ) throws {
    guard state.frontierEpoch >= 0, state.confirmedFrontierEpoch >= 0,
      state.confirmedFrontierEpoch <= state.frontierEpoch,
      state.policyAuthorizedEpoch >= 0,
      state.policyAuthorizedEpoch <= state.frontierEpoch,
      (!state.isPolicyReady || state.policyAuthorizedEpoch == state.frontierEpoch),
      state.refreshRequiredEpoch.map({ $0 >= 0 }) ?? true
    else { throw AuditRetentionStateError.malformedAccountState(state.accountIdentifier) }
    try validateFrontier(state.frontier)
    try validateFrontier(state.confirmedFrontier)
    guard state.confirmedFrontier <= state.frontier else {
      throw AuditRetentionStateError.malformedAccountState(state.accountIdentifier)
    }
    try db.execute(
      sql: """
        UPDATE audit_retention_account_state
        SET frontier_epoch = ?, frontier_cutoff_timestamp = ?,
            frontier_cutoff_entity_id = ?, confirmed_frontier_epoch = ?,
            confirmed_cutoff_timestamp = ?, confirmed_cutoff_entity_id = ?,
            policy_authorized_epoch = ?, policy_value = ?, policy_version = ?,
            policy_ready = ?, refresh_required_epoch = ?, updated_at = ?
        WHERE account_identifier = ?
        """,
      arguments: [
        state.frontierEpoch, state.frontierCutoffTimestamp,
        state.frontierCutoffEntityId, state.confirmedFrontierEpoch,
        state.confirmedCutoffTimestamp, state.confirmedCutoffEntityId,
        state.policyAuthorizedEpoch, state.policy.wireValue, state.policyVersion,
        state.isPolicyReady ? 1 : 0, state.refreshRequiredEpoch, now,
        state.accountIdentifier,
      ])
    guard db.changesCount == 1 else {
      throw AuditRetentionStateError.malformedAccountState(state.accountIdentifier)
    }
  }

  static func requireActiveAccount(_ db: Database, requested: String) throws {
    try validateAccountIdentifier(requested)
    guard let active = try readBinding(db).activeAccountIdentifier else {
      throw AuditRetentionStateError.noActiveAccount
    }
    guard active == requested else {
      throw AuditRetentionStateError.activeAccountMismatch(expected: active, requested: requested)
    }
  }

  static func requireActiveContext(
    _ db: Database, requestedAccount: String, requestedZone: String
  ) throws {
    try requireActiveAccount(db, requested: requestedAccount)
    try validateZoneName(requestedZone)
    guard let activeZone = try readBinding(db).activeZoneName else {
      throw AuditRetentionStateError.noActiveAccount
    }
    guard activeZone == requestedZone else {
      throw AuditRetentionStateError.activeZoneMismatch(
        expected: activeZone, requested: requestedZone)
    }
  }

  static func validateAccountIdentifier(_ value: String) throws {
    guard !value.isEmpty, value.utf8.count <= 512 else {
      throw AuditRetentionStateError.invalidAccountIdentifier
    }
  }

  static func validateZoneName(_ value: String) throws {
    guard !value.isEmpty, value.utf8.count <= 512 else {
      throw AuditRetentionStateError.invalidZoneName
    }
  }

  static func validateEpoch(_ epoch: Int64) throws {
    guard epoch >= 0 else { throw AuditRetentionStateError.invalidEpoch(epoch) }
  }

  static func validateFrontier(_ frontier: AuditRetentionFrontierValue) throws {
    try validateEpoch(frontier.epoch)
    if frontier.minimumRetainedTimestamp.isEmpty {
      guard frontier.minimumRetainedEntityId.isEmpty else {
        throw AuditRetentionStateError.invalidFrontier
      }
      return
    }
    guard
      SyncTimestamp.parse(frontier.minimumRetainedTimestamp)?.asString
        == frontier.minimumRetainedTimestamp,
      frontier.minimumRetainedEntityId.utf8.count <= 512
    else { throw AuditRetentionStateError.invalidFrontier }
  }

  private static func canonicalPolicy(raw: String) -> ChangelogRetentionPolicy? {
    let parsed = ChangelogRetentionPolicy.parse(raw)
    return parsed.wireValue == raw ? parsed : nil
  }

  private static func validatedPolicyVersion(
    _ value: String, accountIdentifier: String
  ) throws -> Hlc? {
    if value.isEmpty { return nil }
    guard let parsed = try? Hlc.parseCanonical(value) else {
      throw AuditRetentionStateError.malformedAccountState(accountIdentifier)
    }
    return parsed
  }

  static func comparePolicyVersion(
    incoming: String, stored: String, accountIdentifier: String
  ) throws -> Int {
    let incomingHlc = try validatedPolicyVersion(incoming, accountIdentifier: accountIdentifier)
    let storedHlc = try validatedPolicyVersion(stored, accountIdentifier: accountIdentifier)
    switch (incomingHlc, storedHlc) {
    case (nil, nil): return 0
    case (nil, .some): return -1
    case (.some, nil): return 1
    case (.some(let incoming), .some(let stored)):
      if incoming < stored { return -1 }
      if incoming > stored { return 1 }
      return 0
    }
  }

  static func incrementEpoch(
    _ epoch: Int64, accountIdentifier: String
  ) throws -> Int64 {
    guard epoch < Int64.max else {
      throw AuditRetentionStateError.malformedAccountState(accountIdentifier)
    }
    return epoch + 1
  }

  static func policyTransitionNeedsGeneration(
    from old: ChangelogRetentionPolicy, to new: ChangelogRetentionPolicy
  ) -> Bool {
    switch (old, new) {
    case (.off, .off), (.maximum, .maximum):
      return false
    case (.off, _), (_, .off):
      return true
    case (.days(let oldDays), .days(let newDays)):
      return newDays > oldDays
    case (.days, .maximum):
      return true
    case (.maximum, .days):
      return false
    }
  }
}
