import Foundation
import LorvexCore

extension MobileStore {
  /// Add a reminder time to a habit. `time` is `HH:mm` (24-hour). The new policy
  /// is created enabled; the core fills its id, habit name, and timestamps.
  /// Mirrors the macOS habit-detail reminder editor and the
  /// `upsert_habit_reminder_policy` MCP tool.
  @discardableResult
  public func addHabitReminder(habitID: LorvexHabit.ID, time: String) async -> Bool {
    await mutateHabitReminder(habitID: habitID) {
      let policy = HabitReminderPolicy(
        id: "", habitID: habitID, habitName: "", reminderTime: time,
        enabled: true, createdAt: "", updatedAt: "")
      _ = try await core.upsertHabitReminderPolicy(id: habitID, policy: policy)
    }
  }

  /// Retime an existing reminder policy to `time` (`HH:mm`), leaving its enabled
  /// state intact.
  @discardableResult
  public func setHabitReminderTime(policy: HabitReminderPolicy, to time: String) async -> Bool {
    await mutateHabitReminder(habitID: policy.habitID) {
      var updated = policy
      updated.reminderTime = time
      _ = try await core.upsertHabitReminderPolicy(id: policy.habitID, policy: updated)
    }
  }

  /// Flip a reminder policy's enabled flag — a disabled policy stays on the habit
  /// but stops firing.
  @discardableResult
  public func toggleHabitReminderEnabled(policy: HabitReminderPolicy) async -> Bool {
    await mutateHabitReminder(habitID: policy.habitID) {
      var updated = policy
      updated.enabled.toggle()
      _ = try await core.upsertHabitReminderPolicy(id: policy.habitID, policy: updated)
    }
  }

  /// Remove a reminder policy from a habit (idempotent).
  @discardableResult
  public func removeHabitReminder(habitID: LorvexHabit.ID, policyID: String) async -> Bool {
    await mutateHabitReminder(habitID: habitID) {
      _ = try await core.deleteHabitReminderPolicy(policyID: policyID)
    }
  }

  /// Run one reminder-policy mutation, then reload the habit's detail (so the
  /// editor reflects the new policy set) and re-plan the local notification
  /// schedule (so an added / retimed / disabled reminder takes effect at once).
  @discardableResult
  private func mutateHabitReminder(
    habitID: LorvexHabit.ID, _ operation: () async throws -> Void
  ) async -> Bool {
    guard !isMutatingHabitReminder else { return false }
    isMutatingHabitReminder = true
    defer { isMutatingHabitReminder = false }
    do {
      try await operation()
      _ = await loadHabitDetail(id: habitID)
      await rescheduleReminders()
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }
}
