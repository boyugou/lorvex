import Darwin
import Foundation
import LorvexCore

/// Serializes widget-snapshot writes per destination URL and drops a write whose
/// database revision predates the one already on disk, so concurrent publishes can't land
/// out of order and pin a destination on stale state.
///
/// `WidgetSnapshotFileStore` is a value type created fresh per publish, so two
/// concurrent publishes to the same URL (a task mutation republishing while a
/// refresh reloads) would otherwise race their atomic writes with no ordering —
/// the older one could land last. Routing every write through this one actor
/// applies the writes to a URL one at a time, and the monotonic revision guard
/// discards a stale straggler even if it reaches the actor last. The snapshot
/// URL is additionally written by a SECOND process (the interactive
/// widget-intent extension), which this actor cannot serialize — a `flock(2)`
/// sidecar beside the snapshot covers the cross-process read-check-write
/// window. The disk I/O is synchronous but runs on the actor's own executor,
/// off the calling (main) actor.
actor WidgetSnapshotWriteSerializer {
  static let shared = WidgetSnapshotWriteSerializer()

  enum WriteResult: Sendable {
    case written
    case rejected(currentData: Data)
  }

  /// Writes `data` (the encoded snapshot) atomically to `url`, creating the
  /// parent directory first, unless the snapshot already on disk at `url`
  /// carries a later local database revision — in which case the incoming write
  /// is a stale straggler and is skipped. Returns either `.written` or the exact
  /// current bytes that won, allowing every downstream reload/mirror/cache to
  /// propagate disk truth rather than the rejected candidate.
  ///
  /// The stale-check + write pair holds a cross-process advisory `flock` (the
  /// `.publish-lock` sidecar) so the app process and the widget-intent
  /// extension cannot interleave their read-check-write sections and land an
  /// older revision last. Lock acquisition fails closed: writing without this
  /// critical section would make the monotonic stale check advisory and allow
  /// erased or older content to land last.
  func write(
    _ data: Data,
    orderingKey: WidgetSnapshotOrdering.OrderingKey,
    to url: URL,
    managedDatabasePath: String?,
    lockTimeout: TimeInterval,
    lockRetryInterval: TimeInterval
  ) throws -> WriteResult {
    let parentURL = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
    guard let lock = SnapshotPublishLock(path: url.path + ".publish-lock") else {
      throw WidgetSnapshotFileStoreError.publishLockUnavailable
    }
    defer { lock.release() }
    guard lock.acquire(timeout: lockTimeout, retryInterval: lockRetryInterval) else {
      throw WidgetSnapshotFileStoreError.publishLockUnavailable
    }
    let existing = try? Data(contentsOf: url)
    if let managedDatabasePath,
      let durableGeneration = SwiftLorvexCoreService.managedStorageGeneration(
        atDatabasePath: managedDatabasePath),
      orderingKey.storageGeneration < durableGeneration
    {
      if let existing,
        let existingSnapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: existing),
        existingSnapshot.version == WidgetSnapshot.supportedVersion,
        existingSnapshot.storageGeneration >= durableGeneration
      {
        return .rejected(currentData: existing)
      }
      throw WidgetSnapshotFileStoreError.supersededStorageGeneration
    }
    if let existing,
      let existingSnapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: existing),
      existingSnapshot.version == WidgetSnapshot.supportedVersion,
      WidgetSnapshotOrdering.isStrictlyOlder(
        orderingKey,
        than: .init(
          storageGeneration: existingSnapshot.storageGeneration,
          focusFilterRevision: existingSnapshot.focusFilterRevision,
          workspaceInstanceID: existingSnapshot.workspaceInstanceID,
          localChangeSequence: existingSnapshot.localChangeSequence,
          logicalDay: existingSnapshot.logicalDay))
    {
      return .rejected(currentData: existing)
    }
    try data.write(to: url, options: [.atomic])
    return .written
  }

  /// Hold the same cross-process publish lock across the canonical storage
  /// cutover and publication of a content-free snapshot at the returned new
  /// generation. Every delayed old writer enters only after this barrier exists
  /// and is rejected by generation ordering.
  func replaceForFactoryReset(
    at url: URL,
    logicalDay: String,
    resetStorage: @Sendable () throws -> Int,
    lockTimeout: TimeInterval,
    lockRetryInterval: TimeInterval
  ) throws -> WidgetSnapshotFactoryResetOutcome {
    let parentURL = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
    guard let lock = SnapshotPublishLock(path: url.path + ".publish-lock") else {
      throw WidgetSnapshotFileStoreError.publishLockUnavailable
    }
    defer { lock.release() }
    guard lock.acquire(timeout: lockTimeout, retryInterval: lockRetryInterval) else {
      throw WidgetSnapshotFileStoreError.publishLockUnavailable
    }

    let generation = try resetStorage()
    let barrier = WidgetSnapshot(
      generatedAt: WidgetSnapshotProjector.timestampString(from: Date()),
      storageGeneration: generation,
      focusFilterRevision: 0,
      workspaceInstanceID: WidgetSnapshot.unscopedWorkspaceInstanceID,
      localChangeSequence: 0,
      timezone: nil,
      logicalDay: logicalDay,
      stats: .init(
        focusCount: 0, overdueCount: 0, dueTodayCount: 0, completedTodayCount: 0),
      briefing: nil,
      focusTasks: [],
      habits: [],
      todayTasks: [],
      lists: [],
      listStats: [])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
      let data = try encoder.encode(barrier)
      try data.write(to: url, options: [.atomic])
      return WidgetSnapshotFactoryResetOutcome(
        barrier: barrier, publicationSucceeded: true)
    } catch {
      // The database generation already advanced and the canonical data is
      // irreversibly erased. Remove stale bytes best-effort, but do NOT throw:
      // the app must finish settings/core reset instead of reporting that the
      // wipe never happened. The host surfaces this as a post-reset warning and
      // its fresh refresh retries publication.
      try? FileManager.default.removeItem(at: url)
      return WidgetSnapshotFactoryResetOutcome(
        barrier: barrier, publicationSucceeded: false)
    }
  }
}

/// One open file description carrying an exclusive advisory `flock(2)` on the
/// snapshot's `.publish-lock` sidecar. The kernel drops the lock when the
/// descriptor closes — including on crash — so no stale-lock recovery is
/// needed. Bounded non-blocking polling keeps the actor's synchronous write
/// path from stalling behind a wedged peer; on timeout the publish fails closed.
private final class SnapshotPublishLock {
  private let fd: Int32
  private var released = false

  init?(path: String) {
    let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
    guard fd >= 0 else { return nil }
    self.fd = fd
  }

  /// Bounded non-blocking polling. Closing the descriptor releases the lock.
  func acquire(timeout: TimeInterval, retryInterval: TimeInterval) -> Bool {
    let deadline = DispatchTime.now() + timeout
    while true {
      if flock(fd, LOCK_EX | LOCK_NB) == 0 { return true }
      guard DispatchTime.now() < deadline else { return false }
      Thread.sleep(forTimeInterval: retryInterval)
    }
  }

  func release() {
    guard !released else { return }
    released = true
    _ = Darwin.close(fd)
  }

  deinit {
    release()
  }
}

/// Encodes a `WidgetSnapshot` to the canonical App-Group JSON and writes it
/// atomically, off the calling actor.
///
/// The one JSON encoding contract for every widget snapshot on disk:
/// `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`. The encode happens
/// on the calling actor (`JSONEncoder` is not `Sendable`); the `Sendable` `Data`
/// + `URL` then cross into `WidgetSnapshotWriteSerializer.shared`, which
/// serializes writes to each URL and drops a snapshot older than the one already
/// on disk — so a slow publish carrying stale state can't overwrite a newer one.
public enum WidgetSnapshotFileStoreError: Error, Equatable, Sendable {
  case publishLockUnavailable
  case rejectedSnapshotUnreadable
  case supersededStorageGeneration
}

/// Outcome after the irreversible managed-storage reset has completed. A
/// failed barrier publication is a recoverable derived-cache warning, never a
/// reason to pretend the canonical wipe did not occur.
public struct WidgetSnapshotFactoryResetOutcome: Sendable, Equatable {
  public let barrier: WidgetSnapshot
  public let publicationSucceeded: Bool

  public init(barrier: WidgetSnapshot, publicationSucceeded: Bool) {
    self.barrier = barrier
    self.publicationSucceeded = publicationSucceeded
  }
}

public struct WidgetSnapshotFileStore: Sendable {
  private let encoder: JSONEncoder
  private let lockTimeout: TimeInterval
  private let lockRetryInterval: TimeInterval

  public init(
    lockTimeout: TimeInterval = 2,
    lockRetryInterval: TimeInterval = 0.02
  ) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    self.encoder = encoder
    self.lockTimeout = max(0, lockTimeout)
    self.lockRetryInterval = max(0.001, lockRetryInterval)
  }

  /// Encodes `snapshot` and writes it atomically to `url` through the shared
  /// per-URL write serializer, which drops the write when a newer snapshot is
  /// already on disk. The encode runs on the calling actor; only the resulting
  /// `Data`, its database ordering key, and the `URL` cross to the serializer.
  @discardableResult
  public func write(
    _ snapshot: WidgetSnapshot,
    to url: URL,
    managedDatabasePath: String? = nil
  ) async throws -> WidgetSnapshot {
    let data = try encoder.encode(snapshot)
    let result = try await WidgetSnapshotWriteSerializer.shared.write(
      data,
      orderingKey: .init(
        storageGeneration: snapshot.storageGeneration,
        focusFilterRevision: snapshot.focusFilterRevision,
        workspaceInstanceID: snapshot.workspaceInstanceID,
        localChangeSequence: snapshot.localChangeSequence,
        logicalDay: snapshot.logicalDay),
      to: url,
      managedDatabasePath: managedDatabasePath,
      lockTimeout: lockTimeout,
      lockRetryInterval: lockRetryInterval)
    switch result {
    case .written:
      return snapshot
    case .rejected(let currentData):
      guard let current = try? JSONDecoder().decode(WidgetSnapshot.self, from: currentData),
        current.version == WidgetSnapshot.supportedVersion
      else {
        throw WidgetSnapshotFileStoreError.rejectedSnapshotUnreadable
      }
      return current
    }
  }

  /// Explicit factory-reset lifecycle. The reset closure returns the newly
  /// durable managed-storage generation; while the snapshot publish lock remains
  /// held, that generation is published as an empty barrier.
  @discardableResult
  public func replaceForFactoryReset(
    at url: URL,
    managedDatabasePath: String,
    logicalDay: String,
    resetStorage: @escaping @Sendable () throws -> Int
  ) async throws -> WidgetSnapshotFactoryResetOutcome {
    try await WidgetSnapshotWriteSerializer.shared.replaceForFactoryReset(
      at: url,
      logicalDay: logicalDay,
      resetStorage: resetStorage,
      lockTimeout: lockTimeout,
      lockRetryInterval: lockRetryInterval)
  }
}

/// Sendable, file-only reset target captured by the host before it enters the
/// CloudSync quiescence gate. It contains no app-store reference, so the gate
/// can hold the snapshot publish lock across the synchronous storage cutover.
public struct WidgetSnapshotFactoryResetTarget: Sendable {
  public let snapshotURL: URL
  public let managedDatabasePath: String
  private let reload: @Sendable () -> Void

  public init(
    snapshotURL: URL,
    managedDatabasePath: String,
    reload: @escaping @Sendable () -> Void = {}
  ) {
    self.snapshotURL = snapshotURL
    self.managedDatabasePath = managedDatabasePath
    self.reload = reload
  }

  @discardableResult
  public func replaceWithEmptyBarrier(
    logicalDay: String,
    resetStorage: @escaping @Sendable () throws -> Int
  ) async throws -> WidgetSnapshotFactoryResetOutcome {
    let outcome = try await WidgetSnapshotFileStore().replaceForFactoryReset(
      at: snapshotURL,
      managedDatabasePath: managedDatabasePath,
      logicalDay: logicalDay,
      resetStorage: resetStorage)
    // WidgetKit caches rendered timelines independently from the JSON file.
    // Invalidate it even when the barrier write failed and stale bytes were
    // removed, so a reset never leaves a pre-reset rendered title on screen.
    reload()
    return outcome
  }
}

public enum WidgetSnapshotPublisherError: Error, Equatable, Sendable {
  case atomicSourceUnavailable
}

/// The single widget-snapshot publishing engine shared by every platform surface
/// (the macOS host, the iOS/visionOS host, and the interactive widget-intent
/// path).
///
/// Everything that differs per platform is captured by `Destination`: where to
/// write (or whether to write at all), which focus filter to apply, whether to
/// redact titles, how to reload glance surfaces, and whether to mirror the
/// snapshot to a paired watch. The engine body is identical everywhere: resolve
/// the focus filter, project the snapshot, write it when a URL is present,
/// reload, then mirror — and return the projected value.
public struct WidgetSnapshotPublisher: Sendable {
  /// The platform seam the engine writes through.
  ///
  /// - `snapshotURL`: the App-Group file to write, or `nil` to SKIP the write
  ///   entirely — the local-build / unentitled no-op. When `nil`, the reload
  ///   still fires but nothing touches disk, so no App-Group permission prompt
  ///   is triggered on unsigned builds.
  /// - `focusFilterStore`: the shared focus-filter store; `nil` ⇒ `.inactive`.
  /// - `hideTitles`: redact task titles in the projected snapshot (macOS
  ///   private-preview surfaces).
  /// - `reload`: reload glance surfaces after a durable write.
  /// - `mirror`: optional sink for the projected `WidgetSnapshot` *value* (not
  ///   encoded `Data`) — the watch transport re-encodes it compactly and runs
  ///   its own transfer-size cap check.
  public struct Destination: Sendable {
    public var snapshotURL: URL?
    public var managedDatabasePath: String?
    public var focusFilterStore: FocusFilterStore?
    public var hideTitles: Bool
    public var reload: @Sendable () -> Void
    public var mirror: (@Sendable (WidgetSnapshot) async -> Void)?

    public init(
      snapshotURL: URL?,
      managedDatabasePath: String? = nil,
      focusFilterStore: FocusFilterStore? = nil,
      hideTitles: Bool = false,
      reload: @escaping @Sendable () -> Void,
      mirror: (@Sendable (WidgetSnapshot) async -> Void)? = nil
    ) {
      self.snapshotURL = snapshotURL
      self.managedDatabasePath = managedDatabasePath
      self.focusFilterStore = focusFilterStore
      self.hideTitles = hideTitles
      self.reload = reload
      self.mirror = mirror
    }
  }

  private let destination: Destination
  private let projector: WidgetSnapshotProjector
  private let store: WidgetSnapshotFileStore
  private let timezone: @Sendable () -> String

  public init(
    destination: Destination,
    projector: WidgetSnapshotProjector = WidgetSnapshotProjector(),
    store: WidgetSnapshotFileStore = WidgetSnapshotFileStore(),
    timezone: @escaping @Sendable () -> String = { TimeZone.current.identifier }
  ) {
    self.destination = destination
    self.projector = projector
    self.store = store
    self.timezone = timezone
  }

  /// Publishes a snapshot projected from already-loaded planning surfaces.
  ///
  /// `statsSource` carries the uncapped canonical actionable + completed-today
  /// task data the projector uses for the numeric stats; pass it (from
  /// ``LorvexCoreServicing/loadWidgetStatsSource()``) so the widget's counts
  /// reflect the whole workload. When nil the stats fall back to the ≤N dashboard
  /// pool, which under-counts past the cap.
  @discardableResult
  public func publish(
    storageGeneration: Int = 0,
    logicalDay: String? = nil,
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    timezone: String? = nil,
    habitCatalog: HabitCatalogSnapshot? = nil,
    lists: ListCatalogSnapshot? = nil,
    statsSource: WidgetStatsSource? = nil
  ) async throws -> WidgetSnapshot {
    let focusState = try await destination.focusFilterStore?.loadState() ?? .inactive
    let snapshot = projector.snapshot(
      storageGeneration: storageGeneration,
      focusFilterRevision: focusState.revision,
      logicalDay: logicalDay,
      today: today,
      currentFocus: currentFocus,
      timezone: timezone ?? self.timezone(),
      hideTitles: destination.hideTitles,
      focusFilter: focusState.configuration,
      habitCatalog: habitCatalog,
      listCatalog: lists,
      statsSource: statsSource
    )
    // The reload is posted only after a durable write succeeds, so a glance
    // surface never reloads onto a stale or half-written file. A `nil` URL skips
    // the write (local/unentitled builds) while still reloading and mirroring.
    let winner: WidgetSnapshot
    if let url = destination.snapshotURL {
      winner = try await store.write(
        snapshot, to: url, managedDatabasePath: destination.managedDatabasePath)
    } else {
      winner = snapshot
    }
    destination.reload()
    await destination.mirror?(winner)
    return winner
  }

  /// Publishes one transactionally captured source. This is the only production
  /// path: it threads the storage generation into ordering and prevents the
  /// projection from mixing Today, focus, habit, list, and stats revisions.
  @discardableResult
  public func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot {
    try await publish(
      storageGeneration: source.storageGeneration,
      logicalDay: source.logicalDay,
      today: source.today,
      currentFocus: source.currentFocus,
      timezone: source.timezone,
      habitCatalog: source.habits,
      lists: source.lists,
      statsSource: source.stats)
  }

  /// Publishes a snapshot loaded fresh from `core`, like the interactive
  /// widget-intent path. `today` is the `YYYY-MM-DD` day whose focus plan and
  /// habit statuses are loaded.
  ///
  /// Habits are loaded alongside tasks/focus/lists because the Habits widget and
  /// habits accessory read them from the same App-Group snapshot; omitting the
  /// catalog would rewrite the snapshot with zero habits on every interactive tap
  /// and blank the Habits widget until the app next republishes.
  @discardableResult
  public func refresh(
    core: any LorvexCoreServicing,
    today: String? = nil
  ) async throws -> WidgetSnapshot {
    guard let sourceCore = core as? any LorvexWidgetSnapshotSourceServicing else {
      throw WidgetSnapshotPublisherError.atomicSourceUnavailable
    }
    let source = try await sourceCore.loadWidgetSnapshotSource(date: today)
    return try await publish(source: source)
  }
}
