import LorvexCore

enum AppMetadata {
  static let appName = LorvexProductMetadata.appName
  static let appDisplayName = LorvexProductMetadata.appDisplayName
  static let mcpHostProduct = LorvexProductMetadata.mcpHostProduct
  static let mcpServerName = LorvexProductMetadata.mcpServerName
  static let bundleIdentifier = LorvexProductMetadata.bundleIdentifier
  static let widgetBundleIdentifier = LorvexProductMetadata.widgetBundleIdentifier
  static let widgetKind = LorvexProductMetadata.widgetKind
  static let widgetDisplayName = LorvexProductMetadata.widgetDisplayName
  static let widgetDescription = LorvexProductMetadata.widgetDescription
  static let widgetExtensionPointIdentifier = LorvexProductMetadata.widgetExtensionPointIdentifier
  static let appGroupIdentifier = LorvexProductMetadata.appGroupIdentifier
  static let cloudKitContainerIdentifier = LorvexProductMetadata.cloudKitContainerIdentifier
  static let marketingVersion = LorvexProductMetadata.marketingVersion
  static let buildVersion = LorvexProductMetadata.buildVersion
  static let minimumSystemVersion = LorvexProductMetadata.minimumSystemVersion
  static let urlScheme = LorvexProductMetadata.urlScheme
  static let appCategory = LorvexProductMetadata.appCategory
  static let calendarWriteUsageDescription = LorvexProductMetadata.calendarWriteUsageDescription
  static let calendarFullAccessUsageDescription =
    LorvexProductMetadata.calendarFullAccessUsageDescription

  static var displayVersion: String {
    LorvexProductMetadata.displayVersion
  }
}
