import Foundation

/// One IANA time zone as the time zone pickers list it: the city the zone is
/// named for ("Los Angeles"), the region ("America"), the zone's generic name
/// in the user's language ("Pacific Time", "北美太平洋时间"), and its current
/// offset from GMT ("GMT−7").
///
/// The synced `timezone` preference is the calendar-day authority for every
/// device, so the pickers offer a concrete zone, never an "automatic" one that
/// would let each device count days in its own zone.
public struct LorvexTimeZoneChoice: Identifiable, Hashable, Sendable {
  public let identifier: String
  public let city: String
  public let region: String
  public let genericName: String
  public let offsetLabel: String
  /// Seconds from GMT at the moment the choice was built; the list's order.
  public let secondsFromGMT: Int

  public var id: String { identifier }

  /// The choice for `identifier`, or nil when it is not a time zone this
  /// system knows.
  public init?(identifier: String, now: Date = Date(), locale: Locale = .current) {
    guard let zone = TimeZone(identifier: identifier) else { return nil }
    let parts = identifier.split(separator: "/")
    self.identifier = identifier
    self.city = (parts.last.map(String.init) ?? identifier).replacingOccurrences(of: "_", with: " ")
    self.region = parts.count > 1 ? String(parts[0]) : ""
    self.genericName = zone.localizedName(for: .generic, locale: locale) ?? ""
    self.secondsFromGMT = zone.secondsFromGMT(for: now)
    self.offsetLabel = Self.offsetLabel(seconds: secondsFromGMT)
  }

  /// "Los Angeles · GMT−7": how a settings row names the chosen zone.
  public var summary: String { "\(city) · \(offsetLabel)" }

  /// Whether `query` names this zone: a case- and accent-insensitive match on
  /// the city, the region, the generic name, or the identifier. An empty query
  /// matches every zone.
  public func matches(_ query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    return [city, region, genericName, identifier].contains {
      $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }

  /// Every geographic zone the system knows ("Region/City"; bare
  /// abbreviations such as "GMT" are left out) plus "UTC", ordered west to
  /// east by current offset, then by city.
  public static func all(now: Date = Date(), locale: Locale = .current) -> [LorvexTimeZoneChoice] {
    (TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") } + ["UTC"])
      .compactMap { LorvexTimeZoneChoice(identifier: $0, now: now, locale: locale) }
      .sorted {
        ($0.secondsFromGMT, $0.city) < ($1.secondsFromGMT, $1.city)
      }
  }

  /// "GMT", "GMT+8", "GMT−7", or "GMT+5:30" for an offset in seconds, with a
  /// true minus sign.
  public static func offsetLabel(seconds: Int) -> String {
    guard seconds != 0 else { return "GMT" }
    let sign = seconds > 0 ? "+" : "\u{2212}"
    let hours = abs(seconds) / 3600
    let minutes = (abs(seconds) % 3600) / 60
    return minutes == 0 ? "GMT\(sign)\(hours)" : String(format: "GMT%@%d:%02d", sign, hours, minutes)
  }
}
