import AppIntents

struct BatchCompleteLorvexHabitsIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.batch_complete.title", defaultValue: "Batch Complete Lorvex Habits", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.batch_complete.description", defaultValue: "Complete multiple Lorvex habits from Shortcuts.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.habits", defaultValue: "Habits", table: "Localizable", bundle: SystemL10n.bundle))
  var habits: [LorvexHabitEntity]

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.date", defaultValue: "Date", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.task.parameter.date.optional_today.description", defaultValue: "Optional date in YYYY-MM-DD format. Leave blank for today.", table: "Localizable", bundle: SystemL10n.bundle))
  var date: String?

  init() {
    habits = []
    date = nil
  }

  init(habits: [LorvexHabitEntity], date: String? = nil) {
    self.habits = habits
    self.date = date
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let snapshot = try await LorvexTaskIntentRunner.batchCompleteHabits(
      habitIDs: habits.map(\.id),
      date: date
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.batch_complete.dialog_count",
          defaultValue: "Completed habits in Lorvex. \(snapshot.habits.count) habits available.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
