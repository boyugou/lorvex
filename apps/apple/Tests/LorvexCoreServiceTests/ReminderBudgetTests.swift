import Foundation
import Testing

@testable import LorvexCore

/// Cross-scheduler notification budgeting: keep the earliest-firing requests
/// across BOTH task and habit reminders under the shared OS pending-notification
/// cap, so a flood of far-future reminders of one kind can't crowd out near-term
/// ones of the other (and the OS never silently drops the excess).
@Suite("Reminder budget")
struct ReminderBudgetTests {
  private struct Item: Equatable { let id: Int; let fire: Date }
  private func date(_ secondsFromEpoch: Double) -> Date {
    Date(timeIntervalSince1970: secondsFromEpoch)
  }

  // MARK: selectEarliest

  @Test("Over the limit keeps the earliest N and reports the drop count")
  func selectsEarliestOverLimit() {
    let items = [
      Item(id: 4, fire: date(400)),
      Item(id: 1, fire: date(100)),
      Item(id: 3, fire: date(300)),
      Item(id: 2, fire: date(200)),
      Item(id: 5, fire: date(500)),
    ]
    let (kept, truncated) = ReminderBudget.selectEarliest(items, limit: 3, fireDate: \.fire)
    #expect(kept.map(\.id) == [1, 2, 3])
    #expect(truncated == 2)
  }

  @Test("At or under the limit keeps everything with zero truncation")
  func keepsAllUnderLimit() {
    let items = [Item(id: 1, fire: date(100)), Item(id: 2, fire: date(200))]
    let (kept, truncated) = ReminderBudget.selectEarliest(items, limit: 5, fireDate: \.fire)
    #expect(kept == items)
    #expect(truncated == 0)
  }

  @Test("Equal fire dates keep input order (stable, deterministic selection)")
  func stableTieBreak() {
    let items = [
      Item(id: 1, fire: date(100)),
      Item(id: 2, fire: date(100)),
      Item(id: 3, fire: date(100)),
    ]
    let (kept, truncated) = ReminderBudget.selectEarliest(items, limit: 2, fireDate: \.fire)
    #expect(kept.map(\.id) == [1, 2])
    #expect(truncated == 1)
  }

  // MARK: budget (task + habit together)

  private func taskCandidate(id: String, fireISO: String) -> ScheduledTaskReminder {
    let task = LorvexTask(
      id: id, title: "T-\(id)", notes: "", priority: .p3, status: .open,
      dueDate: nil, estimatedMinutes: nil, tags: [],
      reminders: [TaskReminder(id: "r-\(id)", reminderAt: fireISO, status: nil)])
    return ScheduledTaskReminder.reminders(for: [task]).first!
  }

  private func habitOccurrence(id: String, fire: Date) -> DueHabitReminderOccurrence {
    DueHabitReminderOccurrence(
      policy: HabitReminderPolicy(
        id: id, habitID: "h-\(id)", habitName: id, reminderTime: "09:00", enabled: true,
        createdAt: "", updatedAt: ""),
      fireDate: fire)
  }

  @Test("Budget keeps the earliest across both kinds and splits by kind")
  func budgetsAcrossBothKinds() {
    // Interleaved fire dates: task Jan 1, habit Jan 2, task Jan 3, habit Jan 4.
    let t1 = taskCandidate(id: "t1", fireISO: "2099-01-01T00:00:00Z")
    let t3 = taskCandidate(id: "t3", fireISO: "2099-01-03T00:00:00Z")
    let h2 = habitOccurrence(id: "h2", fire: t1.fireDate.addingTimeInterval(86_400))
    let h4 = habitOccurrence(id: "h4", fire: t3.fireDate.addingTimeInterval(86_400))

    let result = ReminderBudget.budget(
      taskCandidates: [t1, t3], habitOccurrences: [h2, h4], limit: 2)

    // Earliest two overall are t1 (Jan 1) then h2 (Jan 2); t3/h4 dropped.
    #expect(result.tasks.map(\.taskID) == ["t1"])
    #expect(result.habits.map(\.policy.id) == ["h2"])
    #expect(result.truncated == 2)
  }

  @Test("Budget under the limit keeps both kinds entirely")
  func budgetKeepsAllUnderLimit() {
    let t1 = taskCandidate(id: "t1", fireISO: "2099-01-01T00:00:00Z")
    let h2 = habitOccurrence(id: "h2", fire: t1.fireDate.addingTimeInterval(86_400))

    let result = ReminderBudget.budget(
      taskCandidates: [t1], habitOccurrences: [h2], limit: 60)

    #expect(result.tasks.map(\.taskID) == ["t1"])
    #expect(result.habits.map(\.policy.id) == ["h2"])
    #expect(result.truncated == 0)
  }
}
