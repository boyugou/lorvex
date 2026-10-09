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
    Section {
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
          .foregroundStyle(LorvexDesign.Palette.warning)
      }

      if let summary {
        ImportSummaryView(summary)
      }
    } header: {
      Text(
        String(
          localized: "settings.section.data_import", defaultValue: "Data Import",
          table: "Localizable", bundle: MobileL10n.bundle))
    } footer: {
      Text(
        String(
          localized: "data_import.description",
          defaultValue:
            "Restore from a Lorvex JSON or ZIP export. You’ll see what the file contains before anything is written. Re-importing the same file never creates duplicates.",
          table: "Localizable", bundle: MobileL10n.bundle))
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
          isBackgroundable: store.isDataImportRunning,
          errorMessage: errorMessage,
          onCancel: { dismissPreview() },
          onConfirm: { beginConfirmedImport() },
          onRunInBackground: { dismissPreview() }
        )
        // Block dismissal only during the brief pre-run claim; once the import is
        // actually running in the store it continues detached, so allow closing
        // to background rather than trapping the sheet on a slow CloudKit drain.
        .interactiveDismissDisabled(dataImportInteractionBlocked && !store.isDataImportRunning)
      }
    }
  }

  private var dataImportInteractionBlocked: Bool {
    inProgress || store.isDataImportRunning || store.isSettingCloudSyncMode
      || store.isCloudDataDeletionRunning || store.isLocalDataResetRunning
  }

  private var previewBinding: Binding<Bool> {
    Binding(
      get: { plan != nil },
      set: { presented in
        // Allow dismissal when not blocked, OR once the import is running (it
        // continues in the background); otherwise a swipe would re-present.
        if !presented, !dataImportInteractionBlocked || store.isDataImportRunning {
          dismissPreview()
        }
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
    String(
      localized: "data_import.error.busy",
      defaultValue:
        "Another import or data operation is still running. Wait for it to finish, then try again.",
      table: "Localizable", bundle: MobileL10n.bundle)
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
  /// The import is running in the store (not just the brief local claim), so it
  /// continues on its own detached task if this sheet closes — closing is safe
  /// and merely stops the screen trapping the user while a CloudKit drain is slow.
  let isBackgroundable: Bool
  let errorMessage: String?
  let onCancel: () -> Void
  let onConfirm: () -> Void
  let onRunInBackground: () -> Void

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
                Text(entry.category.localizedDisplayName)
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
                Text(entry.category.localizedDisplayName)
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
              .foregroundStyle(LorvexDesign.Palette.warning)
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
            if isBackgroundable {
              Text(
                String(
                  localized: "data_import.background.note",
                  defaultValue:
                    "The import keeps running if you close this. If it doesn’t finish, check your internet connection.",
                  table: "Localizable", bundle: MobileL10n.bundle)
              )
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
              Button(
                String(
                  localized: "data_import.background.action", defaultValue: "Continue in Background",
                  table: "Localizable", bundle: MobileL10n.bundle), action: onRunInBackground
              )
              .accessibilityIdentifier("mobileDataImport.continueInBackground")
            }
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
          .mobileProminentToolbarButtonStyle()
          .disabled(!plan.hasSupportedRecords || isApplying)
          .accessibilityIdentifier("mobileDataImport.confirm")
        }
      }
    }
    .mobileSystemContentMargins()
  }
}
