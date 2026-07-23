import GRDB
import LorvexDomain
import LorvexSync

extension SwiftLorvexCoreService {
  /// Re-attempt deferred remote envelopes after a local mutation may have
  /// supplied their missing dependency, and fulfill every convergence obligation
  /// before the transaction can commit. Keeping this at the top-level write
  /// funnel avoids recursive enqueue/drain calls that could consume a pending row
  /// without an HLC owner for its required repair.
  func reconcilePendingInboxAfterLocalWrite(
    _ db: Database, hlc: HlcSession, deviceId: String
  ) throws {
    let summary = try PendingInboxDrain.drainPendingInbox(
      db, registry: Self.inboundRegistry)

    try ListDeleteRehome.reenqueueRehomed(
      db, taskIds: summary.listDeleteRehomedTaskIds,
      mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
      deviceId: deviceId)

    for target in summary.absenceReemitTargets {
      let outcome = try ConvergenceEmitter.enqueueCurrentSnapshot(
        db, entityType: target.entityType, entityId: target.entityId,
        mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
        deviceId: deviceId)
      if outcome == .enqueued {
        try AbsencePreserveReemit.recordConvergenceReemitEnqueued(
          db, target: target)
      }
    }

    for obligation in summary.repairObligations {
      try ApplyRepair.fulfill(
        db, obligation: obligation,
        mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
        deviceId: deviceId)
    }

    try FutureRecordHold.fulfillLocalIntentReplays(
      db, replays: summary.futureLocalIntentReplays,
      registry: Self.inboundRegistry,
      mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
      deviceId: deviceId)
  }
}
