import AppIntents
import LorvexCore

struct SkipLorvexHabitIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.skip.title", defaultValue: "Skip Lorvex Habit", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.skip.description", defaultValue: "Skip a Lorvex habit for a day from Shortcuts or Siri. A skipped day counts as neither done nor missed.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.habit", defaultValue: "Habit", table: "Localizable", bundle: SystemL10n.bundle))
  var habit: LorvexHabitEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.date", defaultValue: "Date", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.parameter.date.today_when_blank.description", defaultValue: "Leave blank for today.", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var date: Date?

  init() {
    habit = LorvexHabitEntity(id: "", name: "", completionsToday: 0, targetCount: 0)
    date = nil
  }

  init(habit: LorvexHabitEntity, date: Date? = nil) {
    self.habit = habit
    self.date = date
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let skipped = try await LorvexTaskIntentRunner.skipHabit(
      id: habit.id, date: date.map(IntentDateText.day))
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.skip.dialog", defaultValue: "Skipped \(skipped.name) in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
