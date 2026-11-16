import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

@MainActor
@Suite("Time zone selection waits for the saved choice")
struct TimeZoneSelectionTests {
  @Test func aPendingSelectionRejectsRepeatedTaps() async {
    let selection = LorvexTimeZoneSelection()
    let gate = ReviewGate()
    var writes: [String] = []
    let first = Task {
      await selection.select("Asia/Tokyo", current: "UTC") { identifier in
        writes.append(identifier)
        await gate.hold()
        return true
      }
    }
    await gate.waitUntilHeld()

    #expect(selection.isSaving)
    #expect(selection.pendingIdentifier == "Asia/Tokyo")
    let second = await selection.select("Europe/Berlin", current: "UTC") { identifier in
      writes.append(identifier)
      return true
    }
    #expect(!second)
    #expect(writes == ["Asia/Tokyo"])

    await gate.release()
    #expect(await first.value)
    #expect(!selection.isSaving)
    #expect(selection.pendingIdentifier == nil)
  }

  @Test func aFailedChoiceStaysOpenAndCanBeRetried() async {
    let selection = LorvexTimeZoneSelection()
    #expect(!(await selection.select("Asia/Tokyo", current: "UTC") { _ in false }))
    #expect(!selection.isSaving)
    #expect(await selection.select("Asia/Tokyo", current: "UTC") { _ in true })
    #expect(!selection.isSaving)
  }

  @Test func choosingTheCurrentZoneClosesWithoutAWrite() async {
    let selection = LorvexTimeZoneSelection()
    var writes = 0
    #expect(await selection.select("UTC", current: "UTC") { _ in
      writes += 1
      return true
    })
    #expect(writes == 0)
  }

  @Test func bothStoresKeepTheirZoneWhenAWriteFails() async throws {
    let core = try await makeSeededInMemoryCore()
    _ = try await core.setPreference(key: "timezone", value: "UTC")
    let mac = AppStore(core: core, cloudSyncMode: .off)
    let mobile = MobileStore(core: core)
    await mac.refresh()
    await mobile.refresh()

    #expect(!(await mac.setLogicalTimeZone("Nowhere/Atlantis")))
    #expect(mac.logicalTimezoneName == "UTC")
    #expect(mac.errorMessage != nil)
    #expect(!(await mobile.setLogicalTimeZone("Nowhere/Atlantis")))
    #expect(mobile.logicalTimezoneName == "UTC")
    #expect(mobile.errorMessage != nil)

    #expect(await mac.setLogicalTimeZone("Asia/Tokyo"))
    #expect(await mobile.setLogicalTimeZone("Asia/Tokyo"))
    #expect(mac.logicalTimezoneName == mobile.logicalTimezoneName)
    #expect(mac.logicalTodayDateString == mobile.logicalTodayString)
  }

  @Test func aFailedRefreshDoesNotReportTheNewZoneAsVisible() async throws {
    let core = StubCoreService(preview: try await makeSeededInMemoryCore())
    _ = try await core.setPreference(key: "timezone", value: "UTC")
    let mac = AppStore(core: core, cloudSyncMode: .off)
    let mobile = MobileStore(core: core)
    await mac.refresh()
    await mobile.refresh()
    core.loadTodayError = .validation(field: "today", message: "Injected read failure.")

    #expect(!(await mac.setLogicalTimeZone("Pacific/Kiritimati")))
    #expect(mac.errorMessage != nil)
    #expect(!(await mobile.setLogicalTimeZone("Pacific/Pago_Pago")))
    #expect(mobile.errorMessage != nil)

    core.loadTodayError = nil
    #expect(await mac.setLogicalTimeZone("Pacific/Kiritimati"))
    #expect(await mobile.setLogicalTimeZone("Pacific/Pago_Pago"))
  }

  @Test func macSelectionWaitsForTheRefreshThatObservedItsWrite() async throws {
    let core = StubCoreService(preview: try await makeSeededInMemoryCore())
    _ = try await core.setPreference(key: "timezone", value: "UTC")
    let store = AppStore(core: core, cloudSyncMode: .off)
    await store.refresh()
    let gate = ReviewGate()
    core.loadTodayGate = { await gate.hold() }
    let oldRefresh = Task { await store.refresh() }
    await gate.waitUntilHeld()

    var finished = false
    let change = Task {
      let success = await store.setLogicalTimeZone("Asia/Tokyo")
      finished = true
      return success
    }
    for _ in 0..<1_000 where !store.refreshPending { await Task.yield() }
    #expect(store.refreshPending)
    #expect(!finished)
    #expect(store.logicalTimezoneName == "UTC")

    await gate.release()
    await oldRefresh.value
    #expect(await change.value)
    #expect(store.logicalTimezoneName == "Asia/Tokyo")
  }
}
