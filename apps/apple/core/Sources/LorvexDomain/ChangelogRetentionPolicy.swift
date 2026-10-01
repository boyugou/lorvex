/// User-configurable retention policy for this device's `ai_changelog` audit
/// trail, exposed as the JSON value of the virtual preference
/// ``PreferenceKeys/prefAiChangelogRetentionPolicy``. The audit trail never
/// leaves the device, so the durable value lives in the device-local
/// `device_state` table, never in an ordinary synced `preferences` row.
///
/// Three states, chosen so an assistant inspecting `get_all_preferences` sees a
/// self-documenting token rather than a sentinel integer:
///
/// - ``maximum``: keep up to the absolute row-count safeguard
///   (``SyncNaming/auditMaxEntriesSafeguard``).
/// - ``days(_:)``: keep entries newer than `N` days (`N > 0`).
/// - ``off``: never store — new audit writes are suppressed at the mutation
///   choke point and every existing row is purged.
///
/// The API/wire value is JSON text: the string `"maximum"` / `"off"`, or a bare
/// positive integer number of days. ``parse(_:)`` is deliberately tolerant so an
/// absent, malformed, or unrecognized value degrades to ``maximum`` (never a
/// silent purge). No legacy token aliases are recognized. ``wireValue`` is the
/// canonical form written back and
/// round-trips through ``parse(_:)``.
public enum ChangelogRetentionPolicy: Equatable, Sendable {
  case maximum
  case days(UInt32)
  case off
}

extension ChangelogRetentionPolicy {
  /// Parse the JSON API value of
  /// ``PreferenceKeys/prefAiChangelogRetentionPolicy``.
  ///
  /// Tolerant by design — no ambiguous input ever yields a purge:
  /// - `nil` / empty / whitespace / malformed / JSON `null` / unrecognized
  ///   string → ``maximum``
  /// - JSON string `"maximum"` → ``maximum``
  /// - JSON string `"off"` → ``off``
  /// - JSON number `N > 0` that fits `UInt32` → ``days(_:)``
  ///   (out-of-range → ``maximum``)
  /// - JSON number `N <= 0` → ``maximum``
  public static func parse(_ rawJSON: String?) -> ChangelogRetentionPolicy {
    parseStrict(rawJSON) ?? .maximum
  }

  /// Parse an explicit write value without applying the fail-safe default.
  ///
  /// Durable reads use ``parse(_:)`` because corruption must never trigger a
  /// purge. Product write surfaces use this strict variant so a typo cannot be
  /// silently accepted as `maximum` while reporting the requested write as a
  /// success.
  public static func parseStrict(_ rawJSON: String?) -> ChangelogRetentionPolicy? {
    guard let rawJSON, let value = JSONValue.parse(rawJSON) else { return nil }
    switch value {
    case .string(let token):
      switch token {
      case "maximum": return .maximum
      case "off": return .off
      default: return nil
      }
    case .int(let n):
      return dayCountPolicyStrict(n)
    case .uint:
      // A literal exceeding Int64.max cannot fit UInt32 either.
      return nil
    case .double(let d):
      guard d.isFinite, d > 0 else { return nil }
      // `UInt32(exactly:)` yields the day count only for a whole in-range value;
      // a fractional or out-of-range double is rejected (no trap).
      return UInt32(exactly: d).map { .days($0) }
    default:
      // null, bool, array, object.
      return nil
    }
  }

  private static func dayCountPolicyStrict(_ n: Int64) -> ChangelogRetentionPolicy? {
    guard n > 0, let days = UInt32(exactly: n) else { return nil }
    return .days(days)
  }

  /// Canonical JSON text for this policy. It round-trips through ``parse(_:)``
  /// and is returned by the virtual preference read surface.
  public var wireValue: String {
    switch self {
    case .maximum: return "\"maximum\""
    case .off: return "\"off\""
    case .days(let n): return String(n)
    }
  }
}
