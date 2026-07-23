import AppIntents

struct ReadLorvexHabitCompletionsIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.completions.read.title", defaultValue: "Read Lorvex Habit Completions", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.completions.read.description", defaultValue: "Read Lorvex habit completion history.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.habit", defaultValue: "Habit", table: "Localizable", bundle: SystemL10n.bundle))
  var habit: LorvexHabitEntity

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.from", defaultValue: "From", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.calendar.parameter.from.optional_date.description", defaultValue: "Optional start date in YYYY-MM-DD format.", table: "Localizable", bundle: SystemL10n.bundle))
  var from: String?

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.to", defaultValue: "To", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.calendar.parameter.to.optional_date.description", defaultValue: "Optional end date in YYYY-MM-DD format.", table: "Localizable", bundle: SystemL10n.bundle))
  var to: String?

  init() {
    habit = LorvexHabitEntity(id: "", name: "", completionsToday: 0, targetCount: 0)
    from = nil
    to = nil
  }

  init(habit: LorvexHabitEntity, from: String? = nil, to: String? = nil) {
    self.habit = habit
    self.from = from
    self.to = to
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let snapshot = try await LorvexTaskIntentRunner.readHabitCompletions(
      id: habit.id,
      from: from,
      to: to
    )
    let count = snapshot.completions.count
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.completions.read.dialog_count",
          defaultValue: "\(habit.name) has \(count) completions.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
