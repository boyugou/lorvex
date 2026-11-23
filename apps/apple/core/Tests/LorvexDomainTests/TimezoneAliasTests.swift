import XCTest

@testable import LorvexDomain

/// A device can report its zone, and an assistant can name one, under a name
/// Apple's canonical identifier list leaves out. The product time zone accepts
/// such a name and stores the zone's canonical identifier.
final class TimezoneAliasTests: XCTestCase {
  private let canonical = Set(TimeZone.knownTimeZoneIdentifiers)

  private func zoneData(_ identifier: String) -> Data? {
    TimeZone(identifier: identifier).map { ($0 as NSTimeZone).data }
  }

  /// What a build with the canonical-only rule accepts.
  private func isCanonical(_ name: String?) -> Bool {
    guard let name else { return false }
    return name == "UTC" || canonical.contains(name)
  }

  /// Asserts that `name` is accepted as a product time zone and stored under
  /// a canonical identifier of the same zone. Which identifier that is
  /// depends on this system's list, so the assertion does not name it.
  private func assertAcceptedAsItsOwnZone(
    _ name: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    let stored = Timezone.normalizeProductTimezoneName(name)
    XCTAssertTrue(isCanonical(stored), "\(name) -> \(stored ?? "nil")", file: file, line: line)
    guard let stored, stored != "UTC" else { return }
    XCTAssertEqual(
      zoneData(stored), zoneData(name.trimmingCharacters(in: .whitespaces)), name,
      file: file, line: line)
  }

  func testANameOutsideTheCanonicalListBecomesACanonicalIdentifierOfItsZone() {
    for name in [
      "Asia/Kolkata", "Asia/Calcutta", "US/Pacific", "US/Arizona", "America/Buenos_Aires",
      "Singapore", "  Japan ", "Europe/Kyiv", "Europe/Kiev",
    ] {
      assertAcceptedAsItsOwnZone(name)
    }
    for name in ["Etc/UTC", "Zulu", "GMT", "UTC"] {
      XCTAssertEqual(Timezone.normalizeProductTimezoneName(name), "UTC", name)
    }
  }

  /// Where several canonical identifiers share a zone's data, the table names
  /// the place the alias itself means.
  func testAnAliasOfASharedZoneNamesItsOwnPlace() {
    for (alias, expected) in [
      ("US/Arizona", "America/Phoenix"), ("Singapore", "Asia/Singapore"),
      ("GB", "Europe/London"), ("NZ", "Pacific/Auckland"), ("PRC", "Asia/Shanghai"),
    ] where !canonical.contains(alias) && canonical.contains(expected) {
      XCTAssertEqual(Timezone.normalizeProductTimezoneName(alias), expected, alias)
    }
  }

  func testAbbreviationsFixedOffsetsAndUnknownNamesAreRefused() {
    for name in [
      "PST", "EST", "EET", "CET", "HST", "GMT+5", "GMT-0800", "Etc/GMT+5", "Etc/GMT-14",
      "EST5EDT", "Factory", "Not/AZone", "Asia", "", "US/Pacific\u{0}", "us/pacific",
    ] {
      XCTAssertNil(Timezone.normalizeProductTimezoneName(name), name.debugDescription)
    }
  }

  /// A value arriving by sync is taken only when it is canonical as written,
  /// so the stored bytes stay the peer's.
  func testTheSyncRuleTakesCanonicalNamesOnly() {
    XCTAssertEqual(Timezone.canonicalProductTimezoneName(" America/Los_Angeles "), "America/Los_Angeles")
    XCTAssertEqual(Timezone.canonicalProductTimezoneName("GMT"), "UTC")
    for name in ["US/Pacific", "Etc/UTC", "PST", "Not/AZone"] where !canonical.contains(name) {
      XCTAssertNil(Timezone.canonicalProductTimezoneName(name), name)
      XCTAssertThrowsError(
        try PreferenceValueContract.normalize(
          key: PreferenceKeys.prefTimezone, value: .string(name), acceptingTimezoneAliases: false
        ).get(), name)
    }
  }

  func testADeviceReportingAnAliasAnchorsToACanonicalIdentifier() {
    for reported in ["US/Pacific", "Asia/Kolkata", "Asia/Calcutta"] {
      guard
        case .success(let name) = Timezone.resolveAnchoredTimezoneName(
          activeTimezone: nil, systemTimezoneLookup: .success(reported))
      else { return XCTFail("\(reported) was refused") }
      XCTAssertTrue(isCanonical(name), "\(reported) -> \(name)")
      XCTAssertEqual(zoneData(name), zoneData(reported), reported)
    }
    guard
      case .failure = Timezone.resolveAnchoredTimezoneName(
        activeTimezone: nil, systemTimezoneLookup: .success("Etc/GMT+12"))
    else { return XCTFail("a fixed offset was accepted as a product time zone") }
  }

  /// Every table entry names a canonical identifier, or UTC, of the same
  /// zone as its alias.
  func testEveryTableEntryNamesTheSameZoneUnderACanonicalIdentifier() throws {
    XCTAssertFalse(TimezoneAliases.table.isEmpty)
    let probes = [Date(timeIntervalSince1970: 1_767_225_600), Date(timeIntervalSince1970: 1_782_864_000)]
    for (alias, target) in TimezoneAliases.table {
      guard let aliasZone = TimeZone(identifier: alias) else { continue }
      if target == "UTC" {
        for probe in probes { XCTAssertEqual(aliasZone.secondsFromGMT(for: probe), 0, alias) }
      } else if canonical.contains(target) {
        XCTAssertEqual(zoneData(alias), zoneData(target), "\(alias) -> \(target)")
      }
    }
    // Most targets are canonical on any one system; a list that dropped many
    // would leave the table unused.
    let usable = TimezoneAliases.table.values.filter { $0 == "UTC" || canonical.contains($0) }
    XCTAssertGreaterThan(usable.count, TimezoneAliases.table.count * 9 / 10)
  }

  /// A name the table does not list resolves through its zone data when one
  /// canonical identifier alone shares it, and not when several do.
  func testAnUnlistedNameResolvesOnlyThroughAnUnambiguousDataMatch() {
    for name in ["Asia/Kolkata", "US/Pacific"] where !canonical.contains(name) {
      let match = TimezoneAliases.uniqueZoneDataMatch(for: name)
      XCTAssertTrue(isCanonical(match), name)
      XCTAssertEqual(match.flatMap(zoneData), zoneData(name), name)
    }
    // Several canonical identifiers share this zone's data.
    XCTAssertNil(TimezoneAliases.uniqueZoneDataMatch(for: "Europe/Belfast"))
    // Not of the Area/Location form, whatever its data matches.
    XCTAssertNil(TimezoneAliases.uniqueZoneDataMatch(for: "Japan"))
    XCTAssertNil(TimezoneAliases.uniqueZoneDataMatch(for: "Etc/GMT"))
  }

  /// Every name in this system's time zone database is canonical, resolves to
  /// a canonical identifier, or is one of the kinds the product refuses. A
  /// system update that adds a name of some other kind fails here, which is
  /// the cue to extend ``TimezoneAliases/table``.
  func testEveryNameInTheSystemDatabaseIsAcceptedOrOfARefusedKind() throws {
    let root = "/usr/share/zoneinfo"
    let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: root))
    let refusedNames: Set<String> = [
      "CET", "EET", "EST", "HST", "MET", "MST", "WET",
      "CST6CDT", "EST5EDT", "MST7MDT", "PST8PDT", "Factory",
    ]
    var checked = 0
    var unexplained: [String] = []
    for case let path as String in enumerator {
      var isDirectory: ObjCBool = false
      FileManager.default.fileExists(atPath: root + "/" + path, isDirectory: &isDirectory)
      if isDirectory.boolValue || path.contains(".") || path.hasPrefix("posix")
        || path.hasPrefix("right") || path.hasPrefix("+")
      {
        continue
      }
      guard TimeZone(identifier: path) != nil else { continue }
      checked += 1
      if let stored = Timezone.normalizeProductTimezoneName(path) {
        // Whatever is accepted is stored under a name the canonical-only
        // rule accepts.
        XCTAssertTrue(isCanonical(stored), "\(path) -> \(stored)")
        continue
      }
      if refusedNames.contains(path) || path.hasPrefix("Etc/GMT") { continue }
      unexplained.append(path)
    }
    XCTAssertGreaterThan(checked, 400)
    XCTAssertEqual(unexplained, [])
  }
}
