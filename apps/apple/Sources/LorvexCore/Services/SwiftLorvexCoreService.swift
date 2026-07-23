import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexWorkflow
import os

/// Pure-Swift `LorvexCoreServicing` backend over the `LorvexAppleCore` package.
///
/// Domain logic and SQLite storage live in the `LorvexDomain`/`LorvexStore`/
/// `LorvexWorkflow`/`LorvexSync`/`LorvexRuntime` modules, and this type maps the
/// core's `LorvexDomain` / repository results onto the app's distinct
/// `LorvexCore` model types at the service boundary.
///
/// The store is opened lazily on first use. `databasePath` selects the SQLite
/// file (resolved by `LorvexRuntime.DbLocator` when nil — the App Group
/// container when available, else the platform data dir); `schemaSQL` supplies
/// the authoritative `schema/schema.sql` DDL the store applies at open time —
/// the `LorvexStore` API takes the schema as a string so this package embeds no
/// second copy. When `schemaSQL` is nil it is resolved from
/// `LORVEX_APPLE_SCHEMA_PATH` (or, in development, a `#filePath`-relative
/// fallback to the repo-root `schema/schema.sql`).
public final class SwiftLorvexCoreService: LorvexCoreServicing, LorvexNativeImportServicing,
  LorvexNativeTaskGraphImportServicing, @unchecked Sendable
{
  let databasePath: String?
  private let schemaSQLProvider: @Sendable () throws -> String
  /// Resolves the canonical schema checksum (the normalized SHA-256 recorded in
  /// the shared `checksums.lock`) used to stamp/verify the `schema_migrations`
  /// bookkeeping row. `nil` disables bookkeeping (tests / explicit-schema
  /// callers), matching `LorvexStore.open`'s lenient mode.
  private let schemaChecksumProvider: @Sendable () throws -> String?
  /// Resolves the versioned-migration ladder (versions 2+) from the bundled
  /// byte-copies of the canonical `schema/migrations/` directory, validated
  /// against `checksums.lock`. `{ [] }` for explicit-schema callers (tests /
  /// embedders own their schema's identity, ladder included).
  private let schemaMigrationsProvider: @Sendable () throws -> [LorvexStore.SchemaMigration]
  /// Serializes store open/close state and coordinates live operation borrows.
  /// `NSCondition` retains the ordinary `lock`/`unlock` API while allowing a
  /// cutover close to wait until every transaction using the current store has
  /// returned. See ``withStoreCutoverLease(_:)``.
  private let openLock = NSCondition()
  private var openedStore: LorvexStore?
  /// Operations currently borrowing `openedStore`, guarded by `openLock`.
  /// A managed borrow additionally holds the cross-process shared cutover flock
  /// for its whole body; this count prevents this process from closing the GRDB
  /// writer out from under that body before the flock is released.
  private var activeStoreOperations = 0
  /// True while ``closeStoreForCutover()`` is draining active borrows and
  /// closing the current writer. New borrows wait for the close to finish, then
  /// re-open and validate the current generation.
  private var isClosingStoreForCutover = false

  /// Re-entrant operations on the same service reuse their outer borrow. This
  /// matters when a write-retry helper performs a diagnostic read before the
  /// outer logical operation returns: if a close starts in that window, making
  /// the nested read wait as a new borrow would deadlock (close waits for the
  /// outer borrow, while the outer borrow waits for close). The context is
  /// task-local and owner-qualified, so a nested call through another service
  /// still acquires its own lease normally.
  private struct StoreOperationLeaseContext: Sendable {
    let owner: ObjectIdentifier
    let store: LorvexStore
  }

  @TaskLocal private static var currentStoreOperationLease: StoreOperationLeaseContext?

  /// The managed database path whose durable storage generation
  /// (`ManagedStorageGeneration`) this open store is bound to, with the
  /// generation, marker-file signature, and database-file inode observed at
  /// open. `nil` for an explicit `databasePath` (dev/test injection) and in-memory
  /// stores — the generation protocol governs only Lorvex-managed local
  /// storage, the only storage a factory reset deletes.
  ///
  /// The inode is the defense-in-depth backstop to the marker: a factory reset
  /// bumps the marker *before* deleting the file, so an open that captured the
  /// post-bump marker must still notice the file vanish/change underneath an
  /// unchanged marker signature and reopen onto the recreated file. All four
  /// guarded by `openLock`. Read by the install-identity reconciliation in
  /// `writeState` (after it runs `store()`, so this reflects the current open),
  /// hence module-internal rather than file-private.
  var openedManagedDatabasePath: String?
  private var openedGeneration: Int?
  private var openedMarkerSignature: ManagedStorageGeneration.MarkerSignature?
  private var openedDatabaseInode: UInt64?

  /// Monotonic count of store (re)opens, guarded by `openLock`. Cached
  /// derivations of store contents (the write-side device id + HLC clock)
  /// record the epoch they were resolved under and re-resolve after a cutover
  /// reopened the store — a factory reset replaces the database, so a clock
  /// and device identity read from the old file must not leak into the new one.
  private var storageEpoch = 0

  /// The current storage epoch. Safe to call while holding `writeStateLock`
  /// (the established order is `writeStateLock` → `openLock`; `store()` never
  /// takes `writeStateLock`).
  func storageEpochSnapshot() -> Int {
    openLock.lock()
    defer { openLock.unlock() }
    return storageEpoch
  }

  /// The managed database path this open store is bound to, read under `openLock`
  /// (mirroring ``storageEpochSnapshot()``). `nil` for an explicit `databasePath`
  /// (dev/test injection) and in-memory stores — neither is factory-reset. The
  /// storage-cutover guard (``assertCommittingDatabaseIdentity(_:expected:)``)
  /// uses it to gate the commit-time identity check to managed storage.
  func openedManagedDatabasePathSnapshot() -> String? {
    openLock.lock()
    defer { openLock.unlock() }
    return openedManagedDatabasePath
  }

  /// Set under `openLock` when opening the on-disk database had to quarantine an
  /// unreadable / incompatible file and start fresh (see
  /// `LorvexStore.DatabaseRecovery`). `nil` on a clean open. Surfaced externally
  /// after first use via `databaseRecoveryNotice` to show a one-time "your
  /// previous data was set aside" notice; the quarantined file is preserved on
  /// disk, never deleted.
  private var _lastDatabaseRecovery: LorvexStore.DatabaseRecovery?

  /// Thread-safe snapshot of the open-time quarantine, if any, backing
  /// `databaseRecoveryNotice`. Guarded by `openLock` so the read never races the
  /// lazy `store()` open that sets it.
  private var lastDatabaseRecovery: LorvexStore.DatabaseRecovery? {
    openLock.lock()
    defer { openLock.unlock() }
    return _lastDatabaseRecovery
  }

  /// The open-time quarantine mapped to the host-facing `DatabaseRecoveryNotice`,
  /// or `nil` on a clean open. `nil` until the store has been opened (the first
  /// read/write), since the quarantine is decided at open time.
  public var databaseRecoveryNotice: DatabaseRecoveryNotice? {
    guard let recovery = lastDatabaseRecovery else { return nil }
    return DatabaseRecoveryNotice(backupPath: recovery.backupURL.path, reason: recovery.reason)
  }

  static let log = Logger(subsystem: "com.lorvex.apple", category: "store")

  /// The MCP tool name driving the current write, bound by the MCP host's
  /// dispatch funnel for the duration of one tool call. `writeChangelogRow`
  /// stamps it into `ai_changelog.mcp_tool` so the audit trail records which
  /// tool produced each row. Nil for GUI / App-Intent / sync-apply writes.
  @TaskLocal public static var currentMCPTool: String?

  /// Idempotency key/checksum bound by the MCP host for a write call. The write
  /// funnel records an in-transaction durable marker before commit; the host
  /// replaces it with the full response after the handler returns.
  @TaskLocal public static var currentMCPIdempotency: McpIdempotencyContext?

  /// The validated Watch command whose domain mutation is currently passing
  /// through the write funnel. The funnel preflights its local SQLite ledger
  /// before minting an HLC and records the applied receipt before commit.
  @TaskLocal static var currentWatchCommand: LorvexWatchCommand?

  /// Ambient `ai_changelog.initiated_by` provenance for writes through this
  /// service, overriding the per-service ``writeInitiatorDefault`` for the
  /// dynamic scope it is bound in. `writeChangelogRow` consults it whenever a
  /// `ChangelogEntry` carries no explicit initiator.
  ///
  /// Defaults to ``ChangelogInitiator/unattributed`` — the sentinel meaning "no
  /// surface declared this write's provenance". A caller that owns a write's
  /// provenance binds a real value for its scope: the MCP host binds
  /// ``ChangelogInitiator/assistant`` for the duration of a tool call, and a
  /// data-file restore binds ``ChangelogInitiator/importAttribution`` around the
  /// whole `LorvexDataImporter` run. Left at the sentinel, the write funnel
  /// falls back to the service's construction-time ``writeInitiatorDefault``
  /// (``ChangelogInitiator/user`` for the app's human surfaces); if that is the
  /// sentinel too the write is treated as a forgotten binding rather than
  /// silently recorded as a human — see ``writeChangelogRow``.
  @TaskLocal public static var currentInitiator: String = ChangelogInitiator.unattributed

  /// Explicit override of the fail-closed provenance trap in
  /// ``resolveInitiator(_:)``: when `false`, the write funnel does not trap on a
  /// write whose provenance resolves to ``ChangelogInitiator/unattributed``, even
  /// in a DEBUG app build. The trap is already suppressed automatically under
  /// XCTest (see ``isRunningUnderXCTest``), so tests rarely need this; it exists
  /// so a specific case can force the trap off. Production code never binds it.
  @TaskLocal public static var trapsOnUnattributedInitiator: Bool = true

  /// The transaction-scoped HLC handle resolved for the in-flight write,
  /// bound by ``runWriteAttempt(store:clock:deviceId:dominanceFloor:_:)`` for the
  /// duration of the `BEGIN IMMEDIATE` body and read by ``writeChangelogRow`` to
  /// stamp the audit row's sync envelope on the same normal/detached lane.
  ///
  /// `writeChangelogRow` runs inside the write transaction, on the thread already
  /// holding GRDB's serial writer queue, so it must NOT re-resolve the clock via
  /// ``writeState()`` — that calls ``store()``, which, if a cross-process factory
  /// reset bumped the storage generation mid-transaction, closes the writer
  /// re-entrantly onto that same serial queue and trips GRDB's uncatchable
  /// "not reentrant" trap (and inverts the `openLock`/writer-queue order into a
  /// deadlock). The clock is already resolved once per transaction, so it is
  /// threaded here instead; reusing it is behavior-preserving because it is the
  /// same clock the mutation stamps with, keeping the audit envelope strictly
  /// monotonic with it. Unset outside a bound transaction, so a changelog write
  /// that reaches the funnel off the write path fails closed rather than silently
  /// re-resolving.
  @TaskLocal static var currentTransactionClock: HlcTransactionHandle?

  /// Test seam: invoked by the write funnels (`withWrite`, `applyInbound`)
  /// immediately after `writeState()` resolves identity and before the store
  /// handle is re-resolved for the transaction. It exists so a test can
  /// deterministically interleave a cross-process factory reset into that exact
  /// window — the one the storage-cutover guard defends — rather than racing two
  /// real processes. Task-local (matching ``dbLocatorEnvironmentOverride``) so
  /// concurrent tests never leak a barrier into each other; never bound in
  /// production, where it is `nil` and the call is a no-op.
  @TaskLocal static var afterWriteStateBarrierForTesting: (@Sendable () -> Void)?

  /// Test seam: overrides the physical-time source feeding every HLC mint on
  /// both clock lanes (``HlcClock`` and ``HlcTransactionHandle``). Binding a
  /// deterministic monotonically increasing source gives every mint a distinct
  /// physical millisecond, so version-ordering assertions are independent of
  /// wall-clock resolution and machine load. Task-local (matching
  /// ``afterWriteStateBarrierForTesting``) so concurrent tests never leak a
  /// clock into each other; never bound in production, where wall time is used.
  @TaskLocal static var hlcPhysicalNowMsForTesting: (@Sendable () -> UInt64)?

  /// Test seam inside the native calendar backup read, after durable boundaries
  /// have been fetched and before event rows are fetched from the same SQLite
  /// snapshot. A concurrency test uses it to commit a split from a second
  /// connection in that window and prove the bundle cannot observe mixed eras.
  /// It is never bound in production.
  @TaskLocal static var afterCalendarCutoverExportReadForTesting: (@Sendable () -> Void)?

  /// Test seam inside the native task-graph backup read, after task roots have
  /// been fetched and before independently stored edges/children are fetched
  /// from the same SQLite snapshot. Never bound in production.
  @TaskLocal static var afterNativeTaskRowsExportReadForTesting: (@Sendable () -> Void)?

  /// Test seam inside the whole-export snapshot, after active lists have been
  /// fetched and before archived lists are fetched. A second connection can
  /// archive a list in this window to prove the two catalog partitions still
  /// come from one read transaction. Never bound in production.
  @TaskLocal static var afterActiveListsExportReadForTesting: (@Sendable () -> Void)?

  /// Test seam after the Today portion of the atomic widget source has been
  /// read, while the same SQLite transaction and managed-storage lease remain
  /// active. A peer writer can be started here to prove it cannot split the
  /// later focus/list/habit/stat reads into another revision.
  @TaskLocal static var afterWidgetTodayReadForTesting: (@Sendable () -> Void)?

  /// Test seam: invoked inside ``runWriteAttempt``'s `BEGIN IMMEDIATE` body,
  /// immediately after ``assertCommittingDatabaseIdentity(_:expected:)`` passes and
  /// before the mutation body runs — i.e. while the thread holds GRDB's serial
  /// writer queue and the managed-store shared cutover lease. A test pauses here,
  /// starts reset independently, and proves reset's exclusive acquisition waits
  /// until the transaction commits and releases the lease. Task-local (matching
  /// ``afterWriteStateBarrierForTesting``) so concurrent tests never leak a
  /// barrier into each other; never bound in production, where it is `nil` and
  /// the call is a no-op.
  @TaskLocal static var afterIdentityAssertBarrierForTesting: (@Sendable () -> Void)?

  /// Test seam: invoked in the managed open path once a corrupt / structurally
  /// incomplete file has surfaced a quarantine-recoverable fault and the open is
  /// about to enter the EXCLUSIVE-locked quarantine-and-recreate recovery —
  /// AFTER the shared cutover lock is released and BEFORE the exclusive lock is
  /// acquired. It exists so a test can deterministically rendezvous two openers
  /// in that exact window (both having detected the fault against the same
  /// corrupt file, neither yet holding the exclusive lock), exercising the cross-
  /// process quarantine serialization + under-lock re-check without racing real
  /// processes. Task-local (matching ``afterWriteStateBarrierForTesting``) so
  /// concurrent tests never leak a barrier into each other; never bound in
  /// production, where it is `nil` and the call is a no-op.
  @TaskLocal static var beforeManagedQuarantineRecoveryForTesting: (@Sendable () -> Void)?

  /// True when this process is a `swift test` / XCTest run (the XCTest framework
  /// is linked, or the harness set `XCTestConfigurationFilePath`). The fail-closed
  /// provenance trap in ``resolveInitiator(_:)`` is suppressed here so a test
  /// fixture that seeds through a bare on-disk service — declaring no
  /// ``writeInitiatorDefault`` — records the `unattributed` sentinel and asserts
  /// on it instead of crashing on the debug `assertionFailure`. The production app
  /// and MCP host binaries do not link XCTest, so the trap stays live there.
  static let isRunningUnderXCTest: Bool = {
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
    return NSClassFromString("XCTestCase") != nil
  }()

  /// Guards the lazily-resolved device id + HLC clock used by the write-side
  /// orchestration adapter (`+WriteSurface`). `epoch` records the storage
  /// epoch the pair was resolved under; a cutover reopen (factory reset)
  /// advances the epoch so the identity/clock are re-resolved from the fresh
  /// database instead of leaking the old file's device id into it.
  let writeStateLock = NSLock()
  var cachedWriteState: (epoch: Int, deviceId: String, clock: HlcClock)?

  /// The per-process HLC suffix this service's clock mints under. Each writer
  /// surface uses its own tag so separate processes writing the same database
  /// never share a monotonic counter's suffix.
  let hlcSurface: HlcSurface

  /// The `ai_changelog.initiated_by` provenance stamped when a write reaches the
  /// funnel with no explicit row initiator and no ambient ``currentInitiator``
  /// binding (see ``writeChangelogRow``).
  ///
  /// On-disk services default to ``ChangelogInitiator/unattributed`` (fail-closed):
  /// a surface that forgets to declare its provenance is caught rather than
  /// silently attributed to a human. The app's human factories (`AppCoreFactory`,
  /// `LorvexCoreRuntimeFactory`) construct with ``ChangelogInitiator/user`` so
  /// every UI / App-Intent / widget / notification / mobile / watch-apply write
  /// states `user` intentionally, while the MCP host keeps the fail-closed default
  /// and binds ``ChangelogInitiator/assistant`` per tool call. The in-memory seam
  /// (``init(store:)``, previews + unit fixtures) defaults to
  /// ``ChangelogInitiator/user`` — the dominant local surface — since it never
  /// backs production storage.
  let writeInitiatorDefault: String

  public init(
    databasePath: String?,
    schemaSQL: String? = nil,
    surface: HlcSurface = .app,
    writeInitiatorDefault: String = ChangelogInitiator.unattributed
  ) {
    self.databasePath = databasePath
    self.hlcSurface = surface
    self.writeInitiatorDefault = writeInitiatorDefault
    if let schemaSQL {
      // An explicitly-supplied schema (tests / embedders) opts out of the
      // bookkeeping contract — the caller owns the schema's identity.
      self.schemaSQLProvider = { schemaSQL }
      self.schemaChecksumProvider = { nil }
      self.schemaMigrationsProvider = { [] }
    } else {
      self.schemaSQLProvider = SwiftLorvexCoreService.resolveSchemaSQL
      self.schemaChecksumProvider = SwiftLorvexCoreService.resolveSchemaChecksum
      self.schemaMigrationsProvider = SwiftLorvexCoreService.resolveSchemaMigrations
    }
  }

  /// Test seam: construct a service over an already-opened `LorvexStore`
  /// (typically `LorvexStore.openInMemory`). Production callers use the public
  /// `init(databasePath:schemaSQL:)` initializer; this exists so tests can drive
  /// the service against an in-memory store without the on-disk open path.
  ///
  /// `writeInitiatorDefault` defaults to ``ChangelogInitiator/user`` — the
  /// dominant local surface previews and unit fixtures stand in for; a fail-closed
  /// provenance test passes ``ChangelogInitiator/unattributed`` to exercise a
  /// forgotten binding.
  init(store: LorvexStore, writeInitiatorDefault: String = ChangelogInitiator.user) {
    self.databasePath = nil
    self.hlcSurface = .app
    self.writeInitiatorDefault = writeInitiatorDefault
    self.schemaSQLProvider = { "" }
    self.schemaChecksumProvider = { nil }
    self.schemaMigrationsProvider = { [] }
    self.openedStore = store
  }

  /// The opened `LorvexStore`, opening it on first call. Thread-safe; the open
  /// races are serialized so a single store instance is shared across calls.
  ///
  /// For managed local storage this is also the staleness boundary of the
  /// storage-generation protocol: every call re-checks the durable generation
  /// marker beside the database (one `stat(2)` in the steady state) and, when
  /// a factory reset bumped it, closes the stale store — whose file was
  /// deleted out from under it — and reopens the recreated one, instead of
  /// letting this handle keep writing a deleted inode or serving pre-reset
  /// data. ``withStoreCutoverLease(_:)`` extends that protection through each
  /// complete read/write transaction: reset's exclusive lock waits for the
  /// transaction, then erases its committed result, so no operation can finish
  /// later against an already-unlinked generation.
  func store() throws -> LorvexStore {
    openLock.lock()
    defer { openLock.unlock() }
    if let openedStore {
      guard let managedPath = openedManagedDatabasePath else { return openedStore }
      let signature = ManagedStorageGeneration.markerSignature(forDatabase: managedPath)
      let inode = ManagedStorageGeneration.databaseInode(forDatabase: managedPath)
      if signature == openedMarkerSignature, inode == openedDatabaseInode {
        return openedStore
      }
      let currentGeneration = ManagedStorageGeneration.read(forDatabase: managedPath)
      if currentGeneration == openedGeneration, inode == openedDatabaseInode {
        // The marker was rewritten without a generation change and the database
        // file is unchanged; just adopt the new signature so the fast path
        // resumes.
        openedMarkerSignature = signature
        return openedStore
      }
      // Either the generation moved (a factory reset) or the database file was
      // replaced/removed underneath an unchanged marker (an open that captured
      // the reset's ABA window — marker bumped, file not yet deleted). Both mean
      // this handle is stranded on a dead inode; drop it and reopen.
      Self.log.notice(
        """
        Managed storage changed (generation \(String(describing: self.openedGeneration), privacy: .public) → \
        \(String(describing: currentGeneration), privacy: .public), inode \
        \(String(describing: self.openedDatabaseInode), privacy: .public) → \
        \(String(describing: inode), privacy: .public)); reopening the store.
        """)
      try? openedStore.writer.close()
      self.openedStore = nil
      openedManagedDatabasePath = nil
      openedGeneration = nil
      openedMarkerSignature = nil
      openedDatabaseInode = nil
      storageEpoch += 1
    }
    let resolution = try resolveDatabaseForOpen()
    let opened: LorvexStore
    if let managedPath = resolution.managedGenerationDatabasePath {
      opened = try openManaged(resolution: resolution, managedPath: managedPath)
    } else {
      opened = try performOpen(resolution: resolution)
    }
    openedStore = opened
    return opened
  }

  /// Open a Lorvex-managed resolution, coordinating both the factory-reset
  /// generation capture and the corrupt/incomplete-file quarantine recovery
  /// across processes. Called while holding `openLock`.
  ///
  /// Fast path — the healthy open and every open that fails closed — runs under
  /// only a SHARED cutover lock, holding it across the open AND the
  /// generation/inode capture so a concurrent factory reset (which bumps the
  /// marker then deletes the file under an EXCLUSIVE lock on this same path)
  /// cannot interleave: we either capture the live file's generation before the
  /// reset starts, or block until it finishes and open the recreated file. The
  /// open runs with `onFaultQuarantine: false`, so a corrupt / structurally
  /// incomplete file does NOT self-quarantine under the shared lock — where two
  /// processes could both quarantine and split the store across two inodes — but
  /// surfaces its fault for the exclusive-locked recovery below.
  ///
  /// Recovery path fires only on a quarantine-recoverable fault (see
  /// ``LorvexStore/isQuarantineRecoverable(_:)``); a fault that must fail closed
  /// (checksum mismatch, downgrade, transient) re-throws from the fast path
  /// untouched. Recovery re-opens under the EXCLUSIVE cutover lock, which
  /// serializes quarantine across processes and against a factory reset, and
  /// RE-CHECKS the file: a peer that already quarantined + recreated a healthy
  /// database in the window is found healthy and opened, so only a file STILL
  /// faulted under the lock is set aside. This keeps the healthy path free of any
  /// exclusive-lock acquire while making "detect fault → quarantine → recreate"
  /// atomic and idempotent for the fault path.
  private func openManaged(resolution: ResolvedDatabase, managedPath: String) throws
    -> LorvexStore
  {
    do {
      return try ManagedStorageGeneration.withSharedCutoverLock(forDatabase: managedPath) {
        let store = try performOpen(resolution: resolution, onFaultQuarantine: false)
        captureManagedGeneration(managedPath)
        return store
      }
    } catch let fault where LorvexStore.isQuarantineRecoverable(fault) {
      return try recoverManagedByQuarantine(
        resolution: resolution, managedPath: managedPath, fault: fault)
    }
  }

  /// Re-open a managed database that surfaced a quarantine-recoverable fault on
  /// the fast path, under the EXCLUSIVE cutover lock so the quarantine-and-
  /// recreate is atomic across processes. Called while holding `openLock`, AFTER
  /// the shared cutover lock the fast path took has been released (holding both
  /// on the same file would self-block — see
  /// ``ManagedStorageGeneration/withExclusiveCutoverLock(forDatabase:lockConfiguration:_:)``).
  ///
  /// The re-open first runs with `onFaultQuarantine: false`, so it RE-RUNS the
  /// same fault detection under the lock and branches on the CURRENT result: a
  /// peer that already recreated a healthy database in the window is opened
  /// as-is (no second quarantine and no generation bump). If the file is still
  /// faulted, recovery advances the durable physical-store generation *before*
  /// re-opening with quarantine enabled. This prevents a delayed pre-quarantine
  /// widget/watch snapshot from overwriting fresh data from the replacement
  /// workspace, while retaining reset's crash-safe bump-before-replace ordering.
  /// Idempotent across the openers that arrive in the window.
  private func recoverManagedByQuarantine(
    resolution: ResolvedDatabase, managedPath: String, fault: Error
  ) throws -> LorvexStore {
    Self.log.notice(
      """
      Managed database at \(managedPath, privacy: .private) faulted on open \
      (\(String(describing: fault), privacy: .public)); entering exclusive-locked \
      quarantine recovery.
      """)
    Self.beforeManagedQuarantineRecoveryForTesting?()
    return try ManagedStorageGeneration.withExclusiveCutoverLock(forDatabase: managedPath) {
      advanceGenerationForReplacement in
      do {
        let store = try performOpen(resolution: resolution, onFaultQuarantine: false)
        captureManagedGeneration(managedPath)
        return store
      } catch let currentFault where LorvexStore.isQuarantineRecoverable(currentFault) {
        _ = try advanceGenerationForReplacement()
        // The corrupt store's writer identity is coupled to HLC high-water
        // checkpoints inside that store. Remove the backup-excluded marker
        // before quarantine can replace SQLite, so the fresh database mints a
        // new suffix instead of adopting an old id with erased clock history.
        // Failure is intentionally terminal here: generation has advanced, but
        // the corrupt database is still in place and can be retried safely.
        try ManagedInstallIdentity.remove(forDatabase: managedPath)
        let store = try performOpen(resolution: resolution, onFaultQuarantine: true)
        captureManagedGeneration(managedPath)
        return store
      }
    }
  }

  /// Record the durable storage generation, marker signature, and database inode
  /// observed for `managedPath` at open, binding this handle to the file it just
  /// opened so `store()` reopens when a factory reset replaces it. Called while
  /// holding `openLock`, under the shared (fast path) or exclusive (recovery)
  /// cutover lock so the capture cannot race a reset's bump-then-delete.
  private func captureManagedGeneration(_ managedPath: String) {
    openedManagedDatabasePath = managedPath
    openedMarkerSignature = ManagedStorageGeneration.markerSignature(forDatabase: managedPath)
    openedGeneration = ManagedStorageGeneration.read(forDatabase: managedPath)
    openedDatabaseInode = ManagedStorageGeneration.databaseInode(forDatabase: managedPath)
  }

  /// Borrow the current store for one complete database operation.
  ///
  /// Managed storage holds the generation lock in SHARED mode across the whole
  /// body. The reset path takes the same lock EXCLUSIVELY, so it cannot bump the
  /// marker or unlink SQLite/WAL files until every active read/write transaction
  /// has returned. Because a reset can land between the initial `store()` check
  /// and shared-lock acquisition, the managed path is revalidated under the
  /// acquired lock; a stale handle is released and the open/borrow loop retries
  /// against the recreated generation.
  ///
  /// Every borrow, including an explicit/in-memory test store, is also counted
  /// under `openLock`. That makes ``closeStoreForCutover()`` wait rather than
  /// closing a GRDB writer while one of this service's transaction bodies still
  /// uses it.
  func withStoreCutoverLease<T>(_ body: (LorvexStore) throws -> T) throws -> T {
    if let current = Self.currentStoreOperationLease,
      current.owner == ObjectIdentifier(self)
    {
      return try body(current.store)
    }

    while true {
      _ = try store()

      openLock.lock()
      while isClosingStoreForCutover {
        openLock.wait()
      }
      guard let currentStore = openedStore else {
        openLock.unlock()
        continue
      }
      guard let managedPath = openedManagedDatabasePath else {
        activeStoreOperations += 1
        openLock.unlock()
        defer { releaseStoreOperation() }
        return try Self.$currentStoreOperationLease.withValue(
          StoreOperationLeaseContext(owner: ObjectIdentifier(self), store: currentStore)
        ) {
          try body(currentStore)
        }
      }
      openLock.unlock()

      do {
        return try ManagedStorageGeneration.withSharedCutoverLock(
          forDatabase: managedPath
        ) {
          let leasedStore = try borrowManagedStoreUnderCutoverLock(path: managedPath)
          defer { releaseStoreOperation() }
          return try Self.$currentStoreOperationLease.withValue(
            StoreOperationLeaseContext(owner: ObjectIdentifier(self), store: leasedStore)
          ) {
            try body(leasedStore)
          }
        }
      } catch is ManagedStoreLeaseNeedsRetry {
        // A reset/close landed after `store()` returned but before this shared
        // lock was acquired. Loop through `store()` so it closes the stale
        // handle and reopens the current generation before borrowing again.
        continue
      }
    }
  }

  /// Run one `BEGIN IMMEDIATE` transaction while borrowing the current store's
  /// complete cutover lease. Specialized write funnels use this when they do
  /// not otherwise need the `LorvexStore` handle.
  func withStoreCutoverImmediateTransaction<T>(
    _ body: (Database) throws -> T
  ) throws -> T {
    try withStoreCutoverLease { store in
      try StoreTransactions.withImmediateTransaction(store.writer, body)
    }
  }

  /// Validate and borrow the current managed handle. The caller already holds
  /// the cross-process shared cutover lock, so marker/inode state cannot change
  /// between this check and the end of the returned operation borrow.
  private func borrowManagedStoreUnderCutoverLock(path: String) throws -> LorvexStore {
    openLock.lock()
    defer { openLock.unlock() }
    while isClosingStoreForCutover {
      openLock.wait()
    }
    guard let currentStore = openedStore, openedManagedDatabasePath == path else {
      throw ManagedStoreLeaseNeedsRetry()
    }

    let signature = ManagedStorageGeneration.markerSignature(forDatabase: path)
    let inode = ManagedStorageGeneration.databaseInode(forDatabase: path)
    if signature != openedMarkerSignature || inode != openedDatabaseInode {
      let generation = ManagedStorageGeneration.read(forDatabase: path)
      guard generation == openedGeneration, inode == openedDatabaseInode else {
        throw ManagedStoreLeaseNeedsRetry()
      }
      // A same-generation atomic marker rewrite does not invalidate the file;
      // adopt its new signature so the normal steady-state fast path resumes.
      openedMarkerSignature = signature
    }

    activeStoreOperations += 1
    return currentStore
  }

  private func releaseStoreOperation() {
    openLock.lock()
    activeStoreOperations -= 1
    precondition(activeStoreOperations >= 0, "unbalanced store-operation lease")
    if activeStoreOperations == 0 {
      openLock.broadcast()
    }
    openLock.unlock()
  }

  /// Open the resolved database: create its directory, verify the schema
  /// checksum, open the `LorvexStore`, record any open-time quarantine, and run
  /// best-effort startup payload-shadow promotion. Does not touch the
  /// generation-tracking state — the caller captures that (for managed
  /// resolutions, under the shared cutover lock). Called while holding
  /// `openLock`.
  ///
  /// A managed resolution (`managedGenerationDatabasePath != nil`, i.e. not a
  /// dev/test-injected `databasePath`) opts the store into the managed-only
  /// post-open guarantees: the structural completeness probe (a stamped-but-
  /// tableless or `quick_check`-failing file is quarantined and recreated) and
  /// the idempotent inbox-row ensure. Dev/test-injected stores skip both.
  ///
  /// `onFaultQuarantine` is forwarded to ``LorvexStore/open(at:schemaSQL:schemaChecksum:migrations:managed:onFaultQuarantine:)``.
  /// The managed fast path passes `false` so a corrupt/incomplete file surfaces
  /// its fault under the shared cutover lock instead of self-quarantining there;
  /// the exclusive-locked recovery re-opens with `true`. Dev/test-injected opens
  /// keep the default `true` (in-process quarantine, no cross-process lock).
  private func performOpen(resolution: ResolvedDatabase, onFaultQuarantine: Bool = true) throws
    -> LorvexStore
  {
    let signpost = LorvexSignpost.begin(.databaseOpen)
    defer { LorvexSignpost.end(signpost) }
    let url = URL(fileURLWithPath: resolution.path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let schemaSQL = try schemaSQLProvider()
    let schemaChecksum = try schemaChecksumProvider()
    try Self.verifySchemaChecksum(schemaSQL: schemaSQL, expectedChecksum: schemaChecksum)
    let opened = try LorvexStore.open(
      at: url, schemaSQL: schemaSQL, schemaChecksum: schemaChecksum,
      migrations: try schemaMigrationsProvider(),
      managed: resolution.managedGenerationDatabasePath != nil,
      onFaultQuarantine: onFaultQuarantine)
    if let recovery = opened.recovery {
      _lastDatabaseRecovery = recovery
      Self.log.warning(
        """
        Existing database at \(url.path, privacy: .private) could not be opened \
        (\(recovery.reason, privacy: .public)); it was set aside at \
        \(recovery.backupURL.path, privacy: .private) and a fresh database was created.
        """)
    }
    // Startup maintenance: promote forward-compat payload shadows the upgraded
    // build now understands. Best-effort — a promotion failure is logged, never
    // an open failure.
    do {
      _ = try Self.promoteStartupPayloadShadows(opened)
    } catch {
      Self.log.warning(
        "Startup payload-shadow promotion failed: \(String(describing: error), privacy: .public)")
    }
    return opened
  }

  /// Close the open store ahead of a storage cutover (factory reset), so this
  /// process holds no connection to the database files about to be deleted.
  /// Idempotent and safe on a never-opened service; the next operation reopens
  /// lazily through the full resolution path. Cached store-derived state (the
  /// write-side device id + HLC clock) is invalidated via the storage epoch.
  ///
  /// BLOCKS until every active ``withStoreCutoverLease(_:)`` borrow on this
  /// service has returned — without bound, since force-closing a GRDB writer
  /// under a live transaction would trap. Callers therefore must not invoke it
  /// from within a lease body of the same service, and must not hold a lock a
  /// lease body could need while calling (see
  /// `LorvexCoreRuntimeFactory.invalidateCachedServices()`, which drops its
  /// cache lock before closing).
  public func closeStoreForCutover() {
    openLock.lock()
    defer { openLock.unlock() }
    isClosingStoreForCutover = true
    defer {
      isClosingStoreForCutover = false
      openLock.broadcast()
    }
    while activeStoreOperations > 0 {
      openLock.wait()
    }
    if let openedStore {
      try? openedStore.writer.close()
    }
    openedStore = nil
    openedManagedDatabasePath = nil
    openedGeneration = nil
    openedMarkerSignature = nil
    openedDatabaseInode = nil
    storageEpoch += 1
  }

  /// Runs `body` inside a GRDB write transaction on the (lazily opened) store.
  func write<T>(_ body: @Sendable (Database) throws -> T) throws -> T {
    let signpost = LorvexSignpost.begin(.databaseWrite)
    defer { LorvexSignpost.end(signpost) }
    return try withStoreCutoverLease { store in
      try store.writer.write(body)
    }
  }

  /// Runs `body` inside a GRDB read transaction on the (lazily opened) store.
  func read<T>(_ body: @Sendable (Database) throws -> T) throws -> T {
    let signpost = LorvexSignpost.begin(.databaseRead)
    defer { LorvexSignpost.end(signpost) }
    return try withStoreCutoverLease { store in
      try store.writer.read(body)
    }
  }

}

/// Internal sentinel used only to restart managed-store lease acquisition after
/// a cutover changed the handle in the open-to-lock gap.
private struct ManagedStoreLeaseNeedsRetry: Error {}
