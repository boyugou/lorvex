import Foundation
import LorvexDomain
import LorvexSync

/// Envelope-level sync facade over the `LorvexSync` engine.
///
/// Sits beside ``LorvexCoreServicing`` (it is not part of that protocol) and
/// exposes the outbox and inbound-apply operations without exposing GRDB or
/// engine internals. The CloudKit transport itself talks to Core through
/// ``CloudSyncEngineStore``; this facade serves the app stores (local retention
/// maintenance), the debug seeding tools, and tests that drive sync by hand.
///
/// A caller reaches the facade by conditionally casting its
/// `any LorvexCoreServicing`; backends that do not support envelope sync (the
/// preview service) simply do not conform, and the caller silently no-ops.
public protocol EnvelopeSyncServicing: AnyObject, Sendable {
  /// Pending outbound envelopes ready to emit, FIFO, capped by the engine's
  /// per-pass fetch limit. Empty when the outbox is empty or nothing is yet due.
  func pendingOutbound() throws -> [PendingOutboundEnvelope]

  /// The same capped FIFO read, restricted to rows whose AUTOINCREMENT id is
  /// strictly newer than `afterOutboxId`. A transport uses this as its
  /// per-drain cursor: failures already attempted in the current drain remain
  /// behind it, while collision successors and concurrent coalesced writes are
  /// assigned newer ids and can be sent by the next page.
  func pendingOutbound(afterOutboxId: Int64?) throws -> [PendingOutboundEnvelope]

  /// One bounded raw scan of the outbox. Unlike the array views above, its
  /// cursor advances across rows filtered during decode or fencing.
  func pendingOutboundPage(
    afterOutboxId: Int64?, now: String
  ) throws -> PendingOutboundPage

  /// Mark the given outbox rows as successfully pushed.
  func markOutboundSynced(outboxIds: [Int64]) throws

  /// Record a failed push for one outbox row.
  ///
  /// `kind` is the transport's classification of the failure (see
  /// ``OutboundFailureKind``): ``OutboundFailureKind/transient`` leaves the
  /// retry budget untouched, ``OutboundFailureKind/wholesale`` advances it
  /// without same-error escalation, and ``OutboundFailureKind/perRecord``
  /// advances it with escalation toward delayed retry wait.
  func recordOutboundFailure(outboxId: Int64, error: String, kind: OutboundFailureKind) throws

  /// Apply a batch of inbound envelopes through the engine in one transaction,
  /// then drain the pending inbox. Returns per-envelope outcome counts.
  /// `undecodable` is supplied by the transport for envelopes it could not
  /// decode and is threaded straight into the returned report.
  func applyInbound(_ envelopes: [SyncEnvelope], undecodable: Int) throws -> InboundApplyReport

  /// Atomically consume one completed outbound transport attempt.
  ///
  /// Server-authoritative conflict winners, forward-compatible raw records,
  /// retry bookkeeping, and successful confirmations either all commit or all
  /// roll back. The transport must call this only after one final account and
  /// generation boundary check; if that check fails it calls nothing, leaving
  /// every row pending and unfailed for an idempotent retry.
  func reconcileOutbound(
    _ request: OutboundReconciliationRequest
  ) throws -> OutboundReconciliationReport

  /// Run local retention GC independent of an inbound apply, optionally bounding
  /// the never-pushed `sync_outbox` backlog.
  ///
  /// The retention caps (changelog safeguard, `error_logs` age + row cap,
  /// tombstone / conflict / pending-inbox horizon GC, outbox synced-row GC)
  /// normally ride the post-apply sweep inside
  /// ``applyInbound(_:undecodable:)``. On a signed-out / sync-off install that
  /// path never runs, so nothing enforces those caps and the append-only tables
  /// plus the outbox grow without bound. This entry runs the same sweep from an
  /// app foreground / launch trigger. Ordinary queued work past a generous cap
  /// is shed.
  ///
  /// Call on every foreground/publish trigger, including while live sync is
  /// unavailable, paused, failed, or paced off. Pass `includeActiveOutboxCap`
  /// only for a non-live configured mode: the policy/age retention sweep is safe
  /// in every mode, but shedding active rows is not safe while a live full-resync
  /// backfill may be waiting for transport to resume. A no-op for backends
  /// without an outbox (the default).
  func runLocalRetentionMaintenance(includeActiveOutboxCap: Bool) throws

  /// Durably park records whose `entity_type` is a future/unknown kind this
  /// build cannot model, so the transport can advance its change token without
  /// losing them. Each raw envelope is stored in the pending inbox under HOLD
  /// semantics (no retry-cap pressure); a later build whose ``LorvexSync`` engine
  /// understands the type drains and applies them. A no-op for an empty input.
  func deferUnknownTypeRecords(_ raws: [RawEnvelopeFields]) throws

  /// Whether the durable `reseed_required` marker is set: the retention sweep
  /// horizon-GC'd an expired pending-inbox orphan, so this database lost
  /// records it can only recover through a full reseed. The transport re-runs
  /// the full-resync backfill while it is set; a complete pass clears it.
  func isReseedRequired() throws -> Bool
}
