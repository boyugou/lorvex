import GRDB

extension DatabaseError {
  /// True when this error is a SQLite UNIQUE-constraint violation
  /// (`SQLITE_CONSTRAINT` with the `SQLITE_CONSTRAINT_UNIQUE` extended code).
  ///
  /// The single predicate shared by the aggregate dedup merges — each resolves a
  /// natural-key collision by catching this and collapsing the duplicates — and by
  /// the coalesced-enqueue retry loop, which treats it as the partial-index race
  /// between concurrent writers.
  var isUniqueConstraintViolation: Bool {
    resultCode == .SQLITE_CONSTRAINT && extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE
  }
}
