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
        #if DEBUG
          Color.clear
            .frame(height: 1)
            .listRowBackground(Color.clear)
            .id(Self.debugDailyBackupsAnchor)
        #endif
        LorvexDailyBackupsSection(
          core: store.core,
          isDisabled: store.isDataImportRunning || store.isLocalDataResetRunning,
          idPrefix: "mobileSettings.dailyBackups",
          backUpNow: { await store.runDailyBackupIfDue() },
          describeError: {
            await store.userFacingBannerMessage(for: $0, source: "ios.ui.daily_backups_failed")
          })
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
        #if DEBUG
          Color.clear
            .frame(height: 1)
            .listRowBackground(Color.clear)
            .id(Self.debugEndAnchor)
        #endif
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
      #if DEBUG && !os(macOS)
        .navigationDestination(isPresented: $debugShowsDailyBackups) {
          LorvexDailyBackupsList(backups: debugDailyBackups)
        }
      #endif
    }
  }

  #if DEBUG
    @State private var debugShowsDailyBackups = false
    @State private var debugDailyBackups: [LorvexDailyBackup] = []

    private static let debugDailyBackupsAnchor = "mobileSettings.dailyBackups.anchor"
    private static let debugDiagnosticsAnchor = "mobileSettings.diagnostics.anchor"
    private static let debugDataExportAnchor = "mobileSettings.dataExport.anchor"
    private static let debugEndAnchor = "mobileSettings.end.anchor"

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
    /// up the same way instead, and `-lorvexScrollSettingsToEnd` the end of
    /// the list: the last rows of the failure feed with their Share button,
    /// Reset and About.
    private func revealDiagnosticsForScreenshotIfNeeded(_ proxy: ScrollViewProxy) async {
      if MobileStore.debugOpenDailyBackups {
        // The launch refresh writes today's backup off the main actor.
        for _ in 0..<20 {
          debugDailyBackups =
            (try? (store.core as? any LorvexDailyBackupServicing)?.dailyBackups()) ?? []
          if !debugDailyBackups.isEmpty { break }
          try? await Task.sleep(for: .milliseconds(250))
        }
        debugShowsDailyBackups = true
        return
      }
      if MobileStore.debugScrollSettingsToDailyBackups {
        for _ in 0..<4 {
          try? await Task.sleep(for: .milliseconds(400))
          lorvexAnimated { proxy.scrollTo(Self.debugDailyBackupsAnchor, anchor: .top) }
        }
        return
      }
      if MobileStore.debugScrollSettingsToEnd {
        await store.loadRuntimeDiagnostics()
        for _ in 0..<4 {
          try? await Task.sleep(for: .milliseconds(400))
          lorvexAnimated { proxy.scrollTo(Self.debugEndAnchor, anchor: .bottom) }
        }
        return
      }
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
