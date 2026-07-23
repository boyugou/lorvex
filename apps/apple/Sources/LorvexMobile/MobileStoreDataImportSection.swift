import LorvexCloudSync
import LorvexCore
import SwiftUI
import UniformTypeIdentifiers

/// iOS data import / restore from a previously-exported Lorvex JSON file.
///
/// Flow: pick → file-contents sheet → explicit confirm → apply → summary.
/// Nothing is written until the user taps Import in the sheet; restore uses only
/// idempotent, ID/key-preserving primitives, so re-importing the same file does
/// not create duplicates. The sheet lists what the file *contains* (a decode +
/// count), not a target-DB diff, so it never promises how many records a restore
/// writes.
struct MobileStoreDataImportSection: View {
  @Bindable var store: MobileStore
  @State private var isChoosingFile = false
  @State private var inProgress = false
  @State private var errorMessage: String?
  @State private var plan: LorvexImportPlan?
  @State private var payload: LorvexDataImporter.DecodedImport?
  @State private var summary: LorvexImportSummary?

  var body: some View {
    Section(
      String(
        localized: "settings.section.data_import", defaultValue: "Data Import",
        table: "Localizable", bundle: MobileL10n.bundle)
    ) {
      Text(
        String(
          localized: "data_import.description",
          defaultValue: "Restore from a Lorvex JSON or ZIP export. You'll see what the file contains before anything is written. Re-importing the same file never creates duplicates.",
          table: "Localizable", bundle: MobileL10n.bundle)
      )
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)

      Button {
        errorMessage = nil
        summary = nil
        isChoosingFile = true
      } label: {
        Label(
          String(
            localized: "data_import.import", defaultValue: "Import…", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "square.and.arrow.down")
      }
      .disabled(
        dataImportInteractionBlocked)
      .accessibilityIdentifier("mobileDataImport.pick")

      if inProgress {
        ProgressView(
          String(
            localized: "data_import.reading_file", defaultValue: "Reading file…",
            table: "Localizable", bundle: MobileL10n.bundle)
        )
        .font(LorvexDesign.Typography.tertiaryText)
      }

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.orange)
      }

      if let summary {
        ImportSummaryView(summary, text: MobileImportSummaryText.provider)
      }
    }
    .fileImporter(
      isPresented: $isChoosingFile,
      allowedContentTypes: [.json, .zip],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        guard let url = urls.first else { return }
        Task { await loadPlan(from: url) }
      case .failure(let error):
        errorMessage = error.localizedDescription
      }
    }
    .sheet(isPresented: previewBinding) {
      if let plan {
        MobileImportPreviewSheet(
          plan: plan,
          isApplying: dataImportInteractionBlocked,
          errorMessage: errorMessage,
          onCancel: { dismissPreview() },
          onConfirm: { beginConfirmedImport() }
        )
        .lorvexSpatialBackground()
        .interactiveDismissDisabled(dataImportInteractionBlocked)
      }
    }
  }

  private var dataImportInteractionBlocked: Bool {
    inProgress || store.isDataImportRunning || store.isSettingCloudSyncMode
      || store.isCloudDataDeletionRunning || store.isCloudDeletionMaintenanceRunning
  }

  private var previewBinding: Binding<Bool> {
    Binding(
      get: { plan != nil },
      set: { presented in
        if !presented, !dataImportInteractionBlocked { dismissPreview() }
      }
    )
  }

  private func dismissPreview() {
    plan = nil
    payload = nil
  }

  private func loadPlan(from url: URL) async {
    inProgress = true
    errorMessage = nil
    summary = nil
    defer { inProgress = false }

    // Security-scoped URL from the document picker; hold access for the read.
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

    do {
      let data = try LorvexImportLimits.readBoundedFile(at: url)
      let (decodedPlan, decoded) = try LorvexDataImporter.plan(from: data)
      plan = decodedPlan
      payload = decoded
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func beginConfirmedImport() {
    guard !dataImportInteractionBlocked, let plan, let payload else { return }
    // Claim synchronously so a repeated tap or dismissal cannot clear the
    // payload between confirmation and the async store operation starting.
    inProgress = true
    errorMessage = nil
    Task { await confirmImport(plan: plan, payload: payload) }
  }

  private func confirmImport(
    plan: LorvexImportPlan,
    payload: LorvexDataImporter.DecodedImport
  ) async {
    defer { inProgress = false }

    do {
      summary = try await store.applyDataImport(plan: plan, decoded: payload)
      dismissPreview()
    } catch {
      errorMessage = dataImportErrorMessage(for: error)
    }
  }

  private func dataImportErrorMessage(for error: any Error) -> String {
    if let boundary = error as? CloudSyncDataImportBoundary.BoundaryError {
      switch boundary {
      case .importAlreadyRunning, .dataMaintenanceRunning:
        return String(
          localized: "data_import.error.busy",
          defaultValue:
            "Another import or data operation is still running. Wait for it to finish, then try again.",
          table: "Localizable", bundle: MobileL10n.bundle)
      case .liveCoordinatorUnavailable, .cloudSyncRetryDeferred:
        break
      }
    }
    if let terminal = error as? CloudSyncTerminalInboundDrainError {
      switch terminal {
      case .accountUnavailable(.noAccount):
        return String(
          localized: "settings.sync.delete_cloud.error.no_account",
          defaultValue: "No usable iCloud account. Sign in to iCloud and try again.",
          table: "Localizable", bundle: MobileL10n.bundle)
      case .syncPaused(let reason):
        return dataImportPausedMessage(reason)
      case .unsupportedBackend, .accountUnavailable, .runtimeNotReady,
        .terminalBoundaryNotReached, .inboundStateIncomplete:
        break
      }
    }
    return String(
      localized: "data_import.error.cloud_sync_not_ready",
      defaultValue:
        "Lorvex couldn’t verify the latest iCloud data, so the backup wasn’t imported. Make sure iCloud is signed in and Cloud Sync is ready, then try again.",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  private func dataImportPausedMessage(_ reason: CloudSyncPauseReason) -> String {
    switch reason {
    case .userDeletedZone:
      return String(
        localized: "settings.sync.paused.user_deleted_zone",
        defaultValue:
          "Lorvex data was deleted from iCloud. Sync stays paused so this device doesn’t re-upload it without your consent.",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .accountChanged:
      return String(
        localized: "settings.sync.paused.account_changed",
        defaultValue:
          "The signed-in iCloud account changed. Sync is paused so this device’s data isn’t mixed into a different account.",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .adoptionInProgress, .backfillFailed:
      return String(
        localized: "settings.sync.paused.backfill_failed",
        defaultValue: "Preparing the re-upload failed. Resuming will retry it.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}

/// Modal view of an import content plan on iOS. Lists restorable categories and
/// categories this version can't restore yet — both are counts of what the file
/// *contains*, not a prediction of what a restore writes (apply skips records
/// already present or tombstoned). The Import button is the only control that
/// triggers a write.
private struct MobileImportPreviewSheet: View {
  let plan: LorvexImportPlan
  let isApplying: Bool
  let errorMessage: String?
  let onCancel: () -> Void
  let onConfirm: () -> Void

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(
            String(
              localized: "data_import.preview.notice",
              defaultValue:
                "These are the records this file contains. Nothing is written until you tap Import.",
              table: "Localizable", bundle: MobileL10n.bundle)
          )
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
        }

        Section(
          String(
            localized: "data_import.preview.in_file", defaultValue: "Can be restored",
            table: "Localizable", bundle: MobileL10n.bundle)
        ) {
          let supported = plan.entries.filter(\.isSupported)
          if supported.isEmpty {
            Text(
              String(
                localized: "data_import.preview.nothing_supported",
                defaultValue: "Nothing in a supported category.", table: "Localizable",
                bundle: MobileL10n.bundle)
            )
            .foregroundStyle(.secondary)
          } else {
            ForEach(supported) { entry in
              HStack {
                Text(entry.category.mobileLocalizedDisplayLabel)
                Spacer()
                Text("\(entry.recordCount)")
                  .foregroundStyle(.secondary)
              }
            }
          }
        }

        let deferred = plan.entries.filter { !$0.isSupported }
        if !deferred.isEmpty {
          Section(
            String(
              localized: "data_import.preview.not_imported",
              defaultValue: "Not imported (not yet supported)", table: "Localizable",
              bundle: MobileL10n.bundle)
          ) {
            ForEach(deferred) { entry in
              HStack {
                Text(entry.category.mobileLocalizedDisplayLabel)
                Spacer()
                Text("\(entry.recordCount)")
                  .foregroundStyle(.secondary)
              }
            }
          }
        }

        if let errorMessage {
          Section {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
              .accessibilityIdentifier("mobileDataImport.preview.error")
          }
        }

        if isApplying {
          Section {
            ProgressView(
              String(
                localized: "data_import.confirm", defaultValue: "Import",
                table: "Localizable", bundle: MobileL10n.bundle) + "…")
              .accessibilityIdentifier("mobileDataImport.preview.progress")
          }
        }
      }
      .navigationTitle(
        String(
          localized: "data_import.preview.title", defaultValue: "File Contents",
          table: "Localizable", bundle: MobileL10n.bundle)
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(
            String(
              localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
              bundle: MobileL10n.bundle), action: onCancel
          )
          .disabled(isApplying)
          .accessibilityIdentifier("mobileDataImport.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(
            String(
              localized: "data_import.confirm", defaultValue: "Import", table: "Localizable",
              bundle: MobileL10n.bundle), action: onConfirm
          )
          .disabled(!plan.hasSupportedRecords || isApplying)
          .accessibilityIdentifier("mobileDataImport.confirm")
        }
      }
    }
  }
}
