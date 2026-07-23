import Foundation
import XCTest

@testable import LorvexStore

/// Apple's canonical SQL-checksum normalization. The repo-pin test asserts the
/// Swift digest of the real `schema/schema.sql` equals the identity recorded in
/// `schema/migrations/checksums.lock`; other platforms may remain directionally
/// aligned but are not part of this frozen ladder contract.
final class MigrationSqlChecksumTests: XCTestCase {
  private func repoRoot() -> String {
    var path = (#filePath as NSString).deletingLastPathComponent
    for _ in 0..<5 { path = (path as NSString).deletingLastPathComponent }
    return path
  }

  func testRealSchemaMatchesCanonicalLockEntry() throws {
    let root = repoRoot() as NSString
    let sql = try String(
      contentsOfFile: root.appendingPathComponent("schema/schema.sql"), encoding: .utf8)
    let lockData = try Data(
      contentsOf: URL(
        fileURLWithPath: root.appendingPathComponent("schema/migrations/checksums.lock")))
    let lock = try XCTUnwrap(
      JSONSerialization.jsonObject(with: lockData) as? [String: [String: String]])
    let expected = try XCTUnwrap(lock["001"]?["sha256"])
    XCTAssertEqual(MigrationSqlChecksum.hexDigest(sql), expected)
  }

  func testCommentOnlyEditsDoNotChangeTheDigest() {
    let base = "CREATE TABLE t (id TEXT PRIMARY KEY);\nCREATE INDEX i ON t(id);"
    let reflowed = """
      -- a five-line
      -- comment block
      CREATE TABLE t (id TEXT PRIMARY KEY);
      /* a block
         comment spanning
         lines */
      CREATE INDEX i ON t(id);  -- trailing inline comment
      """
    XCTAssertEqual(
      MigrationSqlChecksum.hexDigest(base), MigrationSqlChecksum.hexDigest(reflowed))
  }

  func testSemanticEditsChangeTheDigest() {
    XCTAssertNotEqual(
      MigrationSqlChecksum.hexDigest("CREATE TABLE t (id TEXT);"),
      MigrationSqlChecksum.hexDigest("CREATE TABLE t (id INTEGER);"))
    // Interior whitespace inside non-comment SQL is significant: reformatting
    // code (not comments) is a real edit.
    XCTAssertNotEqual(
      MigrationSqlChecksum.hexDigest("CREATE TABLE t (id TEXT);"),
      MigrationSqlChecksum.hexDigest("CREATE  TABLE t (id TEXT);"))
  }

  func testBOMAndCRLFAreNormalizedAway() {
    let unix = "CREATE TABLE t (id TEXT);\nCREATE INDEX i ON t(id);\n"
    let windows = "\u{feff}CREATE TABLE t (id TEXT);\r\nCREATE INDEX i ON t(id);\r\n"
    XCTAssertEqual(
      MigrationSqlChecksum.hexDigest(unix), MigrationSqlChecksum.hexDigest(windows))
  }

  func testCommentMarkersInsideLiteralsArePreserved() {
    let withMarkers = "INSERT INTO t VALUES ('a -- not a comment', \"b /* not */\");"
    let commentStripped = "INSERT INTO t VALUES ('a', \"b\");"
    XCTAssertNotEqual(
      MigrationSqlChecksum.hexDigest(withMarkers),
      MigrationSqlChecksum.hexDigest(commentStripped))
    // Escaped quotes keep the literal run open across an embedded marker.
    let escaped = "INSERT INTO t VALUES ('it''s -- still literal');"
    XCTAssertNotEqual(
      MigrationSqlChecksum.hexDigest(escaped),
      MigrationSqlChecksum.hexDigest("INSERT INTO t VALUES ('it''s');"))
  }
}
