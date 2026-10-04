import LorvexCloudSync
import LorvexCore
import SwiftUI

/// Root Settings screen for iPhone/iPad. Groups mobile-facing configuration,
/// permission toggles, data tools, and diagnostics into a single navigable List.
@MainActor
public struct MobileStoreSettingsView: View {
  @Bindable var store: MobileStore

  public init(store: MobileStore) {
    self.store = store
  }

  public var body: some View {
    ScrollViewReader { proxy in
      List {
        MobileSettingsAppearanceSection()
        MobileSettingsLanguageSection(store: store)
        MobileStoreSettingsWorkingHoursSection(store: store)
        MobileStoreSettingsNotificationsSection(store: store)
        MobileStoreSettingsCloudSyncSection(store: store)
        MobileStoreSettingsCalendarSection(store: store)
        #if DEBUG
          Color.clear
            .frame(height: 1)
            .listRowBackground(Color.clear)
            .id(Self.debugDataExportAnchor)
        #endif
        MobileStoreDataExportSection(store: store)
        MobileStoreDataImportSection(store: store)
        MobileStoreSettingsChangelogRetentionSection(store: store)
        #if DEBUG
          // Invisible target immediately above Diagnostics so the screenshot
          // hook can bring that section's own top to the top of the screen.
          Color.clear
            .frame(height: 1)
            .listRowBackground(Color.clear)
            .id(Self.debugDiagnosticsAnchor)
        #endif
        MobileStoreDiagnosticsSection(store: store)
        MobileStoreLocalDataResetSection(store: store)
        MobileSettingsAboutSection()
      }
      .navigationTitle(
        String(
          localized: "destination.settings", defaultValue: "Settings", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .task {
        // Narrow queue read first: it is one table scan, and the account probe
        // below can take seconds. Every read reruns on each appearance, which
        // keeps the Diagnostics section current without a refresh button;
        // the diagnostics load also reloads the recent-failure feed.
        await store.refreshSyncStatus()
        await store.refreshCloudKitAccountAvailability()
        await store.loadRuntimeDiagnostics()
        #if DEBUG
          await revealDiagnosticsForScreenshotIfNeeded(proxy)
        #endif
      }
      .accessibilityIdentifier("mobileSettings.root")
    }
  }

  #if DEBUG
    private static let debugDiagnosticsAnchor = "mobileSettings.diagnostics.anchor"
    private static let debugDataExportAnchor = "mobileSettings.dataExport.anchor"

    /// Dev/QA only: when launched with `-lorvexScrollSettingsToDiagnostics`,
    /// reload diagnostics (so freshly-seeded rows are present) and bring the
    /// Diagnostics section's own top to the top of the screen for a screenshot,
    /// without a manual swipe. Compiled out of release builds.
    ///
    /// Anchored at the section's head rather than the list's end: the summary
    /// card (sync mode, queue depths, last transport error) and the newest rows
    /// of the failure feed are what a diagnostics capture has to show, and the
    /// feed is long enough that a bottom anchor scrolls both of them away.
    ///
    /// `-lorvexScrollSettingsToDataExport` brings the Data Export section's top
    /// up the same way instead.
    private func revealDiagnosticsForScreenshotIfNeeded(_ proxy: ScrollViewProxy) async {
      if MobileStore.debugScrollSettingsToDataExport {
        for _ in 0..<4 {
          try? await Task.sleep(for: .milliseconds(400))
          lorvexAnimated { proxy.scrollTo(Self.debugDataExportAnchor, anchor: .top) }
        }
        return
      }
      guard MobileStore.debugScrollSettingsToDiagnostics else { return }
      await store.loadRuntimeDiagnostics()
      // Scroll a few times as the list settles: the recent rows render one
      // runloop after the diagnostics load, so a single early scroll lands short.
      for _ in 0..<4 {
        try? await Task.sleep(for: .milliseconds(400))
        lorvexAnimated { proxy.scrollTo(Self.debugDiagnosticsAnchor, anchor: .top) }
      }
    }
  #endif
}
