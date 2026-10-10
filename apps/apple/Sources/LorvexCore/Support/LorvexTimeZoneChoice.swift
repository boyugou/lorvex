import Foundation

/// One IANA time zone as the time zone pickers list it, named in the user's
/// language: the city the zone is named for ("Los Angeles", "洛杉矶"), the
/// zone's generic name ("Pacific Time", "北美太平洋时间"), and its current
/// offset from GMT in the locale's own form ("GMT-7"; French writes "UTC−7").
///
/// The synced `timezone` preference is the calendar-day authority for every
/// device, so the pickers offer a concrete zone, never an "automatic" one that
/// would let each device count days in its own zone.
public struct LorvexTimeZoneChoice: Identifiable, Hashable, Sendable {
  public let identifier: String
  /// The zone's city in the user's language (CLDR's exemplar city), or the
  /// identifier's own spelling for a zone CLDR names no city for; "UTC" for UTC.
  public let city: String
  /// The city as the identifier spells it ("Los Angeles" for
  /// "America/Los_Angeles"), so a search in English finds a zone whatever the
  /// display language.
  public let identifierCity: String
  /// The identifier's region ("America"), a search term only.
  public let region: String
  public let genericName: String
  public let offsetLabel: String
  /// Seconds from GMT at the moment the choice was built; the list's order.
  public let secondsFromGMT: Int
  /// The cities of other identifiers that name this same zone and are not
  /// listed ("Montreal" for Toronto's Eastern Time), a search term only.
  public private(set) var searchAliases: [String] = []

  public var id: String { identifier }

  /// The choice for `identifier`, or nil when it is not a time zone this
  /// system knows.
  public init?(identifier: String, now: Date = Date(), locale: Locale = .current) {
    self.init(identifier: identifier, now: now, namer: ZoneNamer(locale: locale))
  }

  private init?(identifier: String, now: Date, namer: ZoneNamer) {
    guard let zone = TimeZone(identifier: identifier) else { return nil }
    let parts = identifier.split(separator: "/")
    self.identifier = identifier
    self.identifierCity =
      (parts.last.map(String.init) ?? identifier).replacingOccurrences(of: "_", with: " ")
    self.city =
      identifier == "UTC" ? identifier : namer.city(of: zone, at: now) ?? identifierCity
    self.region = parts.count > 1 ? String(parts[0]) : ""
    self.genericName = zone.localizedName(for: .generic, locale: namer.locale) ?? ""
    self.secondsFromGMT = zone.secondsFromGMT(for: now)
    self.offsetLabel = namer.offset(of: zone, at: now)
  }

  /// "Los Angeles · GMT-7": how a settings row names the chosen zone.
  public var summary: String { "\(city) · \(offsetLabel)" }

  /// Whether `query` names this zone: a case- and accent-insensitive match on
  /// the city in the user's language or as the identifier spells it, the
  /// region, the generic name, the identifier, or the city of an unlisted
  /// alias. An empty query matches every zone.
  public func matches(_ query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    return ([city, identifierCity, region, genericName, identifier] + searchAliases).contains {
      $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }

  /// Every geographic zone the system knows ("Region/City"; bare
  /// abbreviations such as "GMT" are left out) plus "UTC", ordered west to
  /// east by current offset, then by city in `locale`'s collation.
  ///
  /// The system lists a zone under every identifier that names it
  /// ("Europe/Kyiv", "Europe/Kiev", "Europe/Zaporozhye"). Each zone appears
  /// once, whatever `locale` is, as the identifier spelled like the zone's
  /// English city ("America/Toronto", not "America/Montreal"), or the
  /// shortest identifier when none is. The other identifiers stay searchable
  /// through ``searchAliases``. An identifier in `keeping` (the stored choice,
  /// which may be an alias) always wins its zone, so the zone a person has
  /// chosen keeps its own row.
  public static func all(
    now: Date = Date(), locale: Locale = .current, keeping kept: Set<String> = []
  ) -> [LorvexTimeZoneChoice] {
    let namer = ZoneNamer(locale: locale)
    let english = ZoneNamer(locale: Locale(identifier: "en_US"))
    var zones: [String: [ZoneIdentifier]] = [:]
    for identifier in TimeZone.knownTimeZoneIdentifiers.filter({ $0.contains("/") }) + ["UTC"] {
      guard let choice = LorvexTimeZoneChoice(identifier: identifier, now: now, namer: namer),
        let zone = TimeZone(identifier: identifier)
      else { continue }
      // Identifiers of one zone agree on its English city, offset, and generic name.
      let englishCity = english.city(of: zone, at: now) ?? choice.identifierCity
      let englishName = zone.localizedName(for: .generic, locale: english.locale) ?? ""
      zones["\(englishCity)\u{0}\(choice.secondsFromGMT)\u{0}\(englishName)", default: []]
        .append(ZoneIdentifier(choice: choice, englishCity: englishCity))
    }
    return zones.values
      .map { listedChoice(of: $0, keeping: kept) }
      .sorted {
        guard $0.secondsFromGMT == $1.secondsFromGMT else {
          return $0.secondsFromGMT < $1.secondsFromGMT
        }
        return $0.city.compare($1.city, options: [.caseInsensitive], locale: locale)
          == .orderedAscending
      }
  }

  /// One identifier of a zone with the zone's English city.
  private struct ZoneIdentifier {
    let choice: LorvexTimeZoneChoice
    let englishCity: String

    /// Whether the identifier spells the zone's English city.
    var isSpelledAsCity: Bool {
      englishCity.compare(
        choice.identifierCity, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
  }

  /// The choice that stands for the identifiers of one zone: one in `kept`,
  /// else one spelled as the zone's English city, else the first. Identifiers
  /// rank shortest first, then alphabetically. The choice carries the other
  /// identifiers' cities as search aliases.
  private static func listedChoice(
    of identifiers: [ZoneIdentifier], keeping kept: Set<String>
  ) -> LorvexTimeZoneChoice {
    let ranked = identifiers.sorted {
      ($0.choice.identifier.count, $0.choice.identifier)
        < ($1.choice.identifier.count, $1.choice.identifier)
    }
    let listed =
      ranked.first { kept.contains($0.choice.identifier) }
      ?? ranked.first { $0.isSpelledAsCity }
      ?? ranked[0]
    var choice = listed.choice
    choice.searchAliases = ranked.map(\.choice)
      .filter { $0.identifier != choice.identifier }
      .map(\.identifierCity)
    return choice
  }
}

/// Names zones in one locale through CLDR's own patterns: `VVV`, the zone's
/// city, and `O`, its short localized GMT offset. One namer serves the whole
/// list, because making a `DateFormatter` costs far more than using one.
private final class ZoneNamer {
  let locale: Locale
  private let cityFormatter: DateFormatter
  private let offsetFormatter: DateFormatter
  /// What `VVV` answers for a zone CLDR names no city for ("Unknown
  /// Location"), so such a zone keeps the identifier's spelling instead.
  private let unknownCity: String

  init(locale: Locale) {
    self.locale = locale
    cityFormatter = DateFormatter()
    cityFormatter.locale = locale
    cityFormatter.dateFormat = "VVV"
    offsetFormatter = DateFormatter()
    offsetFormatter.locale = locale
    offsetFormatter.dateFormat = "O"
    cityFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    unknownCity = cityFormatter.string(from: Date())
  }

  func city(of zone: TimeZone, at date: Date) -> String? {
    cityFormatter.timeZone = zone
    let city = cityFormatter.string(from: date)
    return city.isEmpty || city == unknownCity ? nil : city
  }

  func offset(of zone: TimeZone, at date: Date) -> String {
    offsetFormatter.timeZone = zone
    return offsetFormatter.string(from: date)
  }
}
