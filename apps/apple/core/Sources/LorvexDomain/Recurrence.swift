/// Recurrence instance key generation for successor identity validation.
///
/// When a recurring task is completed and a successor is spawned, the successor
/// receives an immutable recurrence instance key. Current runtimes also derive
/// the same deterministic UUIDv8 successor identity from the parent + group on
/// every device. The instance key is the independently validated natural
/// identity; a different task id claiming the same key is rejected.
///
/// Key format: `"{recurrenceGroupID}:{canonicalOccurrenceDate}"` where
/// `canonicalOccurrenceDate` is the RRULE-computed date (`YYYY-MM-DD`), NOT the
/// user-editable planned date.
public enum Recurrence {
  /// Generate a recurrence instance key for a spawned successor task.
  ///
  /// The key is immutable after creation and validated at every write boundary. Its
  /// format is `"{recurrenceGroupID}:{canonicalOccurrenceDate}"`.
  ///
  /// Returns `nil` for empty `recurrenceGroupID`, for any group-id byte that
  /// would corrupt downstream `LIKE` / exact-match queries built from the key —
  /// the separator `:`, ASCII whitespace, ASCII control bytes, or the SQL `LIKE`
  /// wildcards `%` / `_` — or for a `canonicalOccurrenceDate` that is not a
  /// fixed-width zero-padded `YYYY-MM-DD` naming a real calendar date.
  public static func generateInstanceKey(
    recurrenceGroupID: String,
    canonicalOccurrenceDate: String
  ) -> String? {
    if recurrenceGroupID.isEmpty {
      return nil
    }
    for b in recurrenceGroupID.utf8 {
      if b == UInt8(ascii: ":") || isAsciiWhitespace(b) || isAsciiControl(b)
        || b == UInt8(ascii: "%") || b == UInt8(ascii: "_")
      {
        return nil
      }
    }
    if !isCanonicalYMD(canonicalOccurrenceDate) {
      return nil
    }
    return "\(recurrenceGroupID):\(canonicalOccurrenceDate)"
  }

  /// Gate the canonical 10-char zero-padded `YYYY-MM-DD` shape up front (the
  /// fixed width downstream `LIKE` / exact-match queries depend on), then defer
  /// to ``IsoDate/parse(_:)`` for month/day range + leap-year validation so
  /// semantically bogus values like `2026-13-99` are rejected.
  static func isCanonicalYMD(_ s: String) -> Bool {
    let bytes = Array(s.utf8)
    guard bytes.count == 10 else { return false }
    guard bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else { return false }
    return IsoDate.parse(s) != nil
  }

  /// ASCII whitespace: TAB, LF, FF, CR, SPACE. Note this
  /// excludes vertical tab (0x0B).
  static func isAsciiWhitespace(_ b: UInt8) -> Bool {
    b == 0x09 || b == 0x0A || b == 0x0C || b == 0x0D || b == 0x20
  }

  /// ASCII control bytes: `0x00...0x1F` plus DEL (`0x7F`).
  static func isAsciiControl(_ b: UInt8) -> Bool {
    b < 0x20 || b == 0x7F
  }
}
