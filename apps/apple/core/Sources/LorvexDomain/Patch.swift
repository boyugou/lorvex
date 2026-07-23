/// Three-state PATCH primitive for partial-update payloads.
///
/// Encodes the three update intents a partial patch can carry as a closed sum:
///
/// - ``unset`` — the field was absent from the patch; leave the underlying
///   value untouched.
/// - ``clear`` — the field was explicitly cleared (wire form: JSON `null`).
/// - ``set(_:)`` — the field is set to a new value.
///
/// Wire mapping for a partial-update payload field:
///
/// - missing key in the parent object → ``unset``
/// - `null` → ``clear``
/// - any other value → ``set(_:)``
public enum Patch<T: Sendable>: Sendable {
  /// Field absent from the patch — underlying value untouched.
  case unset
  /// Field explicitly cleared (wire form: JSON `null`).
  case clear
  /// Field set to a new value.
  case set(T)

  /// True iff the patch carries any change (``set`` or ``clear``).
  public var isSetOrClear: Bool {
    switch self {
    case .unset: return false
    case .clear, .set: return true
    }
  }

  /// True iff the patch is ``unset``.
  public var isUnset: Bool {
    if case .unset = self { return true }
    return false
  }

  /// True iff the patch is ``clear``.
  public var isClear: Bool {
    if case .clear = self { return true }
    return false
  }

  /// The inner value when the patch is ``set(_:)``; `nil` otherwise.
  public var value: T? {
    if case let .set(v) = self { return v }
    return nil
  }

  /// SQL-bind helper: `nil` for ``unset`` / ``clear``, `Some(v)` for
  /// ``set(_:)``. Callers gate on
  /// ``isSetOrClear`` first to decide whether to bind, then use this to
  /// extract the value to bind (with `nil` meaning SQL NULL).
  public var asBindValue: T? {
    switch self {
    case .unset, .clear: return nil
    case let .set(v): return v
    }
  }

  /// Map the inner value of a ``set(_:)`` patch through `transform`;
  /// ``unset`` and ``clear`` pass through unchanged.
  public func map<U: Sendable>(_ transform: (T) -> U) -> Patch<U> {
    switch self {
    case .unset: return .unset
    case .clear: return .clear
    case let .set(v): return .set(transform(v))
    }
  }

  /// Throwing variant of ``map(_:)``.
  public func tryMap<U: Sendable>(_ transform: (T) throws -> U) rethrows -> Patch<U> {
    switch self {
    case .unset: return .unset
    case .clear: return .clear
    case let .set(v): return .set(try transform(v))
    }
  }
}

extension Patch: Equatable where T: Equatable {}
extension Patch: Hashable where T: Hashable {}
