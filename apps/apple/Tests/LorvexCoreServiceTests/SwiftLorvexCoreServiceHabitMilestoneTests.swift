import LorvexStore
import XCTest

@testable import LorvexCore

/// Coverage for the habit `milestone_target` setter + the computed milestone
/// standing carried on reads, run against a temp store seeded with the
/// authoritative `schema/schema.sql`. Exercises the create/update/import SQL
/// paths (the `milestone_target > 0` CHECK, the `COALESCE`-on-conflict import
/// semantics) and the streak-vs-count metric projection the read tools surface.
final class SwiftLorvexCoreServiceHabitMilestoneTests: XCTestCase {
  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  private func uuid() -> String { UUID().uuidString.lowercased() }

  // MARK: - Setter

  func testCreateHabitSetsMilestoneTarget() async throws {
    let service = try makeService()
    let created = try await service.createHabit(
      name: "Meditate", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily, milestoneTarget: 30)
    XCTAssertEqual(created.milestoneTarget, 30)
    // A daily habit tracks the streak; with no completions the metric reads 0 and
    // the user target (30) is the next milestone.
    XCTAssertEqual(created.milestone?.metric, "streak")
    XCTAssertEqual(created.milestone?.value, 0)
    XCTAssertEqual(created.milestone?.nextMilestone, 30)
    XCTAssertEqual(created.milestone?.progressToNext, 0)

    // The standing survives a fresh read.
    let reloaded = try await service.loadHabits(date: "2026-06-30").habits.first { $0.id == created.id }
    XCTAssertEqual(reloaded?.milestoneTarget, 30)
    XCTAssertEqual(reloaded?.milestone?.nextMilestone, 30)

    let stats = try await service.getHabitStats(id: created.id)
    XCTAssertEqual(stats.milestoneTarget, 30)
    XCTAssertEqual(stats.nextMilestone, 30)
    XCTAssertEqual(stats.progressToNext, 0)
  }

  func testCreateHabitRejectsNonPositiveMilestone() async throws {
    let service = try makeService()
    var threw = false
    do {
      _ = try await service.createHabit(
        name: "Bad", cue: nil, icon: nil, color: nil, targetCount: 1,
        cadence: .daily, milestoneTarget: 0)
    } catch {
      threw = true
    }
    XCTAssertTrue(threw, "A non-positive milestone_target must be rejected.")
  }

  func testUpdateHabitSetsClearsAndLeavesMilestone() async throws {
    let service = try makeService()
    let created = try await service.createHabit(
      name: "Read", cue: nil, targetCount: 1)
    XCTAssertNil(created.milestoneTarget)

    // `.set` writes the goal.
    let set = try await service.updateHabit(
      id: created.id, name: nil, cue: nil, color: nil, icon: nil, targetCount: nil,
      archived: nil, cadence: nil, milestoneTarget: .set(14))
    XCTAssertEqual(set.milestoneTarget, 14)

    // `.unset` (via a name-only convenience update) leaves it untouched.
    let renamed = try await service.updateHabit(
      id: created.id, name: "Read daily", cue: nil, color: nil, icon: nil, targetCount: nil)
    XCTAssertEqual(renamed.milestoneTarget, 14)

    // `.clear` removes it.
    let cleared = try await service.updateHabit(
      id: created.id, name: nil, cue: nil, color: nil, icon: nil, targetCount: nil,
      archived: nil, cadence: nil, milestoneTarget: .clear)
    XCTAssertNil(cleared.milestoneTarget)
  }

  func testUpdateHabitRejectsNonPositiveMilestone() async throws {
    let service = try makeService()
    let created = try await service.createHabit(name: "X", cue: nil, targetCount: 1)
    var threw = false
    do {
      _ = try await service.updateHabit(
        id: created.id, name: nil, cue: nil, color: nil, icon: nil, targetCount: nil,
        archived: nil, cadence: nil, milestoneTarget: .set(-3))
    } catch {
      threw = true
    }
    XCTAssertTrue(threw)
  }

  // MARK: - Cadence input rejection

  func testCreateHabitRejectsOutOfRangeWeekday() async throws {
    let service = try makeService()
    var threw = false
    do {
      _ = try await service.createHabit(
        name: "Bad weekday", cue: nil, icon: nil, color: nil, targetCount: 1,
        cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [0, 9]),
        milestoneTarget: nil)
    } catch {
      threw = true
    }
    XCTAssertTrue(threw, "An out-of-range weekday must be rejected, not silently dropped.")
  }

  func testCreateHabitRejectsOutOfRangeDayOfMonth() async throws {
    let service = try makeService()
    var threw = false
    do {
      _ = try await service.createHabit(
        name: "Bad DOM", cue: nil, icon: nil, color: nil, targetCount: 1,
        cadence: HabitCadenceInput(frequencyType: "monthly", dayOfMonth: 45),
        milestoneTarget: nil)
    } catch {
      threw = true
    }
    XCTAssertTrue(threw, "An out-of-range day_of_month must be rejected, not silently coerced.")
  }

  func testUpdateHabitRejectsOutOfRangeWeekday() async throws {
    let service = try makeService()
    let created = try await service.createHabit(name: "Rhythm", cue: nil, targetCount: 1)
    var threw = false
    do {
      _ = try await service.updateHabit(
        id: created.id, name: nil, cue: nil, color: nil, icon: nil, targetCount: nil,
        archived: nil,
        cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [-1]),
        milestoneTarget: .unset)
    } catch {
      threw = true
    }
    XCTAssertTrue(threw)
  }

  // MARK: - Metric projection

  func testCountCadenceUsesCountMetric() async throws {
    let service = try makeService()
    let created = try await service.createHabit(
      name: "Gym", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3),
      milestoneTarget: nil)
    let habit = try await service.loadHabits(date: "2026-06-30").habits.first { $0.id == created.id }
    XCTAssertEqual(habit?.milestone?.metric, "count")
    XCTAssertEqual(habit?.milestone?.value, 0)
    // Count ladder starts at 10.
    XCTAssertEqual(habit?.milestone?.nextMilestone, 10)
  }

  func testStreakMetricReflectsConsecutiveCompletions() async throws {
    let service = try makeService()
    let created = try await service.createHabit(name: "Stretch", cue: nil, targetCount: 1)
    for day in ["2026-06-28", "2026-06-29", "2026-06-30"] {
      _ = try await service.completeHabit(id: created.id, date: day)
    }
    let habit = try await service.loadHabits(date: "2026-06-30").habits.first { $0.id == created.id }
    XCTAssertEqual(habit?.milestone?.metric, "streak")
    XCTAssertEqual(habit?.milestone?.value, 3)
    // Below the first streak rung (7): no current milestone, aiming for 7.
    XCTAssertNil(habit?.milestone?.currentMilestone)
    XCTAssertEqual(habit?.milestone?.nextMilestone, 7)
  }

  // MARK: - Reached-milestone flagging on completion

  private func justReached(
    _ snapshot: HabitCatalogSnapshot, id: String
  ) -> Int?? {
    snapshot.habits.first { $0.id == id }?.milestone?.justReached
  }

  func testCompleteHabitFlagsReachedMilestoneAtStreakTarget() async throws {
    let service = try makeService()
    let created = try await service.createHabit(
      name: "Streak", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily, milestoneTarget: 3)
    // Days 1 and 2 build the streak without crossing the target-3 milestone.
    let day1 = try await service.completeHabit(id: created.id, date: "2026-06-28")
    XCTAssertNil(justReached(day1, id: created.id) ?? nil)
    let day2 = try await service.completeHabit(id: created.id, date: "2026-06-29")
    XCTAssertNil(justReached(day2, id: created.id) ?? nil)
    // The third consecutive day crosses streak 2→3 == the user target.
    let day3 = try await service.completeHabit(id: created.id, date: "2026-06-30")
    XCTAssertEqual(justReached(day3, id: created.id) ?? nil, 3)
  }

  func testCompleteHabitCrossingNoMilestoneReturnsNil() async throws {
    let service = try makeService()
    let created = try await service.createHabit(name: "Nothing", cue: nil, targetCount: 1)
    // No user target and streak 0→1 is below the first ladder rung (7).
    let after = try await service.completeHabit(id: created.id, date: "2026-06-30")
    XCTAssertNil(justReached(after, id: created.id) ?? nil)
  }

  func testCompleteHabitFlagsReachedMilestoneForCountMetric() async throws {
    let service = try makeService()
    let created = try await service.createHabit(
      name: "Gym", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3),
      milestoneTarget: 2)
    // Count metric: each new day adds to the cumulative total.
    let first = try await service.completeHabit(id: created.id, date: "2026-06-29")
    XCTAssertNil(justReached(first, id: created.id) ?? nil)
    let second = try await service.completeHabit(id: created.id, date: "2026-06-30")
    XCTAssertEqual(justReached(second, id: created.id) ?? nil, 2)
  }

  func testBatchCompleteFlagsReachedMilestone() async throws {
    let service = try makeService()
    let created = try await service.createHabit(
      name: "Batch", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily, milestoneTarget: 1)
    // Streak 0→1 hits the user target of 1 in a single batch completion.
    let snapshot = try await service.batchCompleteHabits(ids: [created.id], date: "2026-06-30")
    XCTAssertEqual(justReached(snapshot, id: created.id) ?? nil, 1)
  }

  func testAdjustHabitCompletionFlagsReachedMilestone() async throws {
    let service = try makeService()
    // Count-metric cadence with a per-day cap of 5, milestone at cumulative 2.
    let created = try await service.createHabit(
      name: "Water", cue: nil, icon: nil, color: nil, targetCount: 5,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3),
      milestoneTarget: 2)
    // A positive adjust that lifts the cumulative count 0→2 crosses the target.
    let up = try await service.adjustHabitCompletion(id: created.id, date: "2026-06-30", delta: 2)
    XCTAssertEqual(justReached(up, id: created.id) ?? nil, 2)
    // A decrement never crosses a milestone upward: no flag.
    let down = try await service.adjustHabitCompletion(id: created.id, date: "2026-06-30", delta: -1)
    XCTAssertNil(justReached(down, id: created.id) ?? nil)
  }

  // MARK: - get_habit_stats field parity

  func testGetHabitStatsCarriesNameAndMetric() async throws {
    let service = try makeService()
    let streak = try await service.createHabit(
      name: "Meditate", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily, milestoneTarget: 30)
    let streakStats = try await service.getHabitStats(id: streak.id)
    XCTAssertEqual(streakStats.name, "Meditate")
    XCTAssertEqual(streakStats.metric, "streak")

    let count = try await service.createHabit(
      name: "Gym", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3),
      milestoneTarget: nil)
    let countStats = try await service.getHabitStats(id: count.id)
    XCTAssertEqual(countStats.name, "Gym")
    XCTAssertEqual(countStats.metric, "count")
  }

  // MARK: - Reminder-policy changelog discoverability

  func testUpsertHabitReminderPolicyStampsChangelogUnderHabitId() async throws {
    let service = try makeService()
    let habit = try await service.createHabit(name: "Floss", cue: nil, targetCount: 1)
    // upsert_habit_reminder_policy is an MCP tool; the diagnostics changelog
    // this discoverability check reads is an assistant-facing surface (`user`
    // rows are filtered out), so drive the write under the assistant binding.
    let policy = try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.assistant
    ) {
      try await service.upsertHabitReminderPolicy(
        id: habit.id,
        policy: HabitReminderPolicy(
          id: "", habitID: habit.id, habitName: "Floss", reminderTime: "20:00",
          enabled: true, createdAt: "", updatedAt: ""))
    }
    let entries = try await service.loadRuntimeDiagnostics().changelog.entries
      .filter { $0.entityType == "habit_reminder_policy" }
    XCTAssertEqual(entries.count, 1)
    // The changelog row is discoverable under the HABIT id (not the policy row id),
    // so get_ai_changelog?entity_id=<habit> surfaces the reminder change.
    XCTAssertEqual(entries.first?.entityId, habit.id)
    XCTAssertNotEqual(entries.first?.entityId, policy.id)
  }

  // MARK: - Export / import round-trip

  func testExportImportRoundTripPreservesMilestone() async throws {
    let source = try makeService()
    let created = try await source.createHabit(
      name: "Journal", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily, milestoneTarget: 21)
    let exported = ExportHabit(from: created)
    XCTAssertEqual(exported.milestoneTarget, 21)

    // Re-apply into a fresh store via the real importer plan/apply path.
    let destination = try makeService()
    let payload = LorvexDataExportPayload(habits: [exported])
    let plan = LorvexDataImporter.plan(for: payload)
    let summary = await LorvexDataImporter.apply(
      plan: plan, payload: payload, using: destination)
    XCTAssertTrue(summary.errors.isEmpty, "Import errors: \(summary.errors)")
    let restored = try await destination.loadHabits(date: "2026-06-30").habits
      .first { $0.id == created.id }
    XCTAssertEqual(restored?.milestoneTarget, 21)
  }

  func testImportNilMilestoneKeepsExistingValue() async throws {
    let service = try makeService()
    let id = uuid()
    // Seed a habit that already carries a milestone (e.g. one that arrived via sync).
    _ = try await service.importHabit(
      id: id, name: "Water", cue: nil, frequencyType: "daily", weekdays: [],
      perPeriodTarget: nil, dayOfMonth: nil, targetCount: 1, milestoneTarget: 9)
    // Re-import the same id with no milestone in the payload: the existing value
    // must survive the COALESCE-on-conflict, not be nulled out.
    _ = try await service.importHabit(
      id: id, name: "Water", cue: "hydrate", frequencyType: "daily", weekdays: [],
      perPeriodTarget: nil, dayOfMonth: nil, targetCount: 1, milestoneTarget: nil)
    let habit = try await service.loadHabits(date: "2026-06-30").habits.first { $0.id == id }
    XCTAssertEqual(habit?.milestoneTarget, 9)
  }
}
