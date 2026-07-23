import GRDB
import XCTest

@testable import LorvexStore

final class StoreTransactionsTests: XCTestCase {
  private struct TestError: Error, Equatable {
    let message: String
  }

  private func freshWriter() throws -> any DatabaseWriter {
    let queue = try DatabaseQueue()
    try queue.write { db in
      try db.execute(sql: "CREATE TABLE t (v INTEGER)")
    }
    return queue
  }

  func testCommitOnSuccess() throws {
    let writer = try freshWriter()
    try StoreTransactions.withImmediateTransaction(writer) { db in
      try db.execute(sql: "INSERT INTO t (v) VALUES (42)")
    }
    let v = try writer.read { db in
      try Int64.fetchOne(db, sql: "SELECT v FROM t")
    }
    XCTAssertEqual(v, 42)
  }

  func testRollbackOnError() throws {
    let writer = try freshWriter()
    XCTAssertThrowsError(
      try StoreTransactions.withImmediateTransaction(writer) { db in
        try db.execute(sql: "INSERT INTO t (v) VALUES (99)")
        throw TestError(message: "boom")
      }
    ) { error in
      XCTAssertEqual((error as? TestError)?.message, "boom")
    }
    let count = try writer.read { db in
      try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM t")
    }
    XCTAssertEqual(count, 0)
  }

  func testSubsequentTransactionAfterErrorSucceeds() throws {
    let writer = try freshWriter()
    _ = try? StoreTransactions.withImmediateTransaction(writer) { db in
      try db.execute(sql: "INSERT INTO t (v) VALUES (1)")
      throw TestError(message: "abort")
    }
    try StoreTransactions.withImmediateTransaction(writer) { db in
      try db.execute(sql: "INSERT INTO t (v) VALUES (7)")
    }
    let v = try writer.read { db in
      try Int64.fetchOne(db, sql: "SELECT v FROM t")
    }
    XCTAssertEqual(v, 7)
  }

  /// A statement whose constraint carries `ON CONFLICT ROLLBACK` aborts AND rolls
  /// back the enclosing transaction, so by the time the closure error propagates
  /// no transaction is open. The error-path `ROLLBACK` must be guarded by
  /// `isInsideTransaction` (like the COMMIT path); issuing a raw `ROLLBACK` with no
  /// active transaction throws "cannot rollback - no transaction is active" and
  /// masks the ORIGINAL constraint error the caller must see.
  func testErrorRollbackGuardedWhenTransactionAlreadyRolledBack() throws {
    let queue = try DatabaseQueue()
    try queue.write { db in
      try db.execute(sql: "CREATE TABLE u (v INTEGER UNIQUE ON CONFLICT ROLLBACK)")
      try db.execute(sql: "INSERT INTO u (v) VALUES (1)")
    }

    XCTAssertThrowsError(
      try StoreTransactions.withImmediateTransaction(queue) { db in
        // Duplicate: the UNIQUE constraint's ON CONFLICT ROLLBACK auto-rolls-back
        // the BEGIN IMMEDIATE transaction, then throws SQLITE_CONSTRAINT.
        try db.execute(sql: "INSERT INTO u (v) VALUES (1)")
      }
    ) { error in
      XCTAssertFalse(
        error is StoreTransactionError,
        "the error-path ROLLBACK must not mask the original error with a 'no transaction' failure")
      XCTAssertEqual(
        (error as? DatabaseError)?.resultCode, .SQLITE_CONSTRAINT,
        "the original SQLite constraint error must surface unmasked")
    }
  }

  /// The savepoint error path has the same masking hazard: when an inner
  /// `ON CONFLICT ROLLBACK` rolls the WHOLE transaction back, the savepoint is
  /// gone, so `ROLLBACK TO` it throws "no such savepoint" and masks the original
  /// error. Guarding on `isInsideTransaction` skips the doomed unwind and lets the
  /// constraint error propagate.
  func testSavepointErrorRollbackGuardedWhenTransactionAlreadyRolledBack() throws {
    let queue = try DatabaseQueue()
    try queue.write { db in
      try db.execute(sql: "CREATE TABLE u (v INTEGER UNIQUE ON CONFLICT ROLLBACK)")
      try db.execute(sql: "INSERT INTO u (v) VALUES (1)")
    }

    XCTAssertThrowsError(
      try StoreTransactions.withImmediateTransaction(queue) { db in
        try StoreTransactions.withSavepoint(db, "sp") { inner in
          try inner.execute(sql: "INSERT INTO u (v) VALUES (1)")
        }
      }
    ) { error in
      XCTAssertFalse(
        error is StoreTransactionError,
        "a rolled-back savepoint's unwind must not mask the original error")
      XCTAssertEqual(
        (error as? DatabaseError)?.resultCode, .SQLITE_CONSTRAINT,
        "the original SQLite constraint error must surface unmasked")
    }
  }
}
