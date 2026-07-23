/// Monotonic, account-relative lower bound for audit rows that may still exist.
/// A row is retired when its epoch is lower, or when its epoch is equal and its
/// `(timestamp, id)` key is lexicographically below the minimum-retained key.
/// An empty key is the beginning of an epoch.
public struct AuditRetentionFrontierValue: Sendable, Equatable, Comparable, Codable {
  public var epoch: Int64
  public var minimumRetainedTimestamp: String
  public var minimumRetainedEntityId: String

  public init(
    epoch: Int64,
    minimumRetainedTimestamp: String = "",
    minimumRetainedEntityId: String = ""
  ) {
    self.epoch = epoch
    self.minimumRetainedTimestamp = minimumRetainedTimestamp
    self.minimumRetainedEntityId = minimumRetainedEntityId
  }

  public static let initial = AuditRetentionFrontierValue(epoch: 0)

  public static func < (
    lhs: AuditRetentionFrontierValue, rhs: AuditRetentionFrontierValue
  ) -> Bool {
    if lhs.epoch != rhs.epoch { return lhs.epoch < rhs.epoch }
    if lhs.minimumRetainedTimestamp != rhs.minimumRetainedTimestamp {
      return lhs.minimumRetainedTimestamp < rhs.minimumRetainedTimestamp
    }
    return lhs.minimumRetainedEntityId < rhs.minimumRetainedEntityId
  }
}

/// Account-scoped state for the CloudKit audit-retention frontier.
///
/// Epochs are meaningful only together with `accountIdentifier`. They are not
/// globally comparable and must never be copied across an iCloud-account
/// switch.
public struct AuditRetentionAccountState: Sendable, Equatable {
  public var accountIdentifier: String
  public var frontierEpoch: Int64
  public var frontierCutoffTimestamp: String
  public var frontierCutoffEntityId: String
  public var confirmedFrontierEpoch: Int64
  public var confirmedCutoffTimestamp: String
  public var confirmedCutoffEntityId: String
  public var policyAuthorizedEpoch: Int64
  public var policy: ChangelogRetentionPolicy
  public var policyVersion: String
  public var isPolicyReady: Bool
  public var refreshRequiredEpoch: Int64?

  public init(
    accountIdentifier: String,
    frontierEpoch: Int64,
    frontierCutoffTimestamp: String = "",
    frontierCutoffEntityId: String = "",
    confirmedFrontierEpoch: Int64,
    confirmedCutoffTimestamp: String = "",
    confirmedCutoffEntityId: String = "",
    policyAuthorizedEpoch: Int64,
    policy: ChangelogRetentionPolicy,
    policyVersion: String,
    isPolicyReady: Bool,
    refreshRequiredEpoch: Int64?
  ) {
    self.accountIdentifier = accountIdentifier
    self.frontierEpoch = frontierEpoch
    self.frontierCutoffTimestamp = frontierCutoffTimestamp
    self.frontierCutoffEntityId = frontierCutoffEntityId
    self.confirmedFrontierEpoch = confirmedFrontierEpoch
    self.confirmedCutoffTimestamp = confirmedCutoffTimestamp
    self.confirmedCutoffEntityId = confirmedCutoffEntityId
    self.policyAuthorizedEpoch = policyAuthorizedEpoch
    self.policy = policy
    self.policyVersion = policyVersion
    self.isPolicyReady = isPolicyReady
    self.refreshRequiredEpoch = refreshRequiredEpoch
  }

  public var frontier: AuditRetentionFrontierValue {
    get {
      AuditRetentionFrontierValue(
        epoch: frontierEpoch,
        minimumRetainedTimestamp: frontierCutoffTimestamp,
        minimumRetainedEntityId: frontierCutoffEntityId)
    }
    set {
      frontierEpoch = newValue.epoch
      frontierCutoffTimestamp = newValue.minimumRetainedTimestamp
      frontierCutoffEntityId = newValue.minimumRetainedEntityId
    }
  }

  public var confirmedFrontier: AuditRetentionFrontierValue {
    get {
      AuditRetentionFrontierValue(
        epoch: confirmedFrontierEpoch,
        minimumRetainedTimestamp: confirmedCutoffTimestamp,
        minimumRetainedEntityId: confirmedCutoffEntityId)
    }
    set {
      confirmedFrontierEpoch = newValue.epoch
      confirmedCutoffTimestamp = newValue.minimumRetainedTimestamp
      confirmedCutoffEntityId = newValue.minimumRetainedEntityId
    }
  }
}

public enum AuditRetentionAccountActivationKind: Sendable, Equatable {
  /// The first CloudKit account ever bound to this database. It consumes the
  /// pre-account candidate and normalizes cloud-unseen audit rows once.
  case firstBinding
  /// An account that already has an independent persisted frontier.
  case resumedAccount
  /// A newly seen account after the first binding. It starts policy-unready and
  /// inherits no frontier, policy, or audit outbox work from the prior account.
  case newAccount
}

public struct AuditRetentionAccountActivation: Sendable, Equatable {
  public var kind: AuditRetentionAccountActivationKind
  public var state: AuditRetentionAccountState

  public init(kind: AuditRetentionAccountActivationKind, state: AuditRetentionAccountState) {
    self.kind = kind
    self.state = state
  }
}

public struct AuditRetentionWriteContext: Sendable, Equatable {
  /// Nil only before this database's first CloudKit account binding.
  public var accountIdentifier: String?
  public var retentionEpoch: Int64
  /// False for a newly seen account until its own remote policy/frontier has
  /// been adopted. Rows may be recorded locally, but transport must not upload
  /// them until readiness normalizes their cloud-unseen generation.
  public var isPolicyReady: Bool

  public init(accountIdentifier: String?, retentionEpoch: Int64, isPolicyReady: Bool) {
    self.accountIdentifier = accountIdentifier
    self.retentionEpoch = retentionEpoch
    self.isPolicyReady = isPolicyReady
  }
}

/// Opaque proof that this outbound pass joined the active account's verified
/// remote frontier. Mark-before-cloud validates the token against durable state;
/// a caller cannot reuse stale account state from an earlier push cycle.
public struct AuditRetentionOutboundAuthorization: Sendable, Equatable {
  public var token: String
  public var accountIdentifier: String
  /// Exact CloudKit zone generation verified by this outbound pass.
  public var zoneName: String
  public var frontier: AuditRetentionFrontierValue

  public init(
    token: String, accountIdentifier: String, zoneName: String,
    frontier: AuditRetentionFrontierValue
  ) {
    self.token = token
    self.accountIdentifier = accountIdentifier
    self.zoneName = zoneName
    self.frontier = frontier
  }
}

/// Opaque proof for copying the retained audit stream into a not-yet-active
/// CloudKit generation. Unlike ``AuditRetentionOutboundAuthorization`` this
/// capability can only authorize snapshot enumeration and mark-before-cloud
/// presence for `candidateZoneName`; it can never route the ordinary outbox or
/// purge queue away from `sourceActiveZoneName`.
public struct AuditRetentionCandidateAuthorization: Sendable, Equatable {
  public var token: String
  public var accountIdentifier: String
  public var sourceActiveZoneName: String
  public var candidateZoneName: String
  public var frontier: AuditRetentionFrontierValue
  public var policy: ChangelogRetentionPolicy
  public var policyVersion: String

  public init(
    token: String, accountIdentifier: String,
    sourceActiveZoneName: String, candidateZoneName: String,
    frontier: AuditRetentionFrontierValue,
    policy: ChangelogRetentionPolicy, policyVersion: String
  ) {
    self.token = token
    self.accountIdentifier = accountIdentifier
    self.sourceActiveZoneName = sourceActiveZoneName
    self.candidateZoneName = candidateZoneName
    self.frontier = frontier
    self.policy = policy
    self.policyVersion = policyVersion
  }
}

public enum AuditRetentionPurgeReason: String, Sendable, Equatable, Codable {
  case belowFrontier = "below_frontier"
  case policyHorizon = "policy_horizon"
  case localRetention = "local_retention"
  case orphanedCloudPresence = "orphaned_cloud_presence"
  case resetTombstone = "reset_tombstone"
}

public struct AuditRetentionPurgeItem: Sendable, Equatable {
  public var accountIdentifier: String
  /// Exact retired/current CloudKit zone containing the record to delete.
  public var zoneName: String
  public var entityId: String
  public var retentionEpoch: Int64
  public var reason: AuditRetentionPurgeReason
  public var attemptCount: Int
  public var nextAttemptAt: String?
  public var lastError: String?
  public var createdAt: String

  public init(
    accountIdentifier: String,
    zoneName: String,
    entityId: String,
    retentionEpoch: Int64,
    reason: AuditRetentionPurgeReason,
    attemptCount: Int,
    nextAttemptAt: String?,
    lastError: String?,
    createdAt: String
  ) {
    self.accountIdentifier = accountIdentifier
    self.zoneName = zoneName
    self.entityId = entityId
    self.retentionEpoch = retentionEpoch
    self.reason = reason
    self.attemptCount = attemptCount
    self.nextAttemptAt = nextAttemptAt
    self.lastError = lastError
    self.createdAt = createdAt
  }
}

/// Retention decision made before an inbound audit upsert touches canonical
/// storage. HOLD is durable and non-destructive: it means this device has seen a
/// generation whose authorizing policy/frontier it does not yet understand.
public enum AuditRetentionInboundDisposition: Sendable, Equatable {
  case accept
  case rejectAndPurge(AuditRetentionPurgeReason)
  case holdForFrontierRefresh(requiredEpoch: Int64)
}

public enum AuditRetentionCloudPresenceMarkResult: Sendable, Equatable {
  /// The local row and its outbox envelope still belonged to the active account;
  /// durable cloud-presence evidence was recorded before transport begins.
  case marked
  /// The canonical row/outbox pair disappeared before transport could begin.
  /// Nothing may be uploaded and no remote purge is required.
  case noLongerPending
}

/// Fail-closed validation and routing failures for retention metadata.
public enum AuditRetentionStateError: Error, Sendable, Equatable, CustomStringConvertible {
  case invalidAccountIdentifier
  case invalidZoneName
  case invalidEpoch(Int64)
  case invalidFrontier
  case invalidTimestamp(String)
  case malformedBindingState
  case malformedAccountState(String)
  case noActiveAccount
  case activeAccountMismatch(expected: String, requested: String)
  case activeZoneMismatch(expected: String, requested: String)
  case policyNotReady(String)
  case invalidOutboundAuditRow(Int64)
  case invalidOutboundAuthorization
  case auditRowAccountMismatch(entityId: String, expected: String, actual: String?)
  case invalidPurgeReason(String)
  case generationSnapshotLimitExceeded(limit: Int, observedAtLeast: Int)
  case invalidGenerationSnapshotRow(String)

  public var description: String {
    switch self {
    case .invalidAccountIdentifier:
      return "audit retention account identifier is empty or exceeds the storage limit"
    case .invalidZoneName:
      return "audit retention CloudKit zone name is empty or exceeds the storage limit"
    case .invalidEpoch(let epoch):
      return "audit retention epoch must be nonnegative, got \(epoch)"
    case .invalidFrontier:
      return "audit retention frontier is malformed"
    case .invalidTimestamp(let timestamp):
      return "audit retention timestamp is malformed: \(timestamp)"
    case .malformedBindingState:
      return "audit retention binding state is malformed"
    case .malformedAccountState(let account):
      return "audit retention state is malformed for account \(account)"
    case .noActiveAccount:
      return "audit retention has no active iCloud account"
    case .activeAccountMismatch(let expected, let requested):
      return
        "audit retention active account \(expected) does not match requested account \(requested)"
    case .activeZoneMismatch(let expected, let requested):
      return "audit retention active zone \(expected) does not match requested zone \(requested)"
    case .policyNotReady(let account):
      return "audit retention policy/frontier is not ready for account \(account)"
    case .invalidOutboundAuditRow(let id):
      return "sync_outbox row \(id) is not a valid pending ai_changelog upsert"
    case .invalidOutboundAuthorization:
      return "audit retention outbound authorization is absent, stale, or for another account"
    case .auditRowAccountMismatch(let id, let expected, let actual):
      return "ai_changelog \(id) belongs to \(actual ?? "an unbound account"), expected \(expected)"
    case .invalidPurgeReason(let reason):
      return "audit retention purge queue contains invalid reason \(reason)"
    case .generationSnapshotLimitExceeded(let limit, let observed):
      return
        "audit retention generation snapshot exceeds \(limit) records "
        + "(observed at least \(observed))"
    case .invalidGenerationSnapshotRow(let entityId):
      return "ai_changelog \(entityId) is outside the authorized generation snapshot"
    }
  }
}
