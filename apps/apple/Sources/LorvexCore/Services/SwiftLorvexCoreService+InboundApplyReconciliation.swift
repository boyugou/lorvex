import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Post-apply reconciliation and error-classification helpers driven by
/// `SwiftLorvexCoreService.applyInbound(_:undecodable:)`: list-delete rehome
/// re-propagation, absence-preserve convergence re-emit, inbound
/// payload-evolution/absence-preserve convergence re-emits, batch-abort
/// classification, and dependency-cycle conflict logging.
extension SwiftLorvexCoreService {
  struct PendingApplyRepair {
    var obligation: ApplyRepairObligation
    var kind: EntityKind
  }

  /// Fold every collision for one mutation identity before minting a successor.
  /// A page may contain three or more cloned contenders at the same HLC; if each
  /// pair were repaired sequentially, the first successor would make later old-
  /// HLC contenders look stale and could discard the true deterministic winner.
  /// Joining obligations first preserves associativity and authors one successor
  /// for the complete contender set.
  static func coalesceApplyRepair(
    _ incoming: ApplyRepairObligation, kind: EntityKind,
    into pending: inout [PendingApplyRepair]
  ) throws {
    switch incoming {
    case .reassertRequiredInbox(let incomingFloor):
      if let index = pending.firstIndex(where: {
        if case .reassertRequiredInbox = $0.obligation { return true }
        return false
      }), case .reassertRequiredInbox(let existingFloor) = pending[index].obligation {
        pending[index].obligation = .reassertRequiredInbox(
          remoteDeleteVersion: max(existingFloor, incomingFloor))
      } else {
        pending.append(PendingApplyRepair(obligation: incoming, kind: kind))
      }

    case .reassertRequiredTimezone(
      let incomingValue, let incomingUpdatedAt, let incomingFloor):
      if let index = pending.firstIndex(where: {
        if case .reassertRequiredTimezone = $0.obligation { return true }
        return false
      }), case .reassertRequiredTimezone(
        let existingValue, let existingUpdatedAt, let existingFloor) =
        pending[index].obligation
      {
        let incomingWins: Bool
        if incomingFloor != existingFloor {
          incomingWins = incomingFloor > existingFloor
        } else {
          // Two malformed/legacy peers may reuse one HLC for different Delete
          // snapshots. Missing-row recovery must not depend on CloudKit delivery
          // order, so join equal-floor fallbacks by their canonical bytes and
          // use updated_at only as the stable secondary key.
          let incomingCanonical = try SyncCanonicalize.canonicalizeJSON(incomingValue)
          let existingCanonical = try SyncCanonicalize.canonicalizeJSON(existingValue)
          incomingWins =
            incomingCanonical == existingCanonical
            ? incomingUpdatedAt > existingUpdatedAt
            : incomingCanonical > existingCanonical
        }
        pending[index].obligation = .reassertRequiredTimezone(
          fallbackValue: incomingWins ? incomingValue : existingValue,
          fallbackUpdatedAt: incomingWins ? incomingUpdatedAt : existingUpdatedAt,
          remoteDeleteVersion: max(existingFloor, incomingFloor))
      } else {
        pending.append(PendingApplyRepair(obligation: incoming, kind: kind))
      }

    case .reassertCalendarSeriesCutover(let entityId, let incomingFloor):
      if let index = pending.firstIndex(where: {
        guard case .reassertCalendarSeriesCutover(let existingId, _) = $0.obligation
        else { return false }
        return existingId == entityId
      }), case .reassertCalendarSeriesCutover(_, let existingFloor) =
        pending[index].obligation
      {
        pending[index].obligation = .reassertCalendarSeriesCutover(
          entityId: entityId,
          remoteDeleteVersion: max(existingFloor, incomingFloor))
      } else {
        pending.append(PendingApplyRepair(obligation: incoming, kind: kind))
      }

    case .propagateCalendarCleanup(let incomingTargets, let incomingFloor):
      if let index = pending.firstIndex(where: {
        if case .propagateCalendarCleanup = $0.obligation { return true }
        return false
      }), case .propagateCalendarCleanup(let existingTargets, let existingFloor) =
        pending[index].obligation
      {
        pending[index].obligation = .propagateCalendarCleanup(
          targets: coalescedCalendarCleanupTargets(
            existingTargets + incomingTargets),
          additionalFloor: max(existingFloor, incomingFloor))
      } else {
        pending.append(
          PendingApplyRepair(
            obligation: .propagateCalendarCleanup(
              targets: coalescedCalendarCleanupTargets(incomingTargets),
              additionalFloor: incomingFloor),
            kind: kind))
      }

    case .propagateTaskRollover(let incomingTargets, let incomingFloor):
      if let index = pending.firstIndex(where: {
        if case .propagateTaskRollover = $0.obligation { return true }
        return false
      }),
        case .propagateTaskRollover(let existingTargets, let existingFloor) =
          pending[index].obligation
      {
        pending[index].obligation = .propagateTaskRollover(
          targets: TaskGraphRepairTarget.coalesced(existingTargets + incomingTargets),
          additionalFloor: max(existingFloor, incomingFloor))
      } else {
        pending.append(
          PendingApplyRepair(
            obligation: .propagateTaskRollover(
              targets: TaskGraphRepairTarget.coalesced(incomingTargets),
              additionalFloor: incomingFloor),
            kind: kind))
      }

    case .resolveEqualVersionCollision(let incomingContender, let incomingFloor):
      let index = pending.firstIndex { candidate in
        guard case .resolveEqualVersionCollision(let existing, _) = candidate.obligation
        else { return false }
        guard existing.entityType == incomingContender.entityType,
          existing.entityId == incomingContender.entityId
        else { return false }
        return existing.entityType == .aiChangelog
          || existing.version == incomingContender.version
      }
      guard let index,
        case .resolveEqualVersionCollision(let existing, let existingFloor) =
          pending[index].obligation
      else {
        pending.append(PendingApplyRepair(obligation: incoming, kind: kind))
        return
      }
      let joined =
        existing.entityType == .aiChangelog
        ? try SyncMutationSemantics.deterministicWinnerIgnoringVersion(
          existing, incomingContender)
        : try SyncMutationSemantics.deterministicWinner(
          existing, incomingContender)
      var floor = max(existing.version, incomingContender.version)
      if let existingFloor { floor = max(floor, existingFloor) }
      if let incomingFloor { floor = max(floor, incomingFloor) }
      pending[index].obligation = .resolveEqualVersionCollision(
        contender: joined, additionalFloor: floor)
    }
  }

  private static func coalescedCalendarCleanupTargets(
    _ targets: [CalendarCleanupRepairTarget]
  ) -> [CalendarCleanupRepairTarget] {
    var byIdentity: [String: CalendarCleanupRepairTarget] = [:]
    for target in targets {
      let key = "\(target.entityType.asString)\u{0}\(target.entityId)"
      if byIdentity[key]?.operation == .delete { continue }
      byIdentity[key] = target
    }
    return byIdentity.values.sorted {
      ($0.entityType.asString, $0.entityId, $0.operation.asString)
        < ($1.entityType.asString, $1.entityId, $1.operation.asString)
    }
  }

  /// Re-propagate a list-delete's trigger re-home of tasks to inbox.
  ///
  /// The apply layer has no HLC clock/device identity, so the re-enqueue is
  /// minted here. Any detection/read/enqueue failure aborts the inbound page so
  /// its CloudKit token cannot advance without the required convergence write.
  static func propagateListDeleteRehome(
    _ db: Database, taskIds: [String], hlc: HlcSession, deviceId: String
  ) throws {
    if taskIds.isEmpty { return }
    try ListDeleteRehome.reenqueueRehomed(
      db, taskIds: taskIds,
      mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
      deviceId: deviceId)
  }

  /// Re-emit a merged snapshot when a just-applied upsert produced a row that
  /// diverges from its envelope — through rolling-schema field preservation, an
  /// absence-preserved child collection, or a per-device list_id fallback — so
  /// peers that only saw the original envelope converge.
  static func reemitIfMergedRowDiverged(
    _ db: Database, envelope: SyncEnvelope, hlc: HlcSession, deviceId: String
  ) throws {
    let target = try AbsencePreserveReemit.convergenceReemitTarget(
      db, envelope: envelope)
    guard let target else { return }
    try propagateAbsencePreserveReemit(
      db, target: target, hlc: hlc, deviceId: deviceId)
  }

  /// Mint a fresh dominating HLC and enqueue an Upsert of the entity's current
  /// (merged) snapshot — the snapshot embeds the diverged state (preserved
  /// children / resolved list), so peers that only saw the original envelope
  /// re-materialize it. The target's own stored version is the HLC floor; only a
  /// concurrently removed target is benign. Any other failure rolls back the
  /// page so the convergence obligation cannot be lost.
  static func propagateAbsencePreserveReemit(
    _ db: Database, target: AbsenceReemitTarget, hlc: HlcSession, deviceId: String
  ) throws {
    let outcome = try ConvergenceEmitter.enqueueCurrentSnapshot(
      db, entityType: target.entityType, entityId: target.entityId,
      mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
      deviceId: deviceId)
    if outcome == .enqueued {
      try AbsencePreserveReemit.recordConvergenceReemitEnqueued(db, target: target)
    }
  }

  static func shouldAbortInboundBatch(for error: ApplyError) -> Bool {
    switch error {
    case .db, .store, .dbBusyOrLocked, .transactionRequired:
      // Genuinely transient / IO `.db`, store, and lock-contention failures are
      // recoverable: abort the batch so the whole page is refetched and retried.
      return true
    case .dbConstraint, .invalidPayload, .invalidOperation, .unknownEntityType, .invalidVersion,
      .entityRedirectCycle, .entityRedirectChainTooDeep, .redirectPayloadTooLarge,
      .dependencyCycleRejected, .deferForwardCompat:
      // `.dbConstraint` is a DETERMINISTIC SQLite constraint trip (CHECK / NOT
      // NULL / FK / UNIQUE) — re-running the same envelope re-fails identically,
      // so dropping (and logging) the one poison envelope degrades gracefully
      // instead of re-aborting the same fetch page forever and wedging all
      // inbound sync. The trust-boundary validators pre-empt the known cases as
      // `.invalidPayload`; this is the defense-in-depth net for the unforeseen.
      // `.deferForwardCompat` is the forward-compat retention sentinel. In
      // practice `Apply.applyEnvelope` catches it and returns `.deferred`, so it
      // never reaches here; classify it non-fatal defensively so a stray escape
      // still drops through to the deferred/drop path rather than wedging sync.
      return false
    }
  }

  static func logDependencyCycleRejectionIfNeeded(
    _ db: Database, envelope: SyncEnvelope, error: ApplyError, syncedAt: String
  ) {
    guard case .dependencyCycleRejected(let taskId, let dependsOn) = error else { return }
    try? ConflictLog.logConflict(
      db,
      ConflictLog.Entry(
        entityType: EdgeName.taskDependency,
        entityId: "\(taskId):\(dependsOn)",
        winnerVersion: "",
        loserVersion: envelope.version.description,
        loserDeviceId: envelope.version.deviceSuffix,
        loserPayload: nil,
        resolvedAt: syncedAt,
        resolutionType: ResolutionName.cycleBreak))
  }
}
