import XCTest

@testable import LorvexDomain

/// Guards on ``JSONValue/parse(_:)``'s two foundational safety properties:
///
/// 1. A recursion-depth bound aligned with ``maxJSONDepth`` (the writer's cap):
///    the parser must not accept input nested deeper than ``canonicalizeJSON(_:)``
///    can re-emit, and must reject over-deep input by returning `nil` rather than
///    overflowing the thread stack.
/// 2. Numeric-literal finiteness: a literal that overflows `Double` to `inf`
///    (`1e999`) is rejected, matching serde_json, so the two cores converge on
///    the same wire bytes. A finite in-range double still parses and round-trips.
final class JSONParseTests: XCTestCase {

  /// Build `[[…n…0…]]`: a single scalar `0` wrapped in `n` arrays, so the
  /// innermost scalar sits at nesting depth `n`.
  private func nestedArrays(depth n: Int) -> String {
    String(repeating: "[", count: n) + "0" + String(repeating: "]", count: n)
  }

  // MARK: - BUG 1: recursion-depth guard

  /// One level under the cap round-trips through both parser and writer: the
  /// parser accepts it and the writer re-emits it byte-identically, upholding
  /// "anything the parser accepts, canonicalizeJSON can serialize."
  func testParseOneUnderDepthCapRoundTrips() throws {
    let input = nestedArrays(depth: maxJSONDepth - 1)
    guard let value = JSONValue.parse(input) else {
      return XCTFail("input one level under the depth cap must parse")
    }
    // The writer accepts exactly what the parser accepts, byte-for-byte.
    XCTAssertEqual(try canonicalizeJSON(value), input)
  }

  /// Input nested exactly at the writer's cap boundary is rejected by the parser
  /// (returns `nil`), mirroring the writer, which throws ``CanonError/depthExceeded``
  /// for the same hand-built value.
  func testParseAtDepthCapRejected() {
    let input = nestedArrays(depth: maxJSONDepth)
    XCTAssertNil(
      JSONValue.parse(input),
      "input nested at the writer's cap must be rejected, not accepted")

    // The reject boundary matches the writer: the same shape hand-built throws.
    var built: JSONValue = 0
    for _ in 0..<maxJSONDepth { built = .array([built]) }
    XCTAssertThrowsError(try canonicalizeJSON(built)) { error in
      XCTAssertEqual(error as? CanonError, .depthExceeded)
    }
  }

  /// The key regression: input nested thousands of levels deep returns `nil`
  /// promptly instead of overflowing the stack and crashing the process. This
  /// test only completes because the depth guard bails out near the cap.
  func testParseVeryDeeplyNestedReturnsNilWithoutCrashing() {
    let input = String(repeating: "[", count: 80_000)
    XCTAssertNil(JSONValue.parse(input))
    // Well-formed (balanced) deep nesting is likewise rejected without crashing.
    XCTAssertNil(JSONValue.parse(nestedArrays(depth: 80_000)))
  }

  // MARK: - BUG 2: non-finite / overflow numeric literals

  /// A numeric literal that overflows `Double` to a non-finite value is rejected
  /// (returns `nil`), matching serde_json — the identical wire bytes must not
  /// parse to `inf` on Swift while failing on Rust.
  func testParseOverflowLiteralsRejected() {
    for literal in ["1e999", "-1e999", "1e309"] {
      XCTAssertNil(JSONValue.parse(literal), "overflow literal \(literal) must be rejected")
    }
  }

  /// A finite in-range double still parses and round-trips stably: parsing,
  /// canonicalizing, and re-parsing yields the same value and the same bytes.
  /// This is the over-rejection guard — the finiteness check must not reject
  /// legitimate doubles including the extremes of the representable range.
  func testFiniteDoublesRoundTripStably() throws {
    for literal in ["0.1", "1e16", "1.7976931348623157e308", "5e-324"] {
      guard let v0 = JSONValue.parse(literal) else {
        XCTFail("finite double \(literal) must parse")
        continue
      }
      guard case .double(let d) = v0, d.isFinite else {
        XCTFail("literal \(literal) must parse to a finite .double")
        continue
      }
      let bytes0 = try canonicalizeJSON(v0)
      let v1 = JSONValue.parse(bytes0)
      XCTAssertEqual(v1, v0, "value drifted on round-trip for \(literal)")
      XCTAssertEqual(try canonicalizeJSON(v1 ?? .null), bytes0, "bytes drifted for \(literal)")
    }
  }
}
