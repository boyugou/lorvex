/// Structured defer reasons — typed mirror of the frontend `DeferReason`
/// literal union. The `rawValue` (snake_case) keeps the persisted / transmitted
/// bytes byte-identical to the wire-format constants in ``DeferReasonName``.
public enum DeferReason: String, Sendable, Hashable, Codable, CaseIterable, CustomStringConvertible {
  case notToday = "not_today"
  case blocked = "blocked"
  case lowEnergy = "low_energy"
  case needsBreakdown = "needs_breakdown"
  case needsInfo = "needs_info"

  /// Canonical wire-format string.
  public var asString: String { rawValue }

  public var description: String { rawValue }

  /// Parse a wire-format string into a typed defer reason. Returns `nil` for
  /// unknown values.
  public static func parse(_ reason: String) -> DeferReason? {
    DeferReason(rawValue: reason)
  }
}

/// Defer-reason wire-format string constants, mirroring ``DeferReason`` raw values.
public enum DeferReasonName {
  public static let notToday = DeferReason.notToday.rawValue
  public static let blocked = DeferReason.blocked.rawValue
  public static let lowEnergy = DeferReason.lowEnergy.rawValue
  public static let needsBreakdown = DeferReason.needsBreakdown.rawValue
  public static let needsInfo = DeferReason.needsInfo.rawValue

  /// All defer reasons in declaration order.
  public static let allDeferReasons: [String] = [
    notToday,
    blocked,
    lowEnergy,
    needsBreakdown,
    needsInfo,
  ]

  /// Returns `true` if `reason` is a recognized defer reason.
  public static func isValid(_ reason: String) -> Bool {
    allDeferReasons.contains(reason)
  }
}
