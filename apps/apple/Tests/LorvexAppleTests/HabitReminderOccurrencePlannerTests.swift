import Foundation
import LorvexDomain
import Testing

import LorvexCore

struct HabitReminderOccurrencePlannerTests {
  private struct ProgressReadError: Error {}

  /// A failed period-progress read must propagate out of `plan`, not be
  /// swallowed as a zero — a silent zero makes an already-completed period look
  /// incomplete and fires a false reminder.
  @Test("plan rethrows a progress-read failure instead of treating it as zero")
  func planRethrowsProgressReadFailure() {
    let policy = HabitReminderPolicy(
      id: "p1", habitID: "h1", habitName: "Stretch", reminderTime: "23:00",
      enabled: true, createdAt: "2026-06-25T00:00:00.000Z",
      updatedAt: "2026-06-25T00:00:00.000Z")
    let input = HabitReminderOccurrencePlanner.PolicyInput(
      policy: policy, cadence: .daily, targetCount: 1)

    let zone = TimeZone(identifier: "UTC") ?? .current
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    // Midnight UTC, so the 23:00 daily reminder is still in the future today and
    // the day walk reaches the progress lookup.
    let now = calendar.date(
      from: DateComponents(year: 2026, month: 6, day: 25, hour: 0, minute: 0))!

    #expect(throws: ProgressReadError.self) {
      try HabitReminderOccurrencePlanner.plan(
        inputs: [input], now: now, horizonDays: 1, zone: zone
      ) { _, _, _ in throw ProgressReadError() }
    }
  }

  private func dailyInput(reminderTime: String) -> HabitReminderOccurrencePlanner.PolicyInput {
    let policy = HabitReminderPolicy(
      id: "p1", habitID: "h1", habitName: "Stretch", reminderTime: reminderTime,
      enabled: true, createdAt: "2026-06-25T00:00:00.000Z",
      updatedAt: "2026-06-25T00:00:00.000Z")
    return HabitReminderOccurrencePlanner.PolicyInput(
      policy: policy, cadence: .daily, targetCount: 1)
  }

  private static let utc = TimeZone(identifier: "UTC") ?? .current
  private func utcInstant(hour: Int, minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Self.utc
    return calendar.date(
      from: DateComponents(year: 2026, month: 6, day: 25, hour: hour, minute: minute))!
  }

  /// The most recent in-period firing whose scheduled time has elapsed is
  /// returned, so the backend can stamp it as `last_delivered_at`.
  @Test("mostRecentDeliveredOccurrence returns an elapsed in-period firing")
  func mostRecentFiredReturnsElapsed() {
    let fired = HabitReminderOccurrencePlanner.mostRecentDeliveredOccurrence(
      input: dailyInput(reminderTime: "08:00"), now: utcInstant(hour: 12), zone: Self.utc
    ) { _, _, _ in 0 }
    #expect(fired == utcInstant(hour: 8))
  }

  /// A period already at/over target stamps nothing — no reminder fired and
  /// `plan` wouldn't fire one either.
  @Test("mostRecentDeliveredOccurrence returns nil once the period is met")
  func mostRecentFiredNilWhenMet() {
    let fired = HabitReminderOccurrencePlanner.mostRecentDeliveredOccurrence(
      input: dailyInput(reminderTime: "08:00"), now: utcInstant(hour: 12), zone: Self.utc
    ) { _, _, _ in 1 }
    #expect(fired == nil)
  }

  /// When today's only firing is still in the future, nothing has fired yet.
  @Test("mostRecentDeliveredOccurrence returns nil when no firing has elapsed")
  func mostRecentFiredNilWhenNotElapsed() {
    let fired = HabitReminderOccurrencePlanner.mostRecentDeliveredOccurrence(
      input: dailyInput(reminderTime: "23:00"), now: utcInstant(hour: 12), zone: Self.utc
    ) { _, _, _ in 0 }
    #expect(fired == nil)
  }

  private func isoUTC(_ raw: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: raw) ?? Date(timeIntervalSince1970: 0)
  }

  /// A reminder whose local wall time falls in a spring-forward DST gap (a time
  /// that does not exist because the clock jumps forward) is skipped, not
  /// silently slid to the next real instant. On 2026-03-08 in
  /// `America/Los_Angeles` the clock jumps 02:00 → 03:00, so 02:30 never
  /// happens; `Calendar.date(from:)` would leniently map it to 03:30, which the
  /// planner must reject. A valid time on the same scheduled day still fires,
  /// proving only the nonexistent instant was dropped.
  @Test("A spring-forward DST-gap reminder time is skipped, not shifted forward")
  func springForwardGapReminderSkipped() throws {
    let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    // 00:30 PST on 2026-03-08 — before the 02:30 fire, so the day-0 walk reaches
    // it, and on the same local calendar day as the gap.
    let now = isoUTC("2026-03-08T08:30:00Z")

    let gap = HabitReminderOccurrencePlanner.plan(
      inputs: [dailyInput(reminderTime: "02:30")], now: now, horizonDays: 1, zone: losAngeles
    ) { _, _, _ in 0 }
    #expect(gap.isEmpty)

    let valid = HabitReminderOccurrencePlanner.plan(
      inputs: [dailyInput(reminderTime: "04:30")], now: now, horizonDays: 1, zone: losAngeles
    ) { _, _, _ in 0 }
    // 04:30 PDT (UTC-7, post-transition) == 11:30Z.
    #expect(valid.map(\.fireDate) == [isoUTC("2026-03-08T11:30:00Z")])
  }
}
