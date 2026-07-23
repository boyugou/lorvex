import Darwin
import Foundation

/// Durable physical-store generation marker for the Lorvex-managed database,
/// stored beside it as `<db>.storage-generation`.
///
/// A monotonically increasing integer that ``resetDatabase(atPath:lockConfiguration:)``
/// bumps before deleting the database files during a factory reset, and that a
/// managed quarantine recovery bumps before replacing a corrupt database. The
/// marker is absent until the first physical-store replacement writes it.
/// Open stores record the generation they observed at open together with the
/// database file's inode, and re-check both at operation boundaries: a changed
/// generation OR a moved inode means "your file was deleted and recreated —
/// reopen", so no process keeps writing into a deleted inode or splits brain
/// across two files. The inode check is the backstop for the reset's ABA window
/// (an open that landed between the generation bump and the file delete records
/// the bumped generation but the doomed inode; the inode moving is the tell).
public enum ManagedStorageGeneration {

  /// The marker's path for a managed database file.
  public static func markerPath(forDatabase databasePath: String) -> String {
    databasePath + ".storage-generation"
  }

  /// The current generation, or `nil` when the marker is absent (no physical
  /// store replacement has happened yet) or unreadable. An open store treats
  /// `nil → N` as a generation change.
  public static func read(forDatabase databasePath: String) -> Int? {
    guard
      let data = try? Data(contentsOf: URL(fileURLWithPath: markerPath(forDatabase: databasePath))),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let generation = object[generationKey] as? Int,
      generation > 0
    else { return nil }
    return generation
  }

  /// A cheap change signature of the marker file (inode + mtime + size), or
  /// `nil` when the marker is absent. Open stores compare it per operation and
  /// re-parse the marker only when it differs, keeping the steady-state cost of
  /// the generation check to one `stat(2)`.
  public struct MarkerSignature: Equatable, Sendable {
    let inode: UInt64
    let mtimeSeconds: Int
    let mtimeNanoseconds: Int
    let size: Int64
  }

  public static func markerSignature(forDatabase databasePath: String) -> MarkerSignature? {
    var status = stat()
    guard stat(markerPath(forDatabase: databasePath), &status) == 0 else { return nil }
    return MarkerSignature(
      inode: UInt64(status.st_ino),
      mtimeSeconds: status.st_mtimespec.tv_sec,
      mtimeNanoseconds: status.st_mtimespec.tv_nsec,
      size: Int64(status.st_size))
  }

  /// The inode of the managed database file itself (not its marker), or `nil`
  /// when the file is absent. An open store captures it at open and re-checks
  /// it per operation so a factory reset that deleted and recreated the file is
  /// caught even in the narrow window where the marker still reads the same
  /// generation: `resetDatabase` bumps the marker *before* deleting the file,
  /// so an open that landed between the bump and the delete would record the
  /// bumped generation and, with only the generation to compare, keep serving
  /// the deleted inode forever. The inode moving underneath an unchanged marker
  /// is the tell that the file was replaced.
  public static func databaseInode(forDatabase databasePath: String) -> UInt64? {
    var status = stat()
    guard stat(databasePath, &status) == 0 else { return nil }
    return UInt64(status.st_ino)
  }

  /// Errors from the factory-reset cutover, phrased for the caller's failure
  /// alert. A database-file delete failure is rethrown as the underlying
  /// `FileManager` error instead.
  public enum ResetError: Error, CustomStringConvertible {
    /// The exclusive migration flock could not be acquired — another process is
    /// migrating, resetting, or holding a legacy-fallback lease. Storage was
    /// not touched.
    case lockUnavailable(String)
    /// The bumped generation marker could not be written. Storage was not
    /// touched (the marker is bumped before anything is deleted).
    case markerWriteFailed(String)
    /// A marker file is present but unparseable (a torn write, external
    /// corruption). Storage was not touched: resetting would have to guess the
    /// generation, and guessing "absent" regresses the monotonic counter to 1,
    /// so the reset fails closed instead.
    case markerCorrupt(String)

    public var description: String {
      switch self {
      case .lockUnavailable(let detail):
        return "the storage cutover lock is unavailable: \(detail)"
      case .markerWriteFailed(let detail):
        return "the storage generation marker could not be written: \(detail)"
      case .markerCorrupt(let path):
        return "the storage generation marker at \(path) is present but unreadable"
      }
    }
  }

  /// Factory-reset cutover for the managed database: under the exclusive
  /// migration flock, bump the storage generation, then delete the database
  /// and its `-wal`/`-shm` sidecars.
  ///
  /// The bump happens FIRST so a failure at any later step degrades safely: a
  /// crash (or delete failure) after the bump leaves the marker advanced but
  /// the data intact — open stores reconnect to the same, still-live file. The
  /// reverse order could let a process latch onto the deleted inode with no
  /// later signal to reconnect. Readers that reopen while the exclusive flock
  /// is held (secondaries re-run their settled check under a shared flock)
  /// block until the delete completes, so they land on the recreated file, not
  /// the dying one.
  ///
  /// Throws ``ResetError`` when the lock or marker write fails, and rethrows
  /// the `FileManager` error when the main database file cannot be deleted —
  /// the erase must never report a false success while the data survives. A
  /// *missing* main file is not a failure (nothing to erase); sidecars are
  /// legitimately absent and removed best-effort.
  ///
  /// A marker file that is *present but unparseable* (a torn write) is failed
  /// closed with ``ResetError/markerCorrupt(_:)`` rather than treated as absent:
  /// treating it as absent would compute the next generation as 1 and regress
  /// the monotonic counter, letting an open that recorded the higher generation
  /// keep serving a deleted inode.
  @discardableResult
  public static func resetDatabase(
    atPath databasePath: String,
    relatedSidecarPaths: [String] = [],
    lockConfiguration: ManagedStorageLock.LockConfiguration = .init()
  ) throws -> Int {
    let fm = FileManager.default
    let directory = (databasePath as NSString).deletingLastPathComponent
    do {
      try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
    } catch {
      throw ResetError.markerWriteFailed("cannot create the storage directory: \(error)")
    }
    guard let lock = ManagedStorageLock.FileLock(
      path: ManagedStorageLock.lockFilePath(forDatabase: databasePath))
    else {
      throw ResetError.lockUnavailable("the lock file could not be created")
    }
    defer { lock.release() }
    guard ManagedStorageLock.acquire(lock, mode: .exclusive, configuration: lockConfiguration)
    else {
      throw ResetError.lockUnavailable("held by another process")
    }

    let next = try writeNextGenerationMarker(forDatabase: databasePath)

    // The install identity is coupled to the database's erased HLC checkpoint.
    // Remove it before SQLite so a failure cannot report success after leaving
    // the fresh store able to adopt an old writer id with no clock history.
    try ManagedInstallIdentity.remove(forDatabase: databasePath)

    // Product-owned sidecars may carry user-derived state that belongs to the
    // same explicit reset lifecycle. Remove them while this generation cutover
    // is still exclusive and before touching SQLite, so a failure leaves the
    // canonical database intact and the reset retryable. The generation already
    // advanced, making any delayed old-generation derived writer subordinate to
    // the reset barrier its owner publishes before releasing its own lock.
    for sidecarPath in Set(relatedSidecarPaths) where fm.fileExists(atPath: sidecarPath) {
      try fm.removeItem(atPath: sidecarPath)
    }

    // Delete the WAL/SHM sidecars before the main file. A present-but-unremovable
    // sidecar must fail the reset rather than be silently ignored: a surviving
    // `-wal` holds recent pages and would be replayed into the recreated database
    // (resurrecting pre-reset data or corrupting the fresh schema). Removing the
    // sidecars first means such a failure throws while the database file is still
    // intact — a clean, retryable failure instead of a half-erased store reported
    // as success. Absent sidecars (the common WAL-checkpointed case) are tolerated.
    for sidecar in ["-wal", "-shm"] {
      let sidecarPath = databasePath + sidecar
      if fm.fileExists(atPath: sidecarPath) {
        try fm.removeItem(atPath: sidecarPath)
      }
    }
    if fm.fileExists(atPath: databasePath) {
      try fm.removeItem(atPath: databasePath)
    }
    return next
  }

  /// Run `body` while holding a SHARED flock on the managed database's cutover
  /// lock — the same lock ``resetDatabase(atPath:lockConfiguration:)`` takes
  /// EXCLUSIVELY.
  ///
  /// An open path wraps its `LorvexStore.open` and generation/inode capture in
  /// this so the open cannot interleave with a factory reset's bump-then-delete:
  /// the reset's exclusive acquisition blocks while any shared holder is open,
  /// and a shared acquisition blocks while the reset holds it exclusively. The
  /// opener therefore either captures the generation on the still-live file
  /// before the reset starts, or blocks until the reset finishes and opens the
  /// recreated file at the bumped generation — it can never land on the
  /// pre-delete inode in the reset's ABA window.
  ///
  /// Fails closed, symmetric with ``resetDatabase(atPath:lockConfiguration:)``:
  /// if the lock file cannot be created, or the shared lock is not acquired
  /// within `lockConfiguration.acquireTimeout`, this throws
  /// ``ResetError/lockUnavailable(_:)`` rather than run `body` unguarded. Running
  /// unguarded would let the open land in the reset's ABA window and commit a
  /// write to the doomed inode — a loss the per-operation generation/inode
  /// re-check can only *reconnect* away from afterward, never recover. The shared
  /// acquisition only ever blocks against a reset holding the lock exclusively (a
  /// sub-second bump-then-delete, so the 20s default budget covers it with room
  /// to spare); ordinary concurrent opens hold the lock in shared mode and never
  /// block each other, so the throw is reachable only against a stuck exclusive
  /// holder or a broken container — where the open would fail regardless.
  public static func withSharedCutoverLock<T>(
    forDatabase databasePath: String,
    lockConfiguration: ManagedStorageLock.LockConfiguration = .init(),
    _ body: () throws -> T
  ) throws -> T {
    // Create the container directory first (the reset side does the same) so a
    // first open — where `<db>` and its sibling lock file do not exist yet — can
    // create the lock rather than failing closed on a missing directory. After
    // this, a lock file that still cannot be created means a genuinely unwritable
    // container, which is a real fail-closed case.
    let directory = (databasePath as NSString).deletingLastPathComponent
    do {
      try FileManager.default.createDirectory(
        atPath: directory, withIntermediateDirectories: true)
    } catch {
      throw ResetError.lockUnavailable("the storage directory could not be created: \(error)")
    }
    guard let lock = ManagedStorageLock.FileLock(
      path: ManagedStorageLock.lockFilePath(forDatabase: databasePath))
    else {
      throw ResetError.lockUnavailable("the lock file could not be created")
    }
    defer { lock.release() }
    guard ManagedStorageLock.acquire(lock, mode: .shared, configuration: lockConfiguration) else {
      throw ResetError.lockUnavailable("held exclusively by a factory reset")
    }
    return try body()
  }

  /// Run `body` while holding an EXCLUSIVE flock on the managed database's cutover
  /// lock — the same lock ``resetDatabase(atPath:lockConfiguration:)`` takes
  /// exclusively and ``withSharedCutoverLock(forDatabase:lockConfiguration:_:)``
  /// takes shared.
  ///
  /// The corrupt/incomplete-database recovery path wraps its quarantine-and-
  /// recreate in this so the "detect fault → quarantine → recreate" step is
  /// atomic across processes: two openers that both detect the same corrupt file
  /// serialize here, and the loser's `body` RE-CHECKS the file under the lock —
  /// finding the healthy database the winner just recreated and opening it
  /// instead of quarantining the fresh file a second time. It also mutually
  /// excludes with a factory reset (which holds this lock exclusively), so a
  /// reset and a quarantine can never interleave.
  ///
  /// Lock ordering (three separate lock files beside `<db>`, deadlock-free):
  /// - The SHARED cutover lock must be RELEASED before this EXCLUSIVE one is
  ///   acquired — holding shared while requesting exclusive on the same file
  ///   would self-block. The recovery caller opens on the fast path under the
  ///   shared lock, releases it, then acquires this exclusive lock only on the
  ///   fault branch.
  /// - The install-identity mint lock (``ManagedInstallIdentity/withMintLock``,
  ///   a distinct file) is always OUTERMOST: its body re-enters the store open,
  ///   which takes the cutover lock, and nothing takes the cutover lock and then
  ///   reaches for the mint lock. So mint → cutover is the only nesting and no
  ///   cycle exists.
  ///
  /// Fails closed exactly like the shared and reset acquisitions: an uncreatable
  /// lock file or an acquisition that exceeds `lockConfiguration.acquireTimeout`
  /// throws ``ResetError/lockUnavailable(_:)`` rather than running `body`
  /// unguarded.
  ///
  /// `advanceGenerationForReplacement` is available only inside `body` and
  /// writes the next durable generation while this exclusive lease is held. A
  /// caller that is about to quarantine or otherwise replace the physical
  /// database must invoke it *before* touching the database files. The helper is
  /// single-use per lease, preventing one replacement from accidentally
  /// advancing the marker twice. A caller that merely re-checks and finds a
  /// healthy database does not invoke it, so concurrent recovery losers do not
  /// manufacture extra generations.
  public static func withExclusiveCutoverLock<T>(
    forDatabase databasePath: String,
    lockConfiguration: ManagedStorageLock.LockConfiguration = .init(),
    _ body: (_ advanceGenerationForReplacement: () throws -> Int) throws -> T
  ) throws -> T {
    let directory = (databasePath as NSString).deletingLastPathComponent
    do {
      try FileManager.default.createDirectory(
        atPath: directory, withIntermediateDirectories: true)
    } catch {
      throw ResetError.lockUnavailable("the storage directory could not be created: \(error)")
    }
    guard let lock = ManagedStorageLock.FileLock(
      path: ManagedStorageLock.lockFilePath(forDatabase: databasePath))
    else {
      throw ResetError.lockUnavailable("the lock file could not be created")
    }
    defer { lock.release() }
    guard ManagedStorageLock.acquire(lock, mode: .exclusive, configuration: lockConfiguration)
    else {
      throw ResetError.lockUnavailable("held by another storage-lifecycle operation")
    }
    var didAdvanceGeneration = false
    return try body {
      precondition(
        !didAdvanceGeneration,
        "one physical-store replacement must advance storage generation exactly once")
      didAdvanceGeneration = true
      return try writeNextGenerationMarker(forDatabase: databasePath)
    }
  }

  private static let generationKey = "generation"

  /// Advance the durable generation. The caller MUST already hold the managed
  /// database's exclusive cutover lock. Keeping this primitive private makes
  /// the two public replacement paths — factory reset and exclusive quarantine
  /// recovery — the only ways to publish a new generation.
  private static func writeNextGenerationMarker(forDatabase databasePath: String) throws -> Int {
    let fm = FileManager.default
    let markerFilePath = markerPath(forDatabase: databasePath)
    let current: Int
    if let existing = read(forDatabase: databasePath) {
      current = existing
    } else if fm.fileExists(atPath: markerFilePath) {
      // The marker is present but did not parse. Re-read once: a concurrent
      // atomic rename may have just published a valid marker in the window
      // between the first read and this existence check. A marker that remains
      // unparseable is genuinely torn/corrupt — fail closed rather than regress
      // the monotonic counter.
      if let recovered = read(forDatabase: databasePath) {
        current = recovered
      } else {
        throw ResetError.markerCorrupt(markerFilePath)
      }
    } else {
      current = 0
    }
    let (next, overflow) = current.addingReportingOverflow(1)
    guard !overflow else {
      throw ResetError.markerWriteFailed("the storage generation counter is exhausted")
    }
    let markerURL = URL(fileURLWithPath: markerFilePath)
    do {
      try markerPayload(generation: next).write(to: markerURL, options: .atomic)
    } catch {
      throw ResetError.markerWriteFailed(String(describing: error))
    }
    return next
  }

  /// The payload is fixed-shape (an `Int` and an ISO-8601 `String`), so
  /// serialization cannot fail in practice; propagating the impossible throw
  /// surfaces as `ResetError.markerWriteFailed` at the caller instead of
  /// silently publishing an empty marker that would classify as corrupt.
  private static func markerPayload(generation: Int) throws -> Data {
    let payload: [String: Any] = [
      generationKey: generation,
      "updatedAt": ISO8601DateFormatter().string(from: Date()),
    ]
    return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
  }
}
