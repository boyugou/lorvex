import Foundation
import LorvexDomain

/// Static SQL fragments for ``LorvexDomain/ColumnAction``.
///
/// The status-transition truth table in `LorvexDomain.statusTransitionColumns`
/// enumerates a fixed set of metadata columns: `completed_at`,
/// `last_deferred_at`, `last_defer_reason`, `planned_date`, `defer_count`.
/// Callers fold those actions into an UPDATE statement's SET clause by
/// pairing each ``ColumnAction`` with one of these fragments.
///
/// A column outside the closed set is a contract violation between
/// LorvexDomain and LorvexStore: the fallback path asserts in debug builds
/// and produces a defensive `"<col> = ?"` / `"<col> = NULL"` fragment in
/// release builds, with `col` validated as a safe SQL identifier before
/// interpolation.
public enum StatusTransitionSql {
  /// SQL fragment of the form `"<col> = ?"` for one of the status-transition
  /// metadata columns. The caller binds the value at the placeholder.
  public static func setValueFragment(_ col: String) -> String {
    switch col {
    case "completed_at": return "completed_at = ?"
    case "last_deferred_at": return "last_deferred_at = ?"
    case "last_defer_reason": return "last_defer_reason = ?"
    case "planned_date": return "planned_date = ?"
    case "defer_count": return "defer_count = ?"
    default:
      assertionFailure(
        "StatusTransitionSql.setValueFragment: unknown status-transition column \(col); "
          + "add it to the switch above to keep the hot path allocation-free")
      assertSafeSqlIdentifier(col)
      return "\(col) = ?"
    }
  }

  /// SQL fragment of the form `"<col> = NULL"` for one of the
  /// status-transition metadata columns.
  public static func setNullFragment(_ col: String) -> String {
    switch col {
    case "completed_at": return "completed_at = NULL"
    case "last_deferred_at": return "last_deferred_at = NULL"
    case "last_defer_reason": return "last_defer_reason = NULL"
    case "planned_date": return "planned_date = NULL"
    case "defer_count": return "defer_count = NULL"
    default:
      assertionFailure(
        "StatusTransitionSql.setNullFragment: unknown status-transition column \(col); "
          + "add it to the switch above to keep the hot path allocation-free")
      assertSafeSqlIdentifier(col)
      return "\(col) = NULL"
    }
  }

  /// Defensive identifier check used by the fallback paths. Accepts ASCII
  /// alphanumerics and underscore. Anything else aborts via `precondition` —
  /// the fallback path runs only on a domain/store contract drift, so a hard
  /// failure with a typed message is preferable to synthesizing broken SQL.
  private static func assertSafeSqlIdentifier(_ s: String) {
    precondition(!s.isEmpty, "SQL identifier must not be empty")
    for scalar in s.unicodeScalars {
      let v = scalar.value
      let isAlpha = (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v)
      let isDigit = (0x30...0x39).contains(v)
      let isUnderscore = v == 0x5F
      precondition(
        isAlpha || isDigit || isUnderscore,
        "SQL identifier contains disallowed character: \(s)")
    }
  }
}
