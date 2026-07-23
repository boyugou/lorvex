import AppIntents
import LorvexCore

struct UpdateLorvexHabitIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.update.title", defaultValue: "Update Lorvex Habit", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.update.description", defaultValue: "Rename or update a Lorvex habit from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.habit", defaultValue: "Habit", table: "Localizable", bundle: SystemL10n.bundle))
  var habit: LorvexHabitEntity

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.name", defaultValue: "Name", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.habit.parameter.name.optional_replacement.description", defaultValue: "Optional replacement name.", table: "Localizable", bundle: SystemL10n.bundle))
  var name: String?

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.cue", defaultValue: "Cue", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.habit.parameter.cue.optional_replacement.description", defaultValue: "Optional replacement cue.", table: "Localizable", bundle: SystemL10n.bundle))
  var cue: String?

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.target_count", defaultValue: "Target Count", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.habit.parameter.target_count.optional_replacement.description", defaultValue: "Optional replacement target count.", table: "Localizable", bundle: SystemL10n.bundle))
  var targetCount: Int?

  init() {
    habit = LorvexHabitEntity(id: "", name: "", completionsToday: 0, targetCount: 0)
    name = nil
    cue = nil
    targetCount = nil
  }

  init(
    habit: LorvexHabitEntity,
    name: String? = nil,
    cue: String? = nil,
    targetCount: Int? = nil
  ) {
    self.habit = habit
    self.name = name
    self.cue = cue
    self.targetCount = targetCount
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let updated = try await LorvexTaskIntentRunner.updateHabit(
      id: habit.id,
      name: name,
      cue: cue,
      targetCount: targetCount
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.update.dialog", defaultValue: "Updated habit \(updated.name) in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
