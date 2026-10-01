import Foundation
import LorvexDomain
import LorvexSync

/// Device-local checkpoints owned by the CKSyncEngine transport, stored in
/// `sync_checkpoints` beside the rest of the database so a restore or a
/// factory reset moves them together with the data they describe.
public enum CloudSyncEngineCheckpoint: String, Sendable, CaseIterable {
  /// The engine's `CKSyncEngine.State.Serialization`, JSON-encoded and then
  /// base64-encoded. Absent means the next engine starts from scratch and
  /// fetches the whole zone.
  case engineState = "cloudkit.engine_state"
  /// `"1"` once this device has saved to or fetched from the `Lorvex` zone.
  /// It separates the first upload, which must create the zone, from a zone
  /// that disappeared afterwards, which is a deletion and must not be
  /// silently recreated.
  case zoneEstablished = "cloudkit.zone_established"
  /// `"1"` once the push subscriptions and zones of the retired
  /// generation-based transport have been removed from the current account.
  case legacyCleanup = "cloudkit.legacy_cleanup"
  /// `"true"` while outbox rows are known to be lost: dropped at the outbox
  /// cap while sync could not drain it, or skipped by a backfill. Core sets
  /// it; a complete full-resync backfill clears it.
  case reseedRequired = "reseed_required"
  /// `"true"` once Core has dropped expired inbound rows that still exist in
  /// CloudKit. The transport discards ``engineState`` so the next engine
  /// fetches the whole zone, then deletes this checkpoint: it is one-shot.
  case refetchRequired = "refetch_required"
}

/// The local-store surface the CKSyncEngine transport depends on.
///
/// The transport never touches SQLite directly. Outbound it reads the outbox
/// and commits each sent batch's outcome through ``reconcileOutbound(_:)``;
/// inbound it hands decoded records to ``applyFetchedRecords(_:parking:undecodable:)``.
/// Every method is synchronous and runs its own transaction.
public protocol CloudSyncEngineStore: AnyObject, Sendable {
  /// CloudKit record names of every outbox row that still has to be sent:
  /// unsynced rows that are active or waiting to retry. Rows held behind a
  /// future record are excluded because only an inbound record can release
  /// them, and the device-local `ai_changelog` entity is never sent.
  func unsyncedOutboundRecordNames() throws -> Set<String>

  /// One bounded FIFO page of eligible outbox rows after `afterOutboxId`.
  /// Rows waiting to retry are included only once due. Advance with
  /// ``PendingOutboundPage/lastScannedOutboxId``, which stays set even when
  /// every scanned row was filtered out.
  func pendingOutboundPage(afterOutboxId: Int64?, now: String) throws -> PendingOutboundPage

  /// Apply fetched envelopes through the HLC merge and park schema-ahead raw
  /// records in one transaction. `undecodable` counts records the transport
  /// dropped as corrupt and is added to the returned report.
  func applyFetchedRecords(
    _ envelopes: [SyncEnvelope], parking raws: [RawEnvelopeFields], undecodable: Int
  ) throws -> InboundApplyReport

  /// Commit one sent batch's outcome atomically: server winners applied,
  /// collisions joined, failures recorded, and confirmed rows marked synced.
  func reconcileOutbound(
    _ request: OutboundReconciliationRequest
  ) throws -> OutboundReconciliationReport

  /// Enqueue the current state of every live entity, so a fresh zone or a
  /// newly adopted account receives this device's whole database.
  @discardableResult
  func enqueueFullResyncBackfill() throws -> FullResyncBackfillReport

  func cloudSyncEngineCheckpoint(_ key: CloudSyncEngineCheckpoint) throws -> String?

  /// Store `value`, or delete the checkpoint when `value` is nil.
  func setCloudSyncEngineCheckpoint(_ key: CloudSyncEngineCheckpoint, value: String?) throws
}
