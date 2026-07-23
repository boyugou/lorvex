import Foundation
import Testing
import UserNotifications

@testable import LorvexCore

/// `ReminderOnboardingGate.gate` decides whether a background reminder
/// re-plan may arm brand-new task/habit reminders, or must withhold them
/// because arming would fire the OS's first-ever (`.notDetermined`)
/// authorization prompt before the setup wizard's own explicit request.
@Suite("Reminder onboarding gate")
struct ReminderOnboardingGateTests {
  private func sampleTasks() -> [ScheduledTaskReminder] {
    let task = LorvexTask(
      id: "task-1", title: "T", notes: "", priority: .p3, status: .open,
      dueDate: nil, estimatedMinutes: nil, tags: [],
      reminders: [TaskReminder(id: "r-1", reminderAt: "2099-01-01T00:00:00Z", status: nil)])
    return ScheduledTaskReminder.reminders(for: [task])
  }

  private func sampleHabits() -> [DueHabitReminderOccurrence] {
    [
      DueHabitReminderOccurrence(
        policy: HabitReminderPolicy(
          id: "policy-1", habitID: "habit-1", habitName: "Stretch", reminderTime: "09:00",
          enabled: true, createdAt: "", updatedAt: ""),
        fireDate: Date(timeIntervalSince1970: 4_000_000_000))
    ]
  }

  @Test("Setup completed arms candidates regardless of authorization status")
  func setupCompletedAlwaysArms() {
    let result = ReminderOnboardingGate.gate(
      tasks: sampleTasks(), habits: sampleHabits(),
      setupCompleted: true, authorizationStatus: .notDetermined)
    #expect(result.tasks.count == 1)
    #expect(result.habits.count == 1)
  }

  @Test("Setup incomplete and authorization not yet determined withholds both kinds")
  func incompleteSetupAndNotDeterminedWithholds() {
    let result = ReminderOnboardingGate.gate(
      tasks: sampleTasks(), habits: sampleHabits(),
      setupCompleted: false, authorizationStatus: .notDetermined)
    #expect(result.tasks.isEmpty)
    #expect(result.habits.isEmpty)
  }

  @Test("Setup incomplete but authorization already granted arms immediately")
  func incompleteSetupButAuthorizedArms() {
    let result = ReminderOnboardingGate.gate(
      tasks: sampleTasks(), habits: sampleHabits(),
      setupCompleted: false, authorizationStatus: .authorized)
    #expect(result.tasks.count == 1)
    #expect(result.habits.count == 1)
  }

  @Test("Setup incomplete but authorization already denied still arms (removal-only path)")
  func incompleteSetupButDeniedArms() {
    let result = ReminderOnboardingGate.gate(
      tasks: sampleTasks(), habits: sampleHabits(),
      setupCompleted: false, authorizationStatus: .denied)
    #expect(result.tasks.count == 1)
    #expect(result.habits.count == 1)
  }

  @Test("Empty candidates pass through untouched either way")
  func emptyCandidatesPassThrough() {
    let result = ReminderOnboardingGate.gate(
      tasks: [], habits: [], setupCompleted: false, authorizationStatus: .notDetermined)
    #expect(result.tasks.isEmpty)
    #expect(result.habits.isEmpty)
  }
}
