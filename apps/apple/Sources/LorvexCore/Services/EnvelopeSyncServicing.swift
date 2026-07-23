import Foundation
import LorvexDomain
import LorvexSync

/// Envelope-level sync facade over the ported `LorvexSync` engine.
///
/// Sits beside ``LorvexCoreServicing`` (it is not part of that protocol) and
/// exposes the operations a sync transport needs without exposing GRDB or
/// engine internals:
///
/// - ``pendingOutbound()`` reads the `sync_outbox` (FIFO, capped) — the
///   transport encodes each envelope and pushes it.
/// - ``markOutboundSynced(outboxIds:)`` confirms a successful push.
/// - ``recordOutboundFailure(outboxId:error:kind:)`` records a failed push so
///   the row's retry state advances per the failure's classification.
/// - ``applyInbound(_:)`` feeds decoded inbound envelopes through
///   `Apply.applyEnvelope` (the sole conflict-resolution path) inside one
///   transaction, then runs the pending-inbox drain once.
/// - ``reconcileOutbound(_:)`` atomically consumes every local consequence of a
///   completed CloudKit drain after its final account/generation validation.
///
/// A transport reaches the facade by conditionally casting its
/// `any LorvexCoreServicing`; backends that do not support envelope sync (the
/// preview service) simply do not conform, and the transport silently no-ops.
/// How the explicit adoption boundary treats a same-account binding.
/// Account switching is detected by the binding CAS itself; the special
/// deleted-zone mode is accepted only from an exact remote `.deleted`
/// generation request. Ordinary retries preserve newly fetched debt/cursors.
public enum CloudTraversalAccountAdoptionMode: Sendable, Equatable {
  case accountSwitchOrRetry
  case sameAccountDeletedZoneReupload
}

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

  /// Bounded raw scan used by the fixed-point transport. Unlike the legacy
  /// array view, its cursor advances across rows filtered during decode/fencing.
  func pendingOutboundPage(
    afterOutboxId: Int64?, now: String
  ) throws -> PendingOutboundPage

  /// Earliest future retry deadline owned by the exact active CloudKit
  /// account/generation: parked outbox rows plus audit physical-delete work.
  /// Nil means no time-gated work is currently durable for that scope.
  func nextDeferredCloudSyncRetryAt(
    forAccountIdentifier accountIdentifier: String,
    zoneName: String
  ) throws -> Date?

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
  /// app foreground / launch trigger. Audit prunes enqueue account- and
  /// generation-scoped CloudKit physical-delete work while sync is inactive;
  /// it waits durably and clears exact zone copies after sync is enabled.
  /// Ordinary queued work past a generous cap is shed, but that privacy queue
  /// is independent and exempt.
  ///
  /// Call on every foreground/publish trigger, including while live sync is
  /// unavailable, paused, failed, or paced off. Pass `includeActiveOutboxCap`
  /// only for a non-live configured mode: the policy/age retention sweep is safe
  /// in every mode, but shedding active rows is not safe while a live full-resync
  /// backfill may be waiting for transport to resume. A no-op for backends
  /// without an outbox (the default).
  func runLocalRetentionMaintenance(includeActiveOutboxCap: Bool) throws

  /// Activate the iCloud account before any audit frontier/apply/outbound work.
  func activateAuditRetentionAccount(
    accountIdentifier: String, zoneName: String
  ) throws -> AuditRetentionAccountActivation

  func auditRetentionState(
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState?

  func auditRetentionActiveZoneName() throws -> String?

  /// Establish the neutral default retention contract only after transport has
  /// verified that this newly seen account has no predecessor generation.
  func initializeAuditRetentionForVerifiedEmptyAccount(
    accountIdentifier: String
  ) throws -> AuditRetentionAccountState

  /// Join a verified remote frontier before inbound apply when no outbound pass
  /// is being prepared.
  func joinAuditRetentionFrontier(
    _ frontier: AuditRetentionFrontierValue,
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState

  /// Adopt the account's authoritative policy snapshot after its frontier has
  /// been joined. A newly seen account remains outbound-blocked until this call.
  func adoptAuditRetentionPolicy(
    _ policy: ChangelogRetentionPolicy, policyVersion: String,
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState

  /// Verified pre-push boundary. Returns the opaque authorization every audit
  /// mark-before-cloud call must present in this transport cycle.
  func authorizeAuditRetentionOutbound(
    verifiedRemoteFrontier: AuditRetentionFrontierValue,
    forAccountIdentifier accountIdentifier: String, zoneName: String
  ) throws -> AuditRetentionOutboundAuthorization

  /// Authorize exactly the metadata already merged and confirmed remotely.
  /// This path must not advance a rolling cutoff after the CloudKit CAS.
  func authorizeAuditRetentionOutboundAfterExactRemoteConfirmation(
    verifiedRemoteFrontier: AuditRetentionFrontierValue,
    verifiedRemotePolicy: ChangelogRetentionPolicy,
    verifiedRemotePolicyVersion: String,
    forAccountIdentifier accountIdentifier: String, zoneName: String
  ) throws -> AuditRetentionOutboundAuthorization

  func authorizeAuditRetentionCandidateGeneration(
    forAccountIdentifier accountIdentifier: String, candidateZoneName: String
  ) throws -> AuditRetentionCandidateAuthorization

  func validateAuditRetentionCandidateGeneration(
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionAccountState

  func activateAuditRetentionCandidateGeneration(
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionAccountState

  func revokeAuditRetentionCandidateGeneration(
    authorization: AuditRetentionCandidateAuthorization
  ) throws

  func confirmAuditRetentionFrontier(
    _ frontier: AuditRetentionFrontierValue,
    forAccountIdentifier accountIdentifier: String
  ) throws -> AuditRetentionAccountState

  func markAuditCloudPresencePossible(
    outboxId: Int64, authorization: AuditRetentionOutboundAuthorization
  ) throws -> AuditRetentionCloudPresenceMarkResult

  func markAuditGenerationSnapshotCloudPresencePossible(
    envelope: SyncEnvelope, authorization: AuditRetentionOutboundAuthorization
  ) throws -> AuditRetentionCloudPresenceMarkResult

  func markAuditCandidateGenerationSnapshotCloudPresencePossible(
    envelope: SyncEnvelope,
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionCloudPresenceMarkResult

  func markAuditGenerationSnapshotBatchCloudPresencePossible(
    envelopes: [SyncEnvelope], authorization: AuditRetentionOutboundAuthorization
  ) throws -> [AuditRetentionCloudPresenceMarkResult]

  func markAuditCandidateGenerationSnapshotBatchCloudPresencePossible(
    envelopes: [SyncEnvelope], authorization: AuditRetentionCandidateAuthorization
  ) throws -> [AuditRetentionCloudPresenceMarkResult]

  /// Atomically materialize an immutable, bounded candidate generation. An
  /// exact existing lease resumes without enumerating mutable domain state.
  func captureGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionOutboundAuthorization
  ) throws -> GenerationSnapshotStaging

  func captureCandidateGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> GenerationSnapshotStaging

  /// Variant used by CloudKit generation construction. The cutoff is derived
  /// exclusively from the rebuilding control record's server modification time.
  func captureGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionOutboundAuthorization,
    tombstoneCompactionCutoff: String?
  ) throws -> GenerationSnapshotStaging

  func captureCandidateGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionCandidateAuthorization,
    tombstoneCompactionCutoff: String?
  ) throws -> GenerationSnapshotStaging

  /// Read an immutable count-and-byte-bounded page from durable staging.
  func stagedGenerationSnapshotPage(
    binding: GenerationSnapshotBinding, offset: Int, limit: Int,
    maximumEncodedBytes: Int
  ) throws -> GenerationSnapshotPage

  func generationSnapshotStaging(
    binding: GenerationSnapshotBinding
  ) throws -> GenerationSnapshotStaging?

  /// Read the singleton lease only for exact post-publication cleanup.
  func currentGenerationSnapshotStaging() throws -> GenerationSnapshotStaging?

  func advanceGenerationSnapshotUploadProgress(
    binding: GenerationSnapshotBinding, expectedNextOrdinal: Int,
    nextOrdinal: Int
  ) throws -> GenerationSnapshotStaging

  func advanceGenerationSnapshotUploadProgress(
    binding: GenerationSnapshotBinding, expectedNextOrdinal: Int,
    nextOrdinal: Int, cloudReceipts: [InboundCloudRecordReceipt]
  ) throws -> GenerationSnapshotStaging

  func recordGenerationSnapshotReadbackPage(
    binding: GenerationSnapshotBinding, expectedPageIndex: Int,
    witnesses: [GenerationSnapshotWitness], deletedRecordNames: [String],
    continuationToken: Data, observedTraversalWitness: Bool, terminal: Bool
  ) throws -> GenerationSnapshotStaging

  func resetGenerationSnapshotReadbackProgress(
    binding: GenerationSnapshotBinding
  ) throws -> GenerationSnapshotStaging

  func finalizePublishedGenerationSnapshot(
    binding: GenerationSnapshotBinding
  ) throws

  func discardGenerationSnapshot(binding: GenerationSnapshotBinding) throws

  /// Return due privacy-delete work for one exact account-zone generation.
  /// The store applies both scope predicates before its bounded `LIMIT`.
  func pendingAuditRetentionPurges(
    forAccountIdentifier accountIdentifier: String, zoneName: String, limit: Int
  ) throws -> [AuditRetentionPurgeItem]

  func acknowledgeAuditRetentionPurges(
    forAccountIdentifier accountIdentifier: String, zoneName: String,
    entityIds: [String]
  ) throws

  /// Clear exact-zone purge/presence evidence after CloudKit confirms that the
  /// whole retired zone no longer exists.
  func acknowledgeAuditRetentionZoneDeletion(
    forAccountIdentifier accountIdentifier: String, zoneName: String
  ) throws

  func recordAuditRetentionPurgeFailure(
    forAccountIdentifier accountIdentifier: String, zoneName: String,
    entityId: String, error: String
  ) throws

  /// Durably park records whose `entity_type` is a future/unknown kind this
  /// build cannot model, so the transport can advance its change token without
  /// losing them. Each raw envelope is stored in the pending inbox under HOLD
  /// semantics (no retry-cap pressure); a later build whose ``LorvexSync`` engine
  /// understands the type drains and applies them. A no-op for an empty input.
  func deferUnknownTypeRecords(_ raws: [RawEnvelopeFields]) throws

  /// Number of future entity/operation records whose only durable local copy is
  /// still parked in the pending inbox. A generation publisher must keep its
  /// predecessor generation alive while this is nonzero.
  func unresolvedFutureRecordCount() throws -> Int

  /// Total durable pending-inbox population, including current-schema
  /// dependency deferrals and forward-compatible HOLD rows.
  func unresolvedInboundRecordCount() throws -> Int

  /// Retry-exhausted inbound envelope identities retained on the poison
  /// blocklist after their pending-inbox rows were removed. They remain
  /// unmaterialized debt until a valid dominating replacement or authoritative
  /// snapshot resolves them.
  func quarantinedInboundRecordCount() throws -> Int

  /// Exact terminal-import completeness for the current CloudKit boundary:
  /// every pending inbox row, retry-exhausted quarantine, plus durable
  /// transport-corruption fences whose cursor has already advanced.
  func cloudInboundCompletenessState(
    boundary: CloudTraversalBoundary
  ) throws -> CloudInboundCompletenessState

  /// Re-enqueue every live (non-tombstoned) entity — plus a `delete` envelope
  /// for every surviving tombstone — into the outbox at its EXISTING stored
  /// version, through the coalesced outbox path, so a freshly (re-)created
  /// CloudKit zone — or the empty zone of a newly signed-in iCloud account — is
  /// repopulated with the data (and death knowledge) this device holds. Without
  /// it, the outbox's 7-day GC means every entity last written more than a week
  /// ago is never re-pushed to the new zone and multi-device users lose data.
  ///
  /// Idempotent and version-preserving: re-enqueuing at the stored version is a
  /// no-op for the version stamp and is discarded by the coalesce LWW gate on a
  /// second pass, so no stored version is advanced and no duplicate divergent row
  /// is created. Returns a ``LorvexSync/FullResyncBackfillReport`` with the
  /// emitted and skipped row counts; a pass with `skipped > 0` retained the
  /// `reseed_required` marker (the reseed is incomplete) and a later pass retries
  /// the skipped rows. Backed by
  /// ``LorvexSync/Outbox/enqueueAllLiveForFullResync(_:)``.
  @discardableResult
  func enqueueFullResyncBackfill() throws -> FullResyncBackfillReport
  func enqueueFullResyncBackfill(
    tombstoneCompactionCutoff: String?
  ) throws -> FullResyncBackfillReport

  /// Reclaim confirmed old tombstones only after the exact ready-generation
  /// baseline reaches its terminal page.
  func compactCloudConfirmedTombstones(through cutoff: String) throws -> UInt64
  func trustedTombstoneCompactionCutoff(
    forAccountIdentifier accountIdentifier: String
  ) throws -> String?
  func trustedTerminalServerTimeCovers(
    cutoff: String, forAccountIdentifier accountIdentifier: String
  ) throws -> Bool

  /// The stable identity of the physical database this backend is bound to, or
  /// `nil` for a backend with no per-database identity (a non-envelope or purely
  /// in-memory backend).
  ///
  /// Cloud traversal state, including its change token, is stored in this same
  /// SQLite database and bound to this identity. A replacement database starts
  /// without the old cursor; a restored/cloned database rotates the identity
  /// before it can reuse the source install's generation lease or traversal
  /// proof. Stable across opens of the same database.
  func databaseInstanceIdentifier() throws -> String?

  /// Durable in-database account lineage and traversal scope. Unlike the
  /// reconstructible external CKRecord system-fields cache, this value and the
  /// atomically applied traversal cursor survive with a database restore.
  func cloudTraversalAccountBinding() throws -> CloudTraversalAccountBinding?

  /// Untrusted stored binding used only to bind an explicit adoption request.
  /// It may carry a pre-restore database instance ID; mutation must go through
  /// ``prepareCloudTraversalForAccountAdoption(newAccountIdentifier:mode:)``.
  func cloudTraversalAccountBindingForAdoption() throws -> CloudTraversalAccountBinding?

  /// First-account claim. Repeating the same account is idempotent; a different
  /// account fails until the explicit CAS adoption operation is used.
  @discardableResult
  func claimCloudTraversalAccount(
    accountIdentifier: String
  ) throws -> CloudTraversalAccountBinding

  /// Highest remote generation authority this database lineage has ever seen
  /// for the active account. `nil` means a first bootstrap has not yet crossed
  /// the remote authority boundary.
  func observedCloudGenerationAuthorityFloor(
    forAccountIdentifier accountIdentifier: String
  ) throws -> Int?

  /// Persist a verified remote/claimed generation before consuming it. The
  /// value is monotonic per account and rejects rollback.
  @discardableResult
  func recordObservedCloudGenerationAuthority(
    forAccountIdentifier accountIdentifier: String, generation: Int
  ) throws -> Int

  /// Crash-safe SQLite side of an explicit account switch. Every unfinished
  /// traversal and terminal witness is discarded in the same transaction as
  /// the binding CAS; an A -> B -> A return must traverse again because local
  /// contents may have changed while B was active.
  @discardableResult
  func adoptCloudTraversalAccount(
    expectedCurrentAccountIdentifier: String, newAccountIdentifier: String
  ) throws -> CloudTraversalAccountBinding

  /// The single explicit-adoption write boundary. It repairs a restored or
  /// cloned database's rotated physical identity, if needed, and then adopts
  /// `newAccountIdentifier` in the same SQLite transaction. The caller must
  /// already hold user consent bound to that exact account and mode.
  @discardableResult
  func prepareCloudTraversalForAccountAdoption(
    newAccountIdentifier: String,
    mode: CloudTraversalAccountAdoptionMode
  ) throws -> CloudTraversalAccountBinding

  /// Explicit restore/clone recovery after the physical database identifier was
  /// rotated. Instance-local traversal/cursor proof is destroyed atomically;
  /// account-scoped generation authority/descriptor anti-rollback history is
  /// retained and rebound to the new physical lineage.
  @discardableResult
  func rebindCloudTraversalAfterDatabaseInstanceRotation(
    expectedAccountIdentifier: String
  ) throws -> CloudTraversalAccountBinding

  /// Read durable progress and the last terminal witness for one account/zone.
  func cloudTraversalState(
    accountIdentifier: String, zoneIdentifier: String
  ) throws -> CloudTraversalState

  /// Start a generation-fixed traversal before issuing its first CloudKit fetch.
  @discardableResult
  func beginCloudTraversal(
    boundary: CloudTraversalBoundary, traversalIdentifier: String,
    start: CloudTraversalStart
  ) throws -> CloudTraversalProgress

  /// Apply an ordinary fetched page, park its validated future/raw records, and
  /// persist corrupt/deleted CloudKit record-name observations atomically with
  /// the page cursor. Duplicate-page preflight runs before either typed apply or
  /// raw parking. A terminal page also enrolls the exact account generation in
  /// that transaction. This is the sole protocol requirement so a backend can
  /// never acknowledge undecodable transport records without their durable
  /// record-name fences.
  func applyInboundTraversalPage(
    _ envelopes: [SyncEnvelope], deferredUnknownTypeRecords: [RawEnvelopeFields],
    cloudReceipts: [InboundCloudRecordReceipt], undecodable: Int,
    boundary: CloudTraversalBoundary, traversalIdentifier: String,
    page: CloudTraversalPageCommit,
    inboundObservation: CloudInboundPageObservation
  ) throws -> InboundApplyReport

  /// Stage an authoritative nonterminal page and advance its continuation in
  /// one SQLite transaction. Terminal pages use the finalizer below.
  func stageAuthoritativeSnapshotContinuationPage(
    records: [AuthoritativeSnapshotRemoteRecord], deletedRecordNames: [String],
    sessionToken: String, boundary: CloudTraversalBoundary,
    traversalIdentifier: String, page: CloudTraversalPageCommit
  ) throws

  /// Stage the terminal authoritative page, reconcile the complete snapshot,
  /// write its terminal witness, and enroll its generation in one transaction.
  func finalizeAuthoritativeSnapshotTerminalPage(
    records: [AuthoritativeSnapshotRemoteRecord], deletedRecordNames: [String],
    sessionToken: String, boundary: CloudTraversalBoundary,
    traversalIdentifier: String, page: CloudTraversalPageCommit
  ) throws -> AuthoritativeSnapshotReport

  /// Cancel only the matching unfinished traversal. Completed proof is retained.
  func cancelCloudTraversal(
    boundary: CloudTraversalBoundary, traversalIdentifier: String
  ) throws

  /// Atomically discard the exact unfinished traversal whose continuation was
  /// rejected and restart it as a nil-token baseline with the same witness id.
  /// `requireFullReseed` also persists the recovery marker in that transaction,
  /// so a crash cannot leave a half-reset baseline eligible to resume from its
  /// rejected cursor.
  func resetCloudTraversalAfterInvalidCursor(
    boundary: CloudTraversalBoundary, traversalIdentifier: String,
    requireFullReseed: Bool
  ) throws

  /// Record that CloudKit withheld a change token because at least one record in
  /// the fetched page failed to materialize. Repeated failures at the same
  /// checkpoint eventually reaches `threshold`. This method only records and
  /// counts; the caller performs its operation-specific recovery atomically
  /// (ready-zone reseed, predecessor reset, or authoritative restart).
  @discardableResult
  func recordRemoteChangeFetchFailure(checkpointKey: String, threshold: Int) throws -> Bool

  /// Whether the durable `reseed_required` marker is set — the retention sweep
  /// (an expired pending-inbox orphan was horizon-GC'd) or the per-record fetch
  /// failure escalation recorded that this database lost records it can only
  /// recover through a full reseed. The transport polls it at cycle start and,
  /// when set, performs the recovery: traversal reset, full-resync backfill
  /// (which clears the marker on a complete pass), and a nil-token re-pull.
  func isReseedRequired() throws -> Bool

  /// The monotonic zone epoch this device last enrolled at for the named iCloud
  /// account, or `nil` if it has never enrolled in that account.
  /// The transport compares it against the zone's live epoch to detect a zone
  /// rebuild that happened while this device was away (S-5 over-window
  /// detection).
  func enrolledZoneEpoch(forAccountIdentifier accountIdentifier: String) throws -> Int?

  /// Current durable over-window authoritative-snapshot session, if any.
  /// While present the transport must suppress every ordinary outbound push.
  func authoritativeSnapshotSession() throws -> AuthoritativeSnapshotSession?

  /// Atomically persist the authoritative-adoption intent and fence the exact
  /// pre-session outbound queue before the transport clears its old CloudKit
  /// change token. The fence must not be repeated after this call: later active
  /// rows are user/MCP edits made while adoption is in flight.
  @discardableResult
  func beginAuthoritativeSnapshot(boundary: CloudTraversalBoundary) throws
    -> AuthoritativeSnapshotSession

  /// Discard staged pages and return the active session to `preparing` after a
  /// zone/token invalidation.
  @discardableResult
  func restartAuthoritativeSnapshot() throws -> AuthoritativeSnapshotSession

  /// Mark that old-token clearing and traversal-witness publication completed.
  /// The initial queue fence already committed with session creation. The next
  /// fetch must start from nil; staging its first page transitions to pulling.
  func markAuthoritativeSnapshotReady(sessionToken: String) throws

  /// Stage one fetched page before its CloudKit token is persisted.
  func stageAuthoritativeSnapshotPage(
    records: [AuthoritativeSnapshotRemoteRecord], deletedRecordNames: [String],
    sessionToken: String
  ) throws

  /// Atomically reconcile a completely drained staged snapshot and enroll the
  /// account at the observed zone epoch when one exists.
  func finalizeAuthoritativeSnapshot(
    sessionToken: String, accountIdentifier: String, zoneName: String,
    enrolledZoneEpoch: Int?
  ) throws -> AuthoritativeSnapshotReport

  /// Abandon an obsolete session at an explicit account/consent boundary.
  func cancelAuthoritativeSnapshot() throws
}
