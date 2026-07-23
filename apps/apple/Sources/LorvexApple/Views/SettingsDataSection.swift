import AppKit
import Foundation
import LorvexCore
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {

  var dataSection: some View {
    Group {
      dataExportSection
      dataImportSection
      cloudDataDeleteSection
      dataResetSection
    }
  }

  /// The two destructive actions sit together at the bottom, each behind a
  /// typed confirmation, so their distinct scopes read side by side: "Delete
  /// iCloud Data" removes the cloud copy everywhere and leaves this Mac's data
  /// alone; "Reset This Device" erases this Mac and leaves iCloud alone.
  var cloudDataDeleteSection: some View {
    Section(String(
      localized: "settings.cloud_delete.section", defaultValue: "iCloud Data",
      table: "Localizable",
      bundle: LorvexL10n.bundle)
    ) {
      Text(LocalizedStringResource(
        "settings.cloud_delete.detail",
        defaultValue:
          "Delete every Lorvex record from your iCloud account — for all devices that sync with it. The local data on this Mac is not touched. iCloud sync turns off and stays off until you re-enable it, which re-uploads this Mac’s data.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)

      Button(role: .destructive) {
        showCloudDeleteConfirmation = true
      } label: {
        if cloudDeleteInProgress {
          ProgressView().controlSize(.small)
        } else {
          Label(
            String(
              localized: "settings.cloud_delete.title", defaultValue: "Delete iCloud Data…",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            systemImage: "icloud.slash")
        }
      }
      .disabled(
        cloudDeleteInProgress || resetInProgress || store.isDataImportRunning
          || store.isLocalFactoryResetRunning || store.isCloudDataDeletionRunning
          || store.isCloudDeletionMaintenanceRunning)
      .accessibilityIdentifier("settings.cloudDelete.button")

      if let cloudDeleteErrorMessage {
        Label(cloudDeleteErrorMessage, systemImage: "exclamationmark.triangle")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.orange)
          .accessibilityIdentifier("settings.cloudDelete.error")
      }

      if cloudDeleteSucceeded {
        Label(
          String(
            localized: "settings.cloud_delete.success",
            defaultValue: "Lorvex data was deleted from iCloud. Sync is now off.",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          systemImage: "checkmark.circle"
        )
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.green)
        .accessibilityIdentifier("settings.cloudDelete.success")
      }
    }
  }

  /// Local factory reset: erase this Mac's data + settings and return to a
  /// first-launch state. Local-only by design — the honest counterpart of
  /// "Delete iCloud Data" above.
  var dataResetSection: some View {
    Section(String(localized: "settings.reset.section", defaultValue: "Reset", table: "Localizable", bundle: LorvexL10n.bundle)) {
      Text(LocalizedStringResource(
        "settings.reset.detail",
        defaultValue:
          "Erase Lorvex-managed local data and settings on this Mac and start fresh. This is local-only: data already synced to iCloud stays in iCloud and can download again when sync is re-enabled. System Calendar events are not deleted.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)

      Button(role: .destructive) {
        showResetConfirmation = true
      } label: {
        if resetInProgress {
          ProgressView().controlSize(.small)
        } else {
          Label(
            String(
              localized: "settings.reset.title", defaultValue: "Reset This Device…",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            systemImage: "trash")
        }
      }
      .disabled(
        resetInProgress || cloudDeleteInProgress || store.isDataImportRunning
          || store.isLocalFactoryResetRunning || store.isCloudDataDeletionRunning
          || store.isCloudDeletionMaintenanceRunning)
      .accessibilityIdentifier("settings.reset.button")
    }
  }

  var dataExportSection: some View {
    Section(String(localized: "settings.data_export.section", defaultValue: "Export", table: "Localizable", bundle: LorvexL10n.bundle)) {
      Text(LocalizedStringResource(
        "settings.data_export.description",
        defaultValue: "Save the categories you pick as a JSON file, a spreadsheet-friendly CSV, or a ZIP (one JSON per category). For backups, moving your data to another Lorvex install, or opening it in other tools.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)

      ExportCategoryPicker(
        selection: $selectedExportCategories,
        idPrefix: "dataExport",
        categoryName: { $0.lorvexLocalizedDisplayLabel },
        selectAllLabel: String(
          localized: "data_export.select_all", defaultValue: "Select All",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        selectNoneLabel: String(
          localized: "data_export.select_none", defaultValue: "Select None",
          table: "Localizable",
          bundle: LorvexL10n.bundle))

      HStack {
        Button {
          Task { await triggerExport(format: "json") }
        } label: {
          Label(
            String(
              localized: "settings.data_export.export_json",
              defaultValue: "Export as JSON…",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
            systemImage: "square.and.arrow.up"
          )
        }
        .disabled(exportInProgress || selectedExportCategories.isEmpty)

        Button {
          Task { await triggerExport(format: "csv") }
        } label: {
          Label(
            String(
              localized: "settings.data_export.export_csv",
              defaultValue: "Export as CSV…",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
            systemImage: "tablecells"
          )
        }
        .disabled(exportInProgress || selectedExportCategories.isEmpty)

        Button {
          Task { await triggerZipExport() }
        } label: {
          Label(
            String(
              localized: "settings.data_export.export_zip",
              defaultValue: "Export as ZIP…",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
            systemImage: "doc.zipper"
          )
        }
        .disabled(exportInProgress || selectedExportCategories.isEmpty)
      }
      .buttonStyle(.bordered)

      if exportInProgress {
        ProgressView(String(
          localized: "settings.data_export.preparing",
          defaultValue: "Preparing export…",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ))
          .font(LorvexDesign.Typography.tertiaryText)
      }

      if let errorMessage = exportErrorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.orange)
      }

      if let exportSuccessMessage {
        Label(exportSuccessMessage, systemImage: "checkmark.circle")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.green)
          .accessibilityIdentifier("dataExport.success")
      }
    }
    // A single file exporter handles JSON, CSV, and ZIP — the document, content
    // type, filename, and status route are set by whichever export the user triggered.
    // Stacking multiple `.fileExporter` modifiers on one view is unreliable (a
    // later presentation modifier can shadow an earlier one).
    .fileExporter(
      isPresented: $isExportingFile,
      document: exportDocument,
      contentType: exportContentType,
      defaultFilename: exportFilename
    ) { result in
      switch result {
      case .success(let url):
        exportErrorMessage = nil
        exportSuccessMessage = String(
          format: String(
            localized: "settings.data_export.exported_to",
            defaultValue: "Exported to %@",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
          url.lastPathComponent
        )
      case .failure(let error):
        exportSuccessMessage = nil
        exportErrorMessage = error.localizedDescription
      }
    }
  }

  func triggerExport(format: String) async {
    exportInProgress = true
    exportErrorMessage = nil
    exportSuccessMessage = nil
    defer { exportInProgress = false }
    do {
      let entities = LorvexDataExportCategory.allCases
        .filter { selectedExportCategories.contains($0) }
        .map(\.rawValue)
      let output = try await store.core.exportData(
        entities: entities,
        format: format,
        appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        generatedAt: LorvexDateFormatters.iso8601.string(from: Date()))
      let ext = format == "csv" ? "csv" : "json"
      exportContentType = format == "csv" ? .commaSeparatedText : .json
      exportFilename = "lorvex-export.\(ext)"
      exportDocument = ExportDataDocument(data: Data(output.utf8))
      isExportingFile = true
    } catch {
      exportErrorMessage = await store.userFacingBannerMessage(
        for: error, source: "macos.ui.data_export_failed")
    }
  }

  func triggerZipExport() async {
    exportInProgress = true
    exportErrorMessage = nil
    exportSuccessMessage = nil
    defer { exportInProgress = false }
    do {
      let entities = LorvexDataExportCategory.allCases
        .filter { selectedExportCategories.contains($0) }
        .map(\.rawValue)
      let data = try await store.core.exportDataZip(
        entities: entities,
        generatedAt: LorvexDateFormatters.iso8601.string(from: Date()),
        appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      )
      exportContentType = .zip
      exportFilename = "lorvex-export.zip"
      exportDocument = ExportDataDocument(data: data)
      isExportingFile = true
    } catch {
      exportErrorMessage = await store.userFacingBannerMessage(
        for: error, source: "macos.ui.data_export_zip_failed")
    }
  }
}

// MARK: - FileDocument (binary)

/// A `FileDocument` vending raw `Data` for every data-export format — JSON, CSV,
/// or a `.zip` archive. The content type is chosen by the caller via the
/// `.fileExporter`'s `contentType:`, so one document type backs a single
/// exporter for all formats.
struct ExportDataDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.json, .commaSeparatedText, .plainText, .zip]

  var data: Data

  init(data: Data) { self.data = data }

  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
