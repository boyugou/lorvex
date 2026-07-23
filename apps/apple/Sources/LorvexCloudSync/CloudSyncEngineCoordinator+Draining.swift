import Foundation
import LorvexCore
import LorvexSync

/// A later page failed after one or more earlier pages committed locally. The
/// transport must still report failure/preserve push debt, while UI surfaces
/// need the committed prefix so they can adopt it immediately rather than stay
/// stale until a future successful trigger.
public struct CloudSyncPartialCycleFailure: Error, LocalizedError, @unchecked Sendable {
  public let partialReport: CloudSyncCycleReport
  public let underlyingError: any Error

  public init(partialReport: CloudSyncCycleReport, underlyingError: any Error) {
    self.partialReport = partialReport
    self.underlyingError = underlyingError
  }

  public var errorDescription: String? { underlyingError.localizedDescription }
}

/// The live CloudKit state could not be proven current enough to authorize a
/// local operation whose decision depends on seeing every existing remote row.
/// These are safety deferrals, not importer failures: callers should keep the
/// user's prepared operation intact and let them retry after Cloud Sync is
/// available again.
public enum CloudSyncTerminalInboundDrainError: Error, LocalizedError, Sendable, Equatable {
  case unsupportedBackend
  case accountUnavailable(CloudKitAccountAvailability)
  case syncPaused(CloudSyncPauseReason)
  case runtimeNotReady
  case terminalBoundaryNotReached(CloudSyncCycleReport)
  case inboundStateIncomplete(
    report: CloudSyncCycleReport,
    pendingRecordCount: Int,
    corruptRecordCount: Int)

  public var errorDescription: String? {
    switch self {
    case .unsupportedBackend:
      "The current data store does not support iCloud synchronization."
    case .accountUnavailable(let availability):
      availability.userFacingMessage
    case .syncPaused:
      "iCloud synchronization is paused and needs attention."
    case .runtimeNotReady:
      "Lorvex could not verify the current iCloud account and sync generation."
    case .terminalBoundaryNotReached:
      "Lorvex could not finish downloading the current iCloud changes."
    case .inboundStateIncomplete:
      "The current iCloud data contains records this version cannot safely evaluate."
    }
  }
}

/// A terminal inbound traversal was durable enough to authorize the guarded
/// operation, but unrelated post-inbound cycle work failed. The operation still
/// succeeds; hosts consume this warning to preserve ordinary CloudSync error and
/// retry-after observability without telling the user to repeat an import that
/// has already run.
public struct CloudSyncPostTerminalFailure: Sendable, Equatable {
  public let errorDescription: String
  public let serverRetryAfter: TimeInterval?

  public init(errorDescription: String, serverRetryAfter: TimeInterval?) {
    self.errorDescription = errorDescription
    self.serverRetryAfter = serverRetryAfter
  }
}

/// A value produced only after the coordinator drained and proved the exact
/// current CloudKit generation while holding its operation gate continuously.
public struct CloudSyncTerminalOperationResult<Value: Sendable>: Sendable {
  public let value: Value
  public let drainReport: CloudSyncCycleReport
  public let postTerminalSyncFailure: CloudSyncPostTerminalFailure?

  public init(
    value: Value,
    drainReport: CloudSyncCycleReport,
    postTerminalSyncFailure: CloudSyncPostTerminalFailure? = nil
  ) {
    self.value = value
    self.drainReport = drainReport
    self.postTerminalSyncFailure = postTerminalSyncFailure
  }
}

extension CloudSyncEngineCoordinator {
  /// Hard ceiling for the local fixed-point tail after CloudKit reaches a
  /// terminal page. Each pass drains up to the core inbox budget; the loop also
  /// stops immediately when no row was removed, so a missing dependency or
  /// future HOLD cannot spin.
  static let maxTerminalPendingInboxDrainIterations = 128

  /// Run cycles until the inbound backlog is drained.
  ///
  /// A single cycle pulls only one CloudKit page; a large remote backlog sets
  /// `moreInboundComing` on the report. This keeps running cycles while the
  /// last report asks for more, so one user-visible trigger drains the whole
  /// backlog instead of one page per trigger.
  public func runDrainingCycle(core: any LorvexCoreServicing) async throws -> CloudSyncCycleReport? {
    guard let sync = core as? any EnvelopeSyncServicing else { return nil }
    return try await withSerializedOperation {
      try await runDrainingCycleUnlocked(sync: sync)
    }
  }

  /// Drain the inbound backlog against an envelope-sync backend. The
  /// orchestration seam the drain tests drive directly with a fake
  /// `EnvelopeSyncServicing`; see `runDrainingCycle(core:)` for the contract.
  ///
  /// The `reseed_required` recovery arm runs on the FIRST iteration only: a
  /// backfill pass that skipped rows keeps the marker standing, and re-running
  /// the recovery each iteration would reset the traversal mid-drain and
  /// restart the pull at page 1 every time — the follow-up iterations must keep
  /// advancing from the saved token so the whole backlog still drains.
  ///
  /// The returned report is the AGGREGATE of every drained page, not just the
  /// last: each per-cycle report describes only its own CloudKit page, but the
  /// store's post-drain reload gates on `fetchedRecordCount` and drives its
  /// domain-selective reload off `inbound.appliedEntityTypes` (see
  /// ``InboundReloadScope``). Returning only the final page would strand every
  /// surface changed by an earlier page — a peer batch that reschedules 200 tasks
  /// on page 1 and completes one habit on page 2 would reload only habits. So the
  /// counts are summed and the applied-kind sets unioned across pages;
  /// the two continuation fields reflect the latest page: inbound continuation
  /// governs terminal traversal proof, while outbound continuation schedules a
  /// bounded follow-up without weakening that proof.
  public func runDrainingCycle(sync: any EnvelopeSyncServicing) async throws -> CloudSyncCycleReport? {
    try await withSerializedOperation {
      try await runDrainingCycleUnlocked(sync: sync)
    }
  }

  /// Drain every currently visible inbound page, prove that SQLite committed a
  /// terminal traversal for the exact still-ready account/generation, and run
  /// `operation` without releasing the coordinator gate between those steps.
  ///
  /// This is the linearization boundary for decisions such as native restore's
  /// "is this domain still empty?" check. Calling the public draining API from a
  /// `withQuiescedCloudSync` closure would recursively acquire the non-reentrant
  /// gate and deadlock; performing the two public calls sequentially would leave
  /// a race between them. Keep refresh/sync/account actions outside `operation`
  /// for the same reason.
  public func withTerminalInboundDrain<Value: Sendable>(
    core: any LorvexCoreServicing,
    operation: @escaping @Sendable () async throws -> Value
  ) async throws -> CloudSyncTerminalOperationResult<Value> {
    guard let sync = core as? any EnvelopeSyncServicing else {
      throw CloudSyncTerminalInboundDrainError.unsupportedBackend
    }
    return try await withSerializedOperation {
      let initialAvailability = try await accountChecker.checkAccountStatus()
      guard initialAvailability == .available else {
        throw CloudSyncTerminalInboundDrainError.accountUnavailable(initialAvailability)
      }
      var report: CloudSyncCycleReport
      var postTerminalSyncFailure: CloudSyncPostTerminalFailure?
      do {
        guard let completed = try await runDrainingCycleUnlocked(sync: sync) else {
          if let pauseReason = await currentPauseReason() {
            throw CloudSyncTerminalInboundDrainError.syncPaused(pauseReason)
          }
          throw CloudSyncTerminalInboundDrainError.runtimeNotReady
        }
        report = completed
      } catch let partial as CloudSyncPartialCycleFailure {
        // Retention/outbound/audit work happens only after a terminal inbound
        // page commits. It may fail independently (for example, a poisoned
        // outbox row) without invalidating that durable inbound proof. Continue
        // to the exact runtime proof below only for a terminal partial prefix;
        // a nonterminal prefix still propagates its original failure.
        guard !partial.partialReport.moreInboundComing else { throw partial }
        report = partial.partialReport
        postTerminalSyncFailure = CloudSyncPostTerminalFailure(
          errorDescription: partial.underlyingError.localizedDescription,
          serverRetryAfter: CloudSyncTransientClassifier.serverRetryAfter(
            partial.underlyingError))
      }
      guard !report.moreInboundComing else {
        throw CloudSyncTerminalInboundDrainError.terminalBoundaryNotReached(report)
      }
      guard let proofBoundary = try await currentTerminalInboundProofBoundary(sync: sync) else {
        let finalAvailability = try await accountChecker.checkAccountStatus()
        if finalAvailability != .available {
          throw CloudSyncTerminalInboundDrainError.accountUnavailable(finalAvailability)
        }
        if let pauseReason = await currentPauseReason() {
          throw CloudSyncTerminalInboundDrainError.syncPaused(pauseReason)
        }
        throw CloudSyncTerminalInboundDrainError.runtimeNotReady
      }
      let completeness = try drainPendingInboxToFixedPoint(
        sync: sync, boundary: proofBoundary, report: &report)
      // The fixed-point apply runs retention. It may discover that an expired
      // pending/quarantine row had to be shed and atomically raise the durable
      // reseed marker. Completeness can become 0/0 only because of that loss, so
      // re-check the marker after the drain before authorizing the operation.
      guard try !sync.isReseedRequired() else {
        throw CloudSyncTerminalInboundDrainError.runtimeNotReady
      }
      guard completeness.isComplete else {
        throw CloudSyncTerminalInboundDrainError.inboundStateIncomplete(
          report: report,
          pendingRecordCount: completeness.pendingRecordCount,
          corruptRecordCount: completeness.corruptRecordCount)
      }
      try Task.checkCancellation()
      let value = try await operation()
      return CloudSyncTerminalOperationResult(
        value: value,
        drainReport: report,
        postTerminalSyncFailure: postTerminalSyncFailure)
    }
  }

  private func runDrainingCycleUnlocked(
    sync: any EnvelopeSyncServicing
  ) async throws -> CloudSyncCycleReport? {
    guard var aggregate = try await runCycleUnlocked(
      sync: sync, performReseedRecovery: true)
    else {
      return nil
    }
    var iterations = 1
    while aggregate.moreInboundComing, iterations < Self.maxDrainIterations {
      let page: CloudSyncCycleReport
      do {
        guard
          let next = try await runCycleUnlocked(
            sync: sync, performReseedRecovery: false)
        else { break }
        page = next
      } catch {
        if let partial = error as? CloudSyncPartialCycleFailure {
          aggregate.accumulate(partial.partialReport)
          throw CloudSyncPartialCycleFailure(
            partialReport: aggregate,
            underlyingError: partial.underlyingError)
        }
        throw CloudSyncPartialCycleFailure(
          partialReport: aggregate, underlyingError: error)
      }
      aggregate.accumulate(page)
      iterations += 1
    }
    return aggregate
  }

  /// Re-prove runtime readiness after the final drain suspension. A non-nil
  /// report with `moreInboundComing == false` is not sufficient: deleted-zone
  /// and authoritative-recovery paths intentionally return an empty report.
  /// The durable traversal witness is the proof that a terminal page and all of
  /// its row effects committed atomically for this exact ready generation.
  private func currentTerminalInboundProofBoundary(
    sync: any EnvelopeSyncServicing
  ) async throws -> CloudTraversalBoundary? {
    guard try await accountChecker.checkAccountStatus() == .available,
      case .proceed = await passesAccountStartGate(sync: sync),
      let account = try await accountIdentityStore.loadLastAccountIdentifier(),
      await accountIdentifier.currentAccountIdentifier() == account,
      case .ready(let descriptor, _, _) = try await pusher.currentZoneGenerationState(),
      await accountIdentifier.currentAccountIdentifier() == account,
      try sync.authoritativeSnapshotSession() == nil,
      try !sync.isReseedRequired()
    else { return nil }

    let context = CloudSyncGenerationContext(
      accountIdentifier: account, descriptor: descriptor)
    let expectation = CloudSyncGenerationExpectation.ready(descriptor)
    let boundaryGuard = generationBoundaryGuard(
      accountIdentifier: account, expectation: expectation)
    guard try await pusher.validateGenerationRoot(
      context: context, expectation: expectation,
      boundaryGuard: boundaryGuard),
      await boundaryGuard()
    else { return nil }

    let boundary = try traversalBoundary(context)
    let state = try sync.cloudTraversalState(
      accountIdentifier: account, zoneIdentifier: descriptor.zoneName)
    let hasExactTerminalWitness = state.incrementalCursor?.boundary == boundary
      || state.baselineWitness?.boundary == boundary
    guard state.progress == nil, hasExactTerminalWitness,
      await accountStillMatchesStartGate(context: "the terminal inbound operation proof"),
      case .ready(let confirmedDescriptor, _, _) =
        try await pusher.currentZoneGenerationState(),
      confirmedDescriptor == descriptor,
      await accountStillMatchesStartGate(context: "the final terminal inbound operation proof")
    else { return nil }
    return boundary
  }

  /// Drain ordinary dependency deferrals beyond the per-transaction inbox
  /// budget before judging completeness. An unresolved future/poison/dependency
  /// row remains durable and therefore fails the terminal operation closed.
  private func drainPendingInboxToFixedPoint(
    sync: any EnvelopeSyncServicing,
    boundary: CloudTraversalBoundary,
    report: inout CloudSyncCycleReport
  ) throws -> CloudInboundCompletenessState {
    var state = try sync.cloudInboundCompletenessState(boundary: boundary)
    for _ in 0..<Self.maxTerminalPendingInboxDrainIterations {
      guard state.pendingRecordCount > 0 else { return state }
      let before = state.pendingRecordCount
      let replay = try sync.applyInbound([], undecodable: 0)
      report.inbound.accumulate(replay)
      state = try sync.cloudInboundCompletenessState(boundary: boundary)
      if state.pendingRecordCount >= before, replay.drainReplayed == 0 {
        return state
      }
    }
    return state
  }
}
