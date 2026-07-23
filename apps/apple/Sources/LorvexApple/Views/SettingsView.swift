import LorvexCore
import SwiftUI
import UniformTypeIdentifiers
import LorvexCloudSync

enum SettingsLayoutMetrics {
  static let sidebarMinWidth: CGFloat = 184
  static let sidebarIdealWidth: CGFloat = 204
  static let sidebarMaxWidth: CGFloat = 224
  static let detailMinWidth: CGFloat = 420
  static let detailIdealWidth: CGFloat = 620
  static let detailMaxWidth: CGFloat = 760
  static let detailHorizontalPadding: CGFloat = 24
}

struct SettingsView: View {
  @Bindable var settings: AppSettingsStore
  @Bindable var store: AppStore
  // Language override (General tab). `launchLanguage` captures the language the
  // app started in so the "relaunch to apply" hint only shows once the choice
  // actually diverges from what's running.
  @State var launchLanguage: AppLanguage = .current
  @State var selectedLanguage: AppLanguage = .current
  @State var languageNeedsRelaunch = false
  @State var showingAcknowledgments = false
  @State var showingPrivacyPolicy = false
  @State var showResetConfirmation = false
  @State var resetInProgress = false
  @State var showCloudDeleteConfirmation = false
  @State var cloudDeleteInProgress = false
  @State var cloudDeleteErrorMessage: String?
  @State var cloudDeleteSucceeded = false
  @State var showResumeSyncConfirmation = false
  @State var resumeSyncInProgress = false
  @State var pendingCloudSyncResumeRequest: CloudSyncResumeRequest?
  @State var exportInProgress = false
  @State var exportErrorMessage: String?
  @State var exportSuccessMessage: String?
  @State var isExportingFile = false
  @State var exportDocument: ExportDataDocument?
  @State var exportContentType: UTType = .json
  @State var exportFilename = "lorvex-export.json"
  @State var selectedExportCategories: Set<LorvexDataExportCategory> = Set(
    LorvexDataExportCategory.allCases)
  @State var isChoosingImportFile = false
  @State var importInProgress = false
  @State var importErrorMessage: String?
  @State var importPlan: LorvexImportPlan?
  @State var importPayload: LorvexDataImporter.DecodedImport?
  @State var importSummary: LorvexImportSummary?
  @SceneStorage("settings.selectedCategory") private var selectedCategoryRawValue = SettingsCategory.general.rawValue

  private var selectedCategory: SettingsCategory {
    get { SettingsCategory(rawValue: selectedCategoryRawValue) ?? .general }
    nonmutating set { selectedCategoryRawValue = newValue.rawValue }
  }

  private var selectedCategoryBinding: Binding<SettingsCategory> {
    Binding(
      get: { selectedCategory },
      set: { selectedCategory = $0 }
    )
  }

  var body: some View {
    NavigationSplitView {
      SettingsSidebar(selectedCategory: selectedCategoryBinding)
    } detail: {
      SettingsDetailPage(category: selectedCategory) {
        settingsContent(for: selectedCategory)
      }
      .task(id: selectedCategory) {
        if selectedCategory == .cloudSync {
          await store.refreshCloudKitAccountAvailability()
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 680, idealWidth: 860, minHeight: 560)
    .task {
      if store.runtimeDiagnostics == nil {
        await store.loadRuntimeDiagnostics()
      }
    }
    // Presented from the root: a presentation modifier attached deep inside
    // the grouped Form (the Data tab's destructive buttons) does not reliably
    // present.
    .sheet(isPresented: $showResetConfirmation) {
      SettingsTypedConfirmationSheet(
        title: String(
          localized: "settings.reset.confirm.title", defaultValue: "Reset Lorvex on this Mac?",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        message: String(
          localized: "settings.reset.confirm.message",
          defaultValue:
            "This permanently erases all Lorvex data and settings on this Mac. It doesn’t touch iCloud: if sync was on, your data stays in iCloud and can download again when sync is re-enabled. To remove the iCloud copy too, use Delete iCloud Data first.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        confirmationWord: String(
          localized: "settings.reset.confirm.word", defaultValue: "RESET",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        confirmTitle: String(
          localized: "settings.reset.confirm.action", defaultValue: "Reset This Device",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "arrow.counterclockwise.circle.fill",
        accessibilityIdentifierPrefix: "settings.reset.confirm"
      ) {
        resetInProgress = true
        Task {
          await store.performFactoryReset(settings: settings)
          resetInProgress = false
        }
      }
    }
    // Root-level for the same reason as the sheets above: a dialog attached
    // inside the Cloud Sync tab's grouped Form does not reliably present.
    .confirmationDialog(
      String(
        localized: "settings.cloud_sync.resume.confirm.title",
        defaultValue: "Re-upload this Mac’s data and resume sync?",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      isPresented: $showResumeSyncConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        String(
          localized: "settings.cloud_sync.resume.confirm.action", defaultValue: "Re-upload & Resume",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
      ) {
        guard let request = pendingCloudSyncResumeRequest else { return }
        pendingCloudSyncResumeRequest = nil
        resumeSyncInProgress = true
        Task {
          await store.adoptCurrentCloudAccountAndResumeSync(request: request)
          resumeSyncInProgress = false
        }
      }
      Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {
        pendingCloudSyncResumeRequest = nil
      }
    } message: {
      Text(LocalizedStringResource(
        "settings.cloud_sync.resume.confirm.message",
        defaultValue:
          "Lorvex will upload the data stored on this Mac to the currently signed-in iCloud account and resume syncing.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
    }
    .sheet(isPresented: $showCloudDeleteConfirmation) {
      SettingsTypedConfirmationSheet(
        title: String(
          localized: "settings.cloud_delete.confirm.title",
          defaultValue: "Delete Lorvex data from iCloud everywhere?",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        message: String(
          localized: "settings.cloud_delete.confirm.message",
          defaultValue:
            "This permanently removes all Lorvex data from your iCloud account, for every device that syncs with it. Data stored locally on this Mac stays intact. Sync stays off until you turn it back on.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        confirmationWord: String(
          localized: "settings.cloud_delete.confirm.word", defaultValue: "DELETE",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        confirmTitle: String(
          localized: "settings.cloud_delete.confirm.action", defaultValue: "Delete iCloud Data",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "icloud.slash.fill",
        accessibilityIdentifierPrefix: "settings.cloudDelete.confirm"
      ) {
        cloudDeleteInProgress = true
        cloudDeleteErrorMessage = nil
        cloudDeleteSucceeded = false
        Task {
          cloudDeleteErrorMessage = await store.deleteCloudDataEverywhere(settings: settings)
          cloudDeleteSucceeded = cloudDeleteErrorMessage == nil
          cloudDeleteInProgress = false
        }
      }
    }
    // Presented from the root: a `.sheet` attached to the About section deep
    // inside the grouped Form (the Diagnostics tab's Acknowledgments button)
    // does not reliably present, the same failure mode as the destructive
    // confirmations above.
    .sheet(isPresented: $showingAcknowledgments) {
      AcknowledgmentsView()
    }
    .sheet(isPresented: $showingPrivacyPolicy) {
      PrivacyPolicyView()
    }
  }

  @ViewBuilder
  private func settingsContent(for category: SettingsCategory) -> some View {
    switch category {
    case .general:
      appearanceSection
      languageSection
      SettingsWorkingHoursRow(store: store)
    case .permissions:
      SettingsPermissionsSection(store: store, settings: settings)
    case .calendar:
      calendarSection
    case .cloudSync:
      cloudSyncSection
    case .mcpHost:
      mcpSection
    case .data:
      dataSection
    case .diagnostics:
      diagnosticsSection
      SettingsChangelogRetentionRow(store: store)
      changelogSection
      logsSection
      aboutSection
    }
  }
}
