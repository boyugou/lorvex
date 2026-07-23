/// Canonical typed wrapper around a calendar date rendered in the
/// schema-storage form (`YYYY-MM-DD`).
///
/// Every `due_date`, `planned_date`, `start_date`, `canonical_occurrence_date`,
/// etc. column flows through this newtype rather than a bare `String`. The only
/// way to construct one is through ``parse(_:)`` / ``init(ymd:)``, both of which
/// route through ``IsoDate/parseIsoDate(_:)``, so a malformed date is rejected
/// with a typed parse error at the boundary. JSON encoding is the bare canonical
/// string, byte-identical to the `String` it replaces.
///
/// Backed by an ``IsoDate/YMD`` triple so two values compare by calendar order,
/// not lexicographically (the two coincide for the zero-padded canonical form,
/// but the typed ordering is the contract).
public struct LorvexDate: Sendable, Equatable, Hashable, Comparable, Codable {
  public let ymd: IsoDate.YMD

  /// Wrap an already-validated `YMD` triple.
  public init(ymd: IsoDate.YMD) {
    self.ymd = ymd
  }

  /// Parse a canonical hyphenated ISO date (`YYYY-MM-DD`).
  public static func parse(_ raw: String) -> Result<LorvexDate, ValidationError> {
    IsoDate.parseIsoDate(raw).map(LorvexDate.init(ymd:))
  }

  /// Render the date as the canonical hyphenated ISO string (`YYYY-MM-DD`).
  public var asString: String { ymd.canonicalString }

  public static func < (lhs: LorvexDate, rhs: LorvexDate) -> Bool { lhs.ymd < rhs.ymd }

  /// Decode from the bare canonical string, surfacing a parse failure as a
  /// decoding error so wire-boundary reads reject malformed dates.
  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    switch LorvexDate.parse(raw) {
    case let .success(date):
      self = date
    case let .failure(error):
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: error.description))
    }
  }

  /// Encode as the bare canonical string.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(asString)
  }
}
