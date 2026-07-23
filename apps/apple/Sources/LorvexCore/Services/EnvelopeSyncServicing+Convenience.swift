import Foundation
import LorvexDomain
import LorvexSync

extension EnvelopeSyncServicing {
  /// Compatibility cursor for lightweight/test backends. Production SQLite
  /// overrides this at the query boundary so an attempted prefix cannot consume
  /// the capped page and hide newer rows.
  public func pendingOutbound(afterOutboxId: Int64?) throws -> [PendingOutboundEnvelope] {
    let pending = try pendingOutbound()
    guard let afterOutboxId else { return pending }
    return pending.filter { $0.outboxId > afterOutboxId }
  }

  /// Lightweight/test backends expose no filtered raw rows, so their decoded
  /// high-water is also the raw high-water. Production SQLite overrides this.
  public func pendingOutboundPage(
    afterOutboxId: Int64?, now _: String
  ) throws -> PendingOutboundPage {
    let pending = try pendingOutbound(afterOutboxId: afterOutboxId)
    return PendingOutboundPage(
      envelopes: pending,
      lastScannedOutboxId: pending.last?.outboxId)
  }

  /// Lightweight/test backends have no durable delayed-work tables unless they
  /// opt in. The production SQLite service overrides this query.
  public func nextDeferredCloudSyncRetryAt(
    forAccountIdentifier _: String,
    zoneName _: String
  ) throws -> Date? {
    nil
  }

  /// Compatibility implementation for lightweight/test backends. The real
  /// SQLite facade overrides this with a single transaction; delegating here
  /// keeps non-storage test doubles small while preserving their recorded call
  /// behavior.
  public func reconcileOutbound(
    _ request: OutboundReconciliationRequest
  ) throws -> OutboundReconciliationReport {
    guard request.collisions.isEmpty else {
      throw OutboundReconciliationFallbackError.collisionRequiresTransactionalStore
    }
    let report = try applyInbound(request.serverWinnerEnvelopes, undecodable: 0)
    try deferUnknownTypeRecords(request.deferredUnknownTypeRecords)
    for failure in request.failures {
      try recordOutboundFailure(
        outboxId: failure.outboxId, error: failure.error, kind: failure.kind)
    }
    try markOutboundSynced(outboxIds: request.confirmedOutboxIds)
    var enriched = report
    enriched.deferredUnknownType += request.deferredUnknownTypeRecords.count
    return OutboundReconciliationReport(inbound: enriched)
  }

  /// Default for lightweight backends without durable database lineage or
  /// CloudKit traversal state. Production SQLite overrides this identity.
  public func databaseInstanceIdentifier() throws -> String? { nil }
  public func cloudTraversalAccountBinding() throws -> CloudTraversalAccountBinding? { nil }
  public func cloudTraversalAccountBindingForAdoption() throws -> CloudTraversalAccountBinding? {
    nil
  }
  public func claimCloudTraversalAccount(
    accountIdentifier: String
  ) throws -> CloudTraversalAccountBinding {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func observedCloudGenerationAuthorityFloor(
    forAccountIdentifier accountIdentifier: String
  ) throws -> Int? { nil }
  public func recordObservedCloudGenerationAuthority(
    forAccountIdentifier accountIdentifier: String, generation: Int
  ) throws -> Int { generation }
  public func adoptCloudTraversalAccount(
    expectedCurrentAccountIdentifier: String, newAccountIdentifier: String
  ) throws -> CloudTraversalAccountBinding {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func prepareCloudTraversalForAccountAdoption(
    newAccountIdentifier: String,
    mode: CloudTraversalAccountAdoptionMode
  ) throws -> CloudTraversalAccountBinding {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func rebindCloudTraversalAfterDatabaseInstanceRotation(
    expectedAccountIdentifier: String
  ) throws -> CloudTraversalAccountBinding {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func cloudTraversalState(
    accountIdentifier: String, zoneIdentifier: String
  ) throws -> CloudTraversalState {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func beginCloudTraversal(
    boundary: CloudTraversalBoundary, traversalIdentifier: String,
    start: CloudTraversalStart
  ) throws -> CloudTraversalProgress {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func applyInboundTraversalPage(
    _ envelopes: [SyncEnvelope], deferredUnknownTypeRecords: [RawEnvelopeFields],
    cloudReceipts: [InboundCloudRecordReceipt], undecodable: Int,
    boundary: CloudTraversalBoundary, traversalIdentifier: String,
    page: CloudTraversalPageCommit,
    inboundObservation: CloudInboundPageObservation
  ) throws -> InboundApplyReport {
    _ = envelopes
    _ = deferredUnknownTypeRecords
    _ = cloudReceipts
    _ = undecodable
    _ = boundary
    _ = traversalIdentifier
    _ = page
    _ = inboundObservation
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func unresolvedFutureRecordCount() throws -> Int { 0 }
  public func unresolvedInboundRecordCount() throws -> Int {
    try unresolvedFutureRecordCount()
  }
  public func quarantinedInboundRecordCount() throws -> Int { 0 }
  public func cloudInboundCompletenessState(
    boundary: CloudTraversalBoundary
  ) throws -> CloudInboundCompletenessState {
    _ = boundary
    return CloudInboundCompletenessState(
      pendingRecordCount: try unresolvedInboundRecordCount(),
      corruptRecordCount: try quarantinedInboundRecordCount())
  }
  public func stageAuthoritativeSnapshotContinuationPage(
    records: [AuthoritativeSnapshotRemoteRecord], deletedRecordNames: [String],
    sessionToken: String, boundary: CloudTraversalBoundary,
    traversalIdentifier: String, page: CloudTraversalPageCommit
  ) throws {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func finalizeAuthoritativeSnapshotTerminalPage(
    records: [AuthoritativeSnapshotRemoteRecord], deletedRecordNames: [String],
    sessionToken: String, boundary: CloudTraversalBoundary,
    traversalIdentifier: String, page: CloudTraversalPageCommit
  ) throws -> AuthoritativeSnapshotReport {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func cancelCloudTraversal(
    boundary: CloudTraversalBoundary, traversalIdentifier: String
  ) throws {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func resetCloudTraversalAfterInvalidCursor(
    boundary: CloudTraversalBoundary, traversalIdentifier: String,
    requireFullReseed: Bool
  ) throws {
    throw CloudTraversalStateError.unsupportedBackend
  }
  /// Default for backends without retention tables / an outbox: nothing to GC.
  public func runLocalRetentionMaintenance(includeActiveOutboxCap: Bool) throws {}
  public func activateAuditRetentionAccount(
    accountIdentifier: String, zoneName: String
  ) throws -> AuditRetentionAccountActivation {
    throw AuditRetentionStateError.noActiveAccount
  }
  public func auditRetentionState(
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState? { nil }
  public func auditRetentionActiveZoneName() throws -> String? { nil }
  public func initializeAuditRetentionForVerifiedEmptyAccount(
    accountIdentifier: String
  ) throws -> AuditRetentionAccountState {
    throw AuditRetentionStateError.policyNotReady(accountIdentifier)
  }
  public func joinAuditRetentionFrontier(
    _ frontier: AuditRetentionFrontierValue,
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState {
    throw AuditRetentionStateError.noActiveAccount
  }
  public func adoptAuditRetentionPolicy(
    _ policy: ChangelogRetentionPolicy, policyVersion: String,
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState {
    throw AuditRetentionStateError.noActiveAccount
  }
  public func authorizeAuditRetentionOutbound(
    verifiedRemoteFrontier: AuditRetentionFrontierValue,
    forAccountIdentifier accountIdentifier: String, zoneName: String
  ) throws -> AuditRetentionOutboundAuthorization {
    throw AuditRetentionStateError.noActiveAccount
  }
  public func authorizeAuditRetentionOutboundAfterExactRemoteConfirmation(
    verifiedRemoteFrontier: AuditRetentionFrontierValue,
    verifiedRemotePolicy: ChangelogRetentionPolicy,
    verifiedRemotePolicyVersion: String,
    forAccountIdentifier accountIdentifier: String, zoneName: String
  ) throws -> AuditRetentionOutboundAuthorization {
    let authorization = try authorizeAuditRetentionOutbound(
      verifiedRemoteFrontier: verifiedRemoteFrontier,
      forAccountIdentifier: accountIdentifier, zoneName: zoneName)
    guard authorization.frontier == verifiedRemoteFrontier else {
      throw AuditRetentionStateError.invalidOutboundAuthorization
    }
    _ = verifiedRemotePolicy
    _ = verifiedRemotePolicyVersion
    return authorization
  }
  public func authorizeAuditRetentionCandidateGeneration(
    forAccountIdentifier accountIdentifier: String, candidateZoneName: String
  ) throws -> AuditRetentionCandidateAuthorization {
    throw AuditRetentionStateError.noActiveAccount
  }
  public func validateAuditRetentionCandidateGeneration(
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionAccountState {
    throw AuditRetentionStateError.invalidOutboundAuthorization
  }
  public func activateAuditRetentionCandidateGeneration(
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionAccountState {
    throw AuditRetentionStateError.invalidOutboundAuthorization
  }
  public func revokeAuditRetentionCandidateGeneration(
    authorization: AuditRetentionCandidateAuthorization
  ) throws {}
  public func confirmAuditRetentionFrontier(
    _ frontier: AuditRetentionFrontierValue,
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState {
    throw AuditRetentionStateError.noActiveAccount
  }
  public func markAuditCloudPresencePossible(
    outboxId: Int64, authorization: AuditRetentionOutboundAuthorization
  ) throws -> AuditRetentionCloudPresenceMarkResult {
    throw AuditRetentionStateError.invalidOutboundAuthorization
  }
  public func markAuditGenerationSnapshotCloudPresencePossible(
    envelope: SyncEnvelope, authorization: AuditRetentionOutboundAuthorization
  ) throws -> AuditRetentionCloudPresenceMarkResult {
    throw AuditRetentionStateError.invalidOutboundAuthorization
  }
  public func markAuditCandidateGenerationSnapshotCloudPresencePossible(
    envelope: SyncEnvelope,
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionCloudPresenceMarkResult {
    throw AuditRetentionStateError.invalidOutboundAuthorization
  }
  public func markAuditGenerationSnapshotBatchCloudPresencePossible(
    envelopes: [SyncEnvelope], authorization: AuditRetentionOutboundAuthorization
  ) throws -> [AuditRetentionCloudPresenceMarkResult] {
    throw AuditRetentionStateError.invalidOutboundAuthorization
  }
  public func markAuditCandidateGenerationSnapshotBatchCloudPresencePossible(
    envelopes: [SyncEnvelope], authorization: AuditRetentionCandidateAuthorization
  ) throws -> [AuditRetentionCloudPresenceMarkResult] {
    throw AuditRetentionStateError.invalidOutboundAuthorization
  }
  public func captureGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionOutboundAuthorization
  ) throws -> GenerationSnapshotStaging {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func captureCandidateGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> GenerationSnapshotStaging {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func captureGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionOutboundAuthorization,
    tombstoneCompactionCutoff: String?
  ) throws -> GenerationSnapshotStaging {
    _ = tombstoneCompactionCutoff
    return try captureGenerationSnapshot(binding: binding, authorization: authorization)
  }
  public func captureCandidateGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionCandidateAuthorization,
    tombstoneCompactionCutoff: String?
  ) throws -> GenerationSnapshotStaging {
    _ = tombstoneCompactionCutoff
    return try captureCandidateGenerationSnapshot(
      binding: binding, authorization: authorization)
  }
  public func stagedGenerationSnapshotPage(
    binding: GenerationSnapshotBinding, offset: Int, limit: Int,
    maximumEncodedBytes: Int
  ) throws -> GenerationSnapshotPage {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func generationSnapshotStaging(
    binding: GenerationSnapshotBinding
  ) throws -> GenerationSnapshotStaging? { nil }
  public func currentGenerationSnapshotStaging() throws -> GenerationSnapshotStaging? { nil }
  public func advanceGenerationSnapshotUploadProgress(
    binding: GenerationSnapshotBinding, expectedNextOrdinal: Int,
    nextOrdinal: Int
  ) throws -> GenerationSnapshotStaging {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func advanceGenerationSnapshotUploadProgress(
    binding: GenerationSnapshotBinding, expectedNextOrdinal: Int,
    nextOrdinal: Int, cloudReceipts: [InboundCloudRecordReceipt]
  ) throws -> GenerationSnapshotStaging {
    _ = cloudReceipts
    return try advanceGenerationSnapshotUploadProgress(
      binding: binding, expectedNextOrdinal: expectedNextOrdinal,
      nextOrdinal: nextOrdinal)
  }
  public func recordGenerationSnapshotReadbackPage(
    binding: GenerationSnapshotBinding, expectedPageIndex: Int,
    witnesses: [GenerationSnapshotWitness], deletedRecordNames: [String],
    continuationToken: Data, observedTraversalWitness: Bool, terminal: Bool
  ) throws -> GenerationSnapshotStaging {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func resetGenerationSnapshotReadbackProgress(
    binding: GenerationSnapshotBinding
  ) throws -> GenerationSnapshotStaging {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func finalizePublishedGenerationSnapshot(
    binding: GenerationSnapshotBinding
  ) throws {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func discardGenerationSnapshot(binding: GenerationSnapshotBinding) throws {
    throw CloudTraversalStateError.unsupportedBackend
  }
  public func pendingAuditRetentionPurges(
    forAccountIdentifier accountIdentifier: String, zoneName: String, limit: Int
  ) throws -> [AuditRetentionPurgeItem] { [] }
  public func acknowledgeAuditRetentionPurges(
    forAccountIdentifier accountIdentifier: String, zoneName: String,
    entityIds: [String]
  ) throws {}
  public func acknowledgeAuditRetentionZoneDeletion(
    forAccountIdentifier accountIdentifier: String, zoneName: String
  ) throws {}
  public func recordAuditRetentionPurgeFailure(
    forAccountIdentifier accountIdentifier: String, zoneName: String,
    entityId: String, error: String
  ) throws {}
  public func recordRemoteChangeFetchFailure(checkpointKey: String, threshold: Int) throws -> Bool {
    _ = (checkpointKey, threshold)
    return false
  }
  /// Default for backends without reseed bookkeeping: the marker is never set,
  /// so no cycle-start recovery is triggered.
  public func isReseedRequired() throws -> Bool { false }
  public func enqueueFullResyncBackfill(
    tombstoneCompactionCutoff: String?
  ) throws -> FullResyncBackfillReport {
    _ = tombstoneCompactionCutoff
    return try enqueueFullResyncBackfill()
  }
  public func compactCloudConfirmedTombstones(through cutoff: String) throws -> UInt64 {
    _ = cutoff
    return 0
  }
  public func trustedTombstoneCompactionCutoff(
    forAccountIdentifier accountIdentifier: String
  ) throws -> String? {
    _ = accountIdentifier
    return nil
  }
  public func trustedTerminalServerTimeCovers(
    cutoff: String, forAccountIdentifier accountIdentifier: String
  ) throws -> Bool {
    _ = cutoff
    _ = accountIdentifier
    return false
  }
  public func authoritativeSnapshotSession() throws -> AuthoritativeSnapshotSession? { nil }
  public func beginAuthoritativeSnapshot(boundary: CloudTraversalBoundary) throws
    -> AuthoritativeSnapshotSession
  {
    throw AuthoritativeSnapshotError.noActiveSession
  }
  public func restartAuthoritativeSnapshot() throws -> AuthoritativeSnapshotSession {
    throw AuthoritativeSnapshotError.noActiveSession
  }
  public func markAuthoritativeSnapshotReady(sessionToken: String) throws {
    throw AuthoritativeSnapshotError.noActiveSession
  }
  public func stageAuthoritativeSnapshotPage(
    records: [AuthoritativeSnapshotRemoteRecord], deletedRecordNames: [String],
    sessionToken: String
  ) throws {
    throw AuthoritativeSnapshotError.noActiveSession
  }
  public func finalizeAuthoritativeSnapshot(
    sessionToken: String, accountIdentifier: String, zoneName: String,
    enrolledZoneEpoch: Int?
  ) throws -> AuthoritativeSnapshotReport {
    throw AuthoritativeSnapshotError.noActiveSession
  }
  public func cancelAuthoritativeSnapshot() throws {}
}

enum OutboundReconciliationFallbackError: Error {
  case collisionRequiresTransactionalStore
}
