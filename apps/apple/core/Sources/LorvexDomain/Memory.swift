import Foundation

/// Memory entity value types: key normalization and content cap.
///
/// `normalizeMemoryKey(_:)` is a persisted/synced natural-key gate — its
/// byte output is a stable wire contract:
/// sanitize (strip invisibles + NFC) → trim boundary whitespace. It
/// intentionally does NOT casefold, NFKC-normalize, or collapse internal
/// visible whitespace; memory keys are structural identifiers.
public enum Memory {
  /// Maximum length (in bytes) of a memory entry's content. Enforced at
  /// MCP write time and on sync apply.
  public static let maxMemoryContentLength: Int = 100_000

  /// Suffix appended to memory content that exceeded
  /// `maxMemoryContentLength` on sync apply. The byte-cap literal is
  /// formatted from `maxMemoryContentLength` so a future cap change
  /// updates the sentinel automatically.
  public static let memoryTruncationSentinel: String =
    "\n\n... [truncated by receiver: exceeded \(maxMemoryContentLength) byte cap]"

  /// Normalize a memory key for machine equality.
  ///
  /// Pipeline:
  ///   1. `UnicodeHygiene.sanitizeUserText` — strip disallowed invisible
  ///      / formatting controls, then NFC normalize.
  ///   2. Trim leading / trailing whitespace.
  ///
  /// Casefolding, NFKC, and internal whitespace collapse are intentionally
  /// omitted; memory keys are structural natural keys.
  public static func normalizeMemoryKey(_ key: String) -> String {
    let sanitized = UnicodeHygiene.sanitizeUserText(key)
    return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Sanitize memory content and enforce the byte cap.
  ///
  /// Strips invisible / formatting controls and NFC-normalizes (memory content
  /// is rendered to the assistant at session start, so a bidi / zero-width
  /// payload must never survive), then rejects content whose sanitized UTF-8
  /// length exceeds ``maxMemoryContentLength``. Every local memory write path
  /// (upsert, rename, import) funnels through this so stored content is provably
  /// clean and within the cap the sync-apply boundary would otherwise silently
  /// truncate — keeping the writer's row identical to what peers receive.
  public static func normalizeContent(_ content: String) throws -> String {
    let sanitized = UnicodeHygiene.sanitizeUserText(content)
    let bytes = sanitized.utf8.count
    if bytes > maxMemoryContentLength {
      throw ValidationError.tooLong(
        field: "content", max: maxMemoryContentLength, actual: bytes)
    }
    return sanitized
  }
}
