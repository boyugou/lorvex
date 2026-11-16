import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

@MainActor
struct CalendarCreationWindowTests {
  @MainActor
  private struct Fixture {
    let core: SwiftLorvexCoreService
    let stub: StubCoreService
    let mac: AppStore
    let phone: MobileStore
    let mobile: Bool

    var timeline: CalendarTimelineSnapshot? { mobile ? phone.calendarTimeline : mac.calendarTimeline }
    var tasks: [LorvexTask] { (mobile ? phone.calendarScheduledTasks : mac.calendarScheduledTasks) ?? [] }

    func load(_ from: String, through to: String) async throws {
      if mobile {
        await phone.refreshCalendarTimeline(from: from, to: to)
      } else {
        let first = try #require(LorvexDateFormatters.ymdUTC.date(from: from))
        let last = try #require(LorvexDateFormatters.ymdUTC.date(from: to))
        let days = Int(last.timeIntervalSince(first) / 86_400)
        let anchor = try #require(LorvexDateFormatters.ymd.date(from: from))
        try await mac.refreshCalendarTimeline(anchorDate: anchor, dayCount: days)
      }
    }

    func create() async {
      if mobile {
        #expect(await phone.createDraftCalendarEvent())
        #expect(phone.errorMessage == nil)
        #expect(phone.calendarDraft.title.isEmpty)
      } else {
        await mac.createDraftCalendarEvent()
        #expect(mac.errorMessage == nil)
        #expect(mac.draftCalendarTitle.isEmpty)
      }
    }
  }

  private func fixture(mobile: Bool) async throws -> Fixture {
    let core = try SwiftLorvexCoreService.inMemory()
    _ = try await core.setPreference(key: "timezone", value: "America/Los_Angeles")
    let stub = StubCoreService(preview: core)
    stub.forwardsCalendarCreates = true
    let mac = AppStore(core: stub, cloudSyncMode: .off)
    let phone = MobileStore(core: stub)
    await mac.refresh()
    await phone.refresh()
    let zone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let start = try #require(ISO8601DateFormatter().date(from: "2026-11-15T15:00:00Z"))
    let timing = CalendarEventTiming.timed(
      startingAt: start, calendar: LorvexDateFormatters.gregorianCalendar(timeZone: zone))
    mac.draftCalendarTitle = "Tokyo midnight"
    mac.draftCalendarTiming = timing
    phone.calendarDraft = MobileCalendarDraft(title: "Tokyo midnight", timing: timing)
    return Fixture(core: core, stub: stub, mac: mac, phone: phone, mobile: mobile)
  }

  @Test(arguments: [false, true], [false, true])
  func createKeepsOnlyProjectedEventsInsideTheVisibleWindow(mobile: Bool, includesEvent: Bool) async throws {
    let f = try await fixture(mobile: mobile)
    let from = includesEvent ? "2026-11-15" : "2026-11-16"
    try await f.load(from, through: "2026-11-17")
    await f.create()
    let saved = try await f.core.searchCalendarEvents(
      query: "Tokyo midnight", from: nil, to: nil, limit: 10)
    #expect(saved.count == 1)
    #expect(saved.first?.timezone == "Asia/Tokyo")
    #expect(saved.first?.startDate == "2026-11-16")
    #expect(f.timeline?.from == from)
    #expect(f.timeline?.to == "2026-11-17")
    if includesEvent {
      let shown = try #require(f.timeline?.events.first)
      #expect(shown.startDate == "2026-11-15")
      #expect(shown.startTime == "07:00")
      #expect(shown.projection?.timezone == "America/Los_Angeles")
    } else {
      #expect(f.timeline?.events.isEmpty == true)
    }
  }

  @Test(arguments: [false, true])
  func aFailedReloadDoesNotInventAnUnprojectedRowOrInviteADuplicateCreate(mobile: Bool) async throws {
    let f = try await fixture(mobile: mobile)
    try await f.load("2026-11-16", through: "2026-11-17")
    let before = f.timeline
    f.stub.loadCalendarTimelineError = .unsupportedOperation("Injected reload failure")
    await f.create()
    #expect(f.timeline == before)
    let saved = try await f.core.searchCalendarEvents(
      query: "Tokyo midnight", from: nil, to: nil, limit: 10)
    #expect(saved.count == 1)
  }

  @Test(arguments: [false, true], [false, true])
  func creatingAndPagingInEitherOrderKeepTheLatestWindow(mobile: Bool, navigationStartsFirst: Bool) async throws {
    let f = try await fixture(mobile: mobile)
    let task = try await f.core.createTask(TaskCreateDraft(
      title: "New window task", plannedDate: PlannedDayBridge.storageDate(forLogicalDay: "2026-11-23")))
    try await f.load("2026-11-16", through: "2026-11-17")
    let gate = CalendarCreationLoadGate(from: navigationStartsFirst ? "2026-11-23" : "2026-11-16")
    f.stub.loadCalendarTimelineGate = { from, _ in await gate.pauseOnce(from: from) }
    if navigationStartsFirst {
      let navigation = Task { try await f.load("2026-11-23", through: "2026-11-24") }
      await gate.waitUntilStarted()
      await f.create()
      await gate.release()
      try await navigation.value
    } else {
      let create = Task { await f.create() }
      await gate.waitUntilStarted()
      try await f.load("2026-11-23", through: "2026-11-24")
      await gate.release()
      await create.value
    }
    #expect(f.timeline?.from == "2026-11-23")
    #expect(f.timeline?.to == "2026-11-24")
    #expect(f.timeline?.events.isEmpty == true)
    #expect(f.tasks.map(\.id) == [task.id])
  }

  @Test func aOneDayMacWindowStaysOneDayAfterCreate() async throws {
    let f = try await fixture(mobile: false)
    try await f.load("2026-11-15", through: "2026-11-15")
    await f.create()
    #expect(f.timeline?.from == "2026-11-15")
    #expect(f.timeline?.to == "2026-11-15")
  }

  @Test func resetDiscardsAnOlderMacWindowStillLoading() async throws {
    let f = try await fixture(mobile: false)
    let gate = CalendarCreationLoadGate(from: "2026-11-23")
    f.stub.loadCalendarTimelineGate = { from, _ in await gate.pauseOnce(from: from) }
    let navigation = Task { try await f.load("2026-11-23", through: "2026-11-24") }
    await gate.waitUntilStarted()
    f.mac.resetRuntimeState()
    await gate.release()
    try await navigation.value
    #expect(f.timeline == nil)
    #expect(f.mac.calendarScheduledTasks == nil)
    #expect(f.mac.calendarStorage.requestedWindow == nil)
  }
}

private actor CalendarCreationLoadGate {
  let from: String
  var didStart = false
  var started: CheckedContinuation<Void, Never>?
  var blocked: CheckedContinuation<Void, Never>?

  init(from: String) { self.from = from }

  func pauseOnce(from: String) async {
    guard from == self.from, !didStart else { return }
    didStart = true
    started?.resume()
    started = nil
    await withCheckedContinuation { blocked = $0 }
  }

  func waitUntilStarted() async {
    if didStart { return }
    await withCheckedContinuation { started = $0 }
  }

  func release() {
    blocked?.resume()
    blocked = nil
  }
}
