import AppIntents
import LorvexCore
import LorvexWidgetKitSupport

/// Marks a task complete directly from a widget, without opening the app.
///
/// The intent is constructed with the task ID from the widget's render model.
/// Its `LorvexWidgetActionIntent` conformance runs it in the widget extension
/// process (`openAppWhenRun = false`). After `perform()` returns, WidgetKit
/// reloads the timeline automatically via its post-intent refresh mechanism.
public struct WidgetCompleteTaskIntent: LorvexWidgetActionIntent {
  public static let title = LocalizedStringResource(
    "widget.intent.complete.title", defaultValue: "Complete Task", table: "Localizable",
    bundle: WidgetSupportL10n.bundle)

  public static let description = IntentDescription(
    LocalizedStringResource(
      "widget.intent.complete.description", defaultValue: "Complete a Lorvex task from a widget.",
      table: "Localizable", bundle: WidgetSupportL10n.bundle))

  @Parameter(
    title: LocalizedStringResource(
      "widget.intent.parameter.task", defaultValue: "Task", table: "Localizable",
      bundle: WidgetSupportL10n.bundle))
  public var task: WidgetTaskEntity

  public init() {
    task = WidgetTaskEntity(id: "")
  }

  public init(taskID: String, title: String = "") {
    task = WidgetTaskEntity(id: taskID, title: title)
  }

  public func perform() async throws -> some IntentResult & ProvidesDialog {
    let core = LorvexCoreRuntimeFactory.makeForWidget()
    let title = try await LorvexSystemIntentRunner.completeTask(
      id: task.id,
      core: core
    )
    // This intent runs in the widget extension process, outside the app's
    // in-process invalidation configuration and its reminder re-plan. After the
    // commit, take back the completed task's pending reminders, which holds even
    // when the re-plan below cannot read the store; the coordinator then signals
    // any open app window, publishes the snapshot, and re-plans the reminders,
    // arming a repeat's next occurrence.
    await ReminderWithdrawal.live.withdrawTaskReminders(taskID: task.id)
    await WidgetIntentPostCommitCoordinator.live().finish(core: core)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "widget.intent.complete.dialog", defaultValue: "Completed \(title).",
          table: "Localizable", bundle: WidgetSupportL10n.bundle)))
  }
}
