/// SQL identifier safety guard — defense-in-depth for string-interpolated SQL
/// identifiers.
public enum ValidationSQL {
  /// Returns `true` when `s` is a safe SQL identifier (table or column name):
  /// non-empty and composed only of ASCII alphanumerics and underscores.
  ///
  /// An invalid identifier at an interpolation site is always a programming
  /// error, not user input. Swift's `precondition` aborts
  /// the process (uncatchable by tests), so the boolean predicate is exposed
  /// directly and ``assertSafeSQLIdentifier(_:)`` wraps it for call sites that
  /// want the abort.
  public static func isSafeSQLIdentifier(_ s: String) -> Bool {
    !s.isEmpty
      && s.unicodeScalars.allSatisfy { c in
        let v = c.value
        let isAlnum =
          (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A)
        return isAlnum || c == "_"
      }
  }

  /// Abort the process if `s` is not a safe SQL identifier; use
  /// ``isSafeSQLIdentifier(_:)`` where a recoverable check is wanted.
  public static func assertSafeSQLIdentifier(
    _ s: String, file: StaticString = #fileID, line: UInt = #line
  ) {
    precondition(
      isSafeSQLIdentifier(s),
      "invalid SQL identifier: \"\(s)\" — only ASCII alphanumeric and underscore are allowed",
      file: file, line: line)
  }
}
