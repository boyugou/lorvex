import Foundation
import LorvexCloudSync
import LorvexCore
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {

  /// Import / restore from a previously-exported Lorvex JSON file. The flow is
  /// pick → file-contents sheet → explicit confirm → apply → summary. Nothing is
  /// written until the user confirms in the sheet; the importer uses only
  /// idempotent, ID/key-preserving primitives, so re-importing the same file does
  /// not duplicate. The sheet lists what the file *contains* (a decode + count),
  /// not a target-DB diff, so it never promises how many records a restore writes.
  var dataImportSection: some View {
    Section(String(localized: "settings.data_import.section", defaultValue: "Import", table: "Localizable", bundle: LorvexL10n.bundle)) {
      Text(LocalizedStringResource(
        "settings.data_import.description",
        defaultValue: "Load data from a JSON or ZIP file you made with Export above. You'll see what the file contains first; importing never duplicates data you already have.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)

      Button {
        importErrorMessage = nil
        importSummary = nil
        isChoosingImportFile = true
      } label: {
        Label(
          String(localized: "settings.data_import.import", defaultValue: "Import…", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "square.and.arrow.down"
        )
      }
      .disabled(
        dataImportInteractionBlocked)
      .accessibilityIdentifier("dataImport.pick")

      if importInProgress {
        ProgressView(String(localized: "settings.data_import.reading_file", defaultValue: "Reading file…", table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.tertiaryText)
      }

      if let importErrorMessage {
        Label(importErrorMessage, systemImage: "exclamationmark.triangle")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.orange)
      }

      if let importSummary {
        ImportSummaryView(importSummary, text: LorvexImportSummaryText.provider)
      }
    }
    .fileImporter(
      isPresented: $isChoosingImportFile,
      allowedContentTypes: [.json, .zip],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        guard let url = urls.first else { return }
        Task { await loadImportPlan(from: url) }
      case .failure(let error):
        importErrorMessage = error.localizedDescription
      }
    }
    .sheet(isPresented: importPreviewBinding) {
      if let importPlan {
        ImportPreviewSheet(
          plan: importPlan,
          isApplying: dataImportInteractionBlocked,
          errorMessage: importErrorMessage,
          onCancel: { dismissImportPreview() },
          onConfirm: { beginConfirmedImport() }
        )
        .interactiveDismissDisabled(dataImportInteractionBlocked)
      }
    }
  }

  private var dataImportInteractionBlocked: Bool {
    importInProgress || store.isDataImportRunning || store.isLocalFactoryResetRunning
      || store.isCloudDataDeletionRunning || store.isCloudDeletionMaintenanceRunning
  }

  private var importPreviewBinding: Binding<Bool> {
    Binding(
      get: { importPlan != nil },
      set: { presented in
        if !presented, !dataImportInteractionBlocked { dismissImportPreview() }
      }
    )
  }

  private func dismissImportPreview() {
    importPlan = nil
    importPayload = nil
  }

  func loadImportPlan(from url: URL) async {
    importInProgress = true
    importErrorMessage = nil
    importSummary = nil
    defer { importInProgress = false }

    // The picked URL is security-scoped on sandboxed builds; hold access for the
    // read or `Data(contentsOf:)` fails.
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

    do {
      let data = try LorvexImportLimits.readBoundedFile(at: url)
      let (plan, decoded) = try LorvexDataImporter.plan(from: data)
      importPlan = plan
      importPayload = decoded
    } catch {
      importErrorMessage = error.localizedDescription
    }
  }

  private func beginConfirmedImport() {
    guard !dataImportInteractionBlocked,
      let plan = importPlan,
      let decoded = importPayload
    else { return }
    // Claim the view-local fence synchronously before creating the Task. This
    // closes the double-click / keyboard-repeat window in which Cancel could
    // clear the captured payload before the async body even started.
    importInProgress = true
    importErrorMessage = nil
    Task { await confirmImport(plan: plan, decoded: decoded) }
  }

  private func confirmImport(
    plan: LorvexImportPlan,
    decoded: LorvexDataImporter.DecodedImport
  ) async {
    defer { importInProgress = false }

    do {
      importSummary = try await store.applyDataImport(plan: plan, decoded: decoded)
      dismissImportPreview()
    } catch {
      importErrorMessage = dataImportErrorMessage(for: error)
    }
  }

  private func dataImportErrorMessage(for error: any Error) -> String {
    if let boundary = error as? CloudSyncDataImportBoundary.BoundaryError {
      switch boundary {
      case .importAlreadyRunning, .dataMaintenanceRunning:
        return String(
          localized: "settings.data_import.error.busy",
          defaultValue:
            "Another import or data operation is still running. Wait for it to finish, then try again.",
          table: "Localizable", bundle: LorvexL10n.bundle)
      case .liveCoordinatorUnavailable, .cloudSyncRetryDeferred:
        break
      }
    }
    if let terminal = error as? CloudSyncTerminalInboundDrainError {
      switch terminal {
      case .accountUnavailable(.noAccount):
        return String(
          localized: "settings.cloud_sync.account.no_account_message",
          defaultValue: "No iCloud account. Sign in via System Settings > Apple Account.",
          table: "Localizable", bundle: LorvexL10n.bundle)
      case .accountUnavailable(.restricted):
        return String(
          localized: "settings.cloud_sync.account.restricted_message",
          defaultValue: "iCloud is restricted by a device management profile.",
          table: "Localizable", bundle: LorvexL10n.bundle)
      case .accountUnavailable(.temporarilyUnavailable):
        return String(
          localized: "settings.cloud_sync.account.temporarily_unavailable_message",
          defaultValue: "iCloud account is temporarily unavailable.",
          table: "Localizable", bundle: LorvexL10n.bundle)
      case .accountUnavailable(.couldNotDetermine), .accountUnavailable(.available):
        return String(
          localized: "settings.cloud_sync.account.unknown_message",
          defaultValue: "Unable to determine iCloud account status.",
          table: "Localizable", bundle: LorvexL10n.bundle)
      case .syncPaused(let reason):
        return dataImportPausedMessage(reason)
      case .unsupportedBackend, .runtimeNotReady, .terminalBoundaryNotReached,
        .inboundStateIncomplete:
        break
      }
    }
    return String(
      localized: "settings.data_import.error.cloud_sync_not_ready",
      defaultValue:
        "Lorvex couldn’t verify the latest iCloud data, so the backup wasn’t imported. Make sure iCloud is signed in and Cloud Sync is ready, then try again.",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private func dataImportPausedMessage(_ reason: CloudSyncPauseReason) -> String {
    switch reason {
    case .userDeletedZone:
      return String(
        localized: "settings.cloud_sync.paused.user_deleted_zone",
        defaultValue:
          "Lorvex data was deleted from iCloud. Sync stays paused so this Mac doesn’t re-upload it without your consent.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .accountChanged:
      return String(
        localized: "settings.cloud_sync.paused.account_changed",
        defaultValue:
          "The signed-in iCloud account changed. Sync is paused so this Mac’s data isn’t mixed into a different account.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .adoptionInProgress, .backfillFailed:
      return String(
        localized: "settings.cloud_sync.paused.backfill_failed",
        defaultValue: "Preparing the re-upload failed. Resuming will retry it.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}

/// Modal view of an import content plan. Lists restorable categories and
/// categories this version can't restore yet — both are counts of what the file
/// *contains*, not a prediction of what a restore writes (apply skips records
/// already present or tombstoned). The "Import" button is the only control that
/// triggers a write.
private struct ImportPreviewSheet: View {
  let plan: LorvexImportPlan
  let isApplying: Bool
  let errorMessage: String?
  let onCancel: () -> Void
  let onConfirm: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      DraftSheetHeader(
        title: String(localized: "settings.data_import.preview.title", defaultValue: "File Contents", table: "Localizable", bundle: LorvexL10n.bundle),
        subtitle: String(
          localized: "settings.data_import.preview.notice",
          defaultValue: "These are the records this file contains. Nothing is written until you choose Import.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "square.and.arrow.down"
      )

      ImportPreviewCategoryPanel(
        title: String(localized: "settings.data_import.preview.in_file", defaultValue: "Can be restored", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "checkmark.circle.fill",
        tint: .green,
        entries: plan.entries.filter(\.isSupported),
        emptyMessage: String(
          localized: "settings.data_import.preview.nothing_supported",
          defaultValue: "Nothing in a supported category.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        accessibilityIdentifier: "dataImport.preview.supported"
      )

      let deferred = plan.entries.filter { !$0.isSupported }
      if !deferred.isEmpty {
        ImportPreviewCategoryPanel(
          title: String(
            localized: "settings.data_import.preview.not_imported",
            defaultValue: "Not imported (can't be safely restored yet)",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
          systemImage: "exclamationmark.triangle.fill",
          tint: .orange,
          entries: deferred,
          emptyMessage: "",
          accessibilityIdentifier: "dataImport.preview.deferred"
        )
      }

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.orange)
          .accessibilityIdentifier("dataImport.preview.error")
      }

      if isApplying {
        ProgressView {
          Text(
            String(
              localized: "settings.data_import.confirm", defaultValue: "Import",
              table: "Localizable", bundle: LorvexL10n.bundle) + "…")
        }
        .accessibilityIdentifier("dataImport.preview.progress")
      }

      HStack {
        Button(
          String(localized: "settings.data_import.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle),
          role: .cancel,
          action: onCancel
        )
          .keyboardShortcut(.cancelAction)
          .disabled(isApplying)
          .accessibilityIdentifier("dataImport.cancel")
        Spacer()
        Button(String(localized: "settings.data_import.confirm", defaultValue: "Import", table: "Localizable", bundle: LorvexL10n.bundle), action: onConfirm)
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .disabled(!plan.hasSupportedRecords || isApplying)
          .accessibilityIdentifier("dataImport.confirm")
      }
      .padding(.top, LorvexDesign.Spacing.xs)
    }
    .padding(LorvexDesign.Spacing.l)
    .frame(minWidth: 460, idealWidth: 520, minHeight: 360)
  }
}

private struct ImportPreviewCategoryPanel: View {
  let title: String
  let systemImage: String
  let tint: Color
  let entries: [LorvexImportPlanEntry]
  let emptyMessage: String
  let accessibilityIdentifier: String

  var body: some View {
    DraftSheetPanel(accessibilityIdentifier: accessibilityIdentifier) {
      Label {
        Text(title)
          .font(LorvexDesign.Typography.primaryEmphasis)
      } icon: {
        Image(systemName: systemImage)
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(tint)
      }

      if entries.isEmpty {
        Text(emptyMessage)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        VStack(spacing: 0) {
          ForEach(entries) { entry in
            ImportPreviewEntryRow(entry: entry, tint: tint)
            if entry.id != entries.last?.id {
              Divider()
            }
          }
        }
      }
    }
  }
}

private struct ImportPreviewEntryRow: View {
  let entry: LorvexImportPlanEntry
  let tint: Color

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      Circle()
        .fill(tint.opacity(0.85))
        .frame(width: 7, height: 7)
        .accessibilityHidden(true)

      Text(entry.category.lorvexLocalizedDisplayLabel)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.primary)
        .lineLimit(1)

      Spacer(minLength: LorvexDesign.Spacing.s)

      Text(entry.localizedRecordCount)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .accessibilityElement(children: .combine)
  }
}

private extension LorvexImportPlanEntry {
  var localizedRecordCount: String {
    String(
      localized: "settings.data_import.records_count",
      defaultValue: "\(recordCount) records",
      table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
}
