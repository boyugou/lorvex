import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

@MainActor
struct CalendarProductClockTests {
  @Test("An open calendar follows a saved zone change across midnight on both platforms")
  func openGridsFollowTheProductDayAndClock() async throws {
    // Today reads the real product day. These fixed-offset zones are 25 hours
    // apart, so a switch always changes its date, at any hour the test runs.
    let instant = Date()
    let core = try SwiftLorvexCoreService.inMemory()
    _ = try await core.setPreference(key: "timezone", value: "Pacific/Pago_Pago")
    let mac = AppStore(core: core, cloudSyncMode: .off)
    let mobile = MobileStore(core: core)
    await mac.refresh()
    await mobile.refresh()
    let firstKey = mac.logicalTodayDateString
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
    let secondKey = formatter.string(from: instant)
    #expect(firstKey < secondKey)
    let task = try await core.createTask(title: "Due before the next product day", notes: "")
    let due = try #require(PlannedDayBridge.storageDate(forLogicalDay: firstKey))
    let dueTask = try await core.updateTask(TaskUpdateDraft(id: task.id, dueDate: .set(due)))
    let first = try #require(PlannedDayBridge.displayDate(
      forLogicalDay: firstKey, timeZone: .current))
    let second = try #require(PlannedDayBridge.displayDate(
      forLogicalDay: secondKey, timeZone: .current))
    // Keep the view values alive through the preference change, like an open
    // grid: their clocks must read the new snapshot rather than an init cache.
    let macGrid = CalendarWeekGridView(
      store: mac, weekStart: first, selectEvent: { _ in }, openTask: { _ in },
      createAt: { _, _, _ in })
    let mobileGrid = MobileCalendarDayView(store: mobile, weekMode: true)
    #expect(macGrid.isToday(first))
    #expect(!macGrid.isToday(second))
    let firstMinute = try #require(macGrid.productClock.nowMinutes(at: instant))
    #expect(mobileGrid.productClock == macGrid.productClock)
    #expect(!mac.isOverdue(dueTask))

    #expect(await mac.setLogicalTimeZone("Pacific/Kiritimati"))
    await mobile.refresh()
    #expect(mac.logicalTodayDateString == secondKey)
    #expect(macGrid.isToday(second))
    #expect(!macGrid.isToday(first))
    #expect(macGrid.productClock.nowMinutes(at: instant) == (firstMinute + 25 * 60) % (24 * 60))
    #expect(mobileGrid.productClock == macGrid.productClock)
    #expect(mobileGrid.calendar.isDate(mobileGrid.today, inSameDayAs: second))
    #expect(mac.isOverdue(dueTask))
    #expect(LorvexTaskSections.isOverdue(dueTask, logicalDay: mobileGrid.productClock.logicalDay))
  }
}
