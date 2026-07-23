import LorvexCore

public enum MobileAppMetadata {
  public static let appName = LorvexProductMetadata.mobileAppName
  public static let appDisplayName = LorvexProductMetadata.mobileAppDisplayName
  public static let bundleIdentifier = LorvexProductMetadata.mobileBundleIdentifier
  public static let appGroupIdentifier = LorvexProductMetadata.appGroupIdentifier
  public static let cloudKitContainerIdentifier = LorvexProductMetadata.cloudKitContainerIdentifier
  public static let marketingVersion = LorvexProductMetadata.marketingVersion
  public static let buildVersion = LorvexProductMetadata.buildVersion
  public static let minimumSystemVersion = LorvexProductMetadata.minimumMobileSystemVersion
  public static let urlScheme = LorvexProductMetadata.urlScheme
  public static let appCategory = LorvexProductMetadata.appCategory
  // No calendar write usage description: iPhone/iPad request full Calendar access
  // only to read the system calendar for display and planning; write-back to
  // Apple Calendar is macOS-only.
  public static let calendarFullAccessUsageDescription =
    LorvexProductMetadata.calendarFullAccessUsageDescription

  public static var displayVersion: String {
    LorvexProductMetadata.displayVersion
  }
}

public enum VisionAppMetadata {
  public static let appName = LorvexProductMetadata.visionAppName
  public static let appDisplayName = LorvexProductMetadata.visionAppDisplayName
  public static let bundleIdentifier = LorvexProductMetadata.visionBundleIdentifier
  public static let appGroupIdentifier = LorvexProductMetadata.appGroupIdentifier
  public static let cloudKitContainerIdentifier = LorvexProductMetadata.cloudKitContainerIdentifier
  public static let marketingVersion = LorvexProductMetadata.marketingVersion
  public static let buildVersion = LorvexProductMetadata.buildVersion
  public static let minimumSystemVersion = LorvexProductMetadata.minimumVisionSystemVersion
  public static let urlScheme = LorvexProductMetadata.urlScheme
  public static let appCategory = LorvexProductMetadata.appCategory
  // No calendar write usage description: visionOS requests full Calendar access
  // only to read the system calendar for display and planning; write-back to
  // Apple Calendar is macOS-only.
  public static let calendarFullAccessUsageDescription =
    LorvexProductMetadata.calendarFullAccessUsageDescription

  public static var displayVersion: String {
    LorvexProductMetadata.displayVersion
  }
}
