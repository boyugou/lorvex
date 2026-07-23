import Foundation
import LorvexCore
import LorvexMobile
import Testing

// I2 — mobile habit editing: the draft's cadence bridge, and the store threading
// cadence + reminder-policy edits to the core (matching macOS habit editing and
// the update_habit / upsert_habit_reminder_policy MCP tools).

@Test
func mobileHabitDraftCadenceInputBridgesEditorSelections() {
  var draft = MobileHabitDraft()
  #expect(draft.cadenceInput.frequencyType == "daily")
  #expect(draft.showsPerDayTarget)
  #expect(draft.frequencyType == "daily")

  draft.cadenceMode = .weekly
  draft.weeklyStyle = .specificDays
  draft.weekdays = [4, 0, 2]
  #expect(draft.cadenceInput.frequencyType == "weekly")
  #expect(draft.cadenceInput.weekdays == [0, 2, 4])
  #expect(draft.frequencyType == "weekly")
  #expect(draft.showsPerDayTarget)

  draft.weeklyStyle = .timesPerWeek
  draft.timesPerWeek = 4
  #expect(draft.cadenceInput.frequencyType == "times_per_week")
  #expect(draft.cadenceInput.perPeriodTarget == 4)
  #expect(!draft.showsPerDayTarget)
  #expect(draft.resolvedTargetCount == 1)

  draft.cadenceMode = .monthly
  draft.dayOfMonth = 15
  #expect(draft.cadenceInput.frequencyType == "monthly")
  #expect(draft.cadenceInput.dayOfMonth == 15)
  #expect(!draft.showsPerDayTarget)
  #expect(draft.resolvedTargetCount == 1)
}

@Test
func mobileHabitDraftInitMapsStoredCadence() {
  let habit = LorvexHabit(
    id: "habit-read", name: "Read", icon: nil, color: nil, cue: nil,
    frequencyType: "weekly", targetCount: 1, completionsToday: 0,
    totalCompletions: 0, completionRate30d: 0, archived: false,
    weekdays: [1, 3, 5])
  let draft = MobileHabitDraft(habit: habit)
  #expect(draft.cadenceMode == .weekly)
  #expect(draft.weeklyStyle == .specificDays)
  #expect(draft.weekdays == [1, 3, 5])
}

@MainActor
@Test
func mobileStoreCreatesHabitWithWeeklyCadenceThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  store.beginCreateHabitDraft()
  store.habitDraft.name = "Gym"
  store.habitDraft.cadenceMode = .weekly
  store.habitDraft.weeklyStyle = .specificDays
  store.habitDraft.weekdays = [0, 2, 4]

  let created = await store.createDraftHabit()

  #expect(created)
  let gym = try #require(
    (try await core.loadHabits(date: "2026-05-23")).habits.first { $0.name == "Gym" })
  #expect(gym.frequencyType == "weekly")
  #expect(Set(gym.weekdays ?? []) == [0, 2, 4])
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreUpdatesHabitCadenceToMonthlyThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let habit = try #require((try await core.loadHabits(date: "2026-05-23")).habits.first)

  store.prepareHabitDraft(for: habit)
  store.habitDraft.cadenceMode = .monthly
  store.habitDraft.dayOfMonth = 12

  let updated = await store.updateHabit(habit)

  #expect(updated)
  let reloaded = try #require(
    (try await core.loadHabits(date: "2026-05-23")).habits.first { $0.id == habit.id })
  #expect(reloaded.frequencyType == "monthly")
  #expect(reloaded.dayOfMonth == 12)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreAddsRetimesTogglesAndRemovesHabitReminder() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let habit = try #require((try await core.loadHabits(date: "2026-05-23")).habits.first)

  #expect(await store.addHabitReminder(habitID: habit.id, time: "08:30"))
  let added = try #require(store.habitDetail(for: habit.id)?.reminderPolicies.first)
  #expect(store.habitDetail(for: habit.id)?.reminderPolicies.count == 1)
  #expect(added.reminderTime == "08:30")
  #expect(added.enabled)

  #expect(await store.toggleHabitReminderEnabled(policy: added))
  let toggled = try #require(store.habitDetail(for: habit.id)?.reminderPolicies.first)
  #expect(!toggled.enabled)

  #expect(await store.setHabitReminderTime(policy: toggled, to: "09:15"))
  let retimed = try #require(store.habitDetail(for: habit.id)?.reminderPolicies.first)
  #expect(retimed.reminderTime == "09:15")
  #expect(!retimed.enabled)

  #expect(await store.removeHabitReminder(habitID: habit.id, policyID: retimed.id))
  let policies = store.habitDetail(for: habit.id)?.reminderPolicies ?? []
  #expect(policies.isEmpty)
  #expect(store.errorMessage == nil)
}
