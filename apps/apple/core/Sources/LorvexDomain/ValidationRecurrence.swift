/// Recurrence-rule validation: FREQ / BYDAY membership tests and the
/// non-fatal warning enum.
///
/// The full normalizers live in `ValidationRecurrenceNormalize.swift`
/// (``normalizeTaskRecurrence(_:)``, ``normalizeTaskRecurrenceWithWarnings(_:)``,
/// ``normalizeCalendarRecurrence(_:)``); the membership helpers below are the
/// self-contained pieces other surfaces (calendar shorthand wrap, RFC-5545
/// plumbing) consume directly.
public enum ValidationRecurrence {
  /// Valid FREQ values for task recurrence rules.
  static let validRecurrenceFreqs = ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"]

  /// Canonical FREQ allowlist membership test.
  public static func isValidRecurrenceFreq(_ value: String) -> Bool {
    validRecurrenceFreqs.contains(value)
  }

  static let validBydayCodes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

  /// Canonical BYDAY weekday-code membership test (bare two-letter codes).
  public static func isValidBydayCode(_ code: String) -> Bool {
    validBydayCodes.contains(code)
  }

  /// Map an RFC 5545 §3.3.10 BYDAY two-letter code to its Sunday-based weekday
  /// number (`SU = 0`, `MO = 1`, … `SA = 6`). Case-insensitive: the code is
  /// uppercased before matching, so `"mo"` resolves the same as `"MO"`.
  /// Returns `nil` for any token that is not one of the seven canonical codes.
  public static func bydayCodeToSundayNumber(_ code: String) -> UInt32? {
    switch code.uppercased() {
    case "SU": return 0
    case "MO": return 1
    case "TU": return 2
    case "WE": return 3
    case "TH": return 4
    case "FR": return 5
    case "SA": return 6
    default: return nil
    }
  }

  /// Shared cap on `COUNT` for calendar-event recurrence rules. Tasks
  /// intentionally do not cap COUNT; the cap exists for calendar events whose
  /// UI grid renders one row per occurrence.
  public static let maxCalendarRecurrenceCount: Int64 = 365

  /// Validate an RFC 5545 §3.3.10 BYDAY token in the context of a `freq`.
  /// Tokens may carry an optional ordinal prefix `[+-]?[1-9][0-9]?` followed by
  /// a two-letter weekday code (`1MO` = first Monday, `-1FR` = last Friday).
  ///
  /// The absolute-value range depends on `freq`: `MONTHLY` → `1...5`,
  /// `YEARLY` → `1...53`, `WEEKLY` → ordinal prefixes rejected (bare codes
  /// only), any other FREQ → bare codes only. Byte-indexed; weekday codes are
  /// always two ASCII bytes.
  public static func isValidBydayTokenForFreq(_ token: String, freq: String) -> Bool {
    let bytes = Array(token.utf8)
    if bytes.count < 2 {
      return false
    }
    let split = bytes.count - 2
    let prefixBytes = bytes[..<split]
    let codeBytes = bytes[split...]
    guard let code = String(bytes: codeBytes, encoding: .utf8), isValidBydayCode(code) else {
      return false
    }
    if prefixBytes.isEmpty {
      return true
    }
    // RFC 5545: WEEKLY rules cannot carry an ordinal-prefixed BYDAY.
    if freq == "WEEKLY" {
      return false
    }
    var stripped = Array(prefixBytes)
    let first = stripped[0]
    if first == UInt8(ascii: "+") || first == UInt8(ascii: "-") {
      stripped.removeFirst()
    }
    if stripped.isEmpty {
      return false
    }
    // Reject a leading zero (`01MO`).
    if stripped.count > 1 && stripped[0] == UInt8(ascii: "0") {
      return false
    }
    guard let str = String(bytes: stripped, encoding: .utf8), let ord = Int(str) else {
      return false
    }
    let maxOrd: Int
    switch freq {
    case "MONTHLY": maxOrd = 5
    case "YEARLY": maxOrd = 53
    default: return false
    }
    return ord >= 1 && ord <= maxOrd
  }
}

/// A non-fatal observation produced while normalizing a recurrence rule,
/// surfaced alongside a valid rule so the apply / export pipeline can warn that
/// a technically-valid rule will silently skip months or fire rarely.
public enum RecurrenceWarning: Sendable, Equatable {
  /// `FREQ=MONTHLY;BYMONTHDAY=29|30|31` skips months whose last day is before
  /// the requested day-of-month. Carries the canonical day.
  case bymonthdaySkipsMonths(day: Int64)
  /// `FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29` — fires only on Feb 29 of leap
  /// years (skipping 2100/2200/2300 under the Gregorian century rule).
  case leapYearBirthday
}
