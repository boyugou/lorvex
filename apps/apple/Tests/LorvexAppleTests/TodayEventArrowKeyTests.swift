import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// On Mac Today the arrow keys stop on the schedule's event rows as well as on
/// task rows, in the order the column draws them, and landing on an event opens
/// it in the inspector the way a click does.
@MainActor
@Suite("Today event arrow keys")
struct TodayEventArrowKeyTests {
  private func makeStore() async throws -> (AppStore, [String: String]) {
    let core = try makeInMemoryCore()
    let today = LorvexDateFormatters.ymd.string(from: Date())
    let dueToday = try #require(LorvexDateFormatters.ymdUTC.date(from: today))
    // An all-day event sits above the schedule's "earlier" fold at any hour,
    // so the expected order does not depend on the clock.
    let event = try await core.createCalendarEvent(
      title: "Offsite", startDate: today, endDate: nil, startTime: nil, endTime: nil,
      allDay: true, location: nil, notes: nil)
    let timed = try await core.createTask(
      TaskCreateDraft(
        title: "Late call", priority: .p1, plannedDate: dueToday,
        plannedTime: 23 * 60..<23 * 60 + 30))
    let untimed = try await core.createTask(
      TaskCreateDraft(title: "Write up", priority: .p2, plannedDate: dueToday))
    let store = AppStore(core: core)
    await store.refresh()
    return (store, ["event": event.id, "timed": timed.id, "untimed": untimed.id])
  }

  @Test("The stops list the event with the tasks in the column's order")
  func stopsFollowTheColumn() async throws {
    let (store, ids) = try await makeStore()
    let stops = store.todayArrowKeyStops()
    #expect(stops.ids == [ids["event"]!, ids["timed"]!, ids["untimed"]!])
    #expect(stops.eventIDs == [ids["event"]!])
    // Select All and batch actions keep reading tasks only.
    #expect(store.orderedTaskIDs(on: .today) == [ids["timed"]!, ids["untimed"]!])
  }

  @Test("An arrow press onto the event opens it, and one onto a task closes it")
  func landingOpensTheRow() async throws {
    let (store, ids) = try await makeStore()
    store.selection = .today
    let navigation = store.arrowKeyTaskNavigation(on: .today)

    navigation.selectOnly(ids["event"]!)
    #expect(store.selectedCalendarEventID == ids["event"])
    #expect(store.selectedTaskID == nil)
    #expect(store.arrowKeyTaskNavigation(on: .today).selectedTaskID == ids["event"])

    store.arrowKeyTaskNavigation(on: .today).selectOnly(ids["timed"]!)
    #expect(store.selectedTaskID == ids["timed"])
    #expect(store.selectedCalendarEventID == nil)
  }

  @Test("Shift from an event opens the next row alone instead of growing a range")
  func shiftFromAnEvent() async throws {
    let (store, ids) = try await makeStore()
    store.selection = .today
    store.arrowKeyTaskNavigation(on: .today).selectOnly(ids["event"]!)
    store.arrowKeyTaskNavigation(on: .today).extendSelection(ids["timed"]!)
    #expect(store.selectedTaskID == ids["timed"])
    #expect(store.todaySelectionCount == 1)
  }
}
