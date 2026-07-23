import AppIntents

struct ReadLorvexHabitReminderPoliciesIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.reminder_policies.read.title", defaultValue: "Read Lorvex Habit Reminder Policies", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.reminder_policies.read.description", defaultValue: "Read reminder policies for a Lorvex habit.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.habit", defaultValue: "Habit", table: "Localizable", bundle: SystemL10n.bundle))
  var habit: LorvexHabitEntity

  init() {
    habit = LorvexHabitEntity(id: "", name: "", completionsToday: 0, targetCount: 0)
  }

  init(habit: LorvexHabitEntity) {
    self.habit = habit
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let policies = try await LorvexTaskIntentRunner.readHabitReminderPolicies(id: habit.id)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.reminder_policies.read.dialog_count",
          defaultValue: "\(habit.name) has \(policies.count) reminder policies.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
