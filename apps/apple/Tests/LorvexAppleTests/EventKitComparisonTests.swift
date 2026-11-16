@preconcurrency import EventKit
import Foundation
import LorvexCore
import Testing

@Suite("EventKit duplicate comparison context")
struct EventKitComparisonTests {
  @Test func recurringContextAndPersonalAlarmsAreComparedWithoutExpandingRules() throws {
    let store = EKEventStore()
    let event = EKEvent(eventStore: store)
    event.startDate = Date(timeIntervalSince1970: 1_800_000_000)
    event.endDate = event.startDate.addingTimeInterval(3600)
    let oneOff = try #require(EventKitComparison.signature(for: event))
    event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)]
    let weekly = try #require(EventKitComparison.signature(for: event))
    #expect(weekly != oneOff)
    event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)]
    #expect(EventKitComparison.signature(for: event) != weekly)
    event.recurrenceRules = nil
    event.alarms = [EKAlarm(relativeOffset: -600)]
    #expect(EventKitComparison.signature(for: event) != oneOff)
  }

  @Test func alarmOrderingDoesNotChangeContext() throws {
    let event = EKEvent(eventStore: EKEventStore())
    event.alarms = [EKAlarm(relativeOffset: -600), EKAlarm(relativeOffset: -300)]
    let first = try #require(EventKitComparison.signature(for: event))
    event.alarms = Array((event.alarms ?? []).reversed())
    #expect(EventKitComparison.signature(for: event) == first)
  }
}
