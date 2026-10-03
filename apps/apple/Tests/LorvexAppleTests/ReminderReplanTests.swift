import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

/// The reminder re-plan both app shells run (`ReminderReplan`): which kinds of
/// pending notifications a pass replaces, what a failed read leaves alone, and
/// which reports each shell keeps.
@Suite("Reminder re-plan")
struct ReminderReplanTests {
  private actor TaskSchedulerSpy: TaskReminderScheduling {
    private(set) var replacements: [[ScheduledTaskReminder]] = []
    func scheduleReminders(_ reminders: [ScheduledTaskReminder]) async -> TaskReminderScheduleReport {
      replacements.append(reminders)
      return .scheduled(reminders.count)
    }
  }

  private actor HabitSchedulerSpy: HabitReminderScheduling {
    private(set) var replacements: [[DueHabitReminderOccurrence]] = []
    func replaceScheduledHabitReminders(
      for occurrences: [DueHabitReminderOccurrence]
    ) async -> TaskReminderScheduleReport {
      replacements.append(occurrences)
      return .scheduled(occurrences.count)
    }
  }

  private static let source = "test.reminders.schedule"

  /// A stub over a seeded core holding a habit with a daily 08:00 reminder, so
  /// a healthy habit read has occurrences to arm.
  private static func makeCore() async throws -> StubCoreService {
    let preview = try await makeSeededInMemoryCore()
    let habit = try await preview.createHabit(name: "Stretch", cue: nil, targetCount: 1)
    _ = try await preview.upsertHabitReminderPolicy(
      id: habit.id,
      policy: HabitReminderPolicy(
        id: "", habitID: habit.id, habitName: habit.name,
        reminderTime: "08:00", enabled: true, createdAt: "", updatedAt: ""))
    return StubCoreService(preview: preview)
  }

  private static func run(
    _ core: StubCoreService, _ tasks: TaskSchedulerSpy, _ habits: HabitSchedulerSpy
  ) async -> ReminderReplan.Outcome {
    await ReminderReplan.run(
      core: core, taskScheduler: tasks, habitScheduler: habits, includeTaskNotes: false,
      setupCompleted: true, authorizationStatus: { .authorized }, now: { Date() },
      diagnosticSource: source)
  }

  private static func loggedFailures(_ core: StubCoreService, source: String) async throws -> Int {
    let logs = try await core.loadRecentLogs(
      limit: 50, offset: 0, since: nil, levels: nil, sources: nil, redact: false)
    return logs.entries.filter { $0.origin == source }.count
  }

  @Test("A healthy pass replaces both kinds and logs nothing")
  func healthyPass() async throws {
    let core = try await Self.makeCore()
    let tasks = TaskSchedulerSpy()
    let habits = HabitSchedulerSpy()

    let outcome = await Self.run(core, tasks, habits)

    #expect(await tasks.replacements.count == 1)
    let armed = try #require(await habits.replacements.first)
    #expect(!armed.isEmpty)
    #expect(outcome.taskReport.status == .scheduled)
    #expect(outcome.habitReport?.status == .scheduled)
    #expect(try await Self.loggedFailures(core, source: Self.source) == 0)
  }

  @Test("A failed task read stops the pass before either kind is replaced")
  func failedTaskRead() async throws {
    let core = try await Self.makeCore()
    core.upcomingReminderTasksError = .unsupportedOperation("task read boom")
    let tasks = TaskSchedulerSpy()
    let habits = HabitSchedulerSpy()

    let outcome = await Self.run(core, tasks, habits)

    // A partial or snapshot task list would cancel every reminder it leaves
    // out, so nothing is replaced at all.
    #expect(await tasks.replacements.isEmpty)
    #expect(await habits.replacements.isEmpty)
    #expect(outcome.taskReport.status == .failed)
    #expect(outcome.habitReport == nil)
    #expect(try await Self.loggedFailures(core, source: Self.source) == 1)
  }

  @Test("A failed habit read re-plans tasks and keeps the pending habit notifications")
  func failedHabitRead() async throws {
    let core = try await Self.makeCore()
    core.dueHabitReminderOccurrencesError = .unsupportedOperation("habit read boom")
    let tasks = TaskSchedulerSpy()
    let habits = HabitSchedulerSpy()

    let outcome = await Self.run(core, tasks, habits)

    #expect(await tasks.replacements.count == 1)
    #expect(await habits.replacements.isEmpty)
    #expect(outcome.taskReport.status == .scheduled)
    #expect(outcome.habitReport?.status == .failed)
    #expect(try await Self.loggedFailures(core, source: Self.source) == 1)
  }

  @MainActor
  @Test("The Mac keeps its habit notifications on a failed habit read and logs it")
  func macFailedHabitRead() async throws {
    let core = try await Self.makeCore()
    core.dueHabitReminderOccurrencesError = .unsupportedOperation("habit read boom")
    let habits = RecordingHabitReminderScheduler()
    let suiteName = "ReminderReplanTests.mac.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = AppStore(core: core, habitReminderScheduler: habits, defaults: defaults)

    await store.rescheduleReminders()

    #expect(await habits.replacements().isEmpty)
    #expect(store.lastHabitReminderScheduleReport.status == .failed)
    #expect(try await Self.loggedFailures(core, source: "macos.reminders.schedule") == 1)
  }

  @MainActor
  @Test("A Mac pass that stops at the task read keeps the previous habit report")
  func macFailedTaskReadKeepsHabitReport() async throws {
    let core = try await Self.makeCore()
    let suiteName = "ReminderReplanTests.macTask.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = AppStore(
      core: core, habitReminderScheduler: RecordingHabitReminderScheduler(), defaults: defaults)
    await store.rescheduleReminders()
    let habitReport = store.lastHabitReminderScheduleReport
    #expect(habitReport.status == .scheduled)

    core.upcomingReminderTasksError = .unsupportedOperation("task read boom")
    await store.rescheduleReminders()

    #expect(store.lastTaskReminderScheduleReport.status == .failed)
    #expect(store.lastHabitReminderScheduleReport == habitReport)
  }

  @MainActor
  @Test("The phone keeps its task reminders on a failed task read instead of re-planning from Today")
  func phoneFailedTaskRead() async throws {
    let core = try await Self.makeCore()
    core.upcomingReminderTasksError = .unsupportedOperation("task read boom")
    let tasks = TaskSchedulerSpy()
    let store = MobileStore(core: core, taskReminderScheduler: tasks)

    await store.rescheduleReminders()

    #expect(await tasks.replacements.isEmpty)
    #expect(store.lastTaskReminderScheduleReport.status == .failed)
    #expect(try await Self.loggedFailures(core, source: "ios.reminders.schedule") == 1)
  }
}
