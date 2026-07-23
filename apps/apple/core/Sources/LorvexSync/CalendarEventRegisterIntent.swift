import Foundation
import LorvexDomain

/// Device-local provenance describing which independent register a queued
/// base calendar-event Upsert actually changed.
///
/// The value is persisted beside the outbox row but never enters the sync wire.
/// It lets snapshot and future-record recovery replay the user's edited group
/// over the newly adopted baseline without re-authoring stale fields from the
/// other register.
public struct CalendarEventRegisterIntent: OptionSet, Sendable, Equatable, Hashable {
  public let rawValue: Int64

  public init(rawValue: Int64) {
    self.rawValue = rawValue
  }

  public static let content = CalendarEventRegisterIntent(rawValue: 1 << 0)
  public static let topology = CalendarEventRegisterIntent(rawValue: 1 << 1)
  public static let all: CalendarEventRegisterIntent = [.content, .topology]

  /// Infer the changed base-event register from a canonical post-workflow row.
  /// Calendar workflows stamp the row and every changed register with the same
  /// HLC before the outbox layer gives the envelope its transport successor.
  /// Occurrence decisions deliberately own neither register.
  public static func inferredLocalMutation(from payload: JSONValue) -> Self {
    guard case .object(let object) = payload, isBasePayloadObject(object),
      case .string(let rowVersion)? = object["version"]
    else { return [] }

    var result: Self = []
    if case .string(rowVersion)? = object["content_version"] {
      result.insert(.content)
    }
    if case .string(rowVersion)? = object["recurrence_topology_version"] {
      result.insert(.topology)
    }
    return result
  }

  static func isBasePayload(_ payload: String) -> Bool {
    guard case .object(let object)? = JSONValue.parse(payload) else { return false }
    return isBasePayloadObject(object)
  }

  /// Retain only provenance whose authored register is still represented by
  /// the replacement payload. Row-level coalescing may replace one register
  /// with a remote convergence winner while leaving the other untouched, so a
  /// bit survives only when that register's clock and every known field match.
  func retainingUnchangedRegisters(
    existingPayload: String, replacementPayload: String
  ) -> Self {
    guard !isEmpty,
      case .object(let existing)? = JSONValue.parse(existingPayload),
      case .object(let replacement)? = JSONValue.parse(replacementPayload),
      Self.isBasePayloadObject(existing), Self.isBasePayloadObject(replacement)
    else { return [] }

    var retained: Self = []
    if contains(.content),
      CalendarEventRegisterDescriptor.snapshotsMatch(
        keys: CalendarEventRegisterDescriptor.contentSnapshotKeys,
        lhs: existing, rhs: replacement)
    {
      retained.insert(.content)
    }
    if contains(.topology),
      CalendarEventRegisterDescriptor.snapshotsMatch(
        keys: CalendarEventRegisterDescriptor.topologySnapshotKeys,
        lhs: existing, rhs: replacement)
    {
      retained.insert(.topology)
    }
    return retained
  }

  private static func isBasePayloadObject(_ object: [String: JSONValue]) -> Bool {
    switch object["series_id"] {
    case nil, .some(.null): return true
    default: return false
    }
  }
}
