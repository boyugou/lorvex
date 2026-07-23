import AppIntents
import LorvexCore
import LorvexWidgetKitSupport

/// Defers a task until tomorrow directly from a widget, without opening the app.
public struct WidgetDeferTaskIntent: LorvexWidgetActionIntent {
  public static let title = LocalizedStringResource(
    "widget.intent.defer.title", defaultValue: "Defer Task", table: "Localizable",
    bundle: WidgetSupportL10n.bundle)

  public static let description = IntentDescription(
    LocalizedStringResource(
      "widget.intent.defer.description", defaultValue: "Defer a Lorvex task from a widget.",
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
    let title = try await LorvexSystemIntentRunner.deferTaskUntilTomorrow(
      id: task.id,
      core: core
    )
    await WidgetIntentPostCommitCoordinator.live().finish(core: core)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "widget.intent.defer.dialog", defaultValue: "Deferred \(title) until tomorrow.",
          table: "Localizable", bundle: WidgetSupportL10n.bundle)))
  }
}
