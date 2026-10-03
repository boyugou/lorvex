import Foundation
import Testing

@testable import LorvexCore

/// The capture parser compiles each pattern once and reuses it on every later
/// parse, since a capture field parses its line on every keystroke.
@Suite("Capture pattern cache")
struct CapturePatternCacheTests {
  @Test("A pattern compiles once, and the same expression serves every later use")
  func compilesOnce() throws {
    let first = try #require(LorvexCapturePatterns.regex(#"\d+ ?min"#))
    let second = try #require(LorvexCapturePatterns.regex(#"\d+ ?min"#))
    #expect(first === second)
    #expect(first.options.contains(.caseInsensitive))
  }

  @Test("A pattern that does not compile reads as nil")
  func invalidPattern() {
    #expect(LorvexCapturePatterns.regex("(unclosed") == nil)
  }
}
