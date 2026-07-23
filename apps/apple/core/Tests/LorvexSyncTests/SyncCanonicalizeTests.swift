import LorvexDomain
import XCTest

@testable import LorvexSync

/// Ports `lorvex-sync/src/canonicalize/tests.rs`. The byte output must be
/// identical to the domain canonicalizer (verified separately for byte parity
/// with Rust) plus the sync byte cap.
final class SyncCanonicalizeTests: XCTestCase {
  private func canon(_ value: JSONValue) -> String {
    try! SyncCanonicalize.canonicalizeJSON(value)
  }

  private func parse(_ s: String) -> JSONValue {
    JSONValue.parse(s)!
  }

  func testIdenticalPayloadsDifferentKeyOrderProduceSameOutput() {
    let a = #"{"title":"Buy milk","status":"open","priority":2}"#
    let b = #"{"priority":2,"status":"open","title":"Buy milk"}"#
    XCTAssertEqual(canon(parse(a)), canon(parse(b)))
  }

  func testSortedKeysInOutput() {
    XCTAssertEqual(
      canon(.object(["z": .int(1), "a": .int(2), "m": .int(3)])),
      #"{"a":2,"m":3,"z":1}"#)
  }

  func testNestedObjectsSortedRecursively() {
    let v: JSONValue = .object([
      "outer_b": .object(["inner_z": .int(1), "inner_a": .int(2)]),
      "outer_a": .string("value"),
    ])
    XCTAssertEqual(canon(v), #"{"outer_a":"value","outer_b":{"inner_a":2,"inner_z":1}}"#)
  }

  func testArraysPreserveElementOrder() {
    XCTAssertEqual(canon(.object(["items": .array([.int(3), .int(1), .int(2)])])), #"{"items":[3,1,2]}"#)
  }

  func testArraysOfObjectsSortedRecursively() {
    let v: JSONValue = .object([
      "tasks": .array([
        .object(["z_field": .string("last"), "a_field": .string("first")]),
        .object(["b": .int(2), "a": .int(1)]),
      ])
    ])
    XCTAssertEqual(
      canon(v), #"{"tasks":[{"a_field":"first","z_field":"last"},{"a":1,"b":2}]}"#)
  }

  func testCompactFormatNoTrailingWhitespace() {
    let result = canon(.object(["key": .string("value")]))
    XCTAssertFalse(result.hasSuffix(" "))
    XCTAssertFalse(result.hasSuffix("\n"))
    XCTAssertFalse(result.hasSuffix("\t"))
    XCTAssertEqual(result, #"{"key":"value"}"#)
  }

  func testNullValuesPreserved() {
    XCTAssertEqual(canon(.object(["a": .null, "b": .string("present")])), #"{"a":null,"b":"present"}"#)
  }

  func testBooleanValues() {
    XCTAssertEqual(
      canon(.object(["done": .bool(true), "active": .bool(false)])), #"{"active":false,"done":true}"#)
  }

  func testEmptyObject() {
    XCTAssertEqual(canon(.object([:])), "{}")
  }

  func testEmptyArray() {
    XCTAssertEqual(canon(.array([])), "[]")
  }

  func testScalarString() {
    XCTAssertEqual(canon(.string("hello")), #""hello""#)
  }

  func testScalarNumber() {
    XCTAssertEqual(canon(.int(42)), "42")
  }

  func testStringValuesPreservedByteForByte() {
    // Build the NFD form from explicit scalars (`e` + combining acute) and the
    // NFC form from the precomposed scalar. Swift `String` literal equality is
    // canonical, so we compare the raw UTF-8 byte sequences directly to prove
    // canonicalizeJSON does not rewrite (NFC-normalize) user content.
    var decomposedView = String.UnicodeScalarView()
    decomposedView.append(contentsOf: "caf".unicodeScalars)
    decomposedView.append(Unicode.Scalar(0x0065)!)  // e
    decomposedView.append(Unicode.Scalar(0x0301)!)  // combining acute
    let decomposed = String(decomposedView)
    let precomposed = "caf\u{00E9}"  // NFC

    let a = canon(.object(["name": .string(decomposed)]))
    let b = canon(.object(["name": .string(precomposed)]))
    XCTAssertNotEqual(
      Array(a.utf8), Array(b.utf8),
      "canonicalization must not rewrite string values — user content preserved byte-for-byte")
  }

  func testDeeplyNestedStructure() {
    let v: JSONValue = .object([
      "level1": .object([
        "z": .object(["deep_z": .int(1), "deep_a": .int(2)]),
        "a": .object(["items": .array([.object(["c": .int(3), "b": .int(2), "a": .int(1)])])]),
      ])
    ])
    XCTAssertEqual(
      canon(v),
      #"{"level1":{"a":{"items":[{"a":1,"b":2,"c":3}]},"z":{"deep_a":2,"deep_z":1}}}"#)
  }

  func testIdempotent() {
    let first = canon(.object(["b": .int(2), "a": .int(1)]))
    let second = canon(parse(first))
    XCTAssertEqual(first, second)
  }

  func testRejectsExcessivelyDeepNesting() {
    var v: JSONValue = .null
    for _ in 0..<35 {
      v = .object(["n": v])
    }
    XCTAssertThrowsError(try SyncCanonicalize.canonicalizeJSON(v)) { error in
      XCTAssertEqual(error as? SyncCanonicalize.SyncCanonError, .depthExceeded)
    }
  }

  func testAcceptsNestingAtCap() {
    var v: JSONValue = .string("leaf")
    for _ in 0..<(SyncCanonicalize.maxJSONDepth - 1) {
      v = .object(["n": v])
    }
    XCTAssertNoThrow(try SyncCanonicalize.canonicalizeJSON(v))
  }

  func testRejectsPayloadAboveByteCap() {
    let bigString = String(repeating: "x", count: SyncCanonicalize.maxCanonicalPayloadBytes + 1024)
    XCTAssertThrowsError(try SyncCanonicalize.canonicalizeJSON(.object(["body": .string(bigString)]))) {
      error in
      guard case .payloadTooLarge(let sizeBytes) = error as? SyncCanonicalize.SyncCanonError else {
        return XCTFail("expected payloadTooLarge, got \(error)")
      }
      XCTAssertGreaterThan(sizeBytes, SyncCanonicalize.maxCanonicalPayloadBytes)
    }
  }

  func testRejectsPayloadWithManyFlatKeys() {
    var map: [String: JSONValue] = [:]
    for i in 0..<50_000 {
      map[String(format: "key_%08d", i)] = .int(Int64(i))
    }
    XCTAssertThrowsError(try SyncCanonicalize.canonicalizeJSON(.object(map))) { error in
      guard case .payloadTooLarge = error as? SyncCanonicalize.SyncCanonError else {
        return XCTFail("expected payloadTooLarge, got \(error)")
      }
    }
  }

  func testAcceptsPayloadAtByteCap() {
    let bodyLen = SyncCanonicalize.maxCanonicalPayloadBytes - 12
    let body = String(repeating: "x", count: bodyLen)
    XCTAssertNoThrow(try SyncCanonicalize.canonicalizeJSON(.object(["body": .string(body)])))
  }

  /// Byte-parity exercise of every escape category the streaming writer
  /// hand-rolls, mixed with multi-byte UTF-8 that must pass through untouched.
  /// Asserts the canonical output is exactly the expected byte string and that
  /// every `\u` escape uses lowercase hex.
  func testByteParityAcrossEveryEscapeCategory() {
    let payload: JSONValue = .object([
      "z_emoji_\u{1F389}_key": .string("tail value"),
      "a_ctrl_key_with_\u{0001}_inside": .string("value with \u{0008} backspace and \u{000C} form-feed"),
      "m_\u{4E2D}\u{6587}_key_\u{00E9}": .object([
        "items": .array([
          .object([
            "z": .string(#"embedded "quote" and \backslash\"#),
            "a": .string("newline\nreturn\rtab\there"),
          ]),
          .object([
            "ctrl_low": .string("\u{0000}\u{0001}\u{0002}\u{0008}\u{000A}\u{000C}\u{000D}\u{001F}"),
            "astral": .string("rocket \u{1F680} and \u{4E2D}\u{6587} mixed with \u{00E9}"),
          ]),
        ]),
        "boundary_0x1f": .string("\u{001F}"),
        "boundary_0x20": .string("\u{0020}"),
      ]),
      "scalars": .array([.null, .bool(true), .bool(false), .int(0), .int(-1), .int(42), .double(3.25)]),
    ])

    let output = canon(payload)

    // Every `\u` escape must use lowercase hex.
    let bytes = Array(output.utf8)
    var idx = 0
    var sawUnicodeEscape = false
    while idx + 6 <= bytes.count {
      if bytes[idx] == 0x5C && bytes[idx + 1] == 0x75 {  // "\u"
        sawUnicodeEscape = true
        for off in 2..<6 {
          let c = bytes[idx + off]
          let isLowerHex = (0x30...0x39).contains(c) || (0x61...0x66).contains(c)
          XCTAssertTrue(isLowerHex, "expected lowercase hex in \\u escape at byte \(idx)")
        }
        idx += 6
      } else {
        idx += 1
      }
    }
    XCTAssertTrue(sawUnicodeEscape, "payload must exercise at least one \\u escape")

    // Round-trip must be stable (idempotent through parse + re-canon).
    XCTAssertEqual(canon(parse(output)), output)
  }

  func testRejectsExcessivelyDeepArrayNesting() {
    var v: JSONValue = .string("leaf")
    for _ in 0..<40 {
      v = .array([v])
    }
    XCTAssertThrowsError(try SyncCanonicalize.canonicalizeJSON(v)) { error in
      XCTAssertEqual(error as? SyncCanonicalize.SyncCanonError, .depthExceeded)
    }
  }
}
