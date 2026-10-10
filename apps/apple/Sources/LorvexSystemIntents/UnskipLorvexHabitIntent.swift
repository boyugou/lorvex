import AppIntents
import LorvexCore

struct UnskipLorvexHabitIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.unskip.title", defaultValue: "Undo Lorvex Habit Skip", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.unskip.description", defaultValue: "Take back a skipped day for a Lorvex habit from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

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
    let restored = try await LorvexTaskIntentRunner.unskipHabit(
      id: habit.id, date: date.map(IntentDateText.day))
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.unskip.dialog", defaultValue: "Took back the skip for \(restored.name) in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
