import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync
@preconcurrency import CloudKit

enum CloudSyncCandidateBuildError: Error {
  case restartRequired
}

/// Publication is intentionally paused, not restarted, while this build holds
/// predecessor records it cannot understand. Retiring that predecessor would
/// destroy the only remote copy; a later app build can drain the durable HOLD
/// rows and resume the exact claimed generation safely.
struct CloudSyncFutureRecordsPending: Error, Sendable, Equatable {
  let count: Int
}

/// A predecessor cannot be compacted while current-schema dependency rows or
/// durable corruption fences mean its remote inventory is not fully
/// materialized locally.
struct CloudSyncInboundStatePending: Error, Sendable, Equatable {
  let pendingRecordCount: Int
  let corruptRecordCount: Int
}

/// Horizon shedding has already proved the local canonical database incomplete.
/// A candidate built from it would make that loss authoritative and retire the
/// only predecessor that can repair it.
struct CloudSyncReseedRequiredPending: Error, Sendable, Equatable {}

enum CloudSyncCandidateRetentionCapability {
  case initialActive(
    authorization: AuditRetentionOutboundAuthorization,
    metadata: CloudSyncAuditRetentionMetadata)
  case staged(
    authorization: AuditRetentionCandidateAuthorization,
    metadata: CloudSyncAuditRetentionMetadata)

  var metadata: CloudSyncAuditRetentionMetadata {
    switch self {
    case .initialActive(_, let metadata), .staged(_, let metadata): metadata
    }
  }
}

extension CloudSyncEngineCoordinator {
  static let maxGenerationBuildAttempts = 8
  static let maxGenerationTraversalPages = 1_024

  /// Build one fresh, immutable custom-zone generation and publish it only after
  /// two terminal predecessor drains, durable snapshot upload, and independent
  /// nil-token readback. The captured rows and both progress cursors live in
  /// SQLite, so every remote phase resumes the exact same bytes after a crash.
  func rebuildGeneration(
    sync: any EnvelopeSyncServicing,
    accountIdentifier: String,
    databaseInstanceIdentifier: String,
    startingState: CloudSyncZoneGenerationState?,
    allowFromDeleted: Bool,
    minimumGenerationFloor: Int = 0,
    tombstoneCompactionCutoff requestedTombstoneCompactionCutoff: String? = nil
  ) async throws -> CloudSyncGenerationDescriptor {
    let accountGuard = accountBoundaryGuard(accountIdentifier: accountIdentifier)
    var lease = try await initialRebuildLease(
      startingState: startingState,
      databaseInstanceIdentifier: databaseInstanceIdentifier,
      allowFromDeleted: allowFromDeleted,
      minimumGenerationFloor: minimumGenerationFloor,
      accountGuard: accountGuard)
    _ = try sync.recordObservedCloudGenerationAuthority(
      forAccountIdentifier: accountIdentifier, generation: lease.epoch)

    for _ in 0..<Self.maxGenerationBuildAttempts {
      var builtRetention: CloudSyncCandidateRetentionCapability?
      let state = try await pusher.currentZoneGenerationState()
      guard case .rebuilding(
        let currentLease, let previousActive, let phase, let retired, _
      ) = state, currentLease == lease
      else { throw CloudSyncZoneEpochError.zoneRebuildLeaseLost }

      // Every abandoned attempt is recorded before a replacement lease is
      // claimed. Delete and CAS-prune those unpublished namespaces before
      // spending another attempt; if CloudKit is unavailable, keep this exact
      // lease claimed and retry later instead of consuming the bounded retired
      // ledger with another fresh candidate.
      try await cleanupAbandonedCandidateZones(
        sync: sync, accountIdentifier: accountIdentifier, lease: lease,
        retiredZoneNames: retired)
      let binding = try generationSnapshotBinding(
        accountIdentifier: accountIdentifier, lease: lease)

      do {
        var initialInbound = try await adoptCompactedPredecessorIfRequired(
          sync: sync, accountIdentifier: accountIdentifier,
          lease: lease, previousActive: previousActive)
        try await prepareReseedRecoveryForCandidateBuild(
          sync: sync, accountIdentifier: accountIdentifier,
          lease: lease, previousActive: previousActive)
        // Retry the durable inbox even for an initial generation with no
        // predecessor. A later build may now understand a raw HOLD, and must
        // materialize it before candidate capture rather than remain blocked
        // forever because there is no predecessor page to drive the drain.
        initialInbound.accumulate(try sync.applyInbound([], undecodable: 0))
        let predecessorInbound = try await drainPreviousGenerationToTerminal(
          sync: sync, accountIdentifier: accountIdentifier,
          lease: lease, previousActive: previousActive)
        initialInbound.accumulate(predecessorInbound)
        let heldFutureRecords = try sync.unresolvedFutureRecordCount()
        guard heldFutureRecords == 0 else {
          throw CloudSyncFutureRecordsPending(count: heldFutureRecords)
        }
        guard try !sync.isReseedRequired() else {
          throw CloudSyncReseedRequiredPending()
        }
        let initialCompleteness = try inboundCompletenessForGenerationBuild(
          sync: sync, accountIdentifier: accountIdentifier,
          previousActive: previousActive)
        guard initialCompleteness.isComplete else {
          throw CloudSyncInboundStatePending(
            pendingRecordCount: initialCompleteness.pendingRecordCount,
            corruptRecordCount: initialCompleteness.corruptRecordCount)
        }

        // A resumed immutable capture predates any inbound replay above. Local
        // user writes are intentionally sent after publication, but remote
        // replay (especially a newly-understood future record) belongs in the
        // generation baseline itself. Restart with a clean candidate namespace;
        // merely recapturing into the same zone could leave deleted stale record
        // names behind.
        if try sync.currentGenerationSnapshotStaging()?.binding == binding,
          Self.reportContainsCanonicalMutation(initialInbound)
        {
          throw CloudSyncCandidateBuildError.restartRequired
        }

        let candidateContext = CloudSyncGenerationContext(
          accountIdentifier: accountIdentifier, lease: lease)
        let candidateExpectation = CloudSyncGenerationExpectation.rebuilding(lease)
        let candidateGuard = generationBoundaryGuard(
          accountIdentifier: accountIdentifier,
          expectation: candidateExpectation)

        try await pusher.ensureZone(
          lease.candidateZoneID, expectation: candidateExpectation,
          boundaryGuard: candidateGuard)
        try await pusher.ensureGenerationRoot(
          lease, boundaryGuard: candidateGuard)

        if let stale = try sync.currentGenerationSnapshotStaging(),
          stale.binding != binding
        {
          try sync.discardGenerationSnapshot(binding: stale.binding)
        }

        let retention = try prepareCandidateRetention(
          sync: sync, accountIdentifier: accountIdentifier,
          candidateZoneName: lease.candidateZoneName,
          hasPreviousActive: previousActive != nil)
        builtRetention = retention
        let remoteMetadata = try await pusher.mergeAuditRetentionMetadata(
          retention.metadata, context: candidateContext,
          expectation: candidateExpectation, boundaryGuard: candidateGuard)
        guard remoteMetadata == retention.metadata else {
          throw CloudSyncCandidateBuildError.restartRequired
        }

        let existingStaging = try sync.currentGenerationSnapshotStaging()
        let tombstoneCompactionCutoff = existingStaging?.binding == binding
          ? existingStaging?.tombstoneCompactionCutoff
          : requestedTombstoneCompactionCutoff
        let captured = try captureDurableCandidateSnapshot(
          sync: sync, binding: binding, retention: retention,
          tombstoneCompactionCutoff: tombstoneCompactionCutoff)
        if phase == .claimed {
          try await pusher.advanceZoneRebuildPhase(
            lease, to: .preparing, boundaryGuard: candidateGuard)
        }
        let uploaded = try await uploadDurableCandidateSnapshot(
          sync: sync, binding: binding, staging: captured,
          context: candidateContext, expectation: candidateExpectation,
          boundaryGuard: candidateGuard, retention: retention)
        let verified = try await verifyDurableCandidateReadback(
          sync: sync, binding: binding, staging: uploaded,
          context: candidateContext, expectation: candidateExpectation,
          boundaryGuard: candidateGuard)

        // A save already in flight when the rebuild claim landed may complete
        // after the first drain and even after candidate readback. Pull the
        // predecessor again immediately before sealing. Any newly APPLIED row
        // was not in the immutable capture, so restart; ordinary local writes
        // do not appear in this report and remain pending for the ready zone.
        let lateInbound = try await drainPreviousGenerationToTerminal(
          sync: sync, accountIdentifier: accountIdentifier,
          lease: lease, previousActive: previousActive)
        guard !Self.reportContainsCanonicalMutation(lateInbound),
          lateInbound.deferred == 0,
          lateInbound.deferredUnknownType == 0,
          verified.remoteManifest == verified.manifest,
          retention.metadata.canonicalDigest == remoteMetadata.canonicalDigest
        else { throw CloudSyncCandidateBuildError.restartRequired }
        let lateHeldFutureRecords = try sync.unresolvedFutureRecordCount()
        guard lateHeldFutureRecords == 0 else {
          throw CloudSyncFutureRecordsPending(count: lateHeldFutureRecords)
        }
        guard try !sync.isReseedRequired() else {
          throw CloudSyncReseedRequiredPending()
        }
        let lateCompleteness = try inboundCompletenessForGenerationBuild(
          sync: sync, accountIdentifier: accountIdentifier,
          previousActive: previousActive)
        guard lateCompleteness.isComplete else {
          throw CloudSyncInboundStatePending(
            pendingRecordCount: lateCompleteness.pendingRecordCount,
            corruptRecordCount: lateCompleteness.corruptRecordCount)
        }

        // Minimize the only unavoidable cross-system race: the candidate
        // capability must still describe the exact local frontier/policy after
        // both predecessor drains and immediately before the immutable seal.
        // A drift here restarts with a new capture. Drift after this check but
        // before the remote ready CAS is preserved by relaxed post-publication
        // route activation, then published by `prepareReadyRetention`.
        if case .staged(let authorization, _) = retention {
          _ = try sync.validateAuditRetentionCandidateGeneration(
            authorization: authorization)
        }

        let sealedManifest = cloudManifest(
          verified.manifest, retentionMetadataDigest: remoteMetadata.canonicalDigest,
          tombstoneCompactionCutoff: verified.tombstoneCompactionCutoff)
        // Deterministic for this immutable lease: a crash in sealing/publishing
        // must re-save and complete with the exact same witness.
        let readyWitness = lease.identifier
        if phase == .claimed || phase == .preparing {
          try await pusher.advanceZoneRebuildPhase(
            lease, to: .sealing, boundaryGuard: candidateGuard)
        }
        try await pusher.saveGenerationSeal(
          lease, readyWitness: readyWitness, manifest: sealedManifest,
          boundaryGuard: candidateGuard)
        if phase != .publishing {
          try await pusher.advanceZoneRebuildPhase(
            lease, to: .publishing, boundaryGuard: candidateGuard)
        }
        let descriptor = try await pusher.completeZoneRebuild(
          lease, readyWitness: readyWitness, manifest: sealedManifest,
          boundaryGuard: accountGuard)

        try sync.finalizePublishedGenerationSnapshot(binding: binding)
        let readyGuard = generationBoundaryGuard(
          accountIdentifier: accountIdentifier,
          expectation: .ready(descriptor))
        try await pusher.publishGenerationWake(
          descriptor: descriptor, boundaryGuard: readyGuard)
        try await cleanupRetiredGenerations(
          sync: sync, accountIdentifier: accountIdentifier,
          activeDescriptor: descriptor, boundaryGuard: readyGuard)
        return descriptor
      } catch let error as CloudSyncFutureRecordsPending {
        // Never leave an immutable capture that predates a future record. A
        // later app build drains the durable HOLD first; without this discard it
        // could resume and publish bytes captured before that record arrived.
        if let staging = try sync.currentGenerationSnapshotStaging() {
          try sync.discardGenerationSnapshot(binding: staging.binding)
        } else {
          try revokeCandidateRetentionIfNeeded(sync: sync, retention: builtRetention)
        }
        throw error
      } catch let error as CloudSyncInboundStatePending {
        if let staging = try sync.currentGenerationSnapshotStaging() {
          try sync.discardGenerationSnapshot(binding: staging.binding)
        } else {
          try revokeCandidateRetentionIfNeeded(sync: sync, retention: builtRetention)
        }
        if error.pendingRecordCount > 0 || error.corruptRecordCount > 0,
          let previousActive
        {
          try await preparePredecessorBaselineRecovery(
            sync: sync, accountIdentifier: accountIdentifier,
            lease: lease, previousActive: previousActive)
        }
        throw error
      } catch let error as CloudSyncReseedRequiredPending {
        if let staging = try sync.currentGenerationSnapshotStaging() {
          try sync.discardGenerationSnapshot(binding: staging.binding)
        } else {
          try revokeCandidateRetentionIfNeeded(sync: sync, retention: builtRetention)
        }
        throw error
      } catch let readback as CloudSyncCandidateReadbackFetchFailure {
        // A persistent hole in candidate readback means this immutable
        // namespace cannot be proven complete. Prepare one fresh candidate now,
        // then yield to app pacing instead of resuming the same poisoned token
        // forever or burning all eight rebuild attempts in a tight loop.
        if readback.failure.kind == .persistent,
          readback.failure.requiresCandidateNamespaceRestart
        {
          _ = try await restartCandidateAttempt(
            sync: sync, accountIdentifier: accountIdentifier, lease: lease,
            retention: builtRetention, boundaryGuard: accountGuard)
        }
        throw readback.failure
      } catch is CloudSyncCandidateBuildError {
        lease = try await restartCandidateAttempt(
          sync: sync, accountIdentifier: accountIdentifier, lease: lease,
          retention: builtRetention, boundaryGuard: accountGuard)
      } catch GenerationSnapshotError.manifestMismatch {
        lease = try await restartCandidateAttempt(
          sync: sync, accountIdentifier: accountIdentifier, lease: lease,
          retention: builtRetention, boundaryGuard: accountGuard)
      } catch AuditRetentionStateError.invalidOutboundAuthorization {
        lease = try await restartCandidateAttempt(
          sync: sync, accountIdentifier: accountIdentifier, lease: lease,
          retention: builtRetention, boundaryGuard: accountGuard)
      }
    }
    throw CloudSyncZoneEpochError.zoneEpochPendingBackfillFailed
  }

  private func inboundCompletenessForGenerationBuild(
    sync: any EnvelopeSyncServicing,
    accountIdentifier: String,
    previousActive: CloudSyncGenerationDescriptor?
  ) throws -> CloudInboundCompletenessState {
    guard let previousActive else {
      return CloudInboundCompletenessState(
        pendingRecordCount: try sync.unresolvedInboundRecordCount(),
        corruptRecordCount: try sync.quarantinedInboundRecordCount())
    }
    let boundary = try traversalBoundary(
      CloudSyncGenerationContext(
        accountIdentifier: accountIdentifier, descriptor: previousActive))
    return try sync.cloudInboundCompletenessState(boundary: boundary)
  }

  /// Resolve a standing recovery marker before treating this database as a
  /// complete generation source. With a predecessor, recovery must start from a
  /// nil-token traversal under the exact rebuild lease; with no predecessor,
  /// the complete local enumeration is the only seed and the candidate's later
  /// immutable readback proves the same inventory independently.
  private func prepareReseedRecoveryForCandidateBuild(
    sync: any EnvelopeSyncServicing, accountIdentifier: String,
    lease: CloudSyncZoneRebuildLease,
    previousActive: CloudSyncGenerationDescriptor?
  ) async throws {
    guard try sync.isReseedRequired() else { return }
    guard let previousActive else {
      _ = try sync.enqueueFullResyncBackfill()
      return
    }
    try await preparePredecessorBaselineRecovery(
      sync: sync, accountIdentifier: accountIdentifier,
      lease: lease, previousActive: previousActive)
  }

  /// Persist a nil-token predecessor traversal before returning a build that
  /// could not resolve current-schema dependency rows. Without this reset, an
  /// already-terminal incremental cursor would keep fetching only newer deltas
  /// and could never rediscover an unchanged parent record.
  private func preparePredecessorBaselineRecovery(
    sync: any EnvelopeSyncServicing, accountIdentifier: String,
    lease: CloudSyncZoneRebuildLease,
    previousActive: CloudSyncGenerationDescriptor
  ) async throws {
    let context = CloudSyncGenerationContext(
      accountIdentifier: accountIdentifier, descriptor: previousActive)
    let expectation = CloudSyncGenerationExpectation.previousActive(
      lease: lease, descriptor: previousActive)
    let guardClosure = generationBoundaryGuard(
      accountIdentifier: accountIdentifier, expectation: expectation)
    do {
      try await prepareInWindowBaselineRecovery(
        sync: sync, boundary: try traversalBoundary(context),
        context: context, expectation: expectation,
        boundaryGuard: guardClosure)
    } catch let error as CKError where error.code == .zoneNotFound {
      // The local nil-token traversal and complete backfill were committed
      // before the witness save. If the predecessor disappeared after the
      // rebuilding CAS, retain that durable local recovery and let the normal
      // predecessor drain independently re-prove absence. Re-checking the exact
      // lease prevents a stale missing-zone result from authorizing a candidate.
      guard await guardClosure() else {
        throw CloudSyncGenerationBoundaryCrossed()
      }
    }
  }

  /// A foreign rebuild takeover may inherit a predecessor that already shed
  /// tombstones beyond the recovery horizon. If this physical database cannot
  /// prove that it published, fully traversed, or server-time-covered that
  /// predecessor, ordinary LWW union would capture stale local rows into the
  /// replacement generation. Adopt the predecessor's complete inventory first
  /// so remote absence remains authoritative across the takeover.
  private func adoptCompactedPredecessorIfRequired(
    sync: any EnvelopeSyncServicing, accountIdentifier: String,
    lease: CloudSyncZoneRebuildLease,
    previousActive: CloudSyncGenerationDescriptor?
  ) async throws -> InboundApplyReport {
    guard let previousActive else { return InboundApplyReport() }
    let context = CloudSyncGenerationContext(
      accountIdentifier: accountIdentifier, descriptor: previousActive)
    let boundary = try traversalBoundary(context)
    let expectation = CloudSyncGenerationExpectation.previousActive(
      lease: lease, descriptor: previousActive)
    let guardClosure = generationBoundaryGuard(
      accountIdentifier: accountIdentifier, expectation: expectation)

    var finalizedLocalPublication = false
    if let staging = try sync.currentGenerationSnapshotStaging(),
      Self.staging(staging, provesPublicationOf: previousActive,
        accountIdentifier: accountIdentifier)
    {
      try sync.finalizePublishedGenerationSnapshot(binding: staging.binding)
      finalizedLocalPublication = true
    }

    let traversal = try sync.cloudTraversalState(
      accountIdentifier: accountIdentifier,
      zoneIdentifier: previousActive.zoneName)
    let hasCurrentBaseline = traversal.baselineWitness?.boundary == boundary
    if hasCurrentBaseline, let cutoff = previousActive.tombstoneCompactionCutoff {
      _ = try sync.compactCloudConfirmedTombstones(through: cutoff)
    }
    let enrolledEpoch = try sync.enrolledZoneEpoch(
      forAccountIdentifier: accountIdentifier)
    // An unfinished first traversal does not erase the exact publisher proof;
    // post-capture writes are valid intent and remain outside that snapshot.
    let hasExactPublicationProof = finalizedLocalPublication
      || (enrolledEpoch == previousActive.epoch && !hasCurrentBaseline)
    let hasTrustedCoverage: Bool
    if let cutoff = previousActive.tombstoneCompactionCutoff {
      hasTrustedCoverage = try sync.trustedTerminalServerTimeCovers(
        cutoff: cutoff, forAccountIdentifier: accountIdentifier)
    } else {
      hasTrustedCoverage = true
    }

    let activeSession = try sync.authoritativeSnapshotSession()
    let mustResumeExactAdoption = activeSession?.boundary == boundary
    let requiresAdoption = !(hasExactPublicationProof || hasCurrentBaseline || hasTrustedCoverage)
    guard mustResumeExactAdoption || requiresAdoption else {
      if activeSession != nil {
        try sync.cancelAuthoritativeSnapshot()
      }
      return InboundApplyReport()
    }

    if !mustResumeExactAdoption {
      await warnOverWindowSnapshotReEnrollment(sync: sync)
    }
    // Do not cancel a mismatched active session before beginning this one.
    // Core replaces it in place and preserves the original outbox boundary,
    // keeping writes made after the old session classified as user intent.
    var aggregate = InboundApplyReport()
    do {
      _ = try await prepareReadyRetention(
        sync: sync, context: context, expectation: expectation,
        boundaryGuard: guardClosure)
      let session = try await prepareAuthoritativeSnapshot(
        sync: sync, boundary: boundary, context: context,
        expectation: expectation, boundaryGuard: guardClosure)
      for _ in 0..<Self.maxGenerationTraversalPages {
        let page = try await pullOneAuthoritativeSnapshotPage(
          sync: sync, session: session, context: context,
          expectation: expectation, boundaryGuard: guardClosure)
        aggregate.accumulate(page.report)
        if page.reachedTerminal { return aggregate }
      }
      throw CloudSyncZoneEpochError.zoneEpochPendingBackfillFailed
    } catch let recovery as CloudSyncAuthoritativeRecordFailureRecovery {
      try await restartAuthoritativeSnapshotAfterInvalidCursor(
        sync: sync, boundary: boundary, context: context,
        expectation: expectation, boundaryGuard: guardClosure)
      throw recovery.failure
    } catch is CloudSyncInvalidChangeCursor {
      try await restartAuthoritativeSnapshotAfterInvalidCursor(
        sync: sync, boundary: boundary, context: context,
        expectation: expectation, boundaryGuard: guardClosure)
      throw CloudSyncCursorRecoveryPrepared()
    } catch let error as CKError where error.code == .changeTokenExpired {
      try await restartAuthoritativeSnapshotAfterInvalidCursor(
        sync: sync, boundary: boundary, context: context,
        expectation: expectation, boundaryGuard: guardClosure)
      throw CloudSyncCursorRecoveryPrepared()
    } catch let error as CKError where error.code == .zoneNotFound {
      // The exact rebuilding CAS authorizes replacement of a predecessor that
      // disappeared before this device could adopt it. No partial snapshot was
      // applied, so release its queue fence and fall back to the surviving
      // canonical database, matching the ordinary predecessor-drain policy.
      guard await guardClosure() else {
        throw CloudSyncGenerationBoundaryCrossed()
      }
      try sync.cancelAuthoritativeSnapshot()
      return InboundApplyReport()
    } catch let error as AuthoritativeSnapshotError {
      if case .unrecognizedRecords = error {
        _ = try sync.restartAuthoritativeSnapshot()
      }
      throw error
    }
  }

  private static func staging(
    _ staging: GenerationSnapshotStaging,
    provesPublicationOf descriptor: CloudSyncGenerationDescriptor,
    accountIdentifier: String
  ) -> Bool {
    let binding = staging.binding
    return binding.accountIdentifier == accountIdentifier
      && binding.candidateZoneName == descriptor.zoneName
      && binding.generation == descriptor.epoch
      && binding.generationIdentifier == descriptor.generationID
      && binding.leaseIdentifier == descriptor.readyWitness
  }

  private static func reportContainsCanonicalMutation(_ report: InboundApplyReport) -> Bool {
    report.applied > 0 || report.remapped > 0 || report.drainReplayed > 0
      || !report.appliedEntityTypes.isEmpty
  }

  private func initialRebuildLease(
    startingState: CloudSyncZoneGenerationState?,
    databaseInstanceIdentifier: String,
    allowFromDeleted: Bool,
    minimumGenerationFloor: Int,
    accountGuard: @escaping @Sendable () async -> Bool
  ) async throws -> CloudSyncZoneRebuildLease {
    if case .rebuilding(let lease, _, _, _, _) = startingState,
      lease.ownerIdentifier == databaseInstanceIdentifier
    {
      return lease
    }
    return try await pusher.beginZoneRebuild(
      atLeast: max(startingState?.epoch ?? 0, minimumGenerationFloor),
      ownerIdentifier: databaseInstanceIdentifier,
      allowFromDeleted: allowFromDeleted,
      boundaryGuard: accountGuard)
  }

  private func drainPreviousGenerationToTerminal(
    sync: any EnvelopeSyncServicing, accountIdentifier: String,
    lease: CloudSyncZoneRebuildLease,
    previousActive: CloudSyncGenerationDescriptor?
  ) async throws -> InboundApplyReport {
    guard let previousActive else { return InboundApplyReport() }
    let context = CloudSyncGenerationContext(
      accountIdentifier: accountIdentifier, descriptor: previousActive)
    let expectation = CloudSyncGenerationExpectation.previousActive(
      lease: lease, descriptor: previousActive)
    let guardClosure = generationBoundaryGuard(
      accountIdentifier: accountIdentifier, expectation: expectation)
    do {
      _ = try await prepareReadyRetention(
        sync: sync, context: context, expectation: expectation,
        boundaryGuard: guardClosure)
      var aggregate = InboundApplyReport()
      var resetInvalidCursor = false
      for _ in 0..<Self.maxGenerationTraversalPages {
        let page: CloudSyncGenerationPullResult
        do {
          page = try await pullOneGenerationPage(
            sync: sync, context: context, expectation: expectation,
            boundaryGuard: guardClosure,
            requireFullReseedOnPersistentFailure: false)
        } catch is CloudSyncInvalidChangeCursor {
          guard !resetInvalidCursor else { throw CloudSyncCandidateBuildError.restartRequired }
          try resetGenerationTraversalAfterInvalidCursor(
            sync: sync, boundary: try traversalBoundary(context),
            requireFullReseed: false)
          resetInvalidCursor = true
          continue
        } catch let error as CKError where error.code == .changeTokenExpired {
          guard !resetInvalidCursor else { throw CloudSyncCandidateBuildError.restartRequired }
          try resetGenerationTraversalAfterInvalidCursor(
            sync: sync, boundary: try traversalBoundary(context),
            requireFullReseed: false)
          resetInvalidCursor = true
          continue
        }
        aggregate.accumulate(page.report)
        if page.reachedTerminal { return aggregate }
      }
      throw CloudSyncZoneEpochError.zoneEpochPendingBackfillFailed
    } catch let error as CKError where error.code == .zoneNotFound {
      // The remote rebuilding CAS already authorizes replacement of this exact
      // predecessor. Re-observe that authority after the failed request instead
      // of relying on an ephemeral caller flag: a crash after the claim simply
      // proves the same absence again on the next trigger. A userDeletedZone is
      // intentionally not accepted here; that is the explicit cloud-deletion
      // transition, not an ordinary missing predecessor.
      guard await guardClosure() else {
        throw CloudSyncGenerationBoundaryCrossed()
      }
      return InboundApplyReport()
    }
  }

  private func prepareCandidateRetention(
    sync: any EnvelopeSyncServicing, accountIdentifier: String,
    candidateZoneName: String, hasPreviousActive: Bool
  ) throws -> CloudSyncCandidateRetentionCapability {
    if hasPreviousActive {
      let authorization = try sync.authorizeAuditRetentionCandidateGeneration(
        forAccountIdentifier: accountIdentifier,
        candidateZoneName: candidateZoneName)
      let metadata = CloudSyncAuditRetentionMetadata(
        frontier: authorization.frontier, policy: authorization.policy,
        policyVersion: authorization.policyVersion,
        policyAuthorizedEpoch: authorization.frontier.epoch)
      return .staged(authorization: authorization, metadata: metadata)
    }

    // True bootstrap/deleted re-enable has no live predecessor whose routing can
    // be protected. Bind the candidate as the initial local transport scope;
    // remote publication still remains blocked on readback+seal.
    let activation = try sync.activateAuditRetentionAccount(
      accountIdentifier: accountIdentifier, zoneName: candidateZoneName)
    var state = activation.state
    if !state.isPolicyReady {
      guard activation.kind == .newAccount else {
        throw AuditRetentionStateError.policyNotReady(accountIdentifier)
      }
      state = try sync.initializeAuditRetentionForVerifiedEmptyAccount(
        accountIdentifier: accountIdentifier)
    }
    let authorization = try sync.authorizeAuditRetentionOutbound(
      verifiedRemoteFrontier: state.frontier,
      forAccountIdentifier: accountIdentifier, zoneName: candidateZoneName)
    let metadata = CloudSyncAuditRetentionMetadata(
      frontier: state.frontier, policy: state.policy,
      policyVersion: state.policyVersion,
      policyAuthorizedEpoch: state.frontierEpoch)
    return .initialActive(authorization: authorization, metadata: metadata)
  }

  private func cloudManifest(
    _ source: GenerationSnapshotManifest,
    retentionMetadataDigest: String,
    tombstoneCompactionCutoff: String?
  ) -> CloudSyncGenerationManifest {
    CloudSyncGenerationManifest(
      sourceLocalChangeSequence: source.sourceLocalChangeSequence,
      expectedEntityCount: source.recordCount,
      expectedEncodedBytes: source.totalEncodedBytes,
      canonicalDigest: source.canonicalDigest,
      expectedAuditCount: source.auditRecordCount,
      auditCanonicalDigest: source.auditWitnessDigest,
      retentionMetadataDigest: retentionMetadataDigest,
      tombstoneCompactionCutoff: tombstoneCompactionCutoff)
  }

  private func revokeCandidateRetentionIfNeeded(
    sync: any EnvelopeSyncServicing,
    retention: CloudSyncCandidateRetentionCapability?
  ) throws {
    if case .staged(let authorization, _) = retention {
      try sync.revokeAuditRetentionCandidateGeneration(
        authorization: authorization)
    }
  }

  private func restartCandidateAttempt(
    sync: any EnvelopeSyncServicing, accountIdentifier: String,
    lease abandonedLease: CloudSyncZoneRebuildLease,
    retention: CloudSyncCandidateRetentionCapability?,
    boundaryGuard: @escaping @Sendable () async -> Bool
  ) async throws -> CloudSyncZoneRebuildLease {
    // Revoke the remote lease first so no crash can leave a locally discarded
    // staging capture attached to a still-publishable candidate. If local
    // cleanup then fails, the next cycle observes the replacement lease and
    // discards the exact old singleton before capturing anything new.
    let replacement = try await pusher.restartZoneRebuild(
      abandonedLease, boundaryGuard: boundaryGuard)
    let oldBinding = try generationSnapshotBinding(
      accountIdentifier: accountIdentifier, lease: abandonedLease)
    if try sync.generationSnapshotStaging(binding: oldBinding) != nil {
      try sync.discardGenerationSnapshot(binding: oldBinding)
    } else {
      try revokeCandidateRetentionIfNeeded(sync: sync, retention: retention)
    }
    await pusher.clearRecordSystemFieldsCache(
      accountIdentifier: accountIdentifier,
      zoneName: abandonedLease.candidateZoneName)
    return replacement
  }

  func cleanupRetiredGenerations(
    sync: any EnvelopeSyncServicing,
    accountIdentifier: String,
    activeDescriptor: CloudSyncGenerationDescriptor,
    boundaryGuard: @escaping @Sendable () async -> Bool
  ) async throws {
    guard case .ready(let current, let retired, _) =
      try await pusher.currentZoneGenerationState(), current == activeDescriptor
    else { throw CloudSyncGenerationBoundaryCrossed() }
    for zoneName in retired where zoneName != activeDescriptor.zoneName {
      do {
        try await pusher.deleteRetiredZone(
          zoneName: zoneName, accountIdentifier: accountIdentifier,
          boundaryGuard: boundaryGuard)
        try sync.acknowledgeAuditRetentionZoneDeletion(
          forAccountIdentifier: accountIdentifier, zoneName: zoneName)
        await pusher.clearRecordSystemFieldsCache(
          accountIdentifier: accountIdentifier, zoneName: zoneName)
        try await pusher.finalizeRetiredZoneDeletion(
          zoneName: zoneName, boundaryGuard: boundaryGuard)
      } catch is CloudSyncGenerationBoundaryCrossed {
        throw CloudSyncGenerationBoundaryCrossed()
      } catch is CloudSyncAccountBoundaryCrossed {
        throw CloudSyncAccountBoundaryCrossed()
      } catch {
        Self.log.error(
          "CloudSync retained generation cleanup deferred for \(zoneName, privacy: .private): \(error.localizedDescription, privacy: .private)")
      }
    }
  }

  func cleanupAbandonedCandidateZones(
    sync: any EnvelopeSyncServicing,
    accountIdentifier: String,
    lease: CloudSyncZoneRebuildLease,
    retiredZoneNames: [String]
  ) async throws {
    guard !retiredZoneNames.isEmpty else { return }
    let guardClosure = generationBoundaryGuard(
      accountIdentifier: accountIdentifier, expectation: .rebuilding(lease))
    for zoneName in retiredZoneNames {
      try await pusher.deleteRetiredZone(
        zoneName: zoneName, accountIdentifier: accountIdentifier,
        boundaryGuard: guardClosure)
      try sync.acknowledgeAuditRetentionZoneDeletion(
        forAccountIdentifier: accountIdentifier, zoneName: zoneName)
      await pusher.clearRecordSystemFieldsCache(
        accountIdentifier: accountIdentifier, zoneName: zoneName)
      try await pusher.finalizeRetiredZoneDeletion(
        zoneName: zoneName, boundaryGuard: guardClosure)
    }
  }
}
