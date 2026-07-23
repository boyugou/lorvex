import AppIntents
import LorvexCore
import LorvexWidgetKitSupport

/// Logs a habit completion for today directly from a widget, without opening the
/// app.
///
/// Mirrors `WidgetCompleteTaskIntent` but identifies the habit by a plain string
/// id (no `AppEntity`/query needed — the id comes from the widget's render data,
/// never a user picker). Its `LorvexWidgetActionIntent` conformance runs it in
/// the widget process (`openAppWhenRun = false`); WidgetKit reloads the timeline
/// after `perform()` returns.
public struct WidgetCompleteHabitIntent: LorvexWidgetActionIntent {
  public static let title = LocalizedStringResource(
    "widget.intent.complete_habit.title", defaultValue: "Complete Habit", table: "Localizable",
    bundle: WidgetSupportL10n.bundle)

  public static let description = IntentDescription(
    LocalizedStringResource(
      "widget.intent.complete_habit.description", defaultValue: "Log a Lorvex habit from a widget.",
      table: "Localizable", bundle: WidgetSupportL10n.bundle))

  @Parameter(
    title: LocalizedStringResource(
      "widget.intent.parameter.habit_id", defaultValue: "Habit ID", table: "Localizable",
      bundle: WidgetSupportL10n.bundle))
  public var habitID: String

  @Parameter(
    title: LocalizedStringResource(
      "widget.intent.parameter.habit_name", defaultValue: "Habit Name", table: "Localizable",
      bundle: WidgetSupportL10n.bundle))
  public var habitName: String

  public init() {
    habitID = ""
    habitName = ""
  }

  public init(habitID: String, name: String = "") {
    self.habitID = habitID
    self.habitName = name
  }

  public func perform() async throws -> some IntentResult & ProvidesDialog {
    let core = LorvexCoreRuntimeFactory.makeForWidget()
    let updated = try await LorvexSystemIntentRunner.completeHabit(
      id: habitID, date: nil, core: core)
    await WidgetIntentPostCommitCoordinator.live().finish(core: core)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "widget.intent.complete_habit.dialog", defaultValue: "Logged \(updated.name).",
          table: "Localizable", bundle: WidgetSupportL10n.bundle)))
  }
}
