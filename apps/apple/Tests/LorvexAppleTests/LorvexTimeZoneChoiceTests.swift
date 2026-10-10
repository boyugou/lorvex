import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

struct LorvexTimeZoneChoiceTests {
  private let winter: Date = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01T00:00:00Z

  @Test func offsetsTakeTheLocalesOwnForm() throws {
    let english = Locale(identifier: "en_US")
    let losAngeles = try #require(
      LorvexTimeZoneChoice(identifier: "America/Los_Angeles", now: winter, locale: english))
    let kolkata = try #require(
      LorvexTimeZoneChoice(identifier: "Asia/Kolkata", now: winter, locale: english))
    let french = try #require(
      LorvexTimeZoneChoice(
        identifier: "America/Los_Angeles", now: winter, locale: Locale(identifier: "fr_FR")))
    #expect(losAngeles.offsetLabel == "GMT-8")
    #expect(kolkata.offsetLabel == "GMT+5:30")
    #expect(french.offsetLabel == "UTC\u{2212}8")
  }

  @Test func aChoiceNamesItsCityRegionAndOffset() throws {
    let choice = try #require(
      LorvexTimeZoneChoice(identifier: "America/Los_Angeles", now: winter, locale: Locale(identifier: "en_US")))
    #expect(choice.city == "Los Angeles")
    #expect(choice.identifierCity == "Los Angeles")
    #expect(choice.region == "America")
    #expect(choice.summary == "Los Angeles · GMT-8")
    #expect(choice.genericName == "Pacific Time")
    #expect(LorvexTimeZoneChoice(identifier: "Nowhere/Atlantis") == nil)
  }

  @Test func theCityIsNamedInTheUsersLanguage() throws {
    let chinese = try #require(
      LorvexTimeZoneChoice(
        identifier: "America/Los_Angeles", now: winter, locale: Locale(identifier: "zh-Hans")))
    let spanish = try #require(
      LorvexTimeZoneChoice(
        identifier: "America/Los_Angeles", now: winter, locale: Locale(identifier: "es")))
    #expect(chinese.city == "洛杉矶")
    #expect(chinese.genericName == "北美太平洋时间")
    #expect(chinese.identifierCity == "Los Angeles")
    #expect(spanish.city == "Los Ángeles")
    let utc = try #require(
      LorvexTimeZoneChoice(identifier: "UTC", now: winter, locale: Locale(identifier: "zh-Hans")))
    #expect(utc.city == "UTC")
    // CLDR names no city for a fixed-offset zone; it keeps the identifier's
    // spelling rather than CLDR's "unknown location" placeholder.
    if TimeZone(identifier: "Etc/GMT+5") != nil {
      let fixed = try #require(
        LorvexTimeZoneChoice(identifier: "Etc/GMT+5", now: winter, locale: Locale(identifier: "zh-Hans")))
      #expect(fixed.city == "GMT+5")
    }
  }

  @Test func searchMatchesCityRegionAndNameIgnoringCaseAndAccents() throws {
    let choice = try #require(
      LorvexTimeZoneChoice(identifier: "America/Sao_Paulo", now: winter, locale: Locale(identifier: "en_US")))
    #expect(choice.matches(""))
    #expect(choice.matches("são"))
    #expect(choice.matches("SAO PAULO"))
    #expect(choice.matches("america"))
    #expect(!choice.matches("Tokyo"))
  }

  @Test func searchFindsAZoneByItsEnglishCityInAnyLanguage() throws {
    let choice = try #require(
      LorvexTimeZoneChoice(
        identifier: "America/Los_Angeles", now: winter, locale: Locale(identifier: "zh-Hans")))
    #expect(choice.matches("洛杉矶"))
    #expect(choice.matches("los angeles"))
    #expect(choice.matches("太平洋"))
  }

  @Test func theListHoldsGeographicZonesWestToEast() {
    let all = LorvexTimeZoneChoice.all(now: winter, locale: Locale(identifier: "en_US"))
    let ids = all.map(\.identifier)
    #expect(ids.contains("Asia/Tokyo"))
    #expect(ids.contains("UTC"))
    #expect(!ids.contains("GMT"))
    #expect(all.map(\.secondsFromGMT) == all.map(\.secondsFromGMT).sorted())
  }

  @Test func aZoneNamedByManyIdentifiersIsListedOnce() {
    let all = LorvexTimeZoneChoice.all(now: winter, locale: Locale(identifier: "en_US"))
    var rowsByName: [String: String] = [:]
    for choice in all {
      let name = "\(choice.city)|\(choice.secondsFromGMT)|\(choice.genericName)"
      #expect(rowsByName[name] == nil, "\(choice.identifier) repeats \(rowsByName[name] ?? "")")
      rowsByName[name] = choice.identifier
    }
    let ids = Set(all.map(\.identifier))
    #expect(ids.contains("America/Toronto"))
    #expect(ids.contains("Europe/Kyiv"))
    #expect(ids.contains("Asia/Shanghai"))
    #expect(ids.contains("UTC"))
    #expect(ids.isDisjoint(with: ["America/Montreal", "Europe/Kiev", "Asia/Chongqing", "Etc/UTC"]))
  }

  @Test func theListHoldsTheSameZonesInEveryLanguage() {
    let english = LorvexTimeZoneChoice.all(now: winter, locale: Locale(identifier: "en_US"))
    for language in ["zh-Hans", "ja", "ar", "de"] {
      let other = LorvexTimeZoneChoice.all(now: winter, locale: Locale(identifier: language))
      #expect(Set(other.map(\.identifier)) == Set(english.map(\.identifier)), "\(language)")
    }
  }

  @Test func theChosenZoneKeepsItsOwnRowEvenWhenItIsAnAlias() {
    let all = LorvexTimeZoneChoice.all(
      now: winter, locale: Locale(identifier: "en_US"), keeping: ["America/Montreal"])
    let ids = all.map(\.identifier)
    #expect(ids.contains("America/Montreal"))
    #expect(!ids.contains("America/Toronto"))
    #expect(all.first { $0.identifier == "America/Montreal" }?.city == "Toronto")
  }

  @Test func searchStillFindsAZoneByTheCityOfAnUnlistedAlias() throws {
    let all = LorvexTimeZoneChoice.all(now: winter, locale: Locale(identifier: "en_US"))
    let toronto = try #require(all.first { $0.identifier == "America/Toronto" })
    #expect(toronto.matches("montreal"))
    #expect(toronto.matches("Thunder Bay"))
    let kyiv = try #require(all.first { $0.identifier == "Europe/Kyiv" })
    #expect(kyiv.matches("Kiev"))
    #expect(!kyiv.matches("Montreal"))
  }

  @MainActor
  @Test func settingTheTimeZoneMovesTheTodaySnapshotToIt() async throws {
    let suiteName = "settingTheTimeZone.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
    await store.refresh()
    let target = store.logicalTimezoneName == "Asia/Tokyo" ? "Europe/Berlin" : "Asia/Tokyo"

    #expect(await store.setLogicalTimeZone(target))
    #expect(store.logicalTimezoneName == target)
    #expect(store.logicalTimeZone.identifier == target)
    #expect(!(await store.setLogicalTimeZone("Nowhere/Atlantis")))
    #expect(store.logicalTimezoneName == target)
  }
}
