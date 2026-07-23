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
        MobileSettingsLanguageSection()
        MobileStoreSettingsWorkingHoursSection(store: store)
        MobileStoreSettingsNotificationsSection(store: store)
        MobileStoreSettingsCloudSyncSection(store: store)
        MobileStoreSettingsCalendarSection(store: store)
        MobileStoreDataExportSection(store: store)
        MobileStoreDataImportSection(store: store)
        MobileStoreSettingsChangelogRetentionSection(store: store)
        MobileStoreDiagnosticsSection(store: store)
        MobileSettingsAboutSection()
        #if DEBUG
          // Invisible trailing target so the screenshot hook can scroll to the
          // true end of the list (past the tall diagnostics summary card),
          // revealing the whole Recent Diagnostics feed.
          Color.clear
            .frame(height: 1)
            .listRowBackground(Color.clear)
            .id(Self.debugBottomAnchor)
        #endif
      }
      .navigationTitle(
        String(
          localized: "destination.settings", defaultValue: "Settings", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .task {
        await store.refreshCloudKitAccountAvailability()
        if store.runtimeDiagnostics == nil {
          await store.loadRuntimeDiagnostics()
        }
        await store.loadRecentDiagnosticLogs()
        #if DEBUG
          await revealDiagnosticsForScreenshotIfNeeded(proxy)
        #endif
      }
      .accessibilityIdentifier("mobileSettings.root")
    }
  }

  #if DEBUG
    private static let debugBottomAnchor = "mobileSettings.bottom.anchor"

    /// Dev/QA only: when launched with `-lorvexScrollSettingsToDiagnostics`,
    /// reload diagnostics (so freshly-seeded rows are present) and scroll to the
    /// end of the list so the whole Recent Diagnostics feed is on screen for a
    /// screenshot, without a manual swipe. Compiled out of release builds.
    private func revealDiagnosticsForScreenshotIfNeeded(_ proxy: ScrollViewProxy) async {
      guard MobileStore.debugScrollSettingsToDiagnostics else { return }
      await store.loadRuntimeDiagnostics()
      // Scroll a few times as the list settles: the recent rows render one
      // runloop after the diagnostics load, so a single early scroll lands short.
      for _ in 0..<4 {
        try? await Task.sleep(for: .milliseconds(400))
        withAnimation { proxy.scrollTo(Self.debugBottomAnchor, anchor: .bottom) }
      }
    }
  #endif
}
