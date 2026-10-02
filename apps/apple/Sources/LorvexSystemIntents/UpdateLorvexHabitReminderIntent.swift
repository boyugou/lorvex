import AppIntents
import LorvexCore

struct UpdateLorvexHabitReminderIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.reminder.update.title", defaultValue: "Update Lorvex Habit Reminder", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.reminder.update.description", defaultValue: "Change when a Lorvex habit reminder goes off, or turn it on or off.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.reminder", defaultValue: "Reminder", table: "Localizable", bundle: SystemL10n.bundle))
  var reminder: LorvexHabitReminderEntity

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.reminder_time", defaultValue: "Reminder Time", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .time)
  var reminderTime: Date?

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.enabled", defaultValue: "Enabled", table: "Localizable", bundle: SystemL10n.bundle))
  var enabled: Bool?

  init() {
    reminder = LorvexHabitReminderEntity(id: "", habitID: "", habitName: "", reminderTime: "", enabled: true)
  }

  init(reminder: LorvexHabitReminderEntity, reminderTime: Date? = nil, enabled: Bool? = nil) {
    self.reminder = reminder
    self.reminderTime = reminderTime
    self.enabled = enabled
  }

  /// Writes the new time, the new on/off state, or both; whichever is left
  /// empty keeps the reminder's current value. With neither, Siri asks for
  /// the time.
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard reminderTime != nil || enabled != nil else {
      throw $reminderTime.needsValueError()
    }
    let policy = try await LorvexTaskIntentRunner.upsertHabitReminderPolicy(
      id: reminder.habitID,
      policyID: reminder.id,
      reminderTime: reminderTime.map(IntentDateText.time) ?? reminder.reminderTime,
      enabled: enabled ?? reminder.enabled
    )
    let time = lorvexClockTimeLabel(policy.reminderTime)
    let dialog =
      policy.enabled
      ? LocalizedStringResource(
        "system.habit.reminder.set.dialog",
        defaultValue: "Set \(reminder.habitName) reminder at \(time).",
        table: "Localizable", bundle: SystemL10n.bundle)
      : LocalizedStringResource(
        "system.habit.reminder.update.off_dialog",
        defaultValue: "Turned off the \(reminder.habitName) reminder at \(time).",
        table: "Localizable", bundle: SystemL10n.bundle)
    return .result(dialog: IntentDialog(dialog))
  }
}
