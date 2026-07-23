import Foundation
import Testing

@testable import LorvexCore

/// `ScheduledHabitReminder` request mapping: one due occurrence → one one-shot
/// calendar trigger, prefix-identified per (policy, instant) so a re-plan reaps
/// stale notifications and re-adds the surviving ones idempotently.
@Suite("Scheduled habit reminder mapping")
struct ScheduledHabitReminderTests {
  private func occurrence(
    policyID: String, habitID: String, name: String, fire: Date
  ) -> DueHabitReminderOccurrence {
    DueHabitReminderOccurrence(
      policy: HabitReminderPolicy(
        id: policyID, habitID: habitID, habitName: name, reminderTime: "09:00", enabled: true,
        createdAt: "", updatedAt: ""),
      fireDate: fire)
  }

  @Test("Identifier carries the prefix, policy id, and a stable per-instant key")
  func identifierShape() {
    let fire = Date(timeIntervalSince1970: 1_800_000_000)
    let reminder = ScheduledHabitReminder(
      occurrence: occurrence(policyID: "p1", habitID: "h1", name: "Hydrate", fire: fire),
      body: "Time for your habit")

    #expect(reminder.identifier.hasPrefix(UserNotificationHabitReminderScheduler.identifierPrefix))
    #expect(reminder.identifier.contains("p1"))
    #expect(reminder.habitID == "h1")
    #expect(reminder.title == "Hydrate")
    // The same occurrence re-plans to the same id (idempotent re-add).
    let again = ScheduledHabitReminder(
      occurrence: occurrence(policyID: "p1", habitID: "h1", name: "Hydrate", fire: fire),
      body: "Time for your habit")
    #expect(again.identifier == reminder.identifier)
  }

  @Test("Distinct fire instants of one policy get distinct identifiers")
  func distinctInstantsDistinctIDs() {
    let first = ScheduledHabitReminder(
      occurrence: occurrence(
        policyID: "p1", habitID: "h1", name: "Hydrate",
        fire: Date(timeIntervalSince1970: 1_800_000_000)),
      body: "b")
    let second = ScheduledHabitReminder(
      occurrence: occurrence(
        policyID: "p1", habitID: "h1", name: "Hydrate",
        fire: Date(timeIntervalSince1970: 1_800_086_400)),
      body: "b")
    #expect(first.identifier != second.identifier)
  }

  @Test("The request is a one-shot trigger that deep-links to the habit")
  func requestIsOneShotWithHabitDeepLink() throws {
    let reminder = ScheduledHabitReminder(
      occurrence: occurrence(
        policyID: "p1", habitID: "habit-42", name: "Hydrate",
        fire: Date(timeIntervalSince1970: 1_800_000_000)),
      body: "Time for your habit")
    let request = reminder.notificationRequest

    #expect(request.identifier == reminder.identifier)
    #expect(request.content.title == "Hydrate")
    #expect(request.content.body == "Time for your habit")
    let deepLink = request.content.userInfo[LorvexNotificationRoute.deepLinkUserInfoKey] as? String
    #expect(deepLink == LorvexDeepLinkRoute.habit("habit-42").url.absoluteString)
  }
}
