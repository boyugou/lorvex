@preconcurrency import CloudKit
import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync
import os

public struct CloudSyncCycleReport: Equatable, Sendable {
  public var pushedRecordCount: Int
  public var failedPushCount: Int
  public var fetchedRecordCount: Int
  /// The exact CloudKit traversal has not yet reached a terminal page.
  public var moreInboundComing: Bool
  /// Eligible local publication or physical-delete work remains after this
  /// cycle's bounded outbound walk.
  public var moreOutboundComing: Bool
  public var inbound: InboundApplyReport
  /// Earliest durable retry deadline among this generation's parked outbox
  /// rows and account/zone-scoped audit physical-delete work. Main-app owners
  /// use it to schedule a wake even when no mutation, push, or activation will
  /// arrive at that time.
  public var nextDeferredRetryAt: Date?

  public init(
    pushedRecordCount: Int, failedPushCount: Int, fetchedRecordCount: Int,
    moreInboundComing: Bool, inbound: InboundApplyReport,
    moreOutboundComing: Bool = false,
    nextDeferredRetryAt: Date? = nil
  ) {
    self.pushedRecordCount = pushedRecordCount
    self.failedPushCount = failedPushCount
    self.fetchedRecordCount = fetchedRecordCount
    self.moreInboundComing = moreInboundComing
    self.moreOutboundComing = moreOutboundComing
    self.inbound = inbound
    self.nextDeferredRetryAt = nextDeferredRetryAt
  }

  /// Whether the main app should arrange a prompt bounded continuation.
  public var moreWorkComing: Bool {
    moreInboundComing || moreOutboundComing
  }
}

struct CloudSyncGenerationPullResult {
  var fetched: Int
  var moreComing: Bool
  var report: InboundApplyReport
  var reachedTerminal: Bool
}

/// Single authority for account-, generation-, traversal-, and outbox-ordered
/// CloudKit synchronization. No operation infers a custom zone from a constant:
/// every request carries an exact account-qualified generation context and is
/// fenced against the default-zone control record before and after CloudKit I/O.
public struct CloudSyncEngineCoordinator: Sendable {
  public static let inboundApplyChunkSize = 50
  /// CloudKit's documented request ceiling is 200 operations. The pusher still
  /// subdivides `limitExceeded` responses because encoded size can impose a
  /// lower dynamic limit, but ordinary drains should not begin above the
  /// published count bound.
  public static let maxPushBatchSize = 200
  public static let maxPushBatchBytes = 768 * 1024
  public static let maxDrainIterations = 64
  public static let perRecordFetchFailureReseedThreshold = 3

  var outboundDrainIterationLimit = Self.maxOutboundDrainIterations

  public var accountChecker: any CloudKitAccountStatusChecking
  public var pusher: any CloudSyncRecordPushing
  public var fetcher: any CloudSyncRemoteChangeFetching
  public var accountIdentifier: any CloudKitAccountIdentifying
  public var accountIdentityStore: any CloudSyncAccountIdentityStoring
  public var accountPauseStore: any CloudSyncPauseStateStoring
  let operationGate: CloudSyncOperationGate

  static let log = Logger(subsystem: "com.lorvex.apple", category: "cloudsync")

  public init(
    accountChecker: any CloudKitAccountStatusChecking,
    pusher: any CloudSyncRecordPushing,
    fetcher: any CloudSyncRemoteChangeFetching,
    accountIdentifier: any CloudKitAccountIdentifying =
      UnavailableCloudSyncAccountIdentifier(),
    accountIdentityStore: any CloudSyncAccountIdentityStoring =
      InMemoryCloudSyncAccountIdentityStore(),
    accountPauseStore: any CloudSyncPauseStateStoring =
      InMemoryCloudSyncPauseStateStore()
  ) {
    self.accountChecker = accountChecker
    self.pusher = pusher
    self.fetcher = fetcher
    self.accountIdentifier = accountIdentifier
    self.accountIdentityStore = accountIdentityStore
    self.accountPauseStore = accountPauseStore
    self.operationGate = CloudSyncOperationGate()
  }

  public func runCycle(sync: any EnvelopeSyncServicing) async throws -> CloudSyncCycleReport? {
    try await withSerializedOperation {
      try await runCycleUnlocked(sync: sync, performReseedRecovery: true)
    }
  }

  func runCycleUnlocked(
    sync: any EnvelopeSyncServicing, performReseedRecovery: Bool
  ) async throws -> CloudSyncCycleReport? {
    do {
      return try await runCycleBodyUnlocked(
        sync: sync, performReseedRecovery: performReseedRecovery)
    } catch is CloudSyncAccountBoundaryCrossed {
      _ = await accountStillMatchesStartGate(
        context: "a per-request account boundary; halting the cycle")
      return nil
    } catch is CloudSyncGenerationBoundaryCrossed {
      // A peer changed the generation while this request was in flight. No
      // result was consumed; the next cycle re-reads the control authority.
      return nil
    }
  }

  private func runCycleBodyUnlocked(
    sync: any EnvelopeSyncServicing, performReseedRecovery: Bool
  ) async throws -> CloudSyncCycleReport? {
    // `.userDeletedZone` closes ordinary sync, but its fleet-visible barrier may
    // still have physical zones to remove after an earlier network/process
    // interruption. Run only that restricted maintenance path before the
    // ordinary account/pause gate; it never uploads or recreates a generation.
    if try await retryPendingCloudDataDeletionCleanupUnlocked(sync: sync) {
      return nil
    }
    guard try await accountChecker.checkAccountStatus() == .available,
      case .proceed = await passesAccountStartGate(sync: sync),
      let account = try await accountIdentityStore.loadLastAccountIdentifier(),
      let databaseInstanceID = try sync.databaseInstanceIdentifier()
    else { return nil }

    try establishTraversalBinding(
      sync: sync, accountIdentifier: account,
      databaseInstanceIdentifier: databaseInstanceID)
    let priorAuthorityFloor = try sync.observedCloudGenerationAuthorityFloor(
      forAccountIdentifier: account)
    let state = try await pusher.currentZoneGenerationState()
    // The generation-control fetch is an external suspension point. Never
    // consume its result (especially the terminal `.deleted` state) after the
    // signed-in iCloud account changed: doing so would persist a
    // `.userDeletedZone` pause for the wrong account and mask the real account
    // transition indefinitely.
    guard await accountStillMatchesStartGate(
      context: "the initial generation-control read")
    else { throw CloudSyncAccountBoundaryCrossed() }
    if let state {
      _ = try sync.recordObservedCloudGenerationAuthority(
        forAccountIdentifier: account, generation: state.epoch)
    }
    let descriptor: CloudSyncGenerationDescriptor

    switch state {
    case nil:
      // Account binding is committed before CloudKit I/O and therefore is not
      // evidence by itself: a fresh app can crash in that half-bootstrap. A
      // durable authority witness, however, proves this lineage previously saw
      // a control generation; its disappearance is protocol/data loss and must
      // never silently bootstrap over an existing fleet.
      guard priorAuthorityFloor == nil else {
        throw CloudSyncZoneEpochError.zoneEpochRecordUndecodable
      }
      descriptor = try await rebuildGeneration(
        sync: sync, accountIdentifier: account,
        databaseInstanceIdentifier: databaseInstanceID,
        startingState: nil, allowFromDeleted: false,
        minimumGenerationFloor: 0)

    case .deleted:
      try await accountPauseStore.savePauseReason(.userDeletedZone)
      return nil

    case .rebuilding(let lease, _, _, let retired, _):
      // A foreign owner may have crashed forever. Let `beginZoneRebuild` enforce
      // the server-modification-date takeover delay instead of permanently
      // halting here. Prune already-retired namespaces under the exact current
      // lease first: otherwise a full 32-entry ledger prevents the takeover CAS
      // from appending the abandoned candidate and wedges the fleet forever.
      if lease.ownerIdentifier != databaseInstanceID {
        try await cleanupAbandonedCandidateZones(
          sync: sync, accountIdentifier: account, lease: lease,
          retiredZoneNames: retired)
      }
      descriptor = try await rebuildGeneration(
        sync: sync, accountIdentifier: account,
        databaseInstanceIdentifier: databaseInstanceID,
        startingState: state, allowFromDeleted: false)

    case .ready(let ready, _, _):
      descriptor = ready
    }

    return try await runReadyGenerationCycle(
      sync: sync, accountIdentifier: account, descriptor: descriptor,
      performReseedRecovery: performReseedRecovery)
  }

  func establishTraversalBinding(
    sync: any EnvelopeSyncServicing, accountIdentifier: String,
    databaseInstanceIdentifier: String
  ) throws {
    let existingBinding: CloudTraversalAccountBinding?
    do {
      existingBinding = try sync.cloudTraversalAccountBinding()
    } catch CloudTraversalStateError.databaseInstanceMismatch {
      // The concrete core intentionally refuses to return an old-lineage
      // binding as a normal value. Treat that fail-closed signal as the one
      // explicit restore/clone boundary authorized to destroy old proofs.
      let rebound = try sync.rebindCloudTraversalAfterDatabaseInstanceRotation(
        expectedAccountIdentifier: accountIdentifier)
      guard rebound.databaseInstanceIdentifier == databaseInstanceIdentifier else {
        throw CloudTraversalStateError.databaseInstanceMismatch
      }
      return
    }
    guard let binding = existingBinding else {
      let claimed = try sync.claimCloudTraversalAccount(
        accountIdentifier: accountIdentifier)
      guard claimed.databaseInstanceIdentifier == databaseInstanceIdentifier else {
        throw CloudTraversalStateError.databaseInstanceMismatch
      }
      return
    }
    guard binding.accountIdentifier == accountIdentifier else {
      throw CloudTraversalStateError.accountBoundaryMismatch(
        expected: binding.accountIdentifier, actual: accountIdentifier)
    }
    if binding.databaseInstanceIdentifier != databaseInstanceIdentifier {
      let rebound = try sync.rebindCloudTraversalAfterDatabaseInstanceRotation(
        expectedAccountIdentifier: accountIdentifier)
      guard rebound.databaseInstanceIdentifier == databaseInstanceIdentifier else {
        throw CloudTraversalStateError.databaseInstanceMismatch
      }
    }
  }

  private func runReadyGenerationCycle(
    sync: any EnvelopeSyncServicing, accountIdentifier: String,
    descriptor: CloudSyncGenerationDescriptor, performReseedRecovery: Bool
  ) async throws -> CloudSyncCycleReport {
    let context = CloudSyncGenerationContext(
      accountIdentifier: accountIdentifier, descriptor: descriptor)
    let expectation = CloudSyncGenerationExpectation.ready(descriptor)
    let guardClosure = generationBoundaryGuard(
      accountIdentifier: accountIdentifier, expectation: expectation)
    guard case .ready(
      let currentDescriptor, let retiredZoneNames, let controlModifiedAt
    ) =
      try await pusher.currentZoneGenerationState(),
      currentDescriptor == descriptor
    else { throw CloudSyncGenerationBoundaryCrossed() }

    do {
      try await pusher.ensureZone(
        descriptor.zoneID, expectation: expectation,
        boundaryGuard: guardClosure)
    } catch let error as CKError where error.code == .userDeletedZone {
      _ = try await pusher.markCloudDataDeleted(
        atLeast: descriptor.epoch, boundaryGuard: guardClosure)
      try await accountPauseStore.savePauseReason(.userDeletedZone)
      return emptyReport()
    } catch let error as CKError where error.code == .zoneNotFound {
      let rebuilt = try await rebuildGeneration(
        sync: sync, accountIdentifier: accountIdentifier,
        databaseInstanceIdentifier: try requiredDatabaseIdentifier(sync),
        startingState: .ready(
          descriptor: descriptor, retiredZoneNames: [], modifiedAt: controlModifiedAt),
        allowFromDeleted: false)
      return try await runReadyGenerationCycle(
        sync: sync, accountIdentifier: accountIdentifier, descriptor: rebuilt,
        performReseedRecovery: performReseedRecovery)
    }

    guard try await pusher.validateGenerationRoot(
      context: context, expectation: expectation,
      boundaryGuard: guardClosure)
    else { throw CloudSyncZoneEpochError.generationMarkerMismatch }

    // Remote publication may have committed immediately before the process
    // crashed. Reconcile the singleton durable capture before ordinary
    // retention authorization: an exact ready descriptor atomically activates
    // its candidate routing and removes staging; anything else is an abandoned
    // lease that can no longer become authoritative.
    var finalizedLocalPublication = false
    if let staging = try sync.currentGenerationSnapshotStaging() {
      let binding = staging.binding
      if binding.accountIdentifier == accountIdentifier,
        binding.candidateZoneName == descriptor.zoneName,
        binding.generation == descriptor.epoch,
        binding.generationIdentifier == descriptor.generationID,
        binding.leaseIdentifier == descriptor.readyWitness
      {
        try sync.finalizePublishedGenerationSnapshot(binding: binding)
        finalizedLocalPublication = true
      } else {
        try sync.discardGenerationSnapshot(binding: binding)
      }
    }

    let boundary = try traversalBoundary(context)
    let localTraversal = try sync.cloudTraversalState(
      accountIdentifier: accountIdentifier, zoneIdentifier: descriptor.zoneName)
    let enrolledEpoch = try sync.enrolledZoneEpoch(
      forAccountIdentifier: accountIdentifier)
    let databaseInstanceIdentifier = try requiredDatabaseIdentifier(sync)
    let hasCurrentBaseline = localTraversal.baselineWitness?.boundary == boundary
    // A crash can happen after the terminal baseline/enrollment transaction but
    // before the old cutoff's local cleanup. Repeat that idempotent cleanup on
    // every cycle with the exact completed baseline, before any outbound drain.
    if hasCurrentBaseline, let cutoff = descriptor.tombstoneCompactionCutoff {
      _ = try sync.compactCloudConfirmedTombstones(through: cutoff)
    }
    let transitionCompactionCutoff = enrolledEpoch.map { $0 < descriptor.epoch } == true
      ? descriptor.tombstoneCompactionCutoff : nil
    // Stable ready zones rotate proactively once ordinary CloudKit receipts
    // prove that a confirmed tombstone crossed the 365-day recovery horizon.
    // This uses only the durable maximum CKRecord.modificationDate, never the
    // device clock. A peer still adopting this generation must finish that
    // baseline first; otherwise every peer could race to rotate the generation
    // it has not yet enrolled.
    let eligibleCompactionCutoff = try sync.trustedTombstoneCompactionCutoff(
      forAccountIdentifier: accountIdentifier)
    if try !sync.isReseedRequired(),
      enrolledEpoch == descriptor.epoch, hasCurrentBaseline,
      let eligibleCompactionCutoff
    {
      let rebuilt = try await rebuildGeneration(
        sync: sync, accountIdentifier: accountIdentifier,
        databaseInstanceIdentifier: databaseInstanceIdentifier,
        startingState: .ready(
          descriptor: descriptor, retiredZoneNames: retiredZoneNames,
          modifiedAt: controlModifiedAt),
        allowFromDeleted: false,
        tombstoneCompactionCutoff: eligibleCompactionCutoff)
      return try await runReadyGenerationCycle(
        sync: sync, accountIdentifier: accountIdentifier, descriptor: rebuilt,
        performReseedRecovery: performReseedRecovery)
    }
    // Starting this generation's first traversal does not revoke the
    // publisher's proof. Writes created after the immutable capture are
    // intentionally still pending and must survive a crash during that
    // traversal instead of being mistaken for stale pre-generation state.
    let hasExactLocalPublicationProof = finalizedLocalPublication
      || (enrolledEpoch == descriptor.epoch && !hasCurrentBaseline)
    // A compaction generation is safe to union only when this physical
    // database already completed a traversal whose CloudKit-owned witness time
    // covers the published cutoff. Device clocks and sidecar timestamps are
    // never recovery authority. The publisher's exact immutable-capture
    // proof and an already-complete baseline of this generation are equivalent
    // stronger proofs.
    let overWindow: Bool
    if let cutoff = descriptor.tombstoneCompactionCutoff,
      !hasExactLocalPublicationProof, !hasCurrentBaseline
    {
      overWindow = !(try sync.trustedTerminalServerTimeCovers(
        cutoff: cutoff, forAccountIdentifier: accountIdentifier))
    } else {
      overWindow = false
    }
    // A draining trigger prepares reseed recovery once, before page 1. Follow-up
    // pages must continue from the saved token: re-reading the standing marker
    // and resetting the traversal here would restart the baseline on every page.
    let reseedRequired: Bool
    if performReseedRecovery {
      reseedRequired = try sync.isReseedRequired()
    } else {
      reseedRequired = false
    }

    // Publication and physical retirement are intentionally separate commits.
    // A crash, force-quit, or transient zone-delete failure after the ready CAS
    // must not strand the retired ledger forever; every ordinary ready cycle
    // retries cleanup before doing current-generation work. Individual cleanup
    // failures are logged and retained by the helper, so they never block the
    // active generation's pull/push path.
    try await cleanupRetiredGenerations(
      sync: sync, accountIdentifier: accountIdentifier,
      activeDescriptor: descriptor, boundaryGuard: guardClosure)

    _ = try await prepareReadyRetention(
      sync: sync, context: context, expectation: expectation,
      boundaryGuard: guardClosure)

    if try sync.authoritativeSnapshotSession() != nil || overWindow {
      if try sync.authoritativeSnapshotSession() == nil {
        await warnOverWindowSnapshotReEnrollment(sync: sync)
      }
      let session = try await prepareAuthoritativeSnapshot(
        sync: sync, boundary: boundary, context: context,
        expectation: expectation, boundaryGuard: guardClosure)
      do {
        let pull = try await pullOneAuthoritativeSnapshotPage(
          sync: sync, session: session, context: context,
          expectation: expectation, boundaryGuard: guardClosure)
        return CloudSyncCycleReport(
          pushedRecordCount: 0, failedPushCount: 0,
          fetchedRecordCount: pull.fetched,
          moreInboundComing: !pull.reachedTerminal, inbound: pull.report)
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
      } catch AuthoritativeSnapshotError.unrecognizedRecords {
        // Valid future records retain their raw envelope and finalize into the
        // durable HOLD lane. This branch is therefore structural corruption:
        // restart from nil so a transient/bad fetch cannot pin the session to a
        // permanently unusable inventory.
        _ = try sync.restartAuthoritativeSnapshot()
        return emptyReport()
      }
    }

    if reseedRequired {
      try await prepareInWindowBaselineRecovery(
        sync: sync, boundary: boundary, context: context,
        expectation: expectation, boundaryGuard: guardClosure,
        tombstoneCompactionCutoff: transitionCompactionCutoff)
    }

    let pull: CloudSyncGenerationPullResult
    do {
      pull = try await pullOneGenerationPage(
        sync: sync, context: context, expectation: expectation,
        boundaryGuard: guardClosure)
    } catch is CloudSyncInvalidChangeCursor {
      try resetGenerationTraversalAfterInvalidCursor(
        sync: sync, boundary: boundary, requireFullReseed: true)
      throw CloudSyncCursorRecoveryPrepared()
    } catch let error as CKError where error.code == .changeTokenExpired {
      try resetGenerationTraversalAfterInvalidCursor(
        sync: sync, boundary: boundary, requireFullReseed: true)
      throw CloudSyncCursorRecoveryPrepared()
    }
    guard pull.reachedTerminal else {
      return CloudSyncCycleReport(
        pushedRecordCount: 0, failedPushCount: 0,
        fetchedRecordCount: pull.fetched,
        moreInboundComing: pull.moreComing, inbound: pull.report)
    }

    // The pull page and its cursor are already committed atomically in SQLite.
    // Every later retention/outbound/audit operation must preserve that prefix
    // in a typed partial failure so app surfaces reload the canonical rows now.
    var committedReport = CloudSyncCycleReport(
      pushedRecordCount: 0, failedPushCount: 0,
      fetchedRecordCount: pull.fetched,
      moreInboundComing: pull.moreComing, inbound: pull.report)
    do {
      if let transitionCompactionCutoff {
        _ = try sync.compactCloudConfirmedTombstones(
          through: transitionCompactionCutoff)
      }

      // Pull/apply may advance a rolling retention cutoff or preserve a local
      // policy write that committed after candidate publication. Re-publish and
      // authorize that exact post-pull state.
      var outboundRetention = try await prepareReadyRetention(
        sync: sync, context: context, expectation: expectation,
        boundaryGuard: guardClosure)
      var outbound: CloudSyncOutboundReport?
      for attempt in 0..<CloudKitRecordPusher.maxZoneEpochCASAttempts {
        do {
          outbound = try await pushOutbound(
            sync: sync, context: context, expectation: expectation,
            authorization: outboundRetention.authorization,
            metadata: outboundRetention.metadata)
          break
        } catch let partial as CloudSyncPartialOutboundFailure {
          committedReport.pushedRecordCount += partial.partialReport.pushed
          committedReport.failedPushCount += partial.partialReport.failed
          committedReport.inbound.accumulate(partial.partialReport.inbound)
          throw partial.underlyingError
        } catch let guardError as CloudSyncAuditRetentionGuardError {
          switch guardError {
          case .missing, .stale:
            guard attempt + 1 < CloudKitRecordPusher.maxZoneEpochCASAttempts else {
              throw CloudSyncZoneEpochError.zoneEpochCASRetryLimitExceeded
            }
            outboundRetention = try await prepareReadyRetention(
              sync: sync, context: context, expectation: expectation,
              boundaryGuard: guardClosure)
          case .invalidAtomicResult, .transport:
            throw guardError
          }
        }
      }
      guard let outbound else {
        throw CloudSyncZoneEpochError.zoneEpochCASRetryLimitExceeded
      }
      committedReport.pushedRecordCount += outbound.pushed
      committedReport.failedPushCount += outbound.failed
      committedReport.inbound.accumulate(outbound.inbound)
      committedReport.moreOutboundComing = outbound.moreComing
      let moreAuditPurges = try await processCurrentZoneAuditPurges(
        sync: sync, context: context, expectation: expectation,
        boundaryGuard: guardClosure)
      committedReport.moreInboundComing = pull.moreComing
      committedReport.moreOutboundComing = outbound.moreComing || moreAuditPurges
      committedReport.nextDeferredRetryAt = try sync.nextDeferredCloudSyncRetryAt(
        forAccountIdentifier: context.accountIdentifier,
        zoneName: context.zoneName)
      return committedReport
    } catch let partial as CloudSyncPartialCycleFailure {
      var merged = committedReport
      merged.accumulate(partial.partialReport)
      throw CloudSyncPartialCycleFailure(
        partialReport: merged, underlyingError: partial.underlyingError)
    } catch {
      throw CloudSyncPartialCycleFailure(
        partialReport: committedReport, underlyingError: error)
    }
  }

  func pullOneGenerationPage(
    sync: any EnvelopeSyncServicing, context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: @escaping @Sendable () async -> Bool,
    requireFullReseedOnPersistentFailure: Bool = true
  ) async throws -> CloudSyncGenerationPullResult {
    let boundary = try traversalBoundary(context)
    var state = try sync.cloudTraversalState(
      accountIdentifier: context.accountIdentifier,
      zoneIdentifier: context.zoneName)
    let progress: CloudTraversalProgress
    if let existing = state.progress, existing.boundary == boundary {
      progress = existing
    } else {
      if let existing = state.progress {
        try sync.cancelCloudTraversal(
          boundary: existing.boundary,
          traversalIdentifier: existing.traversalIdentifier)
      }
      let baselineIsCurrent = state.baselineWitness?.boundary == boundary
      // The first incremental traversal starts at the terminal baseline token;
      // only later incrementals have a newer incremental cursor. Omitting this
      // fallback silently re-ran a nil-token baseline every cycle forever.
      let cursor: Data?
      if state.incrementalCursor?.boundary == boundary {
        cursor = state.incrementalCursor?.changeToken
      } else if baselineIsCurrent {
        cursor = state.baselineWitness?.finalChangeToken
      } else {
        cursor = nil
      }
      // A terminal traversal deliberately leaves its harmless remote witness in
      // place until the next traversal. Deleting it here makes cleanup retryable
      // before new work begins and removes every fallible operation after the
      // page's SQLite commit. At most one completed witness remains per DB.
      let completedTraversalIdentifier: String?
      if state.incrementalCursor?.boundary == boundary {
        completedTraversalIdentifier = state.incrementalCursor?.traversalIdentifier
      } else if baselineIsCurrent {
        completedTraversalIdentifier = state.baselineWitness?.traversalIdentifier
      } else {
        completedTraversalIdentifier = nil
      }
      if let completedTraversalIdentifier {
        try await pusher.deleteTraversalWitness(
          context: context, expectation: expectation,
          traversalIdentifier: completedTraversalIdentifier,
          boundaryGuard: boundaryGuard)
      }
      let traversalIdentifier = CloudSyncGenerationNaming.newGenerationID()
      let start: CloudTraversalStart
      if baselineIsCurrent, let cursor {
        start = try .incremental(from: cursor)
      } else {
        start = .baseline
      }
      // Persist the identifier first. If remote publication fails or the process
      // dies, the next trigger reuses this exact progress instead of leaking an
      // orphan witness with no local pointer.
      progress = try sync.beginCloudTraversal(
        boundary: boundary, traversalIdentifier: traversalIdentifier,
        start: start)
      state = try sync.cloudTraversalState(
        accountIdentifier: context.accountIdentifier,
        zoneIdentifier: context.zoneName)
    }

    if !progress.observedTraversalWitness {
      try await pusher.publishTraversalWitness(
        context: context, expectation: expectation,
        traversalIdentifier: progress.traversalIdentifier,
        boundaryGuard: boundaryGuard)
    }

    let token = progress.continuationToken ?? progress.startingChangeToken
    let cursor = token.map {
      CloudSyncChangeCursor(
        accountIdentifier: context.accountIdentifier,
        zoneName: context.zoneName, generationEpoch: context.epoch,
        generationID: context.generationID,
        readyWitness: context.checkpointWitness,
        serverChangeTokenData: $0)
    }
    let batch = try await fetcher.fetchChanges(
      after: cursor, context: context,
      traversalWitnessIdentifier: progress.traversalIdentifier,
      boundaryGuard: boundaryGuard)
    try batch.assertPreservesGenerationMarkers(context: context)
    guard !batch.discardedInvalidCheckpointToken else {
      throw CloudSyncInvalidChangeCursor()
    }
    if let failure = batch.perRecordFailure {
      if failure.kind == .persistent {
        let reachedThreshold = try sync.recordRemoteChangeFetchFailure(
          checkpointKey:
            "private|\(context.zoneName)|\(failure.checkpointFingerprint)|withheld",
          threshold: Self.perRecordFetchFailureReseedThreshold)
        if reachedThreshold {
          try sync.resetCloudTraversalAfterInvalidCursor(
            boundary: boundary, traversalIdentifier: progress.traversalIdentifier,
            requireFullReseed: requireFullReseedOnPersistentFailure)
        }
      }
      throw failure
    }
    // A successful page must carry the durable cursor that hands this traversal
    // to its next page or to the next incremental traversal. Without it, a
    // terminal incremental apply fails inside SQLite while retaining the same
    // progress row, so every trigger retries the unusable page forever.
    guard batch.serverChangeTokenData != nil
      || (!batch.moreComing && progress.mode == .baseline)
    else {
      throw CloudSyncInvalidChangeCursor()
    }

    var envelopes: [SyncEnvelope] = []
    var cloudReceipts: [InboundCloudRecordReceipt] = []
    var unknown: [RawEnvelopeFields] = []
    var corruptRecordNames: [String] = []
    var undecodable = 0
    for record in batch.records {
      switch CloudSyncEnvelopeRecord.decode(record) {
      case .decoded(let envelope):
        envelopes.append(envelope)
        if let modifiedAt = record.modificationDate {
          cloudReceipts.append(
            Self.inboundCloudReceipt(
              envelope: envelope, serverModifiedAt: modifiedAt))
        }
      case .unknownEntityType(let raw): unknown.append(raw)
      case .foreign: break
      case .corrupt:
        undecodable += 1
        corruptRecordNames.append(record.recordID.recordName)
      }
    }
    let observedTraversal = batch.observedTraversalWitnessIdentifiers.contains(
      progress.traversalIdentifier) ? progress.traversalIdentifier : nil
    let observedTraversalServerTime = batch.traversalWitnessServerModificationDates[
      progress.traversalIdentifier
    ].map(SyncTimestampFormat.formatSyncTimestamp)
    let observation = try CloudTraversalPageObservation(
      generationRootIdentifier: batch.observedGenerationRoot
        ? context.generationID : nil,
      readyWitness: batch.observedReadyWitness,
      traversalWitnessIdentifier: observedTraversal,
      traversalWitnessServerTime: observedTraversalServerTime)
    let page = try CloudTraversalPageCommit(
      pageIndex: progress.nextPageIndex,
      continuationToken: batch.serverChangeTokenData,
      moreComing: batch.moreComing, observation: observation)
    let report = try sync.applyInboundTraversalPage(
      envelopes, deferredUnknownTypeRecords: unknown,
      cloudReceipts: cloudReceipts, undecodable: undecodable, boundary: boundary,
      traversalIdentifier: progress.traversalIdentifier, page: page,
      inboundObservation: CloudInboundPageObservation(
        corruptRecordNames: corruptRecordNames,
        deletedRecordNames: batch.deletedRecordNames))
    return CloudSyncGenerationPullResult(
      fetched: batch.records.count, moreComing: batch.moreComing,
      report: report, reachedTerminal: !batch.moreComing)
  }

  func prepareReadyRetention(
    sync: any EnvelopeSyncServicing, context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: @escaping @Sendable () async -> Bool
  ) async throws -> (
    metadata: CloudSyncAuditRetentionMetadata,
    authorization: AuditRetentionOutboundAuthorization
  ) {
    _ = try sync.activateAuditRetentionAccount(
      accountIdentifier: context.accountIdentifier, zoneName: context.zoneName)
    guard let remote = try await pusher.readAuditRetentionMetadata(
      context: context, expectation: expectation,
      boundaryGuard: boundaryGuard)
    else { throw CloudSyncZoneEpochError.generationMarkerMismatch }
    guard CloudSyncAuditRetentionMetadataRecord.isValid(remote) else {
      throw CloudSyncZoneEpochError.generationMarkerMismatch
    }

    // First absorb the fleet authority. The policy adoption wrapper enforces
    // the resulting canonical local policy once, so a local newer preference or
    // a rolling cutoff becomes part of the proposal below rather than remaining
    // device-only forever.
    _ = try sync.joinAuditRetentionFrontier(
      remote.frontier, forAccountIdentifier: context.accountIdentifier)
    _ = try sync.adoptAuditRetentionPolicy(
      remote.policy, policyVersion: remote.policyVersion,
      forAccountIdentifier: context.accountIdentifier)

    for _ in 0..<CloudKitRecordPusher.maxZoneEpochCASAttempts {
      guard let local = try sync.auditRetentionState(
        forAccountIdentifier: context.accountIdentifier)
      else { throw AuditRetentionStateError.noActiveAccount }
      let proposed = try retentionMetadata(from: local)
      let merged = try await pusher.mergeAuditRetentionMetadata(
        proposed, context: context, expectation: expectation,
        boundaryGuard: boundaryGuard)
      guard CloudSyncAuditRetentionMetadataRecord.isValid(merged) else {
        throw CloudSyncZoneEpochError.generationMarkerMismatch
      }

      _ = try sync.joinAuditRetentionFrontier(
        merged.frontier, forAccountIdentifier: context.accountIdentifier)
      guard var absorbed = try sync.auditRetentionState(
        forAccountIdentifier: context.accountIdentifier)
      else { throw AuditRetentionStateError.noActiveAccount }
      if absorbed.policy != merged.policy
        || absorbed.policyVersion != merged.policyVersion
        || !absorbed.isPolicyReady
        || absorbed.policyAuthorizedEpoch != absorbed.frontierEpoch
      {
        absorbed = try sync.adoptAuditRetentionPolicy(
          merged.policy, policyVersion: merged.policyVersion,
          forAccountIdentifier: context.accountIdentifier)
      }

      // A local write may have advanced policy/frontier during the CloudKit
      // CAS, or applying a concurrently-newer policy may itself advance the
      // cutoff. Publish that monotonic state in another bounded iteration.
      guard try retentionMetadata(from: absorbed) == merged else { continue }
      do {
        _ = try sync.confirmAuditRetentionFrontier(
          merged.frontier, forAccountIdentifier: context.accountIdentifier)
        let authorization = try sync
          .authorizeAuditRetentionOutboundAfterExactRemoteConfirmation(
            verifiedRemoteFrontier: merged.frontier,
            verifiedRemotePolicy: merged.policy,
            verifiedRemotePolicyVersion: merged.policyVersion,
            forAccountIdentifier: context.accountIdentifier,
            zoneName: context.zoneName)
        guard authorization.frontier == merged.frontier else {
          throw AuditRetentionStateError.invalidOutboundAuthorization
        }
        return (merged, authorization)
      } catch AuditRetentionStateError.invalidOutboundAuthorization {
        // Exact state changed after the equality check; loop and publish it.
        continue
      }
    }
    throw CloudSyncZoneEpochError.zoneEpochCASRetryLimitExceeded
  }

  private func retentionMetadata(
    from state: AuditRetentionAccountState
  ) throws -> CloudSyncAuditRetentionMetadata {
    guard state.isPolicyReady,
      state.policyAuthorizedEpoch == state.frontierEpoch
    else { throw AuditRetentionStateError.policyNotReady(state.accountIdentifier) }
    let metadata = CloudSyncAuditRetentionMetadata(
      frontier: state.frontier, policy: state.policy,
      policyVersion: state.policyVersion,
      policyAuthorizedEpoch: state.policyAuthorizedEpoch)
    guard CloudSyncAuditRetentionMetadataRecord.isValid(metadata) else {
      throw CloudSyncZoneEpochError.generationMarkerMismatch
    }
    return metadata
  }

}
