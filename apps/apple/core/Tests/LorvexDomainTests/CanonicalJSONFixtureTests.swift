import XCTest

@testable import LorvexDomain

/// Drives the Swift canonical-JSON serializer with the cross-language vectors
/// committed at `spec/fixtures/canonical-json/vectors.json` — the shared
/// artifact both cores must reproduce byte-for-byte, because sync checksums
/// are computed over canonical bytes. Unlike the hand-ported cases in
/// `CanonicalJSONTests`, these inputs live outside either implementation, so
/// a Rust-side change to the vectors mechanically reaches this suite through
/// the committed file rather than through a manual port.
final class CanonicalJSONFixtureTests: XCTestCase {
  func testSharedVectorsCanonicalizeByteForByte() throws {
    let fixtureURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexDomainTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // core
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("spec/fixtures/canonical-json/vectors.json")
    let text = try String(contentsOf: fixtureURL, encoding: .utf8)

    // Parse with the domain parser, not Codable: the vectors' meaning depends
    // on the integer/float distinction Foundation's NSNumber erases.
    guard
      case .object(let root)? = JSONValue.parse(text),
      case .array(let vectors)? = root["vectors"]
    else {
      return XCTFail("fixture is not an object with a vectors array")
    }
    XCTAssertGreaterThanOrEqual(vectors.count, 10, "vector set unexpectedly shrank")

    for vector in vectors {
      guard
        case .object(let fields) = vector,
        case .string(let name)? = fields["name"],
        let input = fields["input"],
        case .string(let expected)? = fields["canonical"]
      else {
        return XCTFail("malformed vector entry")
      }
      XCTAssertEqual(
        try canonicalizeJSON(input), expected,
        "canonical bytes diverged from the shared fixture for vector \"\(name)\"")
    }
  }
}
