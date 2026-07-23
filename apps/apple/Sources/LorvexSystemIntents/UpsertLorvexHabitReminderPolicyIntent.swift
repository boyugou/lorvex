import AppIntents

struct UpsertLorvexHabitReminderPolicyIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.reminder_policy.upsert.title", defaultValue: "Create or Update Lorvex Habit Reminder Policy", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.reminder_policy.upsert.description", defaultValue: "Create or update a Lorvex habit reminder policy.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.habit", defaultValue: "Habit", table: "Localizable", bundle: SystemL10n.bundle))
  var habit: LorvexHabitEntity

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.policy_id", defaultValue: "Policy ID", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.habit.parameter.policy_id.optional_existing.description", defaultValue: "Optional existing policy ID.", table: "Localizable", bundle: SystemL10n.bundle))
  var policyID: String?

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.reminder_time", defaultValue: "Reminder Time", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.habit.parameter.reminder_time.description", defaultValue: "Time in HH:mm format.", table: "Localizable", bundle: SystemL10n.bundle))
  var reminderTime: String

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.enabled", defaultValue: "Enabled", table: "Localizable", bundle: SystemL10n.bundle))
  var enabled: Bool

  init() {
    habit = LorvexHabitEntity(id: "", name: "", completionsToday: 0, targetCount: 0)
    policyID = nil
    reminderTime = "09:00"
    enabled = true
  }

  init(habit: LorvexHabitEntity, policyID: String? = nil, reminderTime: String, enabled: Bool) {
    self.habit = habit
    self.policyID = policyID
    self.reminderTime = reminderTime
    self.enabled = enabled
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let policy = try await LorvexTaskIntentRunner.upsertHabitReminderPolicy(
      id: habit.id,
      policyID: policyID,
      reminderTime: reminderTime,
      enabled: enabled
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.reminder_policy.upsert.dialog",
          defaultValue: "Set \(habit.name) reminder at \(policy.reminderTime).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
