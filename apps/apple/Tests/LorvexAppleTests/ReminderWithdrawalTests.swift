import Foundation
import Testing

@testable import LorvexCore

/// A widget's Complete runs in the widget extension, where the app's reminder
/// re-plan never runs: the completed task's or met habit's pending reminders
/// are taken back there, and nothing else is touched.
@Suite("Reminder withdrawal")
struct ReminderWithdrawalTests {
  private static let now = Date(timeIntervalSince1970: 1_779_537_600)

  /// A notification center seam: the pending requests it holds and the
  /// identifiers removed from it.
  private final class Center: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [PendingReminderRequest]
    private var removedIDs: [String] = []
    private let now: Date

    init(_ requests: [PendingReminderRequest], now: Date = ReminderWithdrawalTests.now) {
      self.requests = requests
      self.now = now
    }

    var removed: [String] { lock.withLock { removedIDs } }

    var withdrawal: ReminderWithdrawal {
      ReminderWithdrawal(
        pending: { self.lock.withLock { self.requests } },
        remove: { ids in
          self.lock.withLock {
            self.removedIDs += ids
            self.requests.removeAll { ids.contains($0.identifier) }
          }
        },
        now: { [now] in now })
    }
  }

  private static func taskReminder(_ reminderID: String, task: String) -> PendingReminderRequest {
    PendingReminderRequest(
      identifier: ScheduledTaskReminder.identifierPrefix + reminderID, taskID: task,
      nextFireDate: now.addingTimeInterval(3600))
  }

  private static func policy(_ id: String, habit: String) -> HabitReminderPolicy {
    HabitReminderPolicy(
      id: id, habitID: habit, habitName: habit, reminderTime: "20:00", enabled: true,
      createdAt: "", updatedAt: "")
  }

  private static func occurrence(
    _ policy: HabitReminderPolicy, hoursFromNow: Double
  ) -> DueHabitReminderOccurrence {
    DueHabitReminderOccurrence(policy: policy, fireDate: now.addingTimeInterval(hoursFromNow * 3600))
  }

  private static func pending(_ occurrence: DueHabitReminderOccurrence) -> PendingReminderRequest {
    PendingReminderRequest(
      identifier: ScheduledHabitReminder(occurrence: occurrence, body: "").identifier,
      nextFireDate: occurrence.fireDate)
  }

  // MARK: - Tasks

  @Test("a completed task's reminders and snooze are withdrawn, another task's are kept")
  func completedTaskRemindersAreWithdrawn() async {
    let other = Self.taskReminder("r-other", task: "task-other")
    let center = Center([
      Self.taskReminder("r-1", task: "task-done"),
      Self.taskReminder("r-2", task: "task-done"),
      PendingReminderRequest(identifier: ScheduledTaskReminder.snoozeIdentifierPrefix + "task-done"),
      other,
      PendingReminderRequest(identifier: ScheduledTaskReminder.snoozeIdentifierPrefix + "task-other"),
    ])

    await center.withdrawal.withdrawTaskReminders(taskID: "task-done")

    #expect(
      Set(center.removed) == [
        ScheduledTaskReminder.identifierPrefix + "r-1",
        ScheduledTaskReminder.identifierPrefix + "r-2",
        ScheduledTaskReminder.snoozeIdentifierPrefix + "task-done",
      ])
  }

  @Test("a task without pending reminders removes nothing")
  func taskWithoutRemindersRemovesNothing() async {
    let center = Center([Self.taskReminder("r-other", task: "task-other")])
    await center.withdrawal.withdrawTaskReminders(taskID: "task-done")
    #expect(center.removed.isEmpty)
  }

  // MARK: - Habits

  @Test("a met habit's later nudges are withdrawn; the next day, other habits, and the past are kept")
  func metHabitWithdrawsOnlyItsUnwantedLaterNudges() async {
    let meditate = Self.policy("p-meditate", habit: "meditate")
    let walk = Self.policy("p-walk", habit: "walk")
    let tonight = Self.occurrence(meditate, hoursFromNow: 8)
    let tomorrow = Self.occurrence(meditate, hoursFromNow: 32)
    let walkTonight = Self.occurrence(walk, hoursFromNow: 8)
    var justFired = Self.pending(Self.occurrence(meditate, hoursFromNow: 0))
    justFired.nextFireDate = Self.now
    let center = Center([
      Self.pending(tonight), Self.pending(tomorrow), Self.pending(walkTonight), justFired,
    ])

    // Today is met: the query no longer returns tonight's nudge.
    await center.withdrawal.withdrawHabitReminders(
      habitID: "meditate",
      policies: { [meditate] },
      dueOccurrences: { _ in [tomorrow, walkTonight] })

    #expect(center.removed == [Self.pending(tonight).identifier])
  }

  @Test("a check-in short of the target withdraws nothing")
  func checkInBelowTargetWithdrawsNothing() async {
    let water = Self.policy("p-water", habit: "water")
    let noon = Self.occurrence(water, hoursFromNow: 2)
    let evening = Self.occurrence(water, hoursFromNow: 8)
    let center = Center([Self.pending(noon), Self.pending(evening)])

    await center.withdrawal.withdrawHabitReminders(
      habitID: "water",
      policies: { [water] },
      dueOccurrences: { _ in [noon, evening] })

    #expect(center.removed.isEmpty)
  }

  @Test("a read that fails withdraws nothing")
  func failedReadWithdrawsNothing() async {
    struct Busy: Error {}
    let meditate = Self.policy("p-meditate", habit: "meditate")
    let tonight = Self.occurrence(meditate, hoursFromNow: 8)
    let center = Center([Self.pending(tonight)])

    await center.withdrawal.withdrawHabitReminders(
      habitID: "meditate", policies: { throw Busy() }, dueOccurrences: { _ in [] })
    await center.withdrawal.withdrawHabitReminders(
      habitID: "meditate", policies: { [meditate] }, dueOccurrences: { _ in throw Busy() })

    #expect(center.removed.isEmpty)
  }

  @Test("the core's own reads withdraw a met habit's nudge and keep the next day's")
  func coreReadsDriveTheHabitWithdrawal() async throws {
    let core = try await makeSeededInMemoryCore()
    let habit = try await core.createHabit(name: "Stretch", cue: nil, targetCount: 1)
    _ = try await core.upsertHabitReminderPolicy(
      id: habit.id,
      policy: HabitReminderPolicy(
        id: "", habitID: habit.id, habitName: habit.name, reminderTime: "23:59", enabled: true,
        createdAt: "", updatedAt: ""))
    let now = Date()
    let armed = try await core.getDueHabitReminderOccurrences(
      now: now, horizonDays: ReminderReplan.habitHorizonDays
    ).filter { $0.policy.habitID == habit.id }
    try #require(armed.count >= 2)
    let center = Center(armed.map(Self.pending), now: now)

    // A habit reminder's day is the device's: meet the first nudge's day.
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    _ = try await core.completeHabit(id: habit.id, date: formatter.string(from: armed[0].fireDate))

    await center.withdrawal.withdrawHabitReminders(habitID: habit.id, core: core)

    #expect(center.removed == [Self.pending(armed[0]).identifier])
  }

  @Test("both widget Complete intents withdraw reminders after their write")
  func widgetIntentsWithdrawAfterTheirWrite() throws {
    let task = try String(
      contentsOfFile: "Sources/LorvexWidgetIntents/WidgetCompleteTaskIntent.swift", encoding: .utf8)
    #expect(task.contains("ReminderWithdrawal.live.withdrawTaskReminders(taskID: task.id)"))
    let habit = try String(
      contentsOfFile: "Sources/LorvexWidgetIntents/WidgetCompleteHabitIntent.swift", encoding: .utf8)
    #expect(
      habit.contains("ReminderWithdrawal.live.withdrawHabitReminders(habitID: habitID, core: core)"))
  }
}
