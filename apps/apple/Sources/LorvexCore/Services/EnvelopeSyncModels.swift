import Foundation
import LorvexDomain
import LorvexSync

/// Data-transfer and durable-state types used by ``EnvelopeSyncServicing``.
///
/// The canonical wire type is ``LorvexSync/SyncEnvelope`` — its own `Codable`
/// is the lossless contract a transport maps to and from its carrier. These
/// models keep transport and checkpoint concerns out of the facade declaration.

/// One pending outbound envelope paired with its `sync_outbox` row id so the
/// transport can confirm or fail the exact row after a push attempt.
public struct PendingOutboundEnvelope: Sendable, Equatable {
  public var outboxId: Int64
  public var envelope: SyncEnvelope

  public init(outboxId: Int64, envelope: SyncEnvelope) {
    self.outboxId = outboxId
    self.envelope = envelope
  }
}

/// One bounded scan of the durable outbox. `envelopes` excludes rows parked or
/// fenced while decoding; the raw high-water remains present so a transport can
/// continue past an all-filtered page instead of mistaking it for queue EOF.
public struct PendingOutboundPage: Sendable, Equatable {
  public var envelopes: [PendingOutboundEnvelope]
  public var lastScannedOutboxId: Int64?

  public init(envelopes: [PendingOutboundEnvelope], lastScannedOutboxId: Int64?) {
    self.envelopes = envelopes
    self.lastScannedOutboxId = lastScannedOutboxId
  }
}

/// CloudKit server evidence attached to one decoded inbound record. Every
/// timestamp originates from `CKRecord.modificationDate`; delete records also
/// carry the exact tombstone identity/version eligible for confirmation.
public struct InboundCloudRecordReceipt: Sendable, Equatable {
  public var serverModifiedAt: String
  public var tombstoneConfirmation: Tombstone.CloudConfirmation?

  public init(
    serverModifiedAt: String,
    tombstoneConfirmation: Tombstone.CloudConfirmation? = nil
  ) {
    self.serverModifiedAt = serverModifiedAt
    self.tombstoneConfirmation = tombstoneConfirmation
  }
}

/// CloudKit server evidence for an exact outbox capability. Core re-reads the
/// outbox id and matches the delete identity/version before confirming a
/// tombstone, so a late callback cannot bless a coalesced successor.
public struct OutboundCloudRecordReceipt: Sendable, Equatable {
  public var outboxId: Int64
  public var serverModifiedAt: String
  public var tombstoneConfirmation: Tombstone.CloudConfirmation?

  public init(
    outboxId: Int64, serverModifiedAt: String,
    tombstoneConfirmation: Tombstone.CloudConfirmation? = nil
  ) {
    self.outboxId = outboxId
    self.serverModifiedAt = serverModifiedAt
    self.tombstoneConfirmation = tombstoneConfirmation
  }
}

/// Counts produced by applying a batch of inbound envelopes through the engine.
/// Conflict resolution (LWW / redirect / tombstone) lives in the engine; these
/// counts only summarize per-envelope ``LorvexSync/ApplyResult`` outcomes plus
/// the pending-inbox drain so the UI can surface a sync-health report.
public struct InboundApplyReport: Sendable, Equatable {
  public var applied: Int
  public var skipped: Int
  public var deferred: Int
  public var remapped: Int
  /// Entries replayed out of the pending inbox during the post-batch drain.
  public var drainReplayed: Int
  /// Envelopes the transport could not decode into a valid ``SyncEnvelope`` and
  /// dropped before reaching the engine.
  public var undecodable: Int
  /// Well-formed records carrying a future/unknown `entity_type` that this build
  /// cannot model. Durably parked (not dropped) in the same transaction as the
  /// owning traversal page or outbound reconciliation, so a later build that
  /// understands the type recovers them — distinct from ``undecodable``, which
  /// is genuine corruption.
  public var deferredUnknownType: Int
  /// The distinct entity kinds whose local rows this apply actually changed —
  /// the union of direct `.applied` / `.remapped` envelopes and pending-inbox
  /// replays. Skipped and deferred envelopes contribute nothing.
  public var appliedEntityTypes: Set<EntityKind>
  /// Internal transport capability receipts produced only by outbound
  /// reconciliation. Ordinary inbound/traversal reports leave this empty.
  public var reconciledCollisionOutboxIds: Set<Int64>

  public init(
    applied: Int = 0, skipped: Int = 0, deferred: Int = 0, remapped: Int = 0,
    drainReplayed: Int = 0, undecodable: Int = 0, deferredUnknownType: Int = 0,
    appliedEntityTypes: Set<EntityKind> = [],
    reconciledCollisionOutboxIds: Set<Int64> = []
  ) {
    self.applied = applied
    self.skipped = skipped
    self.deferred = deferred
    self.remapped = remapped
    self.drainReplayed = drainReplayed
    self.undecodable = undecodable
    self.deferredUnknownType = deferredUnknownType
    self.appliedEntityTypes = appliedEntityTypes
    self.reconciledCollisionOutboxIds = reconciledCollisionOutboxIds
  }
}

/// How a failed push should advance an outbox row's retry state.
public enum OutboundFailureKind: Sendable, Equatable {
  /// A momentary transport/account outage that is not evidence a row is bad.
  case transient
  /// A non-transient rejection of a whole chunk, not an individual record.
  case wholesale
  /// A non-transient rejection CloudKit reported for this specific record.
  case perRecord
}

/// One transport-classified failure to commit for an exact outbox row.
///
/// The transport collects these while CloudKit requests are in flight, but does
/// not mutate SQLite until its account and generation boundary has been checked
/// one final time. ``OutboundReconciliationRequest`` then commits every failure
/// alongside conflict winners, forward-compatible records, and confirmations in
/// one transaction.
public struct OutboundFailureRecord: Sendable, Equatable {
  public var outboxId: Int64
  public var error: String
  public var kind: OutboundFailureKind

  public init(outboxId: Int64, error: String, kind: OutboundFailureKind) {
    self.outboxId = outboxId
    self.error = error
    self.kind = kind
  }
}

/// A CloudKit slot that cannot be acknowledged as the pushed outbox mutation.
/// The old outbox id is part of the capability: reconciliation re-reads that
/// exact row and ignores a stale callback after a newer local coalesce replaced
/// it with a different id.
public enum OutboundCollisionKind: Sendable, Equatable {
  /// Server and client reused one canonical HLC for different semantic
  /// mutations. Core performs the deterministic contender join.
  case equalVersion(serverEnvelope: SyncEnvelope)
  /// Current-schema contenders for a non-whole-row entity require their typed
  /// semantic join followed by one strict successor above both transport HLCs.
  case semanticMerge(kind: SemanticPushConflictKind, serverEnvelope: SyncEnvelope)
  /// A current-schema logical Delete targeted the permanent redirect ledger.
  /// Reassert the local alias above this remote floor instead of acknowledging
  /// a value no conforming writer is allowed to author.
  case entityRedirectDelete(serverEnvelope: SyncEnvelope)
  /// A valid competing value for an append-only identity (currently the audit
  /// stream). Its materialized row has no version column, so the exact pending
  /// outbox entry supplies local ordering evidence for transactional repair.
  case immutableIdentity(serverEnvelope: SyncEnvelope)
  /// The opaque record slot belongs to this exact entity but its server
  /// `version` is absent or noncanonical. No remote contender can safely enter
  /// ordering, so core re-authors the exact local intent at a fresh successor.
  case corruptServerSlot(serverVersionFloor: Hlc?)
}

public struct OutboundCollisionRecord: Sendable, Equatable {
  public var outboxId: Int64
  public var kind: OutboundCollisionKind

  public init(outboxId: Int64, kind: OutboundCollisionKind) {
    self.outboxId = outboxId
    self.kind = kind
  }
}

/// The complete local outcome of one outbound CloudKit drain.
///
/// Cloud transport is necessarily asynchronous, but consuming its results must
/// be atomic locally. In particular, a server-authoritative conflict winner must
/// never commit without the matching outbox confirmation, and a future record
/// must never be parked while its failure bookkeeping rolls back (or vice
/// versa). The production facade applies all four collections in one SQLite
/// transaction after the transport's final account/generation validation.
public struct OutboundReconciliationRequest: Sendable, Equatable {
  public var accountIdentifier: String?
  public var serverWinnerEnvelopes: [SyncEnvelope]
  public var deferredUnknownTypeRecords: [RawEnvelopeFields]
  public var collisions: [OutboundCollisionRecord]
  public var failures: [OutboundFailureRecord]
  public var confirmedOutboxIds: [Int64]
  public var cloudReceipts: [OutboundCloudRecordReceipt]
  public var serverWinnerCloudReceipts: [InboundCloudRecordReceipt]

  public init(
    accountIdentifier: String? = nil,
    serverWinnerEnvelopes: [SyncEnvelope] = [],
    deferredUnknownTypeRecords: [RawEnvelopeFields] = [],
    collisions: [OutboundCollisionRecord] = [],
    failures: [OutboundFailureRecord] = [],
    confirmedOutboxIds: [Int64] = [],
    cloudReceipts: [OutboundCloudRecordReceipt] = [],
    serverWinnerCloudReceipts: [InboundCloudRecordReceipt] = []
  ) {
    self.accountIdentifier = accountIdentifier
    self.serverWinnerEnvelopes = serverWinnerEnvelopes
    self.deferredUnknownTypeRecords = deferredUnknownTypeRecords
    self.collisions = collisions
    self.failures = failures
    self.confirmedOutboxIds = confirmedOutboxIds
    self.cloudReceipts = cloudReceipts
    self.serverWinnerCloudReceipts = serverWinnerCloudReceipts
  }
}

/// Result of the transactional outbound-result commit.
///
/// `reconciledCollisionOutboxIds` is a capability receipt, not a diagnostic:
/// it contains only collision ids the transaction actually consumed (including
/// an exact semantic confirmation). A callback for an id that disappeared or
/// was replaced while CloudKit was in flight is deliberately absent, so the
/// transport must not cache that callback's server change tag.
public struct OutboundReconciliationReport: Sendable, Equatable {
  public var inbound: InboundApplyReport
  public var reconciledCollisionOutboxIds: Set<Int64>

  public init(
    inbound: InboundApplyReport = InboundApplyReport(),
    reconciledCollisionOutboxIds: Set<Int64> = []
  ) {
    self.inbound = inbound
    self.reconciledCollisionOutboxIds = reconciledCollisionOutboxIds
  }
}

/// Corruption in local-only zone-epoch checkpoint state. Callers fail closed.
public enum ZoneEpochCheckpointStateError: Error, Sendable, Equatable {
  case invalidEnrollment
  case invalidEpoch
}
