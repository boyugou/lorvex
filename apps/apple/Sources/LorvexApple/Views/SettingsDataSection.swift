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
  /// typed confirmation and each in its own group, so its footer sits directly
  /// under it and their distinct scopes read side by side: "Delete iCloud
  /// Data" removes the cloud copy everywhere and leaves this Mac's data alone;
  /// "Reset This Device" erases this Mac and leaves iCloud alone.
  var cloudDataDeleteSection: some View {
    Section {
      LabeledContent {
        Button(role: .destructive) {
          showCloudDeleteConfirmation = true
        } label: {
          if cloudDeleteInProgress {
            ProgressView().controlSize(.small)
          } else {
            Text(LocalizedStringResource(
              "settings.cloud_delete.button", defaultValue: "Delete…",
              table: "Localizable", bundle: LorvexL10n.bundle))
          }
        }
        .disabled(
          cloudDeleteInProgress || resetInProgress || store.isDataImportRunning
            || store.isLocalFactoryResetRunning || store.isCloudDataDeletionRunning)
        .accessibilityLabel(Self.cloudDeleteTitle)
        .accessibilityIdentifier("settings.cloudDelete.button")
      } label: {
        Label(Self.cloudDeleteTitle, systemImage: "icloud.slash")
      }

      if let cloudDeleteErrorMessage {
        Label(cloudDeleteErrorMessage, systemImage: "exclamationmark.triangle")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(LorvexDesign.Palette.warning)
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
        .foregroundStyle(LorvexDesign.Palette.success)
        .accessibilityIdentifier("settings.cloudDelete.success")
      }
    } footer: {
      Text(LocalizedStringResource(
        "settings.cloud_delete.detail",
        defaultValue:
          "Delete every Lorvex record from your iCloud account — for all devices that sync with it. The local data on this Mac is not touched. iCloud sync turns off and stays off until you re-enable it, which re-uploads this Mac’s data.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
    }
  }

  /// Local factory reset: erase this Mac's data + settings and return to a
  /// first-launch state. Local-only by design — the honest counterpart of
  /// "Delete iCloud Data" above.
  var dataResetSection: some View {
    Section {
      LabeledContent {
        Button(role: .destructive) {
          showResetConfirmation = true
        } label: {
          if resetInProgress {
            ProgressView().controlSize(.small)
          } else {
            Text(LocalizedStringResource(
              "settings.reset.button", defaultValue: "Reset…",
              table: "Localizable", bundle: LorvexL10n.bundle))
          }
        }
        .disabled(
          resetInProgress || cloudDeleteInProgress || store.isDataImportRunning
            || store.isLocalFactoryResetRunning || store.isCloudDataDeletionRunning)
        .accessibilityLabel(Self.resetTitle)
        .accessibilityIdentifier("settings.reset.button")
      } label: {
        Label(Self.resetTitle, systemImage: "trash")
      }
    } footer: {
      Text(LocalizedStringResource(
        "settings.reset.detail",
        defaultValue:
          "Erase Lorvex-managed local data and settings on this Mac and start fresh. This is local-only: data already synced to iCloud stays in iCloud and can download again when sync is re-enabled. System Calendar events are not deleted.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
    }
  }

  private static var cloudDeleteTitle: String {
    String(
      localized: "settings.cloud_delete.row_title", defaultValue: "Delete iCloud Data",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private static var resetTitle: String {
    String(
      localized: "settings.reset.row_title", defaultValue: "Reset This Device",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// Export: which categories (``SettingsExportCategoryGrid``), in which
  /// format, and the one Export button beside the format, so the choice and
  /// the action read as one line. Selecting every category, or none, is the
  /// section's own action at the trailing end of its header; the footer says
  /// what the chosen format holds and whether Lorvex can import it again.
  var dataExportSection: some View {
    Section {
      SettingsExportCategoryGrid(selection: $selectedExportCategories)

      LabeledContent {
        HStack(spacing: LorvexDesign.Spacing.s) {
          Picker(selection: $exportFormat) {
            ForEach(SettingsDataExportFormat.allCases) { format in
              Text(verbatim: format.name).tag(format)
            }
          } label: {
            Text(Self.exportFormatTitle)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .fixedSize()
          .accessibilityIdentifier("dataExport.format")

          Button {
            Task { await exportSelectedData() }
          } label: {
            Text(LocalizedStringResource(
              "settings.data_export.export", defaultValue: "Export…",
              table: "Localizable", bundle: LorvexL10n.bundle))
          }
          .buttonStyle(.borderedProminent)
          .disabled(exportInProgress || selectedExportCategories.isEmpty)
          .accessibilityIdentifier("dataExport.export")
        }
      } label: {
        Text(Self.exportFormatTitle)
      }

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
          .foregroundStyle(LorvexDesign.Palette.warning)
      }

      if let exportSuccessMessage {
        Label(exportSuccessMessage, systemImage: "checkmark.circle")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(LorvexDesign.Palette.success)
          .accessibilityIdentifier("dataExport.success")
      }
    } header: {
      HStack(alignment: .firstTextBaseline) {
        Text(String(localized: "settings.data_export.section", defaultValue: "Export", table: "Localizable", bundle: LorvexL10n.bundle))
        Spacer(minLength: LorvexDesign.Spacing.s)
        Button(
          allExportCategoriesSelected
            ? String(localized: "data_export.select_none", defaultValue: "Select None", table: "Localizable", bundle: LorvexL10n.bundle)
            : String(localized: "data_export.select_all", defaultValue: "Select All", table: "Localizable", bundle: LorvexL10n.bundle)
        ) {
          selectedExportCategories =
            allExportCategoriesSelected ? [] : Set(LorvexDataExportCategory.allCases)
        }
        .buttonStyle(.plain)
        .fontWeight(.regular)
        .foregroundStyle(LorvexDesign.Palette.accent)
        .accessibilityIdentifier("dataExport.selectAll")
      }
    } footer: {
      Text(exportFormat.detail)
        .accessibilityIdentifier("dataExport.formatDetail")
    }
    // A single file exporter handles JSON, CSV, and ZIP — the document, content
    // type, and filename are set by the export that ran. Stacking several
    // `.fileExporter` modifiers on one view is unreliable (a later
    // presentation modifier can shadow an earlier one).
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

  private static var exportFormatTitle: String {
    String(
      localized: "settings.data_export.format", defaultValue: "Format",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private var allExportCategoriesSelected: Bool {
    selectedExportCategories.count == LorvexDataExportCategory.allCases.count
  }

  /// Builds the chosen categories in the chosen format, then hands the file
  /// to the exporter.
  func exportSelectedData() async {
    exportInProgress = true
    exportErrorMessage = nil
    exportSuccessMessage = nil
    defer { exportInProgress = false }
    let format = exportFormat
    let entities = LorvexDataExportCategory.allCases
      .filter { selectedExportCategories.contains($0) }
      .map(\.rawValue)
    let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let generatedAt = LorvexDateFormatters.iso8601.string(from: Date())
    do {
      let data: Data
      switch format {
      case .json, .csv:
        let output = try await store.core.exportData(
          entities: entities, format: format.rawValue, appVersion: appVersion,
          generatedAt: generatedAt)
        data = Data(output.utf8)
      case .zip:
        data = try await store.core.exportDataZip(
          entities: entities, generatedAt: generatedAt, appVersion: appVersion)
      }
      exportContentType = format.contentType
      exportFilename = "lorvex-export.\(format.rawValue)"
      exportDocument = ExportDataDocument(data: data)
      isExportingFile = true
    } catch {
      exportErrorMessage = await store.userFacingBannerMessage(
        for: error,
        source: format == .zip ? "macos.ui.data_export_zip_failed" : "macos.ui.data_export_failed")
    }
  }
}

/// The file format of a Settings › Data export: one JSON file, one CSV file
/// with a section per category, or a ZIP archive of one JSON file per
/// category. `rawValue` is both the core's `exportData` format name and the
/// file extension.
enum SettingsDataExportFormat: String, CaseIterable, Identifiable {
  case json
  case csv
  case zip

  var id: String { rawValue }

  /// The format's name, written the same in every language.
  var name: String { rawValue.uppercased() }

  var contentType: UTType {
    switch self {
    case .json: .json
    case .csv: .commaSeparatedText
    case .zip: .zip
    }
  }

  /// What the file holds and whether Lorvex can import it again.
  var detail: String {
    switch self {
    case .json:
      String(
        localized: "settings.data_export.format.json_detail",
        defaultValue:
          "One JSON file Lorvex can import again: a backup, or a way to move your data to another Lorvex install.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .csv:
      String(
        localized: "settings.data_export.format.csv_detail",
        defaultValue:
          "One spreadsheet-friendly CSV file with a section per category, for opening in other tools. Lorvex can’t import CSV.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .zip:
      String(
        localized: "settings.data_export.format.zip_detail",
        defaultValue: "A ZIP archive with one JSON file per category. Lorvex can import it again.",
        table: "Localizable", bundle: LorvexL10n.bundle)
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
