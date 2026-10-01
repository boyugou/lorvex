import AppIntents
import LorvexWidgetViews

/// The Today widget's configuration: an optional list that narrows the widget
/// to that list's tasks.
public struct LorvexTodayWidgetConfigurationIntent: WidgetConfigurationIntent {
  public static let title = LocalizedStringResource("widget.config.today.title", defaultValue: "Today", table: "Localizable", bundle: WidgetL10n.bundle)

  public static let description = IntentDescription(LocalizedStringResource("widget.config.today.description", defaultValue: "Choose a list to show only its tasks.", table: "Localizable", bundle: WidgetL10n.bundle))

  // WidgetConfigurationIntent requires every parameter type to be optional
  // (the App Intents metadata processor warns otherwise); nil shows every list.
  @Parameter(
    title: LocalizedStringResource("widget.config.parameter.list", defaultValue: "List", table: "Localizable", bundle: WidgetL10n.bundle))
  public var list: LorvexWidgetListEntity?

  public init() {
    list = nil
  }
}
