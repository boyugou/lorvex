import AppIntents
import LorvexCore

struct CompleteLorvexHabitIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.complete.title", defaultValue: "Complete Lorvex Habit", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.complete.description", defaultValue: "Complete a Lorvex habit from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

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
    let completed = try await LorvexTaskIntentRunner.completeHabit(
      id: habit.id, date: date.map(IntentDateText.day))
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.complete.dialog", defaultValue: "Completed \(completed.name) in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
