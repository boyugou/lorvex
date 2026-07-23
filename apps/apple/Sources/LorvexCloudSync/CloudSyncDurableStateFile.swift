import Darwin
import Foundation

/// Failure persisting or reading one of CloudSync's small durable state files
/// (account identity and pause reason). These files carry
/// account-binding and consent decisions, so their stores FAIL CLOSED: a write
/// that cannot be proven durable and a present-but-unreadable file both throw,
/// and callers halt (or refuse the guarded action) instead of proceeding on
/// unverified state.
public enum CloudSyncDurableStateError: Error, Equatable {
  /// The file could not be staged, synced, or renamed into place. The previous
  /// on-disk state (if any) is intact — the staged copy never replaces the
  /// published file until it has been fsynced.
  case writeFailed(String)
  /// The post-rename readback did not return the bytes that were written, so
  /// the write cannot be trusted as durable.
  case verificationFailed(String)
  /// The file exists but its content cannot be read or parsed. Distinct from
  /// "no file": absent state is a genuine first run / no-pause, while
  /// unreadable state is unknown and must not be treated as absent.
  case unreadable(String)
}

extension CloudSyncDurableStateError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .writeFailed(let detail):
      return "sync state could not be saved: \(detail)"
    case .verificationFailed(let detail):
      return "sync state could not be verified after saving: \(detail)"
    case .unreadable(let detail):
      return "sync state exists but could not be read: \(detail)"
    }
  }
}

/// Crash-safe, verified persistence for CloudSync's single-value state files,
/// following a stage → fsync → rename → verify durability sequence: stage the
/// bytes next to the target, force them to disk (`F_FULLFSYNC`, falling back to
/// `fsync`), rename
/// atomically into place, then read the published file back and compare. A
/// successful `write` therefore proves the value is durably on disk; any other
/// outcome throws with the previous state intact.
///
/// Callers are actors, so writes to one file are serialized in-process. The
/// deterministic staging name means a crashed attempt's leftover is simply
/// overwritten by the next write.
enum CloudSyncDurableStateFile {

  /// Durably publish `data` at `url` (write staging → fsync → rename → verify
  /// readback). Throws ``CloudSyncDurableStateError/writeFailed(_:)`` when the
  /// bytes cannot be staged or published, and
  /// ``CloudSyncDurableStateError/verificationFailed(_:)`` when the readback
  /// does not match.
  static func write(_ data: Data, to url: URL) throws {
    let fm = FileManager.default
    let directory = url.deletingLastPathComponent()
    do {
      try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      throw CloudSyncDurableStateError.writeFailed(
        "cannot create the state directory: \(error.localizedDescription)")
    }

    let staging = url.appendingPathExtension("staging")
    try? fm.removeItem(at: staging)
    do {
      try data.write(to: staging)
    } catch {
      throw CloudSyncDurableStateError.writeFailed(
        "cannot stage the state file: \(error.localizedDescription)")
    }
    do {
      try synchronizeFile(atPath: staging.path)
      try renameFile(atPath: staging.path, toPath: url.path)
    } catch {
      try? fm.removeItem(at: staging)
      throw error
    }
    // Directory fsync so the rename's directory entry is durable. Best-effort,
    // like the migration's: the data fsync above is the critical barrier.
    synchronizeDirectory(containing: url.path)

    let readback: Data
    do {
      readback = try Data(contentsOf: url)
    } catch {
      throw CloudSyncDurableStateError.verificationFailed(
        "readback failed: \(error.localizedDescription)")
    }
    guard readback == data else {
      throw CloudSyncDurableStateError.verificationFailed(
        "readback returned different bytes")
    }
  }

  /// The file's bytes, or `nil` when no file exists. A file that exists but
  /// cannot be read throws ``CloudSyncDurableStateError/unreadable(_:)`` — it
  /// must never be conflated with absent state.
  static func readIfPresent(at url: URL) throws -> Data? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
      return try Data(contentsOf: url)
    } catch {
      throw CloudSyncDurableStateError.unreadable(error.localizedDescription)
    }
  }

  // MARK: - Durability primitives (stage → fsync → rename → verify)

  private static func synchronizeFile(atPath path: String) throws {
    let fd = open(path, O_RDONLY)
    guard fd >= 0 else {
      throw CloudSyncDurableStateError.writeFailed("open for fsync failed: \(errnoDescription())")
    }
    defer { _ = Darwin.close(fd) }
    // F_FULLFSYNC pushes past the drive cache; fall back to fsync where the
    // filesystem does not support it.
    if fcntl(fd, F_FULLFSYNC) != 0, fsync(fd) != 0 {
      throw CloudSyncDurableStateError.writeFailed("fsync failed: \(errnoDescription())")
    }
  }

  private static func synchronizeDirectory(containing path: String) {
    let dir = (path as NSString).deletingLastPathComponent
    let fd = open(dir, O_RDONLY)
    guard fd >= 0 else { return }
    defer { _ = Darwin.close(fd) }
    _ = fsync(fd)
  }

  private static func renameFile(atPath from: String, toPath to: String) throws {
    guard rename(from, to) == 0 else {
      throw CloudSyncDurableStateError.writeFailed(
        "rename into place failed: \(errnoDescription())")
    }
  }

  private static func errnoDescription() -> String {
    String(cString: strerror(errno))
  }
}
