import XCTest
@testable import LorvexDomain

final class MemoryTests: XCTestCase {

  // MARK: - Memory.normalizeContent

  func testNormalizeContentStripsInvisibleCodepoints() throws {
    // Bidi override + zero-width chars are stripped (content is rendered to the
    // assistant at session start, so a rendering-attack payload must not survive).
    let cleaned = try Memory.normalizeContent("do\u{202E}this\u{200B}now")
    XCTAssertEqual(cleaned, "dothisnow")
  }

  func testNormalizeContentRejectsOverByteCap() {
    // One byte over the cap (ASCII → 1 byte/char) must be rejected so a local
    // write never diverges from what the sync-apply boundary would truncate.
    let overCap = String(repeating: "a", count: Memory.maxMemoryContentLength + 1)
    XCTAssertThrowsError(try Memory.normalizeContent(overCap)) { error in
      guard case ValidationError.tooLong(let field, _, _) = error else {
        return XCTFail("expected tooLong, got \(error)")
      }
      XCTAssertEqual(field, "content")
    }
    let atCap = String(repeating: "a", count: Memory.maxMemoryContentLength)
    XCTAssertEqual(try? Memory.normalizeContent(atCap), atCap)
  }

  // MARK: - normalizeMemoryKey

  func testNormalizeMemoryKeyTrimsStripsInvisiblesAndNfcNormalizes() {
    // "  Cafe\u{0301}.\u{202E}\u{200B}tone  " -> "Café.tone"
    let input = "  Cafe\u{0301}.\u{202E}\u{200B}tone  "
    XCTAssertEqual(Memory.normalizeMemoryKey(input), "Café.tone")
  }

  func testNormalizeMemoryKeyPreservesVisibleCaseAndInternalWhitespace() {
    XCTAssertEqual(
      Memory.normalizeMemoryKey("Project  Alpha"),
      "Project  Alpha",
      "memory keys are structural identifiers; do not casefold or collapse visible spacing"
    )
  }

  // MARK: - regressions

  func testMemoryTruncationSentinelByteCapMatchesConstant() {
    let expected = "exceeded \(Memory.maxMemoryContentLength) byte cap"
    XCTAssertTrue(
      Memory.memoryTruncationSentinel.contains(expected),
      "memoryTruncationSentinel must reference the current maxMemoryContentLength (\(Memory.maxMemoryContentLength)); rendered sentinel was \(Memory.memoryTruncationSentinel.debugDescription)"
    )
  }
}
