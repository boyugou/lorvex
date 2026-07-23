import XCTest

@testable import LorvexDomain
@testable import LorvexStore

/// Drives the payload→canonical-bytes→SHA-256 composition with the
/// cross-language vectors committed at
/// `spec/fixtures/canonical-json/checksums.json`. This is the exact pipeline
/// MCP idempotency and sync payload checksums run, so a divergence at either
/// stage — canonical formatting or digest encoding — surfaces here against a
/// committed artifact instead of in a cross-device sync mismatch.
final class ChecksumFixtureTests: XCTestCase {
  func testSharedChecksumVectorsEndToEnd() throws {
    let fixtureURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexStoreTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // core
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("spec/fixtures/canonical-json/checksums.json")
    let text = try String(contentsOf: fixtureURL, encoding: .utf8)

    guard
      case .object(let root)? = JSONValue.parse(text),
      case .array(let vectors)? = root["vectors"]
    else {
      return XCTFail("fixture is not an object with a vectors array")
    }
    XCTAssertGreaterThanOrEqual(vectors.count, 4, "vector set unexpectedly shrank")

    for vector in vectors {
      guard
        case .object(let fields) = vector,
        case .string(let name)? = fields["name"],
        let input = fields["input"],
        case .string(let expectedCanonical)? = fields["canonical"],
        case .string(let expectedDigest)? = fields["sha256"]
      else {
        return XCTFail("malformed vector entry")
      }
      let canonical = try canonicalizeJSON(input)
      XCTAssertEqual(
        canonical, expectedCanonical,
        "canonical bytes diverged for vector \"\(name)\"")
      XCTAssertEqual(
        McpIdempotency.computeRequestChecksum(canonical), expectedDigest,
        "checksum diverged for vector \"\(name)\"")
    }
  }
}
