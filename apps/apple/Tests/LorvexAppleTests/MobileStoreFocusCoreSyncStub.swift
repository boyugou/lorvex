import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync

/// Production-shaped sync-state forwarding for `StubFocusCoreService`.
///
/// The store tests still own the transport-facing outbox recorders in the main
/// stub, but generation, traversal, and retention state live in the real
/// in-memory core. This keeps end-to-end store tests on the same atomic page
/// commit protocol as production instead of falling through protocol defaults.
extension StubFocusCoreService {
  func runLocalRetentionMaintenance(includeActiveOutboxCap: Bool) throws {
    try preview.runLocalRetentionMaintenance(includeActiveOutboxCap: includeActiveOutboxCap)
  }

  func activateAuditRetentionAccount(
    accountIdentifier: String, zoneName: String
  ) throws -> AuditRetentionAccountActivation {
    try preview.activateAuditRetentionAccount(
      accountIdentifier: accountIdentifier, zoneName: zoneName)
  }

  func auditRetentionState(
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState? {
    try preview.auditRetentionState(forAccountIdentifier: accountIdentifier)
  }

  func auditRetentionActiveZoneName() throws -> String? {
    try preview.auditRetentionActiveZoneName()
  }

  func initializeAuditRetentionForVerifiedEmptyAccount(
    accountIdentifier: String
  ) throws -> AuditRetentionAccountState {
    try preview.initializeAuditRetentionForVerifiedEmptyAccount(
      accountIdentifier: accountIdentifier)
  }

  func joinAuditRetentionFrontier(
    _ frontier: AuditRetentionFrontierValue,
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState {
    try preview.joinAuditRetentionFrontier(
      frontier, forAccountIdentifier: accountIdentifier)
  }

  func adoptAuditRetentionPolicy(
    _ policy: ChangelogRetentionPolicy, policyVersion: String,
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState {
    try preview.adoptAuditRetentionPolicy(
      policy, policyVersion: policyVersion,
      forAccountIdentifier: accountIdentifier)
  }

  func authorizeAuditRetentionOutbound(
    verifiedRemoteFrontier: AuditRetentionFrontierValue,
    forAccountIdentifier accountIdentifier: String, zoneName: String
  ) throws -> AuditRetentionOutboundAuthorization {
    try preview.authorizeAuditRetentionOutbound(
      verifiedRemoteFrontier: verifiedRemoteFrontier,
      forAccountIdentifier: accountIdentifier, zoneName: zoneName)
  }

  func authorizeAuditRetentionOutboundAfterExactRemoteConfirmation(
    verifiedRemoteFrontier: AuditRetentionFrontierValue,
    verifiedRemotePolicy: ChangelogRetentionPolicy,
    verifiedRemotePolicyVersion: String,
    forAccountIdentifier accountIdentifier: String, zoneName: String
  ) throws -> AuditRetentionOutboundAuthorization {
    try preview.authorizeAuditRetentionOutboundAfterExactRemoteConfirmation(
      verifiedRemoteFrontier: verifiedRemoteFrontier,
      verifiedRemotePolicy: verifiedRemotePolicy,
      verifiedRemotePolicyVersion: verifiedRemotePolicyVersion,
      forAccountIdentifier: accountIdentifier, zoneName: zoneName)
  }

  func authorizeAuditRetentionCandidateGeneration(
    forAccountIdentifier accountIdentifier: String, candidateZoneName: String
  ) throws -> AuditRetentionCandidateAuthorization {
    try preview.authorizeAuditRetentionCandidateGeneration(
      forAccountIdentifier: accountIdentifier, candidateZoneName: candidateZoneName)
  }

  func validateAuditRetentionCandidateGeneration(
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionAccountState {
    try preview.validateAuditRetentionCandidateGeneration(authorization: authorization)
  }

  func activateAuditRetentionCandidateGeneration(
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionAccountState {
    try preview.activateAuditRetentionCandidateGeneration(authorization: authorization)
  }

  func revokeAuditRetentionCandidateGeneration(
    authorization: AuditRetentionCandidateAuthorization
  ) throws {
    try preview.revokeAuditRetentionCandidateGeneration(authorization: authorization)
  }

  func confirmAuditRetentionFrontier(
    _ frontier: AuditRetentionFrontierValue,
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState {
    try preview.confirmAuditRetentionFrontier(
      frontier, forAccountIdentifier: accountIdentifier)
  }

  func markAuditCloudPresencePossible(
    outboxId: Int64, authorization: AuditRetentionOutboundAuthorization
  ) throws -> AuditRetentionCloudPresenceMarkResult {
    try preview.markAuditCloudPresencePossible(
      outboxId: outboxId, authorization: authorization)
  }

  func markAuditGenerationSnapshotCloudPresencePossible(
    envelope: SyncEnvelope, authorization: AuditRetentionOutboundAuthorization
  ) throws -> AuditRetentionCloudPresenceMarkResult {
    try preview.markAuditGenerationSnapshotCloudPresencePossible(
      envelope: envelope, authorization: authorization)
  }

  func markAuditCandidateGenerationSnapshotCloudPresencePossible(
    envelope: SyncEnvelope, authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionCloudPresenceMarkResult {
    try preview.markAuditCandidateGenerationSnapshotCloudPresencePossible(
      envelope: envelope, authorization: authorization)
  }

  func markAuditGenerationSnapshotBatchCloudPresencePossible(
    envelopes: [SyncEnvelope], authorization: AuditRetentionOutboundAuthorization
  ) throws -> [AuditRetentionCloudPresenceMarkResult] {
    try preview.markAuditGenerationSnapshotBatchCloudPresencePossible(
      envelopes: envelopes, authorization: authorization)
  }

  func markAuditCandidateGenerationSnapshotBatchCloudPresencePossible(
    envelopes: [SyncEnvelope], authorization: AuditRetentionCandidateAuthorization
  ) throws -> [AuditRetentionCloudPresenceMarkResult] {
    try preview.markAuditCandidateGenerationSnapshotBatchCloudPresencePossible(
      envelopes: envelopes, authorization: authorization)
  }

  func captureGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionOutboundAuthorization
  ) throws -> GenerationSnapshotStaging {
    try preview.captureGenerationSnapshot(binding: binding, authorization: authorization)
  }

  func captureCandidateGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> GenerationSnapshotStaging {
    try preview.captureCandidateGenerationSnapshot(
      binding: binding, authorization: authorization)
  }

  func stagedGenerationSnapshotPage(
    binding: GenerationSnapshotBinding, offset: Int, limit: Int,
    maximumEncodedBytes: Int
  ) throws -> GenerationSnapshotPage {
    try preview.stagedGenerationSnapshotPage(
      binding: binding, offset: offset, limit: limit,
      maximumEncodedBytes: maximumEncodedBytes)
  }

  func generationSnapshotStaging(
    binding: GenerationSnapshotBinding
  ) throws -> GenerationSnapshotStaging? {
    try preview.generationSnapshotStaging(binding: binding)
  }

  func currentGenerationSnapshotStaging() throws -> GenerationSnapshotStaging? {
    try preview.currentGenerationSnapshotStaging()
  }

  func advanceGenerationSnapshotUploadProgress(
    binding: GenerationSnapshotBinding, expectedNextOrdinal: Int,
    nextOrdinal: Int
  ) throws -> GenerationSnapshotStaging {
    try preview.advanceGenerationSnapshotUploadProgress(
      binding: binding, expectedNextOrdinal: expectedNextOrdinal,
      nextOrdinal: nextOrdinal)
  }

  func recordGenerationSnapshotReadbackPage(
    binding: GenerationSnapshotBinding, expectedPageIndex: Int,
    witnesses: [GenerationSnapshotWitness], deletedRecordNames: [String],
    continuationToken: Data, observedTraversalWitness: Bool, terminal: Bool
  ) throws -> GenerationSnapshotStaging {
    try preview.recordGenerationSnapshotReadbackPage(
      binding: binding, expectedPageIndex: expectedPageIndex,
      witnesses: witnesses, deletedRecordNames: deletedRecordNames,
      continuationToken: continuationToken,
      observedTraversalWitness: observedTraversalWitness, terminal: terminal)
  }

  func resetGenerationSnapshotReadbackProgress(
    binding: GenerationSnapshotBinding
  ) throws -> GenerationSnapshotStaging {
    try preview.resetGenerationSnapshotReadbackProgress(binding: binding)
  }

  func finalizePublishedGenerationSnapshot(binding: GenerationSnapshotBinding) throws {
    try preview.finalizePublishedGenerationSnapshot(binding: binding)
  }

  func discardGenerationSnapshot(binding: GenerationSnapshotBinding) throws {
    try preview.discardGenerationSnapshot(binding: binding)
  }

  func pendingAuditRetentionPurges(
    forAccountIdentifier accountIdentifier: String, zoneName: String, limit: Int
  ) throws -> [AuditRetentionPurgeItem] {
    try preview.pendingAuditRetentionPurges(
      forAccountIdentifier: accountIdentifier, zoneName: zoneName, limit: limit)
  }

  func acknowledgeAuditRetentionPurges(
    forAccountIdentifier accountIdentifier: String, zoneName: String,
    entityIds: [String]
  ) throws {
    try preview.acknowledgeAuditRetentionPurges(
      forAccountIdentifier: accountIdentifier, zoneName: zoneName,
      entityIds: entityIds)
  }

  func acknowledgeAuditRetentionZoneDeletion(
    forAccountIdentifier accountIdentifier: String, zoneName: String
  ) throws {
    try preview.acknowledgeAuditRetentionZoneDeletion(
      forAccountIdentifier: accountIdentifier, zoneName: zoneName)
  }

  func recordAuditRetentionPurgeFailure(
    forAccountIdentifier accountIdentifier: String, zoneName: String,
    entityId: String, error: String
  ) throws {
    try preview.recordAuditRetentionPurgeFailure(
      forAccountIdentifier: accountIdentifier, zoneName: zoneName,
      entityId: entityId, error: error)
  }

  func databaseInstanceIdentifier() throws -> String? {
    try preview.databaseInstanceIdentifier()
  }

  func cloudTraversalAccountBinding() throws -> CloudTraversalAccountBinding? {
    try preview.cloudTraversalAccountBinding()
  }

  func claimCloudTraversalAccount(
    accountIdentifier: String
  ) throws -> CloudTraversalAccountBinding {
    try preview.claimCloudTraversalAccount(accountIdentifier: accountIdentifier)
  }

  func adoptCloudTraversalAccount(
    expectedCurrentAccountIdentifier: String, newAccountIdentifier: String
  ) throws -> CloudTraversalAccountBinding {
    try preview.adoptCloudTraversalAccount(
      expectedCurrentAccountIdentifier: expectedCurrentAccountIdentifier,
      newAccountIdentifier: newAccountIdentifier)
  }

  func rebindCloudTraversalAfterDatabaseInstanceRotation(
    expectedAccountIdentifier: String
  ) throws -> CloudTraversalAccountBinding {
    try preview.rebindCloudTraversalAfterDatabaseInstanceRotation(
      expectedAccountIdentifier: expectedAccountIdentifier)
  }

  func cloudTraversalState(
    accountIdentifier: String, zoneIdentifier: String
  ) throws -> CloudTraversalState {
    try preview.cloudTraversalState(
      accountIdentifier: accountIdentifier, zoneIdentifier: zoneIdentifier)
  }

  func beginCloudTraversal(
    boundary: CloudTraversalBoundary, traversalIdentifier: String,
    start: CloudTraversalStart
  ) throws -> CloudTraversalProgress {
    try preview.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: traversalIdentifier, start: start)
  }

  func applyInboundTraversalPage(
    _ envelopes: [SyncEnvelope], deferredUnknownTypeRecords: [RawEnvelopeFields] = [],
    cloudReceipts: [InboundCloudRecordReceipt], undecodable: Int,
    boundary: CloudTraversalBoundary, traversalIdentifier: String,
    page: CloudTraversalPageCommit,
    inboundObservation: CloudInboundPageObservation
  ) throws -> InboundApplyReport {
    let report = try preview.applyInboundTraversalPage(
      envelopes, deferredUnknownTypeRecords: deferredUnknownTypeRecords,
      cloudReceipts: cloudReceipts, undecodable: undecodable, boundary: boundary,
      traversalIdentifier: traversalIdentifier, page: page,
      inboundObservation: inboundObservation)
    recordAppliedInboundBatch(envelopes)
    return report
  }

  func stageAuthoritativeSnapshotContinuationPage(
    records: [AuthoritativeSnapshotRemoteRecord], deletedRecordNames: [String],
    sessionToken: String, boundary: CloudTraversalBoundary,
    traversalIdentifier: String, page: CloudTraversalPageCommit
  ) throws {
    try preview.stageAuthoritativeSnapshotContinuationPage(
      records: records, deletedRecordNames: deletedRecordNames,
      sessionToken: sessionToken, boundary: boundary,
      traversalIdentifier: traversalIdentifier, page: page)
  }

  func finalizeAuthoritativeSnapshotTerminalPage(
    records: [AuthoritativeSnapshotRemoteRecord], deletedRecordNames: [String],
    sessionToken: String, boundary: CloudTraversalBoundary,
    traversalIdentifier: String, page: CloudTraversalPageCommit
  ) throws -> AuthoritativeSnapshotReport {
    try preview.finalizeAuthoritativeSnapshotTerminalPage(
      records: records, deletedRecordNames: deletedRecordNames,
      sessionToken: sessionToken, boundary: boundary,
      traversalIdentifier: traversalIdentifier, page: page)
  }

  func cancelCloudTraversal(
    boundary: CloudTraversalBoundary, traversalIdentifier: String
  ) throws {
    try preview.cancelCloudTraversal(
      boundary: boundary, traversalIdentifier: traversalIdentifier)
  }

  func recordRemoteChangeFetchFailure(checkpointKey: String, threshold: Int) throws -> Bool {
    try preview.recordRemoteChangeFetchFailure(
      checkpointKey: checkpointKey, threshold: threshold)
  }

  func isReseedRequired() throws -> Bool {
    try preview.isReseedRequired()
  }

  func authoritativeSnapshotSession() throws -> AuthoritativeSnapshotSession? {
    try preview.authoritativeSnapshotSession()
  }

  func beginAuthoritativeSnapshot(
    boundary: CloudTraversalBoundary
  ) throws -> AuthoritativeSnapshotSession {
    try preview.beginAuthoritativeSnapshot(boundary: boundary)
  }

  func restartAuthoritativeSnapshot() throws -> AuthoritativeSnapshotSession {
    try preview.restartAuthoritativeSnapshot()
  }

  func markAuthoritativeSnapshotReady(sessionToken: String) throws {
    try preview.markAuthoritativeSnapshotReady(sessionToken: sessionToken)
  }

  func stageAuthoritativeSnapshotPage(
    records: [AuthoritativeSnapshotRemoteRecord], deletedRecordNames: [String],
    sessionToken: String
  ) throws {
    try preview.stageAuthoritativeSnapshotPage(
      records: records, deletedRecordNames: deletedRecordNames,
      sessionToken: sessionToken)
  }

  func finalizeAuthoritativeSnapshot(
    sessionToken: String, accountIdentifier: String, zoneName: String,
    enrolledZoneEpoch: Int?
  ) throws -> AuthoritativeSnapshotReport {
    try preview.finalizeAuthoritativeSnapshot(
      sessionToken: sessionToken, accountIdentifier: accountIdentifier,
      zoneName: zoneName, enrolledZoneEpoch: enrolledZoneEpoch)
  }

  func cancelAuthoritativeSnapshot() throws {
    try preview.cancelAuthoritativeSnapshot()
  }
}
