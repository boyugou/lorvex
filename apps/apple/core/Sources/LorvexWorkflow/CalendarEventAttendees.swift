import Foundation
import LorvexDomain
import LorvexStore

/// Validation + canonical serialization for the Lorvex-native `calendar_events.attendees`
/// column at the trusted local write surface (MCP / UI create + update).
///
/// Attendees are a lightweight annotation, not RSVP/invite state: each entry is a
/// `{name?, email?}` pair with at least one non-empty field. This enum enforces the
/// per-entry hygiene (Unicode-scrub + trim + length cap; no whitespace / control
/// codes in a present email; reject a fully-empty entry) and produces the canonical
/// JSON array stored verbatim in the column. There is no per-attendee identity,
/// PARTSTAT status, dedup, or forward-compat shadow — the column rides the
/// calendar_event aggregate's last-writer-wins sync like any other column.
public enum CalendarEventAttendees {

  /// Validate an attendee list and serialize it to the canonical JSON stored in
  /// `calendar_events.attendees`, or `nil` when the list is empty (NULL = none).
  ///
  /// Each entry is emitted as `{"email": <string, possibly "">, "name"?: <string>}`
  /// with keys sorted canonically. A fully-empty entry (no email AND no name)
  /// throws ``CalendarEventOpError/validation(_:)``.
  public static func serialize(_ attendees: [CalendarAttendeeInput]) throws -> String? {
    if attendees.isEmpty { return nil }
    // Count and per-field caps together bound the attendees column's canonical
    // bytes (PayloadByteBudget's calendar arithmetic), keeping the whole event
    // payload provably under the sync byte cap.
    if attendees.count > PayloadByteBudget.maxCalendarAttendees {
      throw CalendarEventOpError.validation(
        "an event holds at most \(PayloadByteBudget.maxCalendarAttendees) attendees "
          + "(got \(attendees.count))")
    }
    var objects: [JSONValue] = []
    objects.reserveCapacity(attendees.count)
    for attendee in attendees {
      let email = trimWS(UnicodeHygiene.sanitizeUserText(attendee.email))
      if !email.isEmpty {
        if email.unicodeScalars.count > PayloadByteBudget.maxAttendeeFieldLength {
          throw CalendarEventOpError.validation(
            "attendee email exceeds maximum length of "
              + "\(PayloadByteBudget.maxAttendeeFieldLength)")
        }
        if email.unicodeScalars.contains(where: { isWhitespaceOrControl($0) }) {
          throw CalendarEventOpError.validation(
            "attendee email '\(attendee.email)' contains whitespace or "
              + "control characters")
        }
      }

      let name: String? = {
        guard let raw = attendee.name else { return nil }
        let normalized = trimWS(UnicodeHygiene.sanitizeUserText(raw))
        return normalized.isEmpty ? nil : normalized
      }()
      if let n = name, n.unicodeScalars.count > PayloadByteBudget.maxAttendeeFieldLength {
        throw CalendarEventOpError.validation(
          "attendee name exceeds maximum length of "
            + "\(PayloadByteBudget.maxAttendeeFieldLength)")
      }

      if email.isEmpty && name == nil {
        throw CalendarEventOpError.validation(
          "attendee must carry an email or a name")
      }

      var object: [String: JSONValue] = ["email": .string(email)]
      if let name { object["name"] = .string(name) }
      objects.append(.object(object))
    }
    do {
      return try canonicalizeJSON(.array(objects))
    } catch {
      throw CalendarEventOpError.validation(
        "attendees failed canonicalization: \(error)")
    }
  }
}

@inline(__always)
private func trimWS(_ s: String) -> String {
  let scalars = Array(s.unicodeScalars)
  var lo = 0
  var hi = scalars.count
  while lo < hi && scalars[lo].properties.isWhitespace { lo += 1 }
  while hi > lo && scalars[hi - 1].properties.isWhitespace { hi -= 1 }
  return String(String.UnicodeScalarView(scalars[lo..<hi]))
}

@inline(__always)
private func isWhitespaceOrControl(_ s: Unicode.Scalar) -> Bool {
  if s.properties.isWhitespace { return true }
  return s.properties.generalCategory == .control
}
