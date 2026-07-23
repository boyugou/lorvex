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
    // in-process invalidation configuration. Signal only after the mutation has
    // committed so any open app window can re-read the shared App Group store.
    await WidgetIntentPostCommitCoordinator.live().finish(core: core)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "widget.intent.complete.dialog", defaultValue: "Completed \(title).",
          table: "Localizable", bundle: WidgetSupportL10n.bundle)))
  }
}
