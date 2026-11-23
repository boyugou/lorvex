import Foundation

/// Other names of the time zones Apple's canonical identifier list covers.
///
/// A device can report its own zone under a name the list leaves out: the tz
/// database's current name where the list keeps an older one ("Asia/Kolkata"
/// for "Asia/Calcutta"), or a legacy link ("US/Pacific"). An assistant passes
/// such names too. Each resolves here to a canonical identifier of the same
/// zone, which is what the synced `timezone` preference stores, so a build
/// that accepts canonical identifiers only accepts what this device writes.
enum TimezoneAliases {
  /// Apple's canonical identifiers.
  static let canonicalIdentifiers = Set(TimeZone.knownTimeZoneIdentifiers)

  /// The canonical identifier for `name`, or nil when `name` is not another
  /// name of a canonical zone.
  ///
  /// The table answers first, so a listed name does not depend on how many
  /// canonical identifiers share its zone data on this system; its target is
  /// used when this system's list has it. A name the table does not list
  /// resolves only when it has the `Area/Location` form and exactly one
  /// canonical identifier has the same zone data; abbreviations ("PST",
  /// "EET") and fixed offsets ("GMT+5", "Etc/GMT+5") are never accepted.
  static func canonicalName(for name: String) -> String? {
    if let listed = table[name], listed == "UTC" || canonicalIdentifiers.contains(listed) {
      return listed
    }
    return uniqueZoneDataMatch(for: name)
  }

  static func uniqueZoneDataMatch(for name: String) -> String? {
    // The characters tz database names are made of; Foundation resolves a
    // name with a trailing NUL as the name before it.
    guard name.contains("/"), !name.hasPrefix("Etc/"),
      name.unicodeScalars.allSatisfy({ nameCharacters.contains($0) }),
      let zone = TimeZone(identifier: name)
    else { return nil }
    let matches = canonicalIdentifiersByZoneData[(zone as NSTimeZone).data] ?? []
    return matches.count == 1 ? matches[0] : nil
  }

  private static let nameCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/_-+")

  private static let canonicalIdentifiersByZoneData: [Data: [String]] = {
    var identifiers: [Data: [String]] = [:]
    for identifier in TimeZone.knownTimeZoneIdentifiers {
      guard let zone = TimeZone(identifier: identifier) else { continue }
      identifiers[(zone as NSTimeZone).data, default: []].append(identifier)
    }
    return identifiers
  }()

  /// The tz database's names outside the canonical list, each with the
  /// canonical identifier of the same zone: the link's own target where
  /// several canonical identifiers share the zone's data ("US/Arizona" is
  /// Phoenix, not Creston), and "UTC" for every name of UTC.
  static let table: [String: String] = [
    "Africa/Asmera": "Africa/Asmara", "Africa/Timbuktu": "Africa/Bamako",
    "America/Argentina/ComodRivadavia": "America/Argentina/Catamarca",
    "America/Atka": "America/Adak", "America/Buenos_Aires": "America/Argentina/Buenos_Aires",
    "America/Catamarca": "America/Argentina/Catamarca",
    "America/Coral_Harbour": "America/Atikokan", "America/Cordoba": "America/Argentina/Cordoba",
    "America/Ensenada": "America/Tijuana", "America/Fort_Wayne": "America/Indiana/Indianapolis",
    "America/Indianapolis": "America/Indiana/Indianapolis",
    "America/Jujuy": "America/Argentina/Jujuy", "America/Knox_IN": "America/Indiana/Knox",
    "America/Louisville": "America/Kentucky/Louisville",
    "America/Mendoza": "America/Argentina/Mendoza", "America/Porto_Acre": "America/Rio_Branco",
    "America/Rosario": "America/Argentina/Cordoba", "America/Virgin": "America/St_Thomas",
    "Asia/Ashkhabad": "Asia/Ashgabat", "Asia/Chungking": "Asia/Chongqing",
    "Asia/Dacca": "Asia/Dhaka", "Asia/Istanbul": "Europe/Istanbul",
    "Asia/Kolkata": "Asia/Calcutta", "Asia/Macao": "Asia/Macau",
    "Asia/Saigon": "Asia/Ho_Chi_Minh", "Asia/Tel_Aviv": "Asia/Jerusalem",
    "Asia/Thimbu": "Asia/Thimphu", "Asia/Ujung_Pandang": "Asia/Makassar",
    "Asia/Ulan_Bator": "Asia/Ulaanbaatar", "Atlantic/Faeroe": "Atlantic/Faroe",
    "Atlantic/Jan_Mayen": "Europe/Oslo", "Australia/ACT": "Australia/Sydney",
    "Australia/Canberra": "Australia/Sydney", "Australia/LHI": "Australia/Lord_Howe",
    "Australia/NSW": "Australia/Sydney", "Australia/North": "Australia/Darwin",
    "Australia/Queensland": "Australia/Brisbane", "Australia/South": "Australia/Adelaide",
    "Australia/Tasmania": "Australia/Hobart", "Australia/Victoria": "Australia/Melbourne",
    "Australia/West": "Australia/Perth", "Australia/Yancowinna": "Australia/Broken_Hill",
    "Brazil/Acre": "America/Rio_Branco", "Brazil/DeNoronha": "America/Noronha",
    "Brazil/East": "America/Sao_Paulo", "Brazil/West": "America/Manaus",
    "Canada/Atlantic": "America/Halifax", "Canada/Central": "America/Winnipeg",
    "Canada/Eastern": "America/Toronto", "Canada/Mountain": "America/Edmonton",
    "Canada/Newfoundland": "America/St_Johns", "Canada/Pacific": "America/Vancouver",
    "Canada/Saskatchewan": "America/Regina", "Canada/Yukon": "America/Whitehorse",
    "Chile/Continental": "America/Santiago", "Chile/EasterIsland": "Pacific/Easter",
    "Cuba": "America/Havana", "Egypt": "Africa/Cairo", "Eire": "Europe/Dublin", "Etc/GMT": "UTC",
    "Etc/GMT+0": "UTC", "Etc/GMT-0": "UTC", "Etc/GMT0": "UTC", "Etc/Greenwich": "UTC",
    "Etc/UCT": "UTC", "Etc/UTC": "UTC", "Etc/Universal": "UTC", "Etc/Zulu": "UTC",
    "Europe/Belfast": "Europe/London", "Europe/Nicosia": "Asia/Nicosia",
    "Europe/Tiraspol": "Europe/Chisinau", "GB": "Europe/London", "GB-Eire": "Europe/London",
    "GMT+0": "UTC", "GMT-0": "UTC", "GMT0": "UTC", "Greenwich": "UTC",
    "Hongkong": "Asia/Hong_Kong", "Iceland": "Atlantic/Reykjavik", "Iran": "Asia/Tehran",
    "Israel": "Asia/Jerusalem", "Jamaica": "America/Jamaica", "Japan": "Asia/Tokyo",
    "Kwajalein": "Pacific/Kwajalein", "Libya": "Africa/Tripoli",
    "Mexico/BajaNorte": "America/Tijuana", "Mexico/BajaSur": "America/Mazatlan",
    "Mexico/General": "America/Mexico_City", "NZ": "Pacific/Auckland",
    "NZ-CHAT": "Pacific/Chatham", "Navajo": "America/Denver", "PRC": "Asia/Shanghai",
    "Pacific/Samoa": "Pacific/Pago_Pago", "Pacific/Yap": "Pacific/Chuuk",
    "Poland": "Europe/Warsaw", "Portugal": "Europe/Lisbon", "ROC": "Asia/Taipei",
    "ROK": "Asia/Seoul", "Singapore": "Asia/Singapore", "Turkey": "Europe/Istanbul", "UCT": "UTC",
    "US/Alaska": "America/Anchorage", "US/Aleutian": "America/Adak",
    "US/Arizona": "America/Phoenix", "US/Central": "America/Chicago",
    "US/East-Indiana": "America/Indiana/Indianapolis", "US/Eastern": "America/New_York",
    "US/Hawaii": "Pacific/Honolulu", "US/Indiana-Starke": "America/Indiana/Knox",
    "US/Michigan": "America/Detroit", "US/Mountain": "America/Denver",
    "US/Pacific": "America/Los_Angeles", "US/Samoa": "Pacific/Pago_Pago", "Universal": "UTC",
    "W-SU": "Europe/Moscow", "Zulu": "UTC",
  ]
}
