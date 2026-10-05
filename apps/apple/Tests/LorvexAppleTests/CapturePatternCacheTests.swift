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
    #expect(!LorvexCapturePatterns.isCompiled("(unclosed"))
  }

  @Test("Warming up compiles every pattern the rules of a language read with")
  func warmUpCompilesEveryRulePattern() {
    LorvexCaptureParser.warmUp(languages: ["he"])
    var patterns: [String] = []
    for vocabulary in LorvexCaptureVocabulary.vocabularies(for: ["he"]) {
      patterns += vocabulary.priority.map(\.pattern)
      patterns += vocabulary.dateRange.map(\.pattern)
      patterns += vocabulary.keptInTitle.map(\.pattern)
      patterns += vocabulary.length.map(\.pattern)
      patterns += vocabulary.time.map(\.pattern)
      patterns += vocabulary.repeats.map(\.pattern)
      patterns += vocabulary.due.map(\.pattern)
      patterns += vocabulary.when.map(\.pattern)
    }
    #expect(patterns.count > 20)
    #expect(patterns.allSatisfy { LorvexCapturePatterns.isCompiled($0) })
  }

  @Test("Both stores warm the cache from a background task when they start")
  func storesWarmTheCacheOffTheMainThread() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sources = [
      "Sources/LorvexApple/Stores/AppStoreRuntimeLifecycle.swift",
      "Sources/LorvexMobile/MobileStoreCloudSyncActions.swift",
    ]
    for path in sources {
      let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
      #expect(
        source.contains("Task.detached(priority: .utility) { LorvexCaptureParser.warmUp() }"),
        "\(path) must warm the capture patterns off the main thread")
    }
  }
}
