import XCTest
@testable import LorvexDomain

/// The canonical bytes sync checksums are computed over: sorted keys, no
/// insignificant whitespace, and the escape table below. Each case pins the
/// exact output, so a serializer change that would move a checksum fails here.
final class CanonicalJSONTests: XCTestCase {
  private func canon(_ value: JSONValue) throws -> String {
    try canonicalizeJSON(value)
  }

  func testSortedKeysInOutput() throws {
    let v: JSONValue = ["z": 1, "a": 2, "m": 3]
    XCTAssertEqual(try canon(v), #"{"a":2,"m":3,"z":1}"#)
  }

  func testNestedObjectsSortedRecursively() throws {
    let v: JSONValue = ["outer_b": ["inner_z": 1, "inner_a": 2], "outer_a": "value"]
    XCTAssertEqual(try canon(v), #"{"outer_a":"value","outer_b":{"inner_a":2,"inner_z":1}}"#)
  }

  func testArraysPreserveOrder() throws {
    let v: JSONValue = ["items": [3, 1, 2]]
    XCTAssertEqual(try canon(v), #"{"items":[3,1,2]}"#)
  }

  func testDepthOverflowErrorsCleanly() {
    var nested: JSONValue = 0
    for _ in 0..<maxJSONDepth {
      nested = .array([nested])
    }
    XCTAssertThrowsError(try canonicalizeJSON(nested)) { error in
      XCTAssertEqual(error as? CanonError, .depthExceeded)
    }
  }

  func testDepthAtBoundaryCanonicalizesSuccessfully() throws {
    var nested: JSONValue = 0
    for _ in 0..<(maxJSONDepth - 1) {
      nested = .array([nested])
    }
    XCTAssertNoThrow(try canonicalizeJSON(nested))
  }

  func testNonFiniteDoubleThrowsInsteadOfEmittingInvalidToken() {
    // A non-finite .double can only arise from a hand-built value (the parser
    // rejects overflow literals). Emitting the bare tokens "inf"/"nan" would
    // produce unparseable, non-round-tripping JSON, so canonicalization throws.
    for d in [Double.infinity, -Double.infinity, Double.nan] {
      XCTAssertThrowsError(try canonicalizeJSON(.double(d))) { error in
        XCTAssertEqual(error as? CanonError, .nonFiniteDouble)
      }
    }
  }

  func testParityWithSyncLayerForSimplePayload() throws {
    let v: JSONValue = ["title": "Buy milk", "status": "open", "priority": 2]
    XCTAssertEqual(try canon(v), #"{"priority":2,"status":"open","title":"Buy milk"}"#)
  }

  // MARK: - Escape table: short escapes for tab, newline, return, backspace,
  // form feed, quote, and backslash; lowercase \u00xx for other control
  // characters; everything else, non-ASCII included, written as is.

  func testControlCharacterEscapes() throws {
    let v: JSONValue = .string("a\tb\nc\rd\u{08}e\u{0c}f\"g\\h")
    XCTAssertEqual(try canon(v), #""a\tb\nc\rd\be\ff\"g\\h""#)
  }

  func testLowControlCharEscapedAsLowercaseHex() throws {
    let v: JSONValue = .string("\u{01}\u{1f}")
    XCTAssertEqual(try canon(v), #""\u0001\u001f""#)
  }

  func testNonASCIIPassesThroughUnescaped() throws {
    let v: JSONValue = .string("café — 日本語")
    XCTAssertEqual(try canon(v), "\"café — 日本語\"")
  }

  func testUTF8ByteOrderedKeySort() throws {
    // 'Z' (0x5A) sorts before 'a' (0x61) by UTF-8 bytes; a Unicode-collated
    // sort would place them differently.
    let v: JSONValue = ["a": 1, "Z": 2, "A": 3]
    XCTAssertEqual(try canon(v), #"{"A":3,"Z":2,"a":1}"#)
  }
}
