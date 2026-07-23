import Foundation
import LorvexCore
import LorvexDomain
import Testing

@testable import LorvexMobile

/// N2 / N3 exercised through the live `MobileStore` reschedule flow with
/// recording schedulers: the rolling reminder window replenishes as earlier
/// reminders leave the pending set, and a consumed weekly habit cadence's
/// already-armed later same-cycle reminders are cancelled on the next replenish.
private final class MutableClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Date
  init(_ value: Date) { self.value = value }
  var now: Date { lock.withLock { value } }
  func set(_ newValue: Date) { lock.withLock { value = newValue } }
}

/// N2: only the earliest ``ReminderBudget/pendingNotificationLimit`` reminders
/// fit the shared OS cap, so a later reminder is dropped until an earlier one
/// leaves the active set. `replenishReminderWindow` re-selects the earliest-due
/// set every pass, so once the earlier reminders are consumed the previously
/// budgeted-out reminder gets armed — the window is self-refilling rather than
/// permanently starving requests 61+.
@MainActor
@Test("The reminder window replenishes as earlier reminders leave the pending set")
func mobileStoreReplenishesReminderWindow() async throws {
  let core = try makeInMemoryCore()
  let scheduler = RecordingTaskReminderScheduler()
  let store = MobileStore(core: core, taskReminderScheduler: scheduler)

  let task = try await core.createTask(title: "Many reminders", notes: "")
  let iso = ISO8601DateFormatter()
  iso.formatOptions = [.withInternetDateTime]
  // Reminders spaced an hour apart starting an hour out — all future, and inside
  // the store's upcoming-reminder query horizon (well under a year). Floored to a
  // whole second so the derived instants match the whole-second stored form
  // parsed back off the reminder rows.
  let base = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 3600).rounded())
  let overCap = ReminderBudget.pendingNotificationLimit + 1
  let all = (0..<overCap).map { iso.string(from: base.addingTimeInterval(Double($0) * 3600)) }
  _ = try await core.setTaskReminders(taskID: task.id, reminderAts: all)

  await store.replenishReminderWindow()
  let armed1 = Set(await scheduler.lastScheduledFireDates())
  let latest = base.addingTimeInterval(Double(overCap - 1) * 3600)
  #expect(armed1.count == ReminderBudget.pendingNotificationLimit)
  #expect(!armed1.contains(latest))  // the latest reminder is budgeted out

  // The earliest 31 fire / are consumed and leave the active reminder set.
  let remaining = Array(all[30...])
  _ = try await core.setTaskReminders(taskID: task.id, reminderAts: remaining)

  await store.replenishReminderWindow()
  let armed2 = Set(await scheduler.lastScheduledFireDates())
  #expect(armed2.count == remaining.count)  // all now fit the cap
  #expect(armed2.contains(latest))  // the previously-dropped reminder is armed
}

/// N3: a daily-scheduled weekly habit (one nudge per week, below target) would
/// pre-arm a reminder on every remaining day of the week. Once the earliest one
/// fires and a replenish reconciles the consumed cadence period, the already-
/// armed later same-cycle reminders must be cancelled rather than continuing to
/// fire (over-notification). `replenishReminderWindow` runs that reconcile.
@MainActor
@Test("A consumed weekly habit cadence cancels its remaining same-cycle reminders")
func mobileStoreCancelsRemainingSameCycleHabitRemindersOnReplenish() async throws {
  let core = try makeInMemoryCore()
  let habitScheduler = RecordingHabitReminderScheduler()
  let iso = ISO8601DateFormatter()
  iso.formatOptions = [.withInternetDateTime]
  // Wednesday noon UTC: in every device timezone (UTC-12..+14) the two earliest
  // future fire days land in the same ISO week, so consuming the first debounces
  // the second regardless of the test machine's zone.
  let clock = MutableClock(iso.date(from: "2026-06-24T12:00:00Z")!)
  let store = MobileStore(
    core: core, habitReminderScheduler: habitScheduler, now: { clock.now })

  let habit = try await core.createHabit(
    name: "Read", cue: nil, icon: nil, color: nil, targetCount: 1,
    cadence: HabitCadenceInput(frequencyType: "weekly"))
  _ = try await core.upsertHabitReminderPolicy(
    id: habit.id,
    policy: HabitReminderPolicy(
      id: "", habitID: habit.id, habitName: habit.name, reminderTime: "23:30",
      enabled: true, createdAt: "", updatedAt: ""))

  await store.replenishReminderWindow()
  let armed1 = ((await habitScheduler.replacements().last ?? []).map(\.fireDate)).sorted()
  #expect(armed1.count >= 2)  // multiple same-cycle occurrences pre-armed

  // The earliest reminder fires: advance the clock just past it, then let the
  // launch/foreground replenish reconcile the now-consumed cadence period.
  let fired = try #require(armed1.first)
  let nextSameCycle = armed1[1]
  clock.set(fired.addingTimeInterval(60))
  await store.replenishReminderWindow()
  let armed2 = Set((await habitScheduler.replacements().last ?? []).map(\.fireDate))

  #expect(nextSameCycle > fired.addingTimeInterval(60))  // still in the future
  #expect(!armed2.contains(nextSameCycle))  // cancelled by the reconcile
}
