import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

actor MobileRecordingHabitReminderScheduler: HabitReminderScheduling {
  private var occurrences: [[DueHabitReminderOccurrence]] = []
  func replacements() -> [[DueHabitReminderOccurrence]] { occurrences }
  func replaceScheduledHabitReminders(
    for occurrences: [DueHabitReminderOccurrence]
  ) async -> TaskReminderScheduleReport {
    self.occurrences.append(occurrences)
    return .scheduled(occurrences.count)
  }
}

@MainActor
@Test
func mobileStoreRefreshReplansHabitReminders() async throws {
  let core = try await makeSeededInMemoryCore()
  let habit = try await core.createHabit(name: "Hydrate", cue: nil, targetCount: 1)
  _ = try await core.upsertHabitReminderPolicy(
    id: habit.id,
    policy: HabitReminderPolicy(
      id: "", habitID: habit.id, habitName: habit.name,
      reminderTime: "08:00", enabled: true, createdAt: "", updatedAt: ""))
  let scheduler = MobileRecordingHabitReminderScheduler()
  let store = MobileStore(
    core: core,
    habitReminderScheduler: scheduler,
    todayString: { "2026-05-23" },
    now: { Date(timeIntervalSince1970: 1_779_562_800) }
  )

  await store.refresh()

  let last = try #require(await scheduler.replacements().last)
  #expect(last.contains { $0.policy.habitID == habit.id && $0.policy.reminderTime == "08:00" })
}

// sf#1: a transient habit occurrence-read failure must NOT clear the pending
// habit notifications. The scheduler reaps every pending request before arming,
// so re-planning with an empty set on a read failure would silently cancel all
// habit notifications. The reschedule instead skips the reap entirely (keeping
// the last-good armed set), records the failure on the store report, and leaves
// an observable trace in the diagnostics ring.
@MainActor
@Test
func mobileStoreKeepsLastGoodHabitRemindersAndRecordsHabitReadFailure() async throws {
  let preview = try await makeSeededInMemoryCore()
  // A habit + reminder policy so a healthy read WOULD produce occurrences —
  // proving the skipped reap is what preserves the last-good armed set.
  let habit = try await preview.createHabit(name: "Stretch", cue: nil, targetCount: 1)
  _ = try await preview.upsertHabitReminderPolicy(
    id: habit.id,
    policy: HabitReminderPolicy(
      id: "", habitID: habit.id, habitName: habit.name,
      reminderTime: "08:00", enabled: true, createdAt: "", updatedAt: ""))
  let core = StubFocusCoreService(preview: preview)
  core.dueHabitReminderOccurrencesError = .unsupportedOperation("occurrence read boom")

  let scheduler = MobileRecordingHabitReminderScheduler()
  let store = MobileStore(
    core: core,
    habitReminderScheduler: scheduler,
    todayString: { "2026-05-23" },
    now: { Date(timeIntervalSince1970: 1_779_562_800) })

  await store.rescheduleReminders()

  // The reap is skipped entirely: the scheduler is never asked to replace, so
  // the last-good pending notifications survive.
  #expect(await scheduler.replacements().isEmpty)
  // The failure is recorded on the store report rather than being swallowed.
  #expect(store.lastHabitReminderScheduleReport.status == .failed)
  // And surfaced into the diagnostics ring for observability.
  let logs = try await core.loadRecentLogs(
    limit: 50, offset: 0, since: nil, levels: nil, sources: nil, redact: false)
  #expect(logs.entries.contains { $0.origin == "ios.reminders.schedule" })
}
