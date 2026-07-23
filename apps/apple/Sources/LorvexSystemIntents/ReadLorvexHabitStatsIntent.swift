import AppIntents

struct ReadLorvexHabitStatsIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.stats.read.title", defaultValue: "Read Lorvex Habit Stats", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.stats.read.description", defaultValue: "Read Lorvex habit streaks and completion stats.", table: "Localizable", bundle: SystemL10n.bundle))

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
    let stats = try await LorvexTaskIntentRunner.readHabitStats(id: habit.id)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.stats.read.dialog",
          defaultValue:
            "\(habit.name): \(stats.currentStreak) current streak, \(stats.totalCompletions) total.",
          table: "Localizable", bundle: SystemL10n.bundle))
    )
  }
}
