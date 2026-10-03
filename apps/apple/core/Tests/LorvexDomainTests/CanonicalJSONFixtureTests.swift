import XCTest

@testable import LorvexDomain

/// Drives the canonical-JSON serializer with the language-neutral vectors
/// committed at `spec/fixtures/canonical-json/vectors.json`. Sync checksums
/// are computed over canonical bytes, so every app version must reproduce
/// these strings byte-for-byte. Unlike the cases in `CanonicalJSONTests`, the
/// vectors live outside the implementation, so a serializer change cannot
/// move its expected outputs along with it.
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
