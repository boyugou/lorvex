import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

@MainActor
@Test
func appStoreAddsAndRemovesHabitReminder() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let habit = try #require(
    store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })

  await store.addHabitReminder(habitID: habit.id, time: "08:00")
  await store.addHabitReminder(habitID: habit.id, time: "20:30")

  let afterAdd = try #require(store.habitDetail(for: habit.id))
  #expect(Set(afterAdd.reminderPolicies.map(\.reminderTime)) == ["08:00", "20:30"])
  #expect(store.errorMessage == nil)

  let policy = try #require(afterAdd.reminderPolicies.first { $0.reminderTime == "08:00" })
  await store.removeHabitReminder(habitID: habit.id, policyID: policy.id)

  let afterRemove = try #require(store.habitDetail(for: habit.id))
  #expect(afterRemove.reminderPolicies.map(\.reminderTime) == ["20:30"])
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreTogglesHabitReminderEnabled() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let habit = try #require(
    store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })

  await store.addHabitReminder(habitID: habit.id, time: "09:00")
  let policy = try #require(store.habitDetail(for: habit.id)?.reminderPolicies.first)
  #expect(policy.enabled)

  await store.toggleHabitReminderEnabled(policy: policy)
  let disabled = try #require(store.habitDetail(for: habit.id)?.reminderPolicies.first)
  #expect(!disabled.enabled)

  await store.toggleHabitReminderEnabled(policy: disabled)
  let reenabled = try #require(store.habitDetail(for: habit.id)?.reminderPolicies.first)
  #expect(reenabled.enabled)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreSetsHabitReminderTimesReconcilesTheSet() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let habit = try #require(
    store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })

  await store.addHabitReminder(habitID: habit.id, time: "08:00")
  await store.addHabitReminder(habitID: habit.id, time: "12:00")

  // Reconcile to a new set: 08:00 stays, 12:00 is dropped, 16:00/20:00 are added.
  await store.setHabitReminderTimes(habitID: habit.id, times: ["08:00", "16:00", "20:00"])

  let detail = try #require(store.habitDetail(for: habit.id))
  #expect(Set(detail.reminderPolicies.map(\.reminderTime)) == ["08:00", "16:00", "20:00"])
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreRetimesHabitReminderInPlace() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let habit = try #require(
    store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })

  await store.addHabitReminder(habitID: habit.id, time: "08:00")
  let policies = try #require(store.habitDetail(for: habit.id)?.reminderPolicies)
  let policy = try #require(policies.first)

  await store.setHabitReminderTime(policy: policy, to: "07:15", in: policies)

  let detail = try #require(store.habitDetail(for: habit.id))
  #expect(detail.reminderPolicies.map(\.reminderTime) == ["07:15"])
  #expect(detail.reminderPolicies.first?.id == policy.id)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreCreateDraftHabitArmsCreateTimeReminders() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()

  store.beginCreateHabitDraft()
  store.draftHabitName = "Meditate"
  store.draftHabitReminderTimes = ["07:00", "21:30"]
  await store.createDraftHabit()
  #expect(store.errorMessage == nil)

  let created = try #require(store.habits?.habits.first { $0.name == "Meditate" })
  let policies = try await core.getHabitReminderPolicies(id: created.id)
  #expect(Set(policies.map(\.reminderTime)) == ["07:00", "21:30"])
  #expect(policies.allSatisfy { $0.enabled })
  // A successful create clears the shared draft, including its reminder times.
  #expect(store.draftHabitReminderTimes.isEmpty)
}

@Test("habit and create-time reminders roll back as one mutation")
func createHabitWithRemindersIsAtomic() async throws {
  let core = try await makeSeededInMemoryCore()
  let beforeHabits = try await core.loadHabits(date: "2026-05-23")
  let beforePolicies = try await core.getAllHabitReminderPolicies()

  do {
    _ = try await core.createHabit(
      name: "Must Roll Back",
      cue: nil,
      icon: nil,
      color: nil,
      targetCount: 1,
      cadence: .daily,
      milestoneTarget: nil,
      reminderTimes: ["07:00", "not-a-time"])
    Issue.record("invalid reminder must fail the atomic habit creation")
  } catch {
    // Expected: the invalid second slot aborts the same transaction that inserted
    // the habit and first slot.
  }

  let afterHabits = try await core.loadHabits(date: "2026-05-23")
  let afterPolicies = try await core.getAllHabitReminderPolicies()
  #expect(afterHabits.habits.map(\.id) == beforeHabits.habits.map(\.id))
  #expect(afterPolicies.map(\.id) == beforePolicies.map(\.id))
  #expect(!afterHabits.habits.contains { $0.name == "Must Roll Back" })
}

@Test
func habitReminderWindowGeneratesEvenlySpacedTimes() {
  // 09:00–21:00 (720 min) split into 8 reminders: step 90 min, first at 10:30.
  let times = HabitReminderTime.evenlySpacedTimes(start: 9 * 60, end: 21 * 60, count: 8)
  #expect(times == ["10:30", "12:00", "13:30", "15:00", "16:30", "18:00", "19:30", "21:00"])
  #expect(times.count == 8)
}

@Test
func habitReminderWindowRoundsToFiveMinuteGrain() throws {
  // 09:00–21:00 (720 min) over 7 reminders: step ≈102.86 min, each snapped to 5.
  let times = HabitReminderTime.evenlySpacedTimes(start: 9 * 60, end: 21 * 60, count: 7)
  #expect(times.count == 7)
  for time in times {
    let minutes = try #require(HabitReminderTime.minutesOfDay(time))
    #expect(minutes % 5 == 0)
    #expect(minutes <= 21 * 60)
  }
  #expect(times.last == "21:00")
}

@Test
@MainActor
func habitReminderWindowIntervalAndLabel() {
  #expect(HabitReminderTime.intervalMinutes(start: 9 * 60, end: 21 * 60, count: 7) == 103)
  #expect(HabitReminderWindowSection.intervalLabel(minutes: 103) == "1h 43m")
  #expect(HabitReminderWindowSection.intervalLabel(minutes: 120) == "2h")
  #expect(HabitReminderWindowSection.intervalLabel(minutes: 45) == "45m")
}

@Test
func habitReminderHintIsCadenceAware() throws {
  let daily = LorvexHabit(
    id: "h1", name: "Stretch", icon: nil, color: nil, cue: nil,
    frequencyType: "daily", targetCount: 1, completionsToday: 0, totalCompletions: 0,
    completionRate30d: 0, archived: false)
  let dailyHint = try #require(HabitReminderHint.text(for: daily, mode: .specific))
  #expect(dailyHint.contains("scheduled"))

  let custom = LorvexHabit(
    id: "h2", name: "Walk", icon: nil, color: nil, cue: nil,
    frequencyType: "times_per_week", targetCount: 3, completionsToday: 0, totalCompletions: 0,
    completionRate30d: 0, archived: false, perPeriodTarget: 4)
  let customHint = try #require(HabitReminderHint.text(for: custom, mode: .specific))
  #expect(customHint.contains("4"))

  let multi = LorvexHabit(
    id: "h3", name: "Hydrate", icon: nil, color: nil, cue: nil,
    frequencyType: "daily", targetCount: 8, completionsToday: 0, totalCompletions: 0,
    completionRate30d: 0, archived: false)
  let multiHint = try #require(HabitReminderHint.text(for: multi, mode: .specific))
  #expect(multiHint.contains("8"))
  // The window mode defers to its own preview line, so the section hint is nil.
  #expect(HabitReminderHint.text(for: multi, mode: .window) == nil)
}
