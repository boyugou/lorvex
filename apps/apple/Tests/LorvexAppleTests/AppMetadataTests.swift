import LorvexCore
import LorvexMobile
import Testing

@testable import LorvexApple

@Test
func appMetadataMatchesAppleDistributionIdentity() {
  #expect(AppMetadata.appName == "Lorvex")
  #expect(AppMetadata.appDisplayName == "Lorvex")
  #expect(MobileAppMetadata.appName == "LorvexMobileApp")
  #expect(MobileAppMetadata.appDisplayName == "Lorvex")
  #expect(LorvexProductMetadata.watchComplicationProduct == "LorvexWatchComplication")
  #expect(
    LorvexProductMetadata.watchComplicationBundleIdentifier
      == "com.lorvex.apple.watchkitapp.widgets")
  #expect(
    LorvexProductMetadata.watchComplicationKind
      == "com.lorvex.apple.watchkitapp.widgets.today")
  #expect(LorvexProductMetadata.watchComplicationDisplayName == "Lorvex Today")
  // Apple's embedded-companion rule (TN3157) requires the Watch app's bundle ID
  // to be prefixed by its iOS host's, and the complication's by the Watch app's.
  // A regression that breaks this nesting fails watch install/submission, so pin
  // the parent/child topology, not only the literal strings above.
  #expect(
    LorvexProductMetadata.watchBundleIdentifier
      .hasPrefix(LorvexProductMetadata.mobileBundleIdentifier + "."))
  #expect(
    LorvexProductMetadata.watchComplicationBundleIdentifier
      .hasPrefix(LorvexProductMetadata.watchBundleIdentifier + "."))
  #expect(AppMetadata.mcpHostProduct == "LorvexMCPHost")
  #expect(AppMetadata.mcpServerName == "lorvex")
  #expect(AppMetadata.bundleIdentifier == "com.lorvex.apple")
  #expect(MobileAppMetadata.bundleIdentifier == "com.lorvex.apple")
  #expect(AppMetadata.widgetBundleIdentifier == "com.lorvex.apple.focuswidget")
  #expect(LorvexProductMetadata.widgetExecutable == "LorvexWidgets")
  #expect(LorvexProductMetadata.widgetAppeXName == "LorvexWidgets.appex")
  // The kind strings are WidgetKit identities: a placed widget finds its
  // timeline by them, so they stay fixed whatever the widget is called.
  #expect(AppMetadata.widgetKind == "com.lorvex.apple.widget.today")
  #expect(LorvexProductMetadata.progressWidgetKind == "com.lorvex.apple.widget.progress")
  #expect(LorvexProductMetadata.habitsWidgetKind == "com.lorvex.apple.widget.habits")
  #expect(AppMetadata.widgetDisplayName == "Lorvex Today")
  #expect(AppMetadata.widgetDescription == "See today’s tasks at a glance.")
  #expect(AppMetadata.widgetExtensionPointIdentifier == "com.apple.widgetkit-extension")
  #expect(LorvexProductMetadata.controlWidgetKind == "com.lorvex.control.today")
  #expect(LorvexProductMetadata.controlWidgetDisplayName == "Lorvex Today")
  #expect(LorvexProductMetadata.controlWidgetDescription == "Shows the task at the top of Today.")
  #expect(AppMetadata.appGroupIdentifier == "group.com.lorvex.apple")
  #expect(AppMetadata.cloudKitContainerIdentifier == "iCloud.com.lorvex.apple")
  #expect(AppMetadata.marketingVersion == "1.0.0")
  #expect(AppMetadata.buildVersion == "101")
  // Derived, not a third literal: the marketing and build values are pinned
  // above, so a build bump must not require editing a duplicate of them here.
  #expect(
    AppMetadata.displayVersion
      == "\(AppMetadata.marketingVersion) (\(AppMetadata.buildVersion))")
  #expect(AppMetadata.minimumSystemVersion == "26.0")
  #expect(MobileAppMetadata.minimumSystemVersion == "26.0")
  #expect(AppMetadata.urlScheme == "lorvex")
  #expect(AppMetadata.appCategory == "public.app-category.productivity")
  #expect(
    AppMetadata.calendarWriteUsageDescription
      == "Lorvex can add planning blocks you create to Apple Calendar.")
  #expect(
    AppMetadata.calendarFullAccessUsageDescription
      == "Lorvex can read event details to build schedules and assistant context.")
}

@Test
func appMetadataUsesSharedProductMetadata() {
  #expect(AppMetadata.appName == LorvexProductMetadata.appName)
  #expect(AppMetadata.appDisplayName == LorvexProductMetadata.appDisplayName)
  #expect(MobileAppMetadata.appName == LorvexProductMetadata.mobileAppName)
  #expect(MobileAppMetadata.appDisplayName == LorvexProductMetadata.mobileAppDisplayName)
  #expect(AppMetadata.mcpHostProduct == LorvexProductMetadata.mcpHostProduct)
  #expect(AppMetadata.mcpServerName == LorvexProductMetadata.mcpServerName)
  #expect(AppMetadata.bundleIdentifier == LorvexProductMetadata.bundleIdentifier)
  #expect(MobileAppMetadata.bundleIdentifier == LorvexProductMetadata.mobileBundleIdentifier)
  #expect(AppMetadata.widgetBundleIdentifier == LorvexProductMetadata.widgetBundleIdentifier)
  #expect(AppMetadata.widgetKind == LorvexProductMetadata.widgetKind)
  #expect(AppMetadata.widgetDisplayName == LorvexProductMetadata.widgetDisplayName)
  #expect(AppMetadata.widgetDescription == LorvexProductMetadata.widgetDescription)
  #expect(
    AppMetadata.widgetExtensionPointIdentifier
      == LorvexProductMetadata.widgetExtensionPointIdentifier)
  #expect(AppMetadata.appGroupIdentifier == LorvexProductMetadata.appGroupIdentifier)
  #expect(
    AppMetadata.cloudKitContainerIdentifier
      == LorvexProductMetadata.cloudKitContainerIdentifier)
  #expect(AppMetadata.marketingVersion == LorvexProductMetadata.marketingVersion)
  #expect(AppMetadata.buildVersion == LorvexProductMetadata.buildVersion)
  #expect(AppMetadata.displayVersion == LorvexProductMetadata.displayVersion)
  #expect(AppMetadata.minimumSystemVersion == LorvexProductMetadata.minimumSystemVersion)
  #expect(
    MobileAppMetadata.minimumSystemVersion
      == LorvexProductMetadata.minimumMobileSystemVersion)
  #expect(AppMetadata.urlScheme == LorvexProductMetadata.urlScheme)
  #expect(MobileAppMetadata.urlScheme == LorvexProductMetadata.urlScheme)
  #expect(AppMetadata.appCategory == LorvexProductMetadata.appCategory)
  #expect(MobileAppMetadata.appCategory == LorvexProductMetadata.appCategory)
  // Write-back to Apple Calendar is macOS-only, so only macOS re-exports a
  // calendar write usage description; mobile is read-only.
  #expect(
    AppMetadata.calendarWriteUsageDescription
      == LorvexProductMetadata.calendarWriteUsageDescription)
  #expect(
    AppMetadata.calendarFullAccessUsageDescription
      == LorvexProductMetadata.calendarFullAccessUsageDescription)
  #expect(
    MobileAppMetadata.calendarFullAccessUsageDescription
      == LorvexProductMetadata.calendarFullAccessUsageDescription)
}

// The App Store legal & support entry points are the live lorvex.app static
// pages, not the source repository. Pin the URLs so repo visibility/name can
// never leak back into the shipped contact/privacy surface.
@Test
func publicContactURLsPointAtLorvexAppNotGitHub() {
  #expect(LorvexWebLinks.websiteURL == "https://lorvex.app/")
  #expect(LorvexWebLinks.supportURL == "https://lorvex.app/support/")
  #expect(PrivacyPolicySummary.fullPolicyURL == "https://lorvex.app/privacy/")
  for url in [
    LorvexWebLinks.websiteURL,
    LorvexWebLinks.supportURL,
    PrivacyPolicySummary.fullPolicyURL,
  ] {
    #expect(!url.contains("github.com"))
  }
}
