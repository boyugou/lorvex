import AppIntents
import LorvexWidgetViews

public enum LorvexTodayWidgetViewMode: String, AppEnum {
  case today
  case focus

  public static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("widget.config.view_type", defaultValue: "Widget View", table: "Localizable", bundle: WidgetL10n.bundle))

  public static let caseDisplayRepresentations: [LorvexTodayWidgetViewMode: DisplayRepresentation] = [
    .today: DisplayRepresentation(
      title: LocalizedStringResource("widget.config.view.today", defaultValue: "Today Tasks", table: "Localizable", bundle: WidgetL10n.bundle)),
    .focus: DisplayRepresentation(
      title: LocalizedStringResource("widget.config.view.focus", defaultValue: "Focus Queue", table: "Localizable", bundle: WidgetL10n.bundle)),
  ]
}

public struct LorvexTodayWidgetConfigurationIntent: WidgetConfigurationIntent {
  public static let title = LocalizedStringResource("widget.config.today.title", defaultValue: "Lorvex Today Widget", table: "Localizable", bundle: WidgetL10n.bundle)

  public static let description = IntentDescription(LocalizedStringResource("widget.config.today.description", defaultValue: "Choose which Lorvex view this widget shows.", table: "Localizable", bundle: WidgetL10n.bundle))

  // WidgetConfigurationIntent requires every parameter type to be optional
  // (the App Intents metadata processor warns otherwise); nil means "not
  // configured" and resolves to `.today` at the timeline provider.
  @Parameter(
    title: LocalizedStringResource("widget.config.parameter.view", defaultValue: "View", table: "Localizable", bundle: WidgetL10n.bundle))
  public var viewMode: LorvexTodayWidgetViewMode?

  @Parameter(
    title: LocalizedStringResource("widget.config.parameter.list", defaultValue: "List", table: "Localizable", bundle: WidgetL10n.bundle))
  public var list: LorvexWidgetListEntity?

  public init() {
    viewMode = .today
    list = nil
  }
}
