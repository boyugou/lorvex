import Foundation
import Synchronization

/// The capture parser's patterns, each compiled once per process.
///
/// A capture field parses its line on every keystroke, and each parse tries
/// every rule of every vocabulary the user reads, so compiling the patterns on
/// each parse would be most of its cost. Every pattern is fixed text from a
/// vocabulary (no user text is ever part of one), so the cache holds one
/// compiled expression per rule and stops growing once each has been used.
/// `NSRegularExpression` is immutable and may match from any thread.
enum LorvexCapturePatterns {
  private static let compiled = Mutex<[String: NSRegularExpression]>([:])

  /// `pattern` compiled to match without regard to case, or nil when it does
  /// not compile.
  static func regex(_ pattern: String) -> NSRegularExpression? {
    if let regex = compiled.withLock({ $0[pattern] }) { return regex }
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    compiled.withLock { $0[pattern] = regex }
    return regex
  }

  /// Whether `pattern` is already compiled, which tells a warmed cache
  /// (``LorvexCaptureParser/warmUp(languages:)``) from a cold one.
  static func isCompiled(_ pattern: String) -> Bool {
    compiled.withLock { $0[pattern] != nil }
  }
}
