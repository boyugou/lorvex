import AppIntents
import LorvexCore

/// One reminder of a Lorvex habit, as Siri and Shortcuts pick it: the habit's
/// name, with the reminder's clock time underneath, marked when it is off.
struct LorvexHabitReminderEntity: AppEntity, Identifiable {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.entity.habit_reminder.type", defaultValue: "Lorvex Habit Reminder", table: "Localizable", bundle: SystemL10n.bundle))
  static let defaultQuery = LorvexHabitReminderEntityQuery()

  var id: String
  var habitID: LorvexHabit.ID
  var habitName: String
  /// The reminder's `HH:MM` clock time.
  var reminderTime: String
  var enabled: Bool

  var displayRepresentation: DisplayRepresentation {
    let time = lorvexClockTimeLabel(reminderTime)
    return DisplayRepresentation(
      title: "\(habitName)",
      subtitle: enabled
        ? "\(time)"
        : LocalizedStringResource(
          "system.entity.habit_reminder.off",
          defaultValue: "\(time) · Off",
          table: "Localizable",
          bundle: SystemL10n.bundle),
      image: .init(systemName: enabled ? "bell" : "bell.slash")
    )
  }

  init(id: String, habitID: LorvexHabit.ID, habitName: String, reminderTime: String, enabled: Bool) {
    self.id = id
    self.habitID = habitID
    self.habitName = habitName
    self.reminderTime = reminderTime
    self.enabled = enabled
  }

  init(policy: HabitReminderPolicy) {
    self.init(
      id: policy.id,
      habitID: policy.habitID,
      habitName: policy.habitName,
      reminderTime: policy.reminderTime,
      enabled: policy.enabled
    )
  }
}
