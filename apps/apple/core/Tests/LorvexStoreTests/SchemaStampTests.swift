import GRDB
import XCTest

@testable import LorvexStore

/// `applySchema` runs at autocommit, so two processes opening a brand-new
/// database can both observe no bookkeeping row and both try to stamp it. The
/// loser's primary-key conflict must be absorbed as a concurrent stamp, not
/// bubbled up to the quarantine path where it would set aside a healthy database.
final class SchemaStampTests: XCTestCase {
  func testStampToleratesMatchingConcurrentStampButRejectsMismatch() throws {
    let queue = try DatabaseQueue()
    try queue.writeWithoutTransaction { db in
      try LorvexStore.ensureSchemaMigrationsTable(db)
      try LorvexStore.stampSchemaMigration(db, checksum: "abc123")

      // A concurrent process stamped the same checksum between our absence-check
      // and this insert: re-stamping must NOT throw.
      XCTAssertNoThrow(try LorvexStore.stampSchemaMigration(db, checksum: "abc123"))

      // A genuinely different recorded checksum is a real mismatch.
      XCTAssertThrowsError(try LorvexStore.stampSchemaMigration(db, checksum: "different")) {
        XCTAssertTrue($0 is LorvexStore.SchemaMismatch)
      }
    }
  }
}
