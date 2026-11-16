import Foundation

/// Device-local origin of a fully readable calendar event. An absent origin
/// never proves that two cached events came from different calendars.
public struct ProviderCalendarOrigin: Codable, Hashable, Sendable {
  public let calendarID: String
  public let calendarTitle: String
  public let accountTitle: String?
  public let contentSignature: String?

  public init(
    calendarID: String, calendarTitle: String, accountTitle: String? = nil,
    contentSignature: String? = nil
  ) {
    self.calendarID = calendarID
    self.calendarTitle = calendarTitle
    self.accountTitle = accountTitle
    self.contentSignature = contentSignature
  }

  public var encoded: String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
  }

  public static func decode(_ json: String?) -> Self? {
    guard let json, let origin = try? JSONDecoder().decode(Self.self, from: Data(json.utf8)),
      !origin.calendarID.isEmpty
    else { return nil }
    return origin
  }
}

/// A server UID can name copies in several calendars. Qualify imported keys
/// by calendar, while keeping the original UID recoverable for EventKit lookup.
public enum EventKitProviderIdentity {
  public static func key(base: String, calendarID: String) -> String {
    "ek2.\(encode(calendarID)).\(encode(base))"
  }

  public static func components(_ key: String) -> (
    calendarID: String, base: String, suffix: String
  )? {
    let parts = key.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    let fields = parts[0].split(separator: ".", omittingEmptySubsequences: false)
    guard fields.count == 3, fields[0] == "ek2",
      let calendar = decode(String(fields[1])), !calendar.isEmpty,
      let base = decode(String(fields[2])), !base.isEmpty
    else { return nil }
    return (calendar, base, parts.count == 2 ? ":" + parts[1] : "")
  }

  private static func encode(_ text: String) -> String {
    Data(text.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
  }

  private static func decode(_ text: String) -> String? {
    Data(
      base64Encoded: text.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    )
    .flatMap { String(data: $0, encoding: .utf8) }
  }
}
