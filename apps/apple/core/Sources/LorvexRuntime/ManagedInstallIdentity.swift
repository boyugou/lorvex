import Foundation

/// Backup-excluded, per-INSTALL identity marker for the Lorvex-managed database,
/// stored beside it as `<db>.install-identity`.
///
/// `sync_checkpoints.device_id` lives INSIDE the database, so any restore or copy
/// of the DB onto another device carries that id (and every HLC suffix derived
/// from it) verbatim. Two live installs would then share one device id, collide
/// on a single HLC clock suffix, and can silently drop each other's
/// last-writer-wins writes.
///
/// This marker is the out-of-database anchor that a restore does NOT bring: it is
/// excluded from iCloud / Time Machine backup, so restoring a backup onto a
/// different install brings the DB but leaves the marker absent. Open-time
/// reconciliation (``SwiftLorvexCoreService`` install-identity resolution) reads
/// it to tell a genuine reopen (marker id == DB device id) from a restored/cloned
/// DB (marker absent, or a different id) and rotates the device identity on the
/// latter, so the two installs get distinct ids.
///
/// Residual gap: a raw `cp -R` of the whole container copies the marker verbatim,
/// so the file approach alone does not catch that (non-mainstream) path; the
/// backup-exclusion covers the realistic iCloud/Finder/Time-Machine restore.
public enum ManagedInstallIdentity {
  /// The marker's path for a managed database file.
  public static func markerPath(forDatabase databasePath: String) -> String {
    databasePath + ".install-identity"
  }

  /// The exclusive first-open mint lock's path for a managed database file.
  static func lockFilePath(forDatabase databasePath: String) -> String {
    databasePath + ".install-identity-lock"
  }

  /// Raised when the exclusive first-open mint lock cannot be taken, so identity
  /// resolution fails closed instead of running the race-prone mint unguarded.
  public enum LockError: Error, CustomStringConvertible {
    case lockUnavailable(String)

    public var description: String {
      switch self {
      case .lockUnavailable(let detail):
        return "the install-identity mint lock is unavailable: \(detail)"
      }
    }
  }

  /// Run `body` while holding an EXCLUSIVE cross-process `flock(2)` on the
  /// install-identity lock beside the managed database (`<db>.install-identity-lock`),
  /// serializing the read-marker → mint/rotate → write-marker reconciliation
  /// across every process that opens one managed path (the app service and the
  /// MCP helper).
  ///
  /// Without it two genuine first-opens race: both read the still-absent marker,
  /// the first mints a device id and stamps it into the database, and the second
  /// — seeing the now-stamped in-DB id against the marker it read as absent —
  /// treats the database as a clone and rotates, churning the device identity
  /// and reseeding the HLC self-monotonic clock's retired-suffix seed on every
  /// open. Under the lock the loser blocks until the winner has published the
  /// marker, then reads that id and takes the ordinary-reopen no-op path.
  ///
  /// The lock file is dedicated, NOT the storage-cutover lock in
  /// ``ManagedStorageGeneration``: `body` re-enters the store open, which takes
  /// the cutover lock in shared mode, so guarding identity resolution with that
  /// same file would make this exclusive hold self-deadlock against the nested
  /// shared acquisition (distinct file descriptions contend even within one
  /// process). A separate file lets identity resolution serialize only against
  /// itself while a factory reset and ordinary opens keep using the cutover lock.
  ///
  /// Fails closed with ``LockError/lockUnavailable(_:)`` when the lock file
  /// cannot be created or the exclusive lock is not acquired within the budget,
  /// matching the storage-cutover lock's fail-closed contract — running the mint
  /// unguarded would re-expose the very race this guards. Identity resolution is
  /// sub-second, so the default 20s budget is exhausted only by a genuinely
  /// stuck holder, where failing the open is the correct outcome.
  public static func withMintLock<T>(
    forDatabase databasePath: String,
    lockConfiguration: ManagedStorageLock.LockConfiguration = .init(),
    _ body: () throws -> T
  ) throws -> T {
    // Create the container directory first (the cutover lock does the same) so a
    // first open — where `<db>` and its sibling lock file do not exist yet — can
    // create the lock rather than failing closed on a missing directory.
    let directory = (databasePath as NSString).deletingLastPathComponent
    do {
      try FileManager.default.createDirectory(
        atPath: directory, withIntermediateDirectories: true)
    } catch {
      throw LockError.lockUnavailable("the storage directory could not be created: \(error)")
    }
    guard let lock = ManagedStorageLock.FileLock(
      path: lockFilePath(forDatabase: databasePath))
    else {
      throw LockError.lockUnavailable("the lock file could not be created")
    }
    defer { lock.release() }
    guard ManagedStorageLock.acquire(lock, mode: .exclusive, configuration: lockConfiguration)
    else {
      throw LockError.lockUnavailable("held by another process")
    }
    return try body()
  }

  /// The outcome of reading the install-identity marker beside a managed
  /// database, distinguishing a genuinely-absent marker from one that exists but
  /// could not be read this open. Reconciliation must not conflate the two:
  /// genuine absence is the signal a restored/cloned DB rotates on (the
  /// backup-excluded marker is not carried forward by a restore), so a transient
  /// read failure misread as absence would spuriously rotate a healthy install's
  /// identity — churning the device id, forcing a reseed, and re-pulling the zone.
  public enum MarkerRead: Equatable, Sendable {
    /// The marker holds a valid, non-empty device id.
    case present(String)
    /// The marker file does not exist (`ENOENT` / `NSFileReadNoSuchFileError`) —
    /// the genuine "no marker" a restore leaves behind.
    case absent
    /// The marker file exists but could not be turned into a device id this open
    /// (a transient I/O or permissions failure, or corrupt/partial bytes). The
    /// recorded id is unknown; a caller must NOT treat this as absence.
    case unreadable
  }

  /// Read the install marker, distinguishing genuine absence from a transient or
  /// content read failure. Only a missing file is ``MarkerRead/absent``; every
  /// other failure — the file exists but a read errored, or its bytes carry no
  /// usable id — is ``MarkerRead/unreadable`` so reconciliation keeps the in-DB
  /// identity rather than rotating on incomplete information. A present file is
  /// not the restore-dropped-marker signal regardless of whether its content
  /// parses.
  public static func readMarkerState(forDatabase databasePath: String) -> MarkerRead {
    let url = URL(fileURLWithPath: markerPath(forDatabase: databasePath))
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      return isFileNotFound(error) ? .absent : .unreadable
    }
    guard
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let id = object[deviceIdKey] as? String,
      !id.isEmpty
    else { return .unreadable }
    return .present(id)
  }

  /// The install's recorded device id, or `nil` when the marker holds no usable id
  /// (absent, unreadable, or corrupt). A thin convenience over
  /// ``readMarkerState(forDatabase:)`` for callers that only need the id;
  /// reconciliation uses the tri-state directly so it can tell genuine absence
  /// from a transient failure.
  public static func read(forDatabase databasePath: String) -> String? {
    if case .present(let id) = readMarkerState(forDatabase: databasePath) { return id }
    return nil
  }

  /// Whether `error` from `Data(contentsOf:)` means the file does not exist, as
  /// opposed to a permissions/I/O failure on a file that is present. Genuine
  /// absence is the only read failure reconciliation may treat as "no marker".
  private static func isFileNotFound(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
      if nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError {
        return true
      }
      if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
        underlying.domain == NSPOSIXErrorDomain, underlying.code == Int(ENOENT)
      {
        return true
      }
    }
    if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOENT) { return true }
    return false
  }

  /// Atomically write the marker with `deviceId`, then exclude it from backup so a
  /// later restore does not carry it forward. The content write throws on failure
  /// (a genuinely unwritable container — where the database open would fail too),
  /// matching the fail-closed reset marker; the backup-exclusion is best-effort
  /// (a set failure must never fail the write it guards).
  public static func write(forDatabase databasePath: String, deviceId: String) throws {
    var url = URL(fileURLWithPath: markerPath(forDatabase: databasePath))
    let payload: [String: Any] = [
      deviceIdKey: deviceId,
      "updatedAt": ISO8601DateFormatter().string(from: Date()),
    ]
    let data =
      (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
    try data.write(to: url, options: .atomic)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
  }

  /// Remove the marker (used by a factory reset so the next open mints a fresh
  /// install identity rather than reusing the erased store's writer identity).
  ///
  /// Failure is surfaced: after the database and its HLC checkpoint have been
  /// erased, silently retaining this marker would make the fresh store adopt the
  /// old device id without its monotonic clock history. A reset must therefore
  /// remove the marker before it deletes SQLite, or fail while the canonical
  /// database is still intact.
  public static func remove(forDatabase databasePath: String) throws {
    let path = markerPath(forDatabase: databasePath)
    guard FileManager.default.fileExists(atPath: path) else { return }
    try FileManager.default.removeItem(atPath: path)
  }

  private static let deviceIdKey = "device_id"
}
