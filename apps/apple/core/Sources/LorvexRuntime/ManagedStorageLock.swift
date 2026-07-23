import Darwin
import Foundation
import Synchronization

/// A `flock(2)`-based cross-process lock beside the Lorvex-managed database,
/// used to serialize storage-lifecycle operations (the factory-reset cutover in
/// ``ManagedStorageGeneration``) across every process that opens the store.
///
/// The lock lives at `<db>.storage-lock`. `flock` is advisory and tied to the
/// open file description, so the kernel drops it when the descriptor closes —
/// including on crash — and no stale-lock recovery is ever needed.
public enum ManagedStorageLock {

  /// The lock file's path for a managed database file.
  static func lockFilePath(forDatabase databasePath: String) -> String {
    databasePath + ".storage-lock"
  }

  /// Cross-process lock acquisition budget. The default absorbs a brief
  /// contention window when two processes (app vs. MCP helper) touch storage
  /// concurrently; tests inject short budgets to exercise contention quickly.
  /// Public because it appears in ``ManagedStorageGeneration``'s public
  /// reset/cutover signatures.
  public struct LockConfiguration: Sendable {
    public var acquireTimeout: TimeInterval
    public var retryInterval: TimeInterval

    public init(acquireTimeout: TimeInterval = 20, retryInterval: TimeInterval = 0.05) {
      self.acquireTimeout = acquireTimeout
      self.retryInterval = retryInterval
    }
  }

  enum LockMode {
    case exclusive
    case shared

    var operation: Int32 {
      switch self {
      case .exclusive: return LOCK_EX
      case .shared: return LOCK_SH
      }
    }
  }

  /// Non-blocking `flock` attempts retried until `configuration.acquireTimeout`
  /// elapses. Polling (instead of a blocking `flock`) keeps the wait bounded
  /// and interruption-free on this synchronous open path.
  static func acquire(
    _ lock: FileLock, mode: LockMode, configuration: LockConfiguration
  ) -> Bool {
    let deadline = DispatchTime.now() + configuration.acquireTimeout
    while true {
      if lock.tryLock(operation: mode.operation) {
        return true
      }
      guard DispatchTime.now() < deadline else {
        return false
      }
      Thread.sleep(forTimeInterval: configuration.retryInterval)
    }
  }

  /// One open file description carrying a `flock(2)` lock. Distinct instances
  /// contend with each other even inside one process (each `open` creates its
  /// own file description), so in-process concurrency is serialized exactly
  /// like cross-process concurrency. The kernel drops the lock when the
  /// descriptor closes — including on crash — so no stale-lock recovery is
  /// needed. `release` is idempotent and also runs on deinit.
  final class FileLock: Sendable {
    private let fd: Int32
    private let released = Mutex(false)

    init?(path: String) {
      let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
      guard fd >= 0 else { return nil }
      self.fd = fd
    }

    /// `flock(fd, operation | LOCK_NB)`; also performs atomic-ish lock
    /// conversion (exclusive → shared and back) on an already-locked fd.
    func tryLock(operation: Int32) -> Bool {
      released.withLock { isReleased in
        guard !isReleased else { return false }
        return flock(fd, operation | LOCK_NB) == 0
      }
    }

    func release() {
      released.withLock { isReleased in
        guard !isReleased else { return }
        isReleased = true
        _ = Darwin.close(fd)
      }
    }

    deinit {
      release()
    }
  }
}
