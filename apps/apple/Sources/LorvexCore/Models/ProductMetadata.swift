public enum LorvexProductMetadata {
  public static let appName = "Lorvex"
  public static let appDisplayName = "Lorvex"
  public static let mobileAppName = "LorvexMobileApp"
  public static let mobileAppDisplayName = "Lorvex"
  public static let watchAppName = "LorvexWatchApp"
  public static let watchAppDisplayName = "Lorvex"
  public static let watchComplicationProduct = "LorvexWatchComplication"
  public static let watchComplicationBundleIdentifier = "com.lorvex.apple.watchkitapp.widgets"
  public static let watchComplicationKind = "com.lorvex.apple.watchkitapp.widgets.today"
  public static let watchComplicationDisplayName = "Lorvex Today"
  public static let mcpHostProduct = "LorvexMCPHost"
  /// The bundled MCP helper's own `CFBundleIdentifier`. The helper ships as a
  /// minimal `LorvexMCPHost.app` inside `Contents/Helpers/` (not the app's
  /// bundle ID) so the sandbox can initialize a container for it and it can
  /// carry its own provisioning-profile-authorized app group entitlement.
  public static let mcpHostBundleIdentifier = "com.lorvex.apple.mcp-host"
  public static let mcpServerName = "lorvex"
  public static let bundleIdentifier = "com.lorvex.apple"
  public static let mobileBundleIdentifier = "com.lorvex.apple"
  /// The embedded companion Watch app's bundle ID MUST be prefixed by the iOS
  /// host's (`mobileBundleIdentifier`). Apple's embedded-companion rule (TN3157)
  /// rejects a watchOS app whose bundle ID does not descend from its iOS
  /// companion, and the complication (`watchComplicationBundleIdentifier`) must
  /// in turn descend from this one.
  public static let watchBundleIdentifier = "com.lorvex.apple.watchkitapp"
  /// The widget extension's bundle ID MUST be prefixed by the host app's
  /// bundle ID (`com.lorvex.apple`) — Apple's embedded-binary
  /// validation rejects an app-extension whose bundle ID isn't a child of
  /// the containing app's. This is deliberately NOT equal to `widgetKind`
  /// below: `widgetKind` is a WidgetKit timeline identifier (free-form, must
  /// stay stable for reload calls), the bundle ID is a code-signing
  /// identity. Aligning them would break embedded-binary validation; keep
  /// them distinct.
  public static let widgetBundleIdentifier = "com.lorvex.apple.focuswidget"
  public static let widgetExecutable = "LorvexWidgets"
  public static let widgetAppeXName = "LorvexWidgets.appex"
  /// WidgetKit kind of the Today widget: the identifier its timeline reloads
  /// and the release manifests name. It is not the bundle ID; see
  /// `widgetBundleIdentifier`.
  public static let widgetKind = "com.lorvex.apple.widget.today"
  public static let progressWidgetKind = "com.lorvex.apple.widget.progress"
  public static let habitsWidgetKind = "com.lorvex.apple.widget.habits"
  /// Atomic sidecar beside the managed database containing the local Focus
  /// filter configuration and its cross-process monotonic revision.
  public static let focusFilterStateFileSuffix = ".focus-filter-state-v1.json"
  public static let widgetDisplayName = "Lorvex Today"
  public static let widgetDescription = "See today’s tasks at a glance."
  public static let widgetExtensionPointIdentifier = "com.apple.widgetkit-extension"
  public static let controlWidgetKind = "com.lorvex.control.today"
  public static let controlWidgetDisplayName = "Lorvex Today"
  public static let controlWidgetDescription = "Shows the task at the top of Today."
  public static let appGroupIdentifier = "group.com.lorvex.apple"
  public static let cloudKitContainerIdentifier = "iCloud.com.lorvex.apple"
  public static let marketingVersion = "1.0.0"
  public static let buildVersion = "103"
  public static let minimumSystemVersion = "26.0"
  public static let minimumMobileSystemVersion = "26.0"
  public static let minimumWatchSystemVersion = "26.0"
  public static let urlScheme = "lorvex"
  public static let appCategory = "public.app-category.productivity"
  public static let calendarWriteUsageDescription =
    "Lorvex can add planning blocks you create to Apple Calendar."
  public static let calendarFullAccessUsageDescription =
    "Lorvex can read event details to build schedules and assistant context."

  public static var displayVersion: String {
    "\(marketingVersion) (\(buildVersion))"
  }
}
