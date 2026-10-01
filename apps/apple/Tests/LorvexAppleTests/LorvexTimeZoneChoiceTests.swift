import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

struct LorvexTimeZoneChoiceTests {
  private let winter: Date = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01T00:00:00Z

  @Test func offsetLabelsUseATrueMinusAndMinutesOnlyWhenNeeded() {
    #expect(LorvexTimeZoneChoice.offsetLabel(seconds: 0) == "GMT")
    #expect(LorvexTimeZoneChoice.offsetLabel(seconds: 8 * 3600) == "GMT+8")
    #expect(LorvexTimeZoneChoice.offsetLabel(seconds: -8 * 3600) == "GMT\u{2212}8")
    #expect(LorvexTimeZoneChoice.offsetLabel(seconds: 5 * 3600 + 1800) == "GMT+5:30")
  }

  @Test func aChoiceNamesItsCityRegionAndOffset() throws {
    let choice = try #require(
      LorvexTimeZoneChoice(identifier: "America/Los_Angeles", now: winter, locale: Locale(identifier: "en_US")))
    #expect(choice.city == "Los Angeles")
    #expect(choice.region == "America")
    #expect(choice.offsetLabel == "GMT\u{2212}8")
    #expect(choice.summary == "Los Angeles · GMT\u{2212}8")
    #expect(choice.genericName == "Pacific Time")
    #expect(LorvexTimeZoneChoice(identifier: "Nowhere/Atlantis") == nil)
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

  @Test func theListHoldsGeographicZonesWestToEast() {
    let all = LorvexTimeZoneChoice.all(now: winter, locale: Locale(identifier: "en_US"))
    let ids = all.map(\.identifier)
    #expect(ids.contains("Asia/Tokyo"))
    #expect(ids.contains("UTC"))
    #expect(!ids.contains("GMT"))
    #expect(all.map(\.secondsFromGMT) == all.map(\.secondsFromGMT).sorted())
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
