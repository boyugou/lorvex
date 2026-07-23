import Foundation

/// Canonical RFC 5545 PARTSTAT subset for EventKit provider-event attendees.
///
/// The EventKit ingest path maps each `EKParticipant.participantStatus` onto one
/// of these before serializing the provider attendee list into
/// `provider_calendar_events.attendees_json`. Only the canonical hyphen form
/// `needs-action` is accepted (the underscore variant `needs_action` is rejected,
/// not normalized). The closed 4-value set is an enum so every consumer can
/// exhaustive-match instead of dispatching on canonical strings.
///
/// Lorvex-native `calendar_events.attendees` carries no status — it is a
/// lightweight `{name?, email?}` annotation, not RSVP state.
public enum AttendeeStatus: Sendable, Hashable, CaseIterable, CustomStringConvertible {
  case accepted
  case declined
  case tentative
  case needsAction

  /// Canonical RFC 5545 PARTSTAT spelling stored inside
  /// `provider_calendar_events.attendees_json`.
  public var asString: String {
    switch self {
    case .accepted: return "accepted"
    case .declined: return "declined"
    case .tentative: return "tentative"
    case .needsAction: return "needs-action"
    }
  }

  public var description: String { asString }

  /// Strict parse: only accepts the canonical RFC 5545 wording (the
  /// hyphen form for `needs-action`). Returns `nil` for any other input.
  public static func parseStrict(_ raw: String) -> AttendeeStatus? {
    switch raw {
    case "accepted": return .accepted
    case "declined": return .declined
    case "tentative": return .tentative
    case "needs-action": return .needsAction
    default: return nil
    }
  }

  /// Iterate the canonical 4-value set in stable order.
  public static let all: [AttendeeStatus] = [.accepted, .declined, .tentative, .needsAction]
}

/// Error returned when parsing a non-canonical attendee status.
public struct UnknownAttendeeStatus: Error, Equatable, Sendable, CustomStringConvertible {
  public let value: String
  public init(_ value: String) { self.value = value }
  public var description: String { "unknown attendee status: \(value)" }
}

extension AttendeeStatus {
  /// Strict throwing parse. Throws ``UnknownAttendeeStatus`` for non-canonical input.
  public static func fromString(_ s: String) throws -> AttendeeStatus {
    guard let v = parseStrict(s) else { throw UnknownAttendeeStatus(s) }
    return v
  }
}

/// Canonical attendee `status` values as raw strings, in stable order.
public let attendeeStatusAllowlist: [String] = AttendeeStatus.all.map { $0.asString }

/// Render the allowlist as a stable comma-joined string for validation error wording.
public func attendeeStatusAllowlistDisplay() -> String {
  attendeeStatusAllowlist.joined(separator: ", ")
}
