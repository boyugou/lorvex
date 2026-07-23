import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Write-side orchestration for `SwiftLorvexCoreService` — the reusable surface
/// adapter every mutation funnels through.
///
/// The pure-Swift core's workflow ops (`TaskCreate`, `TaskUpdate`,
/// `LifecycleTransitions`, …) are deliberately transaction- / audit- /
/// idempotency-agnostic: they take an injected `HlcSession` + `now` + device id
/// and mutate rows, but do NOT open transactions, write `ai_changelog`, or bump
/// `local_change_seq`. Those side effects are the calling surface's
/// responsibility. This adapter is shared by the Apple app, App Intents,
/// widgets, notifications, mobile/watch surfaces, and later write slices
/// (Calendar, Habit, Focus, …).
///
/// Responsibilities:
///   - **Device identity / HLC suffix.** Resolves the stable device id from
///     `sync_checkpoints` (`LorvexRuntime.DeviceIdentity.getOrCreateDeviceId`)
///     once, then derives the 16-hex HLC device suffix for this service's
///     `HlcSurface`.
///   - **Normal + detached HLC lanes.** Ordinary writes use a bounded,
///     device/surface-scoped normal high-water. An explicit edit that must beat
///     a future row retries on a separately persisted detached lane, leaving
///     unrelated ordinary writes near wall time. One transaction-scoped
///     `HlcSession` is handed to each top-level mutation attempt.
///   - **Transaction wrapping.** `withWrite` opens a single
///     `BEGIN IMMEDIATE` transaction, runs the body, then bumps
///     `local_change_seq` inside the same transaction.
///   - **Changelog.** `recordChangelog` writes one `ai_changelog` row (every
///     task mutation is AI-changelog by design — Core Design Rule 2). It runs
///     inside the same transaction as the mutation.
///   - **Error mapping.** `mapWriteError` narrows the core's thrown
///     `ValidationError` / `StoreError` to the app's `LorvexCoreError`
///     (`emptyTitle`, `taskNotFound`).
///
/// Every mutation — including `TaskUpdate.updateTask` and `TaskBatchUpdate` —
/// runs through `withWrite`, so the row mutation, the `ai_changelog` row, and
/// the `local_change_seq` bump all commit in one `BEGIN IMMEDIATE` transaction.
extension SwiftLorvexCoreService {

  // MARK: - Device identity + clock access

  /// The cached device id + HLC clock, resolved once per storage epoch.
  ///
  /// Both depend on the device id, which lives in the store, so resolution is
  /// deferred to first write and memoized behind ``writeStateLock``. A storage
  /// cutover (factory reset) reopens the store under a new epoch, so the pair
  /// is re-resolved from the fresh database rather than reusing an identity
  /// read from the deleted one.
  func writeState() throws -> (deviceId: String, clock: HlcClock) {
    writeStateLock.lock()
    defer { writeStateLock.unlock() }
    // Observe any pending storage cutover BEFORE consulting the epoch-keyed
    // cache. `store()` bumps `storageEpoch` when it reopens a database a
    // cross-process factory reset replaced; without running it first, a cache
    // resolved against the deleted database would still match the (not-yet-
    // bumped) epoch and the first post-reset write would stamp the fresh store
    // with the old device id/HLC and never populate `sync_checkpoints.device_id`.
    // Lock order holds: `writeStateLock` → `openLock`; `store()` takes only
    // `openLock`, never `writeStateLock`.
    _ = try store()
    if let cached = cachedWriteState, cached.epoch == storageEpochSnapshot() {
      return (cached.deviceId, cached.clock)
    }
    // Device-id resolution may INSERT a fresh id (and, for a restored/cloned
    // managed DB, rotate it), so it runs on the writer. `store()` above already
    // populated `openedManagedDatabasePath` for this open, so reconciliation can
    // read the install marker beside the managed file. The write itself may
    // reopen the store after a cutover, so the epoch the cache is keyed to is
    // captured AFTER it.
    let (deviceId, _) = try resolveInstallIdentity(
      managedPath: openedManagedDatabasePathSnapshot())
    let epoch = storageEpochSnapshot()
    let clock = try HlcClock(deviceId: deviceId, surface: hlcSurface)
    cachedWriteState = (epoch, deviceId, clock)
    return (deviceId, clock)
  }

  // MARK: - Transaction funnels

  /// Run `body` inside one `BEGIN IMMEDIATE` transaction with a fresh
  /// `HlcSession`, then bump `local_change_seq` in the same transaction.
  ///
  /// `body` receives the mid-transaction `Database`, the per-mutation
  /// `HlcSession`, and the resolved device id. This is the funnel for every
  /// core op that takes a mid-transaction `Database`.
  func withWrite<T>(
    _ body: (Database, HlcSession, String) throws -> T
  ) throws -> T {
    // Re-resolve identity AND the store handle on every attempt so a
    // cross-process factory reset landing between the two — detected inside the
    // transaction by the storage-cutover guard — is retried against the fresh
    // database rather than stamped with the erased one's identity.
    try withStorageCutoverRetry {
      let (deviceId, clock) = try writeState()
      Self.afterWriteStateBarrierForTesting?()
      do {
        return try withStoreCutoverLease { store in
          try runWriteAttempt(
            store: store, clock: clock, deviceId: deviceId, dominanceFloor: nil, body)
        }
      } catch let cutover as StorageCutoverDuringWrite {
        // Feed the detected cutover back to `withStorageCutoverRetry` to
        // re-resolve and retry, rather than through `mapWriteError` (which would
        // pass it through unchanged — but the routing is made explicit here).
        throw cutover
      } catch {
        throw mapWriteError(error)
      }
    }
  }

  /// Run a `withWrite` transaction, replaying on the detached HLC lane when a
  /// local mutation loses its own LWW gate against a future row.
  ///
  /// A peer can stamp a row with a FUTURE HLC (its clock ahead — dead RTC, manual
  /// clock). LWW correctly applies it, so the local row keeps the peer's future
  /// `version`. The S-1 bound deliberately keeps this device's clock from being
  /// dragged forward by that passive observation, so a fresh local mint sits
  /// BELOW the row `version`: every LWW-gated local write of that row
  /// (`writeStatusAndMetadata`, `LwwOps`, and the outbox `VersionStamp`) then
  /// loses — `StoreError.staleVersion` / `EnqueueError.versionSuperseded` — and
  /// the whole mutation rolls back. Left unhandled the row is un-editable until
  /// wall-clock passes the stamp (hours/days, or forever for a crafted
  /// near-`Hlc.maxPhysicalMs` stamp), and its local delete reverts on push (the
  /// delete envelope loses LWW and the server re-upserts the row).
  ///
  /// A user's explicit local mutation must always be able to supersede the row it
  /// edits. On such a loss this reads the highest HLC represented anywhere in
  /// the local sync state and replays the whole body with the detached lane past
  /// that ceiling. This makes a multi-row mutation with heterogeneous future
  /// versions succeed in one normal replay instead of discovering one floor per
  /// attempt. If another process lands a still-higher floor between attempts,
  /// the loop advances again only when the floor strictly increases. Every
  /// failed attempt is fully rolled back; the normal lane remains near wall time.
  private func runWriteAttempt<T>(
    store: LorvexStore,
    clock: HlcClock,
    deviceId: String,
    dominanceFloor: Hlc?,
    _ body: (Database, HlcSession, String) throws -> T
  ) throws -> T {
    var retryFloor = dominanceFloor
    while true {
      do {
        let attemptFloor = retryFloor
        let result = try StoreTransactions.withImmediateTransaction(store.writer) { db in
          // First statement in the transaction: abort before any HLC is minted if a
          // cross-process factory reset redirected this write onto a fresh database.
          try self.assertCommittingDatabaseIdentity(db, expected: deviceId)
          // A Watch command is fenced and deduplicated before the clock or any
          // domain row is touched. A non-apply gate escapes this transaction and
          // is converted to an identity-bound ACK by the Watch service boundary.
          try self.preflightCurrentWatchCommand(db)
          // Claim a keyed MCP mutation under this same BEGIN IMMEDIATE before
          // minting a clock or touching domain state. This is the cross-process
          // correctness boundary; the MCP host's actor claim is only an
          // in-process latency optimization.
          try self.preflightCurrentMCPIdempotency(db)
          Self.afterIdentityAssertBarrierForTesting?()
          let transactionClock = try clock.makeTransactionHandle(db)
          if let attemptFloor {
            transactionClock.enterDetached(dominating: attemptFloor)
          }
          // Bind the transaction handle so `writeChangelogRow` uses this exact
          // lane and never re-enters `writeState()` from the GRDB writer queue.
          return try Self.$currentTransactionClock.withValue(transactionClock) {
            try SyncHlcObserver.withTransactionObserver({ value in
              transactionClock.reserveAfterDeterministicMerge(value)
            }) {
              let session = HlcSession(handle: transactionClock)
              let result = try body(db, session, deviceId)
              try reconcilePendingInboxAfterLocalWrite(
                db, hlc: session, deviceId: deviceId)
              // Same BEGIN IMMEDIATE as the domain effect: a crash can expose
              // neither both missing nor an effect without its applied receipt.
              try recordCurrentWatchCommandApplied(db)
              try LocalChangeSeq.bump(db)
              try transactionClock.persistHighWaters(db)
              return result
            }
          }
        }
        // Signal whichever peers this process opted into after commit: the MCP
        // host uses Darwin for the running app; the app uses a coalesced local
        // delivery so independent window stores converge.
        DatabaseChangeSignal.broadcastIfEnabled()
        return result
      } catch {
        guard let failedFloor = try futureRowVersionForLwwLoss(error) else { throw error }
        // The first LWW loss is evidence that this explicit mutation needs the
        // exceptional lane. Scan the complete local HLC ceiling so a batch does
        // not require one rollback per differently future-stamped row.
        let localCeiling = try store.writer.read { db in
          try HlcClock.maxAnyLocalHlc(db)
        }
        let nextFloor = localCeiling.map { max($0, failedFloor) } ?? failedFloor
        guard Hlc.hasOperationalWireSuccessor(after: nextFloor) else {
          throw HlcHighWaterError.unrecoverableFloor(value: nextFloor.description)
        }
        if let retryFloor, nextFloor <= retryFloor {
          // A detached replay that still loses without discovering a strictly
          // higher floor is not recoverable by spinning: surface the real error.
          throw error
        }
        retryFloor = nextFloor
      }
    }
  }

  /// The persisted `version` (as an `Hlc`) of the row a local mutation just lost
  /// an LWW gate against, when it is a retryable future-stamped-row case;
  /// otherwise `nil` so the caller surfaces the original error unchanged.
  ///
  /// Typed store/enqueue supersession errors already carry the existing version.
  /// `StoreError.staleVersion` carries only `(entity, id)`, so the row is
  /// re-read: an absent row (the same gate fires for a missing row), a
  /// tainted/unparseable stored version, or a composite/edge kind with no simple
  /// `(table, pk)` all return `nil` — none is a loss a clock advance can
  /// legitimately win.
  private func futureRowVersionForLwwLoss(_ error: Error) throws -> Hlc? {
    let entity: String
    let id: String
    switch error {
    case StoreError.versionSuperseded(_, _, _, let existingVersion):
      return try? Hlc.parseCanonical(existingVersion)
    case StoreError.staleVersion(let e, let i):
      (entity, id) = (e, i)
    case EnqueueError.versionSuperseded(_, _, _, let existingVersion):
      return try? Hlc.parseCanonical(existingVersion)
    default:
      return nil
    }
    guard let kind = EntityKind.parse(entity), let (table, pk) = kind.tablePk else {
      return nil
    }
    ValidationSQL.assertSafeSQLIdentifier(table)
    ValidationSQL.assertSafeSQLIdentifier(pk)
    let raw: String? = try read { db in
      try String.fetchOne(
        db, sql: "SELECT version FROM \(table) WHERE \(pk) = ?", arguments: [id])
    }
    guard let raw, let hlc = try? Hlc.parseCanonical(raw) else { return nil }
    return hlc
  }

  /// Run local maintenance that must be atomic but must not advertise a user
  /// data mutation. Used for MCP idempotency response-cache upkeep after the
  /// mutation transaction has already committed.
  func withLocalMaintenanceWrite<T>(
    _ body: (Database) throws -> T
  ) throws -> T {
    do {
      return try withStoreCutoverLease { store in
        try StoreTransactions.withImmediateTransaction(store.writer, body)
      }
    } catch {
      throw mapWriteError(error)
    }
  }

  /// Guarded local-only transaction for Watch protocol maintenance and terminal
  /// receipts that accompany a deterministic rejection before a domain write.
  /// Applied commands, including true domain no-ops, record their receipt through
  /// the ordinary `withWrite` transaction instead.
  func withWatchCommandMaintenanceWrite<T>(
    _ body: (Database) throws -> T
  ) throws -> T {
    try withStorageCutoverRetry {
      let (deviceId, _) = try writeState()
      Self.afterWriteStateBarrierForTesting?()
      do {
        return try withStoreCutoverLease { store in
          try StoreTransactions.withImmediateTransaction(store.writer) { db in
            try self.assertCommittingDatabaseIdentity(db, expected: deviceId)
            return try body(db)
          }
        }
      } catch let cutover as StorageCutoverDuringWrite {
        throw cutover
      } catch {
        throw mapWriteError(error)
      }
    }
  }

  func preflightCurrentMCPIdempotency(_ db: Database) throws {
    guard let idempotency = Self.currentMCPIdempotency else { return }
    let claimPayload = McpIdempotencyDurablePayload.transactionClaim(
      token: idempotency.claimToken)
    switch try McpIdempotency.claimMutation(
      db,
      key: idempotency.key,
      toolName: idempotency.toolName,
      requestChecksum: idempotency.checksum,
      claimPayload: claimPayload)
    {
    case .acquired, .owned:
      return
    case .replay(let responsePayload):
      let gate = McpIdempotencyTransactionError.replay(responsePayload: responsePayload)
      idempotency.attemptState.record(gate)
      throw gate
    case .checksumMismatch(let storedChecksum, let suppliedChecksum):
      let gate = McpIdempotencyTransactionError.checksumMismatch(
        storedChecksum: storedChecksum, suppliedChecksum: suppliedChecksum)
      idempotency.attemptState.record(gate)
      throw gate
    }
  }

  // MARK: - Changelog

  /// Raised when ``writeChangelogRow`` runs with no ambient
  /// ``SwiftLorvexCoreService/currentTransactionClock`` bound — i.e. a changelog
  /// write reached the funnel outside a `runWriteAttempt` transaction. A
  /// programming error (every changelog write must run inside the write funnel),
  /// surfaced fail-closed rather than silently re-resolving the clock through
  /// ``store()`` from inside the transaction (which could re-enter the writer).
  enum ChangelogWriteFunnelError: Error, CustomStringConvertible {
    case transactionClockUnbound
    var description: String {
      switch self {
      case .transactionClockUnbound:
        return "writeChangelogRow ran with no bound currentTransactionClock: a "
          + "changelog write reached the funnel outside a runWriteAttempt transaction."
      }
    }
  }

  /// A pending `ai_changelog` row described by a write method, materialized into
  /// the store-layer `ChangelogWrite.ChangelogRow` by ``writeChangelogRow``.
  struct ChangelogEntry {
    var operation: String
    var entityType: String
    var entityId: String?
    var entityIds: [String]
    var summary: String
    /// Explicit `ai_changelog.initiated_by` provenance for this row, or `nil` to
    /// resolve it at write time via ``resolveInitiator(_:)`` — an ambient
    /// ``SwiftLorvexCoreService/currentInitiator`` binding
    /// (``ChangelogInitiator/assistant`` while the MCP host drives the call,
    /// ``ChangelogInitiator/importAttribution`` around a `LorvexDataImporter`
    /// run) when one is installed, else the service's
    /// ``SwiftLorvexCoreService/writeInitiatorDefault``
    /// (``ChangelogInitiator/user`` for the app's human surfaces). The
    /// id-preserving importers themselves set no explicit initiator, so a
    /// replayed backup's audit rows — whose before/after JSON is caller-supplied
    /// and syncs fleet-wide — inherit the `import` binding and stay
    /// provenance-distinct from live actions.
    var initiatedBy: String?
    var before: JSONValue?
    var after: JSONValue?

    init(
      operation: String,
      entityType: String = EntityName.task,
      entityId: String? = nil,
      entityIds: [String] = [],
      summary: String,
      initiatedBy: String? = nil,
      before: JSONValue? = nil,
      after: JSONValue? = nil
    ) {
      self.operation = operation
      self.entityType = entityType
      self.entityId = entityId
      self.entityIds = entityIds
      self.summary = summary
      self.initiatedBy = initiatedBy
      self.before = before
      self.after = after
    }
  }

  /// `ai_changelog.initiated_by` attribution values written by this service's
  /// local mutation paths. `initiated_by` is a free TEXT column, so these are
  /// plain strings, not a closed enum — a new provenance is a new constant.
  ///
  /// `user` is one of the human/non-assistant actors recognized by
  /// ``AiChangelogActorFilter`` (`human` / `system` / `user` / `manual`), so a
  /// row stamped `user` is excluded from assistant-facing changelog reads;
  /// `assistant` and `import` fall outside that set and read as AI-originated.
  /// `unattributed` is a fail-closed sentinel, not a real actor: it too falls
  /// outside the human set (so it never masquerades as a person), and its
  /// presence in the audit trail flags a write that reached the funnel with no
  /// declared provenance — see ``writeChangelogRow``.
  public enum ChangelogInitiator {
    /// The assistant surface: an MCP-host-driven mutation. Bound ambiently for
    /// the duration of a tool call via ``SwiftLorvexCoreService/currentInitiator``.
    public static let assistant = "assistant"
    /// A direct human mutation — app UI, App Intents / Shortcuts / Siri, an
    /// interactive widget, a CarPlay action, or a watch mutation applied on the
    /// phone. The app's human surfaces declare it through the service's
    /// ``SwiftLorvexCoreService/writeInitiatorDefault`` at construction. The
    /// vocabulary distinguishes human from assistant, not the specific human
    /// surface, so every non-assistant local write shares this token rather than
    /// minting per-surface values the actor filter would misclassify as
    /// AI-originated.
    public static let user = "user"
    /// A data-import / restore mutation. Distinguishes replayed backup rows —
    /// whose before/after payloads are caller-supplied — from live actions.
    public static let importAttribution = "import"
    /// Fail-closed sentinel: the write funnel reached a row with no explicit
    /// per-row initiator, no ambient ``SwiftLorvexCoreService/currentInitiator``
    /// binding, and a service whose ``SwiftLorvexCoreService/writeInitiatorDefault``
    /// was left unset (the on-disk default). It is the ambient default so a
    /// forgotten binding surfaces as this visibly-wrong marker instead of a
    /// silent human `user`. Never bound deliberately by a real surface.
    public static let unattributed = "unattributed"
  }

  /// Resolve the `ai_changelog.initiated_by` provenance for a row, fail-closed.
  ///
  /// Precedence: an explicit per-row `initiatedBy` wins; otherwise an ambient
  /// ``currentInitiator`` binding (the MCP host's `.assistant`, an importer's
  /// `.import`) wins; otherwise the service's construction-time
  /// ``writeInitiatorDefault`` (`.user` for the app's human surfaces). The
  /// ambient default is ``ChangelogInitiator/unattributed``, so "was a binding
  /// installed?" is exactly "is the ambient value not the sentinel".
  ///
  /// If resolution still yields ``ChangelogInitiator/unattributed`` — no row
  /// initiator, no ambient binding, and a service that declared no default (the
  /// fail-closed on-disk default) — the write reached the funnel with no
  /// provenance. The recorded value is the `unattributed` sentinel either way, so
  /// the row is visibly wrong in the audit trail rather than masquerading as a
  /// human `user`. In a DEBUG app build the funnel additionally traps with a
  /// message naming the omission so a new write path that forgets to bind fails
  /// loudly; the trap is suppressed under XCTest (``isRunningUnderXCTest``) so a
  /// test fixture seeding through a bare on-disk service records and asserts the
  /// sentinel instead of crashing.
  func resolveInitiator(_ explicit: String?) -> String {
    if let explicit { return explicit }
    let ambient = Self.currentInitiator
    let resolved = ambient == ChangelogInitiator.unattributed ? writeInitiatorDefault : ambient
    if resolved == ChangelogInitiator.unattributed,
      Self.trapsOnUnattributedInitiator,
      !Self.isRunningUnderXCTest
    {
      assertionFailure(
        "ai_changelog write has no provenance: no explicit row initiator, no ambient "
          + "SwiftLorvexCoreService.currentInitiator binding, and the service declares no "
          + "writeInitiatorDefault. Bind $currentInitiator (e.g. .assistant for a new MCP "
          + "path, .import for a restore) or construct the service with "
          + "writeInitiatorDefault: .user for a human surface.")
    }
    return resolved
  }

  /// Write one `ai_changelog` row inside the current transaction, then emit it
  /// once to the sync outbox. Every mutation is recorded (Core Design Rule 2);
  /// the row's `initiated_by` provenance is resolved by ``resolveInitiator(_:)``
  /// (fail-closed — a write with no declared provenance never records as a human
  /// `user`). The before/after payloads are size-capped by the store layer.
  ///
  /// The audit row syncs across a user's devices (ACF-14) under the append-only,
  /// emit-once mutation contract: it is enqueued exactly once here and converges
  /// on peers by id-dedup. Ordinary full-resync excludes it; a candidate-zone
  /// baseline is the deliberate exception and stages every retained row before
  /// the old generation retires. Retention pruning propagates through durable
  /// account/zone-scoped CloudKit physical deletes, never sync tombstones.
  func writeChangelogRow(
    _ db: Database, _ entry: ChangelogEntry, deviceId: String
  ) throws {
    let id = EntityID.newEntityIDString()
    let timestamp = SyncTimestampFormat.syncTimestampNow()
    let retention = try AuditRetentionFrontier.currentWriteContext(db)
    // The mutation itself still commits when audit recording is disabled or a
    // clock anomaly puts this row below the account's minimum-retained key.
    guard
      try AuditRetentionFrontier.shouldRecordLocalAudit(
        db, context: retention, timestamp: timestamp, entityId: id)
    else { return }
    let row = ChangelogWrite.ChangelogRow(
      id: id,
      timestamp: timestamp,
      operation: entry.operation,
      entityType: entry.entityType,
      entityId: entry.entityId,
      entityIds: entry.entityIds,
      summary: entry.summary,
      initiatedBy: resolveInitiator(entry.initiatedBy),
      mcpTool: Self.currentMCPTool,
      sourceDeviceId: deviceId,
      beforeJson: try ChangelogWrite.encodeStateJson(entry.before),
      afterJson: try ChangelogWrite.encodeStateJson(entry.after),
      retentionEpoch: retention.retentionEpoch,
      retentionAccountIdentifier: retention.accountIdentifier)
    try ChangelogWrite.writeChangelogRow(db, row)

    // Emit-once outbound sync. The audit envelope reuses the transaction's
    // already-resolved clock — bound by `runWriteAttempt` in
    // `currentTransactionClock` — rather than re-resolving it through
    // `writeState()`. This code runs inside the transaction, on the thread holding
    // GRDB's serial writer queue; a `writeState()` → `store()` call there would
    // close the writer re-entrantly (an uncatchable GRDB reentrancy trap, plus a
    // lock-order inversion against `openLock`) if a cross-process factory reset
    // bumped the storage generation mid-transaction. The bound clock is the SAME
    // process-wide clock the mutation stamps with, so the envelope's version stays
    // strictly monotonic with — and never collides with — the mutation's. Fail
    // closed if the ambient is unset: a changelog write must always run inside a
    // bound `runWriteAttempt` transaction.
    let payload = try ChangelogWrite.buildChangelogSyncPayload(row)
    guard let transactionClock = Self.currentTransactionClock else {
      throw ChangelogWriteFunnelError.transactionClockUnbound
    }
    let session = HlcSession(handle: transactionClock)
    try enqueueChangelogUpsert(
      db, session: session, deviceId: deviceId, kind: .aiChangelog,
      entityId: row.id, payload: payload)
  }

}
