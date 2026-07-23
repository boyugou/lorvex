import AppIntents
import LorvexCore

struct CreateLorvexHabitIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.create.title", defaultValue: "Create Lorvex Habit", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.create.description", defaultValue: "Create a Lorvex habit from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.name", defaultValue: "Name", table: "Localizable", bundle: SystemL10n.bundle))
  var name: String

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.cue", defaultValue: "Cue", table: "Localizable", bundle: SystemL10n.bundle))
  var cue: String?

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.target_count", defaultValue: "Target Count", table: "Localizable", bundle: SystemL10n.bundle))
  var targetCount: Int?

  init() {
    name = ""
    cue = nil
    targetCount = nil
  }

  init(name: String, cue: String? = nil, targetCount: Int? = nil) {
    self.name = name
    self.cue = cue
    self.targetCount = targetCount
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let habit = try await LorvexTaskIntentRunner.createHabit(
      name: name,
      cue: cue,
      targetCount: targetCount
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.create.dialog", defaultValue: "Created habit \(habit.name) in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
