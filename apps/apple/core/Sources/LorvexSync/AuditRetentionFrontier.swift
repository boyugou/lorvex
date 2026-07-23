import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Account binding, monotonic frontier joins, and policy-generation fencing for
/// the synced audit stream.
///
/// This is the sole SQL owner for `audit_retention_binding` and
/// `audit_retention_account_state`. Transport consumes the typed methods; it
/// must never reproduce the state transitions with checkpoint strings or ad-hoc
/// SQL.
public enum AuditRetentionFrontier {
  struct UnboundScopeState {
    var frontier: AuditRetentionFrontierValue
    var policy: ChangelogRetentionPolicy
    var isPolicyReady: Bool
  }
  /// Bind the database to the CloudKit account that is about to sync.
  ///
  /// The first-ever binding consumes the unbound candidate and assigns only
  /// cloud-unseen, account-NULL audit rows to that account. Every later new
  /// account starts independently and policy-unready. Switching accounts swaps
  /// the device's single audit working set: canonical rows and every identity-
  /// scoped sync cache are removed before the new binding becomes active. The
  /// account-scoped frontier, cloud-presence evidence, and physical-purge queue
  /// remain durable; switching back rebuilds canonical history from that
  /// account's authoritative CloudKit generation instead of retaining private
  /// content from two accounts in one queryable table.
  public static func activateAccount(
    _ db: Database, accountIdentifier: String, zoneName: String,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> AuditRetentionAccountActivation {
    try validateAccountIdentifier(accountIdentifier)
    try validateZoneName(zoneName)
    try enforceControlPlanePreferenceIsolation(db)
    let binding = try readBinding(db)

    let kind: AuditRetentionAccountActivationKind
    if !binding.everBound {
      try db.execute(
        sql: """
            INSERT INTO audit_retention_account_state (
            account_identifier, frontier_epoch, frontier_cutoff_timestamp,
            frontier_cutoff_entity_id, confirmed_frontier_epoch,
            confirmed_cutoff_timestamp, confirmed_cutoff_entity_id,
            policy_authorized_epoch, policy_value, policy_version,
            policy_ready, refresh_required_epoch, created_at, updated_at
          ) VALUES (?, ?, ?, ?, 0, '', '', ?, ?, ?, ?, NULL, ?, ?)
          """,
        arguments: [
          accountIdentifier, binding.unboundFrontierEpoch,
          binding.unboundFrontierCutoffTimestamp,
          binding.unboundFrontierCutoffEntityId,
          binding.unboundPolicyAuthorizedEpoch, binding.unboundPolicy.wireValue,
          binding.unboundPolicyVersion, binding.unboundPolicyReady ? 1 : 0, now, now,
        ])
      try db.execute(
        sql: """
          UPDATE audit_retention_binding
          SET active_account_identifier = ?, active_zone_name = ?,
              ever_bound = 1, updated_at = ?
          WHERE singleton = 1
          """,
        arguments: [accountIdentifier, zoneName, now])
      try normalizeCloudUnseenAuditRows(
        db, accountIdentifier: accountIdentifier, epoch: binding.unboundFrontierEpoch)
      kind = .firstBinding
    } else {
      if let priorAccount = binding.activeAccountIdentifier,
        priorAccount != accountIdentifier
      {
        try clearAuditWorkingSetForAccountSwitch(db)
      }
      let alreadyKnown = try state(db, accountIdentifier: accountIdentifier) != nil
      if !alreadyKnown {
        // Deliberately neutral and unready: neither the old account's current
        // preference row nor its frontier is evidence about this account.
        try db.execute(
          sql: """
            INSERT INTO audit_retention_account_state (
              account_identifier, frontier_epoch, frontier_cutoff_timestamp,
              frontier_cutoff_entity_id, confirmed_frontier_epoch,
              confirmed_cutoff_timestamp, confirmed_cutoff_entity_id,
              policy_authorized_epoch, policy_value, policy_version,
              policy_ready, refresh_required_epoch, created_at, updated_at
            ) VALUES (?, 0, '', '', 0, '', '', 0, ?, '', 0, NULL, ?, ?)
            """,
          arguments: [accountIdentifier, ChangelogRetentionPolicy.maximum.wireValue, now, now])
      }
      try db.execute(
        sql: """
          UPDATE audit_retention_binding
          SET active_account_identifier = ?, active_zone_name = ?, updated_at = ?
          WHERE singleton = 1
          """,
        arguments: [accountIdentifier, zoneName, now])
      if binding.activeAccountIdentifier != accountIdentifier {
        // The working-set swap above already removed every audit pending row.
      } else if binding.activeZoneName != zoneName {
        // Pending inbound rows do not carry their source zone. They cannot be
        // reinterpreted inside the newly activated generation. Outbound audit
        // rows are different: they belong to the same account and are exactly
        // the unsent history the candidate generation must preserve.
        try dropAuditPendingInbox(db)
      }
      kind = alreadyKnown ? .resumedAccount : .newAccount
    }

    try repairActiveWorkingSetIsolation(
      db, accountIdentifier: accountIdentifier)
    // Every activation starts a new transport cycle. An authorization minted
    // against an earlier remote-frontier read is no longer sufficient.
    try db.execute(sql: "DELETE FROM audit_retention_outbound_authorization")
    guard let activated = try state(db, accountIdentifier: accountIdentifier) else {
      throw AuditRetentionStateError.malformedAccountState(accountIdentifier)
    }
    return AuditRetentionAccountActivation(kind: kind, state: activated)
  }

  /// Enforce that audit retention has exactly one sync authority. The product
  /// exposes its policy through the preference API, but the ordinary preference
  /// table/entity stream must contain no copy that can race the account-scoped
  /// metadata during account switches or generation capture.
  public static func enforceControlPlanePreferenceIsolation(_ db: Database) throws {
    let key = PreferenceKeys.prefAiChangelogRetentionPolicy
    try db.execute(sql: "DELETE FROM preferences WHERE key = ?", arguments: [key])
    try db.execute(
      sql: "DELETE FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
      arguments: [EntityName.preference, key])
    try db.execute(
      sql:
        "DELETE FROM sync_pending_inbox WHERE envelope_entity_type = ? AND envelope_entity_id = ?",
      arguments: [EntityName.preference, key])
    try db.execute(
      sql: "DELETE FROM sync_payload_shadow WHERE entity_type = ? AND entity_id = ?",
      arguments: [EntityName.preference, key])
    try db.execute(
      sql: "DELETE FROM sync_quarantine_blocklist WHERE entity_type = ? AND entity_id = ?",
      arguments: [EntityName.preference, key])
    try db.execute(
      sql: "DELETE FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
      arguments: [EntityName.preference, key])
  }

  /// Remove the complete user-queryable / transport-working audit surface while
  /// preserving account-scoped control-plane evidence. This runs before the
  /// binding update in the caller's transaction, so readers can observe neither
  /// old-account content under a new binding nor a half-cleared switch.
  private static func clearAuditWorkingSetForAccountSwitch(_ db: Database) throws {
    try db.execute(
      sql: "DELETE FROM sync_outbox WHERE entity_type = ?",
      arguments: [EntityName.aiChangelog])
    try db.execute(
      sql: "DELETE FROM sync_pending_inbox WHERE envelope_entity_type = ?",
      arguments: [EntityName.aiChangelog])
    try db.execute(
      sql: "DELETE FROM sync_payload_shadow WHERE entity_type = ?",
      arguments: [EntityName.aiChangelog])
    try db.execute(
      sql: "DELETE FROM sync_quarantine_blocklist WHERE entity_type = ?",
      arguments: [EntityName.aiChangelog])
    // Current schema forbids audit tombstones. Keep the defensive identity
    // cleanup so a manually repaired or partially written database cannot make
    // one account's audit identity visible after the binding changes.
    try db.execute(
      sql: "DELETE FROM sync_tombstones WHERE entity_type = ?",
      arguments: [EntityName.aiChangelog])
    try db.execute(sql: "DELETE FROM ai_changelog")
  }

  /// Repair the single-queryable-working-set invariant even when a database was
  /// manually edited or a transaction was interrupted outside Lorvex's write
  /// funnel. Account-scoped frontier, presence, and purge evidence stays
  /// durable; only canonical content and its ordinary sync caches are removed.
  private static func repairActiveWorkingSetIsolation(
    _ db: Database, accountIdentifier: String
  ) throws {
    let foreignIdentitySQL = """
      SELECT id FROM ai_changelog
      WHERE retention_account_identifier IS NOT NULL
        AND retention_account_identifier <> ?
      """
    try db.execute(
      sql: """
        DELETE FROM sync_outbox
        WHERE entity_type = ? AND entity_id IN (\(foreignIdentitySQL))
        """,
      arguments: [EntityName.aiChangelog, accountIdentifier])
    try db.execute(
      sql: """
        DELETE FROM sync_pending_inbox
        WHERE envelope_entity_type = ?
          AND envelope_entity_id IN (\(foreignIdentitySQL))
        """,
      arguments: [EntityName.aiChangelog, accountIdentifier])
    for table in ["sync_payload_shadow", "sync_quarantine_blocklist", "sync_tombstones"] {
      try db.execute(
        sql: """
          DELETE FROM \(table)
          WHERE entity_type = ? AND entity_id IN (\(foreignIdentitySQL))
          """,
        arguments: [EntityName.aiChangelog, accountIdentifier])
    }
    try db.execute(
      sql: """
        DELETE FROM ai_changelog
        WHERE retention_account_identifier IS NOT NULL
          AND retention_account_identifier <> ?
        """,
      arguments: [accountIdentifier])
  }

  /// The currently active account, if this database has ever been bound.
  public static func activeAccountIdentifier(_ db: Database) throws -> String? {
    try readBinding(db).activeAccountIdentifier
  }

  /// Exact CloudKit generation zone bound to the active sync traversal.
  public static func activeZoneName(_ db: Database) throws -> String? {
    try readBinding(db).activeZoneName
  }

  /// Initialize the neutral retention contract for a newly seen account whose
  /// CloudKit control plane has been independently verified empty.
  ///
  /// A later account must never inherit the previous account's frontier,
  /// policy version, or retained-set evidence. ``activateAccount`` therefore
  /// creates it policy-unready. The generation bootstrap calls this method only
  /// after observing no predecessor generation/metadata in that account. The
  /// exact neutral-shape guard makes a mistaken call against a non-empty or
  /// partially adopted account fail closed.
  public static func initializePolicyForVerifiedEmptyAccount(
    _ db: Database, accountIdentifier: String,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> AuditRetentionAccountState {
    try requireActiveAccount(db, requested: accountIdentifier)
    guard let current = try state(db, accountIdentifier: accountIdentifier) else {
      throw AuditRetentionStateError.malformedAccountState(accountIdentifier)
    }
    if current.isPolicyReady { return current }
    guard current.frontier == .initial,
      current.confirmedFrontier == .initial,
      current.policyAuthorizedEpoch == 0,
      current.policy == .maximum,
      current.policyVersion.isEmpty,
      current.refreshRequiredEpoch == nil
    else { throw AuditRetentionStateError.policyNotReady(accountIdentifier) }
    return try adoptPolicyForActiveAccount(
      db, accountIdentifier: accountIdentifier, policy: .maximum,
      policyVersion: "", now: now)
  }

  /// Read one account's state, validating every relational invariant.
  public static func state(
    _ db: Database, accountIdentifier: String
  ) throws -> AuditRetentionAccountState? {
    try validateAccountIdentifier(accountIdentifier)
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT account_identifier, frontier_epoch, frontier_cutoff_timestamp,
                 frontier_cutoff_entity_id, confirmed_frontier_epoch,
                 confirmed_cutoff_timestamp, confirmed_cutoff_entity_id,
                 policy_authorized_epoch, policy_value, policy_version,
                 policy_ready, refresh_required_epoch
          FROM audit_retention_account_state
          WHERE account_identifier = ?
          """,
        arguments: [accountIdentifier])
    else { return nil }
    return try decodeAccountState(row, expectedAccountIdentifier: accountIdentifier)
  }

  static func allAccountStates(_ db: Database) throws -> [AuditRetentionAccountState] {
    let accounts = try String.fetchAll(
      db,
      sql: """
        SELECT account_identifier FROM audit_retention_account_state
        ORDER BY account_identifier ASC
        """)
    return try accounts.compactMap { try state(db, accountIdentifier: $0) }
  }

  static func unboundScopeState(_ db: Database) throws -> UnboundScopeState? {
    let binding = try readBinding(db)
    guard binding.activeAccountIdentifier == nil else { return nil }
    return UnboundScopeState(
      frontier: AuditRetentionFrontierValue(
        epoch: binding.unboundFrontierEpoch,
        minimumRetainedTimestamp: binding.unboundFrontierCutoffTimestamp,
        minimumRetainedEntityId: binding.unboundFrontierCutoffEntityId),
      policy: binding.unboundPolicy, isPolicyReady: binding.unboundPolicyReady)
  }

  /// Effective policy for the currently active account, or the pre-binding
  /// scope before CloudKit activation. This is the sole backing read for the
  /// virtual retention preference.
  public static func currentPolicy(_ db: Database) throws -> ChangelogRetentionPolicy {
    let binding = try readBinding(db)
    guard let account = binding.activeAccountIdentifier else {
      return binding.unboundPolicy
    }
    guard let current = try state(db, accountIdentifier: account) else {
      throw AuditRetentionStateError.malformedAccountState(account)
    }
    return current.policy
  }

  /// HLC version of the current policy contract. Local preference writes use
  /// this as a dominance floor so an explicit owner choice cannot silently lose
  /// to metadata previously observed from another device.
  public static func currentPolicyVersion(_ db: Database) throws -> String {
    let binding = try readBinding(db)
    guard let account = binding.activeAccountIdentifier else {
      return binding.unboundPolicyVersion
    }
    guard let current = try state(db, accountIdentifier: account) else {
      throw AuditRetentionStateError.malformedAccountState(account)
    }
    return current.policyVersion
  }

  /// Write context stamped onto a newly-authored local audit row.
  public static func currentWriteContext(_ db: Database) throws -> AuditRetentionWriteContext {
    let binding = try readBinding(db)
    guard let account = binding.activeAccountIdentifier else {
      return AuditRetentionWriteContext(
        accountIdentifier: nil, retentionEpoch: binding.unboundFrontierEpoch,
        isPolicyReady: binding.unboundPolicyReady)
    }
    guard let state = try state(db, accountIdentifier: account) else {
      throw AuditRetentionStateError.malformedAccountState(account)
    }
    return AuditRetentionWriteContext(
      accountIdentifier: account, retentionEpoch: state.frontierEpoch,
      isPolicyReady: state.isPolicyReady)
  }

  /// Whether a newly-authored audit row belongs inside the current local
  /// policy/frontier. The business mutation still commits when this returns
  /// false; only its optional audit record is suppressed.
  public static func shouldRecordLocalAudit(
    _ db: Database, context: AuditRetentionWriteContext,
    timestamp: String, entityId: String
  ) throws -> Bool {
    guard SyncTimestamp.parse(timestamp)?.asString == timestamp, !entityId.isEmpty else {
      throw AuditRetentionStateError.invalidFrontier
    }
    if let account = context.accountIdentifier {
      guard let state = try state(db, accountIdentifier: account) else {
        throw AuditRetentionStateError.malformedAccountState(account)
      }
      guard state.frontierEpoch == context.retentionEpoch else {
        throw AuditRetentionStateError.malformedAccountState(account)
      }
      if case .off = state.policy { return false }
      return !rowIsDominated(
        epoch: context.retentionEpoch, timestamp: timestamp,
        entityId: entityId, by: state.frontier)
    }
    let binding = try readBinding(db)
    guard binding.activeAccountIdentifier == nil,
      binding.unboundFrontierEpoch == context.retentionEpoch
    else { throw AuditRetentionStateError.malformedBindingState }
    if case .off = binding.unboundPolicy { return false }
    return !rowIsDominated(
      epoch: context.retentionEpoch, timestamp: timestamp, entityId: entityId,
      by: AuditRetentionFrontierValue(
        epoch: binding.unboundFrontierEpoch,
        minimumRetainedTimestamp: binding.unboundFrontierCutoffTimestamp,
        minimumRetainedEntityId: binding.unboundFrontierCutoffEntityId))
  }

  /// Monotonic join of a remote account frontier. This never authorizes the
  /// local policy to act on the joined generation; until the matching policy
  /// transition is adopted, future-generation audit rows remain HOLDed.
  public static func joinRemoteFrontier(
    _ db: Database, accountIdentifier: String,
    frontier: AuditRetentionFrontierValue,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> AuditRetentionAccountState {
    try requireActiveAccount(db, requested: accountIdentifier)
    try validateFrontier(frontier)
    guard var current = try state(db, accountIdentifier: accountIdentifier) else {
      throw AuditRetentionStateError.malformedAccountState(accountIdentifier)
    }
    let priorFrontier = current.frontier
    current.frontier = max(current.frontier, frontier)
    if current.frontierEpoch > current.policyAuthorizedEpoch {
      current.isPolicyReady = false
    }
    if let required = current.refreshRequiredEpoch,
      required <= current.policyAuthorizedEpoch
    {
      current.refreshRequiredEpoch = nil
    }
    try persist(current, db: db, now: now)
    if current.frontier != priorFrontier {
      try db.execute(sql: "DELETE FROM audit_retention_outbound_authorization")
    }
    return current
  }

  /// Monotonic acknowledgement of the account frontier known durable remotely.
  /// Confirmation also joins the local frontier, so `confirmed <= frontier`
  /// remains structural rather than a caller convention.
  public static func confirmRemoteFrontier(
    _ db: Database, accountIdentifier: String,
    confirmedFrontier: AuditRetentionFrontierValue,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> AuditRetentionAccountState {
    try requireActiveAccount(db, requested: accountIdentifier)
    try validateFrontier(confirmedFrontier)
    guard var current = try state(db, accountIdentifier: accountIdentifier) else {
      throw AuditRetentionStateError.malformedAccountState(accountIdentifier)
    }
    let priorFrontier = current.frontier
    current.frontier = max(current.frontier, confirmedFrontier)
    current.confirmedFrontier = max(current.confirmedFrontier, confirmedFrontier)
    if current.frontierEpoch > current.policyAuthorizedEpoch {
      current.isPolicyReady = false
    }
    try persist(current, db: db, now: now)
    if current.frontier != priorFrontier {
      try db.execute(sql: "DELETE FROM audit_retention_outbound_authorization")
    }
    return current
  }

  /// Join the verified remote frontier, retire every dominated local/outbox
  /// audit copy, then mint the opaque authorization required by
  /// `markCloudPresencePossible`. This is the only safe pre-push entry point.
  public static func authorizeOutboundAuditPush(
    _ db: Database, accountIdentifier: String,
    zoneName: String,
    verifiedRemoteFrontier: AuditRetentionFrontierValue,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> AuditRetentionOutboundAuthorization {
    try requireActiveContext(
      db, requestedAccount: accountIdentifier, requestedZone: zoneName)
    var current = try joinRemoteFrontier(
      db, accountIdentifier: accountIdentifier,
      frontier: verifiedRemoteFrontier, now: now)
    guard current.isPolicyReady else {
      throw AuditRetentionStateError.policyNotReady(accountIdentifier)
    }
    try AuditRetention.enforcePolicyForAccount(
      db, accountIdentifier: accountIdentifier, now: now)
    guard let policyApplied = try state(db, accountIdentifier: accountIdentifier) else {
      throw AuditRetentionStateError.malformedAccountState(accountIdentifier)
    }
    current = policyApplied
    try pruneAuditRowsDominatedByFrontier(
      db, accountIdentifier: accountIdentifier, frontier: current.frontier, now: now)
    guard let refreshed = try state(db, accountIdentifier: accountIdentifier) else {
      throw AuditRetentionStateError.malformedAccountState(accountIdentifier)
    }
    current = refreshed
    return try mintOutboundAuthorization(
      db, accountIdentifier: accountIdentifier, zoneName: zoneName,
      state: current, now: now)
  }

  /// Mint an authorization only for metadata already CAS-published and then
  /// confirmed by the transport. Unlike ``authorizeOutboundAuditPush``, this
  /// deliberately does not advance a rolling time cutoff again: doing so after
  /// the metadata merge would authorize a frontier the fleet has never seen.
  /// Any local retention mutation between merge and this transaction makes the
  /// exact-state guard fail, so the next cycle republishes the newer proposal.
  public static func authorizeOutboundAuditPushAfterExactRemoteConfirmation(
    _ db: Database, accountIdentifier: String, zoneName: String,
    verifiedRemoteFrontier: AuditRetentionFrontierValue,
    verifiedRemotePolicy: ChangelogRetentionPolicy,
    verifiedRemotePolicyVersion: String,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> AuditRetentionOutboundAuthorization {
    try requireActiveContext(
      db, requestedAccount: accountIdentifier, requestedZone: zoneName)
    try validateFrontier(verifiedRemoteFrontier)
    guard let current = try state(db, accountIdentifier: accountIdentifier),
      current.isPolicyReady,
      current.policyAuthorizedEpoch == current.frontierEpoch,
      current.frontier == verifiedRemoteFrontier,
      current.confirmedFrontier >= verifiedRemoteFrontier,
      current.policy == verifiedRemotePolicy,
      current.policyVersion == verifiedRemotePolicyVersion
    else { throw AuditRetentionStateError.invalidOutboundAuthorization }
    try pruneAuditRowsDominatedByFrontier(
      db, accountIdentifier: accountIdentifier,
      frontier: verifiedRemoteFrontier, now: now)
    guard let refreshed = try state(db, accountIdentifier: accountIdentifier),
      refreshed.frontier == verifiedRemoteFrontier,
      refreshed.policy == verifiedRemotePolicy,
      refreshed.policyVersion == verifiedRemotePolicyVersion,
      refreshed.isPolicyReady,
      refreshed.policyAuthorizedEpoch == refreshed.frontierEpoch
    else { throw AuditRetentionStateError.invalidOutboundAuthorization }
    return try mintOutboundAuthorization(
      db, accountIdentifier: accountIdentifier, zoneName: zoneName,
      state: refreshed, now: now)
  }

  private static func mintOutboundAuthorization(
    _ db: Database, accountIdentifier: String, zoneName: String,
    state current: AuditRetentionAccountState, now: String
  ) throws -> AuditRetentionOutboundAuthorization {
    let token = UUID().uuidString.lowercased()
    try db.execute(sql: "DELETE FROM audit_retention_outbound_authorization")
    try db.execute(
      sql: """
        INSERT INTO audit_retention_outbound_authorization (
          singleton, token, account_identifier, zone_name, frontier_epoch,
          frontier_cutoff_timestamp, frontier_cutoff_entity_id, created_at
        ) VALUES (1, ?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [
        token, accountIdentifier, zoneName, current.frontierEpoch,
        current.frontierCutoffTimestamp, current.frontierCutoffEntityId, now,
      ])
    return AuditRetentionOutboundAuthorization(
      token: token, accountIdentifier: accountIdentifier, zoneName: zoneName,
      frontier: current.frontier)
  }

  /// Advance an account's same-generation minimum-retained key. Time-window GC
  /// calls this as wall time moves; the tuple closes the resurrection hole that
  /// a generation number alone cannot represent.
  @discardableResult
  public static func advanceMinimumRetainedKey(
    _ db: Database, accountIdentifier: String,
    minimumRetainedTimestamp: String, minimumRetainedEntityId: String = "",
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> AuditRetentionAccountState {
    guard var current = try state(db, accountIdentifier: accountIdentifier) else {
      throw AuditRetentionStateError.malformedAccountState(accountIdentifier)
    }
    let candidate = AuditRetentionFrontierValue(
      epoch: current.frontierEpoch,
      minimumRetainedTimestamp: minimumRetainedTimestamp,
      minimumRetainedEntityId: minimumRetainedEntityId)
    try validateFrontier(candidate)
    current.frontier = max(current.frontier, candidate)
    try persist(current, db: db, now: now)
    // A frontier change invalidates the retained set authorized for transport.
    // Delete eagerly as well as relying on tuple validation so no stale token
    // remains durable after this transaction.
    try db.execute(sql: "DELETE FROM audit_retention_outbound_authorization")
    try pruneAuditRowsDominatedByFrontier(
      db, accountIdentifier: accountIdentifier, frontier: current.frontier, now: now)
    return current
  }

  /// Pre-account twin of `advanceMinimumRetainedKey`.
  public static func advanceUnboundMinimumRetainedKey(
    _ db: Database, minimumRetainedTimestamp: String,
    minimumRetainedEntityId: String = "",
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws {
    let binding = try readBinding(db)
    guard binding.activeAccountIdentifier == nil else {
      throw AuditRetentionStateError.malformedBindingState
    }
    let current = AuditRetentionFrontierValue(
      epoch: binding.unboundFrontierEpoch,
      minimumRetainedTimestamp: binding.unboundFrontierCutoffTimestamp,
      minimumRetainedEntityId: binding.unboundFrontierCutoffEntityId)
    let candidate = AuditRetentionFrontierValue(
      epoch: current.epoch,
      minimumRetainedTimestamp: minimumRetainedTimestamp,
      minimumRetainedEntityId: minimumRetainedEntityId)
    try validateFrontier(candidate)
    let joined = max(current, candidate)
    try db.execute(
      sql: """
        UPDATE audit_retention_binding
        SET unbound_frontier_cutoff_timestamp = ?,
            unbound_frontier_cutoff_entity_id = ?, updated_at = ?
        WHERE singleton = 1
        """,
      arguments: [
        joined.minimumRetainedTimestamp, joined.minimumRetainedEntityId, now,
      ])
    try pruneAuditRowsDominatedByFrontier(
      db, accountIdentifier: nil, frontier: joined, now: now)
  }

  /// Adopt the active account's authoritative retention policy/version.
  /// Call this only after activation and after that account's metadata frontier
  /// has been observed (or after a local explicit policy write).
  ///
  /// Entering disabled retention, re-enabling it, or widening the window fences
  /// old stricter devices by advancing a generation. When a remote frontier
  /// arrived first, the matching newer policy adopts that frontier rather than
  /// incrementing a second time.
  public static func adoptPolicyForActiveAccount(
    _ db: Database, accountIdentifier: String,
    policy: ChangelogRetentionPolicy, policyVersion: String,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> AuditRetentionAccountState {
    try requireActiveAccount(db, requested: accountIdentifier)
    guard var current = try state(db, accountIdentifier: accountIdentifier) else {
      throw AuditRetentionStateError.malformedAccountState(accountIdentifier)
    }
    let priorPolicy = current.policy
    let priorPolicyVersion = current.policyVersion
    let priorPolicyReady = current.isPolicyReady
    let priorPolicyAuthorizedEpoch = current.policyAuthorizedEpoch
    let wasPolicyReady = current.isPolicyReady
    let ordering = try comparePolicyVersion(
      incoming: policyVersion, stored: current.policyVersion,
      accountIdentifier: accountIdentifier)
    if ordering < 0 { return current }
    if ordering == 0 {
      // Equal-version divergence can be produced only by damaged/restored
      // state or a historical implementation bug. Converge to the same
      // data-preserving join as the CloudKit metadata layer; throwing here
      // would wedge every ready cycle before its CAS had a chance to repair the
      // record. No extra epoch is needed: all current clients apply this join
      // before enforcing the policy, and the maximum observed frontier remains
      // authoritative.
      current.policy = ChangelogRetentionPolicy.conservativeCollisionWinner(
        current.policy, policy)
      if !current.isPolicyReady {
        current.isPolicyReady = true
        current.policyAuthorizedEpoch = current.frontierEpoch
      }
    } else {
      let mustAdvance = policyTransitionNeedsGeneration(
        from: current.policy, to: policy)
      if current.frontierEpoch > current.policyAuthorizedEpoch {
        // Remote frontier won the race; this newer policy authorizes it.
        current.policyAuthorizedEpoch = current.frontierEpoch
      } else if mustAdvance {
        current.frontierEpoch = try incrementEpoch(
          current.frontierEpoch, accountIdentifier: accountIdentifier)
        current.frontierCutoffTimestamp = ""
        current.frontierCutoffEntityId = ""
        current.policyAuthorizedEpoch = current.frontierEpoch
      } else {
        current.policyAuthorizedEpoch = current.frontierEpoch
      }
      current.policy = policy
      current.policyVersion = policyVersion
      current.isPolicyReady = true
    }
    if let required = current.refreshRequiredEpoch,
      required <= current.frontierEpoch && required <= current.policyAuthorizedEpoch
    {
      current.refreshRequiredEpoch = nil
    }
    try persist(current, db: db, now: now)
    if priorPolicy != current.policy
      || priorPolicyVersion != current.policyVersion
      || priorPolicyReady != current.isPolicyReady
      || priorPolicyAuthorizedEpoch != current.policyAuthorizedEpoch
    {
      // A changed policy contract must not reuse a retained-set authorization
      // minted before the change, even when the frontier tuple did not move.
      try db.execute(sql: "DELETE FROM audit_retention_outbound_authorization")
    }
    // Rows authored while this newly-seen account was unready are safe to
    // normalize only because durable cloud-presence evidence is still false.
    // Ordinary epoch transitions do NOT rewrite old rows into the new
    // generation; doing so would defeat the retirement fence.
    if !wasPolicyReady, current.policy != .off {
      try normalizeCloudUnseenAuditRows(
        db, accountIdentifier: accountIdentifier, epoch: current.frontierEpoch)
    }
    try pruneAuditRowsDominatedByFrontier(
      db, accountIdentifier: accountIdentifier, frontier: current.frontier, now: now)
    return current
  }

  /// Local preference hook before the first account binding. Once an account is
  /// active this delegates to the account-scoped transition above.
  public static func adoptPolicyForCurrentScope(
    _ db: Database, policy: ChangelogRetentionPolicy, policyVersion: String,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws {
    let binding = try readBinding(db)
    if let account = binding.activeAccountIdentifier {
      _ = try adoptPolicyForActiveAccount(
        db, accountIdentifier: account, policy: policy,
        policyVersion: policyVersion, now: now)
      return
    }
    let ordering = try comparePolicyVersion(
      incoming: policyVersion, stored: binding.unboundPolicyVersion,
      accountIdentifier: "<unbound>")
    if ordering < 0 { return }
    var frontier = binding.unboundFrontierEpoch
    var cutoffTimestamp = binding.unboundFrontierCutoffTimestamp
    var cutoffEntityId = binding.unboundFrontierCutoffEntityId
    var authorized = binding.unboundPolicyAuthorizedEpoch
    let adoptedPolicy: ChangelogRetentionPolicy
    if ordering == 0 {
      adoptedPolicy = ChangelogRetentionPolicy.conservativeCollisionWinner(
        binding.unboundPolicy, policy)
    } else if policyTransitionNeedsGeneration(from: binding.unboundPolicy, to: policy) {
      adoptedPolicy = policy
      frontier = try incrementEpoch(frontier, accountIdentifier: "<unbound>")
      cutoffTimestamp = ""
      cutoffEntityId = ""
      authorized = frontier
    } else {
      adoptedPolicy = policy
      authorized = frontier
    }
    try db.execute(
      sql: """
        UPDATE audit_retention_binding
        SET unbound_frontier_epoch = ?,
            unbound_frontier_cutoff_timestamp = ?,
            unbound_frontier_cutoff_entity_id = ?,
            unbound_policy_authorized_epoch = ?,
            unbound_policy_value = ?, unbound_policy_version = ?,
            unbound_policy_ready = 1, updated_at = ?
        WHERE singleton = 1
        """,
      arguments: [
        frontier, cutoffTimestamp, cutoffEntityId, authorized,
        adoptedPolicy.wireValue, policyVersion, now,
      ])
    try pruneAuditRowsDominatedByFrontier(
      db, accountIdentifier: nil,
      frontier: AuditRetentionFrontierValue(
        epoch: frontier, minimumRetainedTimestamp: cutoffTimestamp,
        minimumRetainedEntityId: cutoffEntityId),
      now: now)
  }

  /// Record that an inbound generation cannot yet be interpreted. Repeated
  /// observations only raise the requested epoch.
  static func requireRefresh(
    _ db: Database, accountIdentifier: String, epoch: Int64,
    now: String = SyncTimestampFormat.syncTimestampNow()
  ) throws {
    try validateEpoch(epoch)
    try db.execute(
      sql: """
        UPDATE audit_retention_account_state
        SET refresh_required_epoch = CASE
              WHEN refresh_required_epoch IS NULL OR refresh_required_epoch < ?
              THEN ? ELSE refresh_required_epoch END,
            updated_at = ?
        WHERE account_identifier = ?
        """,
      arguments: [epoch, epoch, now, accountIdentifier])
    guard db.changesCount == 1 else {
      throw AuditRetentionStateError.malformedAccountState(accountIdentifier)
    }
  }

}
