import Foundation
import GRDB
import Synchronization

/// `BEGIN IMMEDIATE` transaction wrapper over a GRDB `DatabaseWriter`.
///
/// The block runs inside an explicit `BEGIN IMMEDIATE` so cross-process
/// contention (app + MCP host both claiming the write lock) surfaces at
/// transaction open rather than at the first statement. On `Ok` the
/// transaction commits; on a thrown error it rolls back and the original
/// error propagates.
///
/// GRDB's `writer.write { ... }` wraps a DEFERRED transaction by default.
/// We bypass that machinery via `writeWithoutTransaction` and drive
/// `BEGIN IMMEDIATE` / `COMMIT` / `ROLLBACK` explicitly so the transaction
/// kind is unambiguously `IMMEDIATE`.
public enum StoreTransactions {
  /// Run `body` inside a `BEGIN IMMEDIATE` transaction on `writer`.
  ///
  /// - On success: `COMMIT` and return the closure's value.
  /// - On a thrown error: `ROLLBACK` the still-open transaction and rethrow. The
  ///   `ROLLBACK` is guarded by `isInsideTransaction` because some closure errors
  ///   (e.g. an `ON CONFLICT ROLLBACK` constraint, `SQLITE_FULL`) already rolled
  ///   the transaction back; a raw `ROLLBACK` with none open would throw "no
  ///   transaction is active" and mask the original error the caller must see.
  /// - If a guarded `ROLLBACK` itself fails after a closure error, the rollback
  ///   error is thrown ("rollback failed: …" semantics) so callers don't silently
  ///   swallow the unwind cleanup failure.
  /// - If `COMMIT` itself fails, best-effort `ROLLBACK` the still-open
  ///   transaction so the shared connection isn't wedged, then rethrow the
  ///   commit error.
  public static func withImmediateTransaction<T>(
    _ writer: any DatabaseWriter,
    _ body: (Database) throws -> T
  ) throws -> T {
    try writer.writeWithoutTransaction { db in
      try db.execute(sql: "BEGIN IMMEDIATE")
      let value: T
      do {
        value = try body(db)
      } catch {
        // Skip the ROLLBACK when the closure error already ended the transaction
        // (auto-rollback on `ON CONFLICT ROLLBACK`, `SQLITE_FULL`, …): a raw
        // ROLLBACK with none open throws and would mask the original error.
        if db.isInsideTransaction {
          do {
            try db.execute(sql: "ROLLBACK")
          } catch let rollbackError {
            throw StoreTransactionError.rollbackFailed(
              original: error, rollback: rollbackError)
          }
        }
        throw error
      }
      do {
        try db.execute(sql: "COMMIT")
      } catch let commitError {
        // SQLite auto-rolls-back many COMMIT failures (SQLITE_FULL/IOERR…) but
        // not all; a connection left inside the transaction fails every
        // subsequent BEGIN IMMEDIATE on this shared connection until restart.
        // Best-effort unwind before rethrowing.
        if db.isInsideTransaction {
          try? db.execute(sql: "ROLLBACK")
        }
        throw commitError
      }
      return value
    }
  }

  /// Per-process counter feeding the savepoint identifier suffix so concurrent
  /// nested `withSavepoint` invocations on the same connection cannot collide
  /// on the savepoint name.
  private static let savepointCounter = SavepointCounter()

  private final class SavepointCounter: Sendable {
    private let value = Mutex<UInt64>(0)
    func next() -> UInt64 {
      value.withLock { current in
        current &+= 1
        return current
      }
    }
  }

  /// Run `body` inside a SQLite `SAVEPOINT` on an already-open `Database`.
  ///
  /// Unlike ``withImmediateTransaction``, this nests cleanly inside any outer
  /// transaction (the caller's `BEGIN IMMEDIATE`) and provides identical
  /// atomicity: on success the savepoint is `RELEASE`d; on a thrown error it is
  /// rolled back via `ROLLBACK TO` + `RELEASE` so only the work done inside
  /// `body` is undone, leaving the outer transaction intact.
  ///
  /// The savepoint identifier is double-quoted and carries the requested
  /// `name` plus a per-process counter suffix; `name` must be a safe SQL
  /// identifier prefix (alphanumeric + underscore).
  public static func withSavepoint<T>(
    _ db: Database,
    _ name: String,
    _ body: (Database) throws -> T
  ) throws -> T {
    let identifier = "\(name)_\(savepointCounter.next())"
    let quoted = "\"\(identifier)\""
    try db.execute(sql: "SAVEPOINT \(quoted)")
    let value: T
    do {
      value = try body(db)
    } catch {
      // Skip the savepoint unwind when the closure error already rolled the whole
      // transaction back (auto-rollback on `ON CONFLICT ROLLBACK`, `SQLITE_FULL`,
      // …): the savepoint is gone, so `ROLLBACK TO` it would throw "no such
      // savepoint" and mask the original error the caller must see.
      if db.isInsideTransaction {
        do {
          try db.execute(sql: "ROLLBACK TO \(quoted)")
          try db.execute(sql: "RELEASE \(quoted)")
        } catch let rollbackError {
          throw StoreTransactionError.rollbackFailed(
            original: error, rollback: rollbackError)
        }
      }
      throw error
    }
    try db.execute(sql: "RELEASE \(quoted)")
    return value
  }
}

/// Composite error raised when a transaction rollback itself fails after the
/// closure already threw. The original closure error is preserved verbatim;
/// the rollback error is appended for diagnostic context.
public struct StoreTransactionError: Error, CustomStringConvertible {
  public let original: any Error
  public let rollback: any Error

  public var description: String {
    "\(original); rollback failed: \(rollback)"
  }

  public static func rollbackFailed(
    original: any Error, rollback: any Error
  ) -> StoreTransactionError {
    StoreTransactionError(original: original, rollback: rollback)
  }
}
