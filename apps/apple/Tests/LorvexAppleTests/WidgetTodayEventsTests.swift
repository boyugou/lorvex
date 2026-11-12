import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile
@testable import LorvexWidgetKitSupport

/// The large Today widget lists the day's calendar events still ahead under
/// its tasks, as the app's schedule reads them: an all-day event first, then
/// by start, each gone once it ends.
@Suite("Today widget events")
struct WidgetTodayEventsTests {
  private static let day = "2026-06-30"

  private static func event(
    _ id: String, start: Int? = nil, end: Int? = nil, carriedOver: Bool = false
  ) -> WidgetSnapshot.TodayEvent {
    WidgetSnapshot.TodayEvent(
      id: id, title: id, color: "#3B82F6", startMinutes: start, endMinutes: end,
      isCarriedOver: carriedOver)
  }

  private static func snapshot(
    tasks: [WidgetSnapshot.TodayTask] = [], events: [WidgetSnapshot.TodayEvent]
  ) -> WidgetSnapshot {
    WidgetSnapshot(
      generatedAt: "\(day)T08:00:00Z", timezone: "UTC", logicalDay: day,
      stats: .init(todayCount: tasks.count, overdueCount: 0, dueTodayCount: 0),
      briefing: nil, tasks: tasks, events: events)
  }

  private static func model(
    _ snapshot: WidgetSnapshot, at clock: String, family: WidgetFamilyKind = .systemLarge
  ) -> WidgetRenderModel {
    let date = LorvexDateFormatters.iso8601.date(from: "\(day)T\(clock):00Z") ?? Date()
    return WidgetRenderModelBuilder().model(
      entry: .init(
        date: date, state: .snapshot(snapshot, freshness: .fresh(ageSeconds: 0)),
        refreshAfter: date),
      family: family, statusText: "")
  }

  @Test("a snapshot carries the events key only when the day has events")
  func encoding() throws {
    func keys(_ snapshot: WidgetSnapshot) throws -> Set<String> {
      let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))
      return Set((object as? [String: Any] ?? [:]).keys)
    }
    #expect(try !keys(Self.snapshot(events: [])).contains("events"))
    let busy = Self.snapshot(events: [Self.event("standup", start: 540, end: 555), Self.event("holiday")])
    #expect(try keys(busy).contains("events"))
    #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(busy)) == busy)

    // A file written before the key existed still reads, with no events.
    var older = try JSONSerialization.jsonObject(
      with: JSONEncoder().encode(busy)) as? [String: Any] ?? [:]
    older.removeValue(forKey: "events")
    let decoded = try JSONDecoder().decode(
      WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: older))
    #expect(decoded.events.isEmpty)
  }

  @Test("an event alone changes what the widgets show")
  func eventsCountAsContent() {
    let before = Self.snapshot(events: [Self.event("standup", start: 540, end: 555)])
    let moved = Self.snapshot(events: [Self.event("standup", start: 600, end: 615)])
    #expect(!before.showsTheSame(as: moved))
    #expect(!before.showsTheSame(as: Self.snapshot(events: [])))
    #expect(before.showsTheSame(as: before))
  }

  @Test("a widget configured for one list shows that list's tasks and no events")
  func aListWidgetShowsNoEvents() {
    let snapshot = WidgetSnapshot(
      generatedAt: "\(Self.day)T08:00:00Z", timezone: "UTC", logicalDay: Self.day,
      stats: .init(todayCount: 0, overdueCount: 0, dueTodayCount: 0), briefing: nil, tasks: [],
      lists: [.init(id: "work", name: "Work", icon: nil)],
      events: [Self.event("standup", start: 540, end: 555)])
    #expect(snapshot.scoped(toList: "work").events.isEmpty)
    #expect(snapshot.scoped(toList: nil).events == snapshot.events)
  }

  @Test("the day's events reach the widget snapshot from the database, and not the watch")
  func eventsReachTheSnapshot() async throws {
    let core = try await makeSeededInMemoryCore()
    let source = try await core.loadWidgetSnapshotSource(date: nil)
    let day = source.logicalDay
    let tomorrow = try #require(LorvexDateFormatters.ymdUTCAddingDays(day, days: 1))
    let seeded = Set(source.events.map(\.id))
    func create(_ title: String, on date: String, from start: String?, to end: String?) async throws {
      _ = try await core.createCalendarEvent(
        title: title, startDate: date, endDate: nil, startTime: start, endTime: end,
        allDay: start == nil, location: nil, notes: nil)
    }
    try await create("Design review", on: day, from: "14:00", to: "15:00")
    try await create("Company holiday", on: day, from: nil, to: nil)
    try await create("Dentist", on: tomorrow, from: "09:00", to: "09:30")

    let loaded = try await core.loadWidgetSnapshotSource(date: day)
    let snapshot = try await WidgetSnapshotPublisher(
      destination: .init(snapshotURL: nil, reload: {})
    ).publish(source: loaded)
    let added = snapshot.events.filter { !seeded.contains($0.id) }
    #expect(added.map(\.title) == ["Company holiday", "Design review"], "all-day first, tomorrow's left out")
    let review = try #require(added.last)
    #expect(review.startMinutes == 14 * 60)
    #expect(review.endMinutes == 15 * 60)
    #expect(added.first?.isAllDay == true)

    let replica = try JSONDecoder().decode(
      WidgetSnapshot.self, from: WatchReplicaSnapshotProjector().encodedSnapshot(from: snapshot))
    #expect(replica.events.isEmpty, "the watch draws no events, so its replica carries none")
  }

  @Test("hidden titles hide the events' titles too")
  func hiddenTitles() {
    let event = CalendarTimelineEvent(
      id: "e1", title: "Salary negotiation", source: "lorvex", editable: true,
      startDate: Self.day, startTime: "14:00", endDate: Self.day, endTime: "15:00",
      allDay: false, location: nil, color: nil, eventType: "event", timezone: "UTC",
      isRecurring: false)
    let today = TodaySnapshot(summary: "", tasks: [], localChangeSequence: 0)
    let open = WidgetSnapshotProjector().snapshot(
      logicalDay: Self.day, today: today, timezone: "UTC", events: [event])
    let hidden = WidgetSnapshotProjector().snapshot(
      logicalDay: Self.day, today: today, timezone: "UTC", hideTitles: true, events: [event])
    #expect(open.events.map(\.title) == ["Salary negotiation"])
    #expect(hidden.events.map(\.title) == ["Busy"])
  }

  @Test("the large widget lists the events still ahead, each with its time")
  func eventRows() throws {
    let snapshot = Self.snapshot(events: [
      Self.event("holiday"),
      Self.event("late-flight", start: 0, end: 60, carriedOver: true),
      Self.event("standup", start: 540, end: 555),
      Self.event("review", start: 840, end: 900),
      Self.event("dinner", start: 1140, end: 1260),
    ])
    let morning = Self.model(snapshot, at: "09:05")
    #expect(morning.eventRows.map(\.id) == ["holiday", "standup", "review"], "the finished flight is gone; three at most")
    #expect(morning.eventRows[0].timeLabel == "All day")
    #expect(morning.eventRows[1].timeLabel == "Until \(lorvexClockTimeLabel(minutes: 555))")
    #expect(morning.eventRows[1].tone == .running)
    #expect(morning.eventRows[2].timeLabel == lorvexClockTimeLabel(minutes: 840))
    #expect(morning.eventRows[2].tone == .plain)

    let night = Self.model(snapshot, at: "00:30")
    #expect(night.eventRows.map(\.id).prefix(2) == ["holiday", "late-flight"])
    #expect(night.eventRows[1].timeLabel == "Until \(lorvexClockTimeLabel(minutes: 60))")

    let evening = Self.model(snapshot, at: "21:00")
    #expect(evening.eventRows.map(\.id) == ["holiday"], "each timed event left once it ended")

    #expect(Self.model(snapshot, at: "09:05", family: .systemMedium).eventRows.isEmpty)
  }

  @Test("the widget redraws when an event starts and when it ends")
  func changeDatesFollowEvents() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    let from = try #require(LorvexDateFormatters.iso8601.date(from: "\(Self.day)T08:00:00Z"))
    let until = try #require(calendar.date(byAdding: .hour, value: 12, to: from))
    let dates = WidgetTodayGlance.changeDates(
      tasks: [], events: [Self.event("review", start: 840, end: 900), Self.event("holiday")],
      from: from, until: until, timezoneName: "UTC", calendar: calendar)
    let minutes = dates.map { calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0) }
    #expect(minutes == [840, 900])
  }
}
