import LorvexCore
import SwiftUI

struct MobileStoreDataExportSection: View {
  @Bindable var store: MobileStore
  @State private var exportItem: MobileDataExportTransferable?
  @State private var selectedCategories: Set<LorvexDataExportCategory> = Set(
    LorvexDataExportCategory.allCases)

  var body: some View {
    Section(
      String(
        localized: "settings.section.data_export", defaultValue: "Data Export",
        table: "Localizable", bundle: MobileL10n.bundle)
    ) {
      Text(
        String(
          localized: "data_export.description",
          defaultValue:
            "Full-table export of the categories you select, as JSON, CSV, or a ZIP package.",
          table: "Localizable", bundle: MobileL10n.bundle)
      )
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)

      ExportCategoryPicker(
        selection: $selectedCategories,
        idPrefix: "mobileDataExport",
        categoryName: { $0.mobileLocalizedDisplayLabel },
        selectAllLabel: String(
          localized: "data_export.select_all", defaultValue: "Select All", table: "Localizable",
          bundle: MobileL10n.bundle),
        selectNoneLabel: String(
          localized: "data_export.select_none", defaultValue: "Select None", table: "Localizable",
          bundle: MobileL10n.bundle))

      ForEach(MobileDataExportFormat.allCases) { format in
        Button {
          Task {
            await prepareExport(format)
          }
        } label: {
          Label(
            String(
              format: String(
                localized: "data_export.export_format", defaultValue: "Export %@",
                table: "Localizable", bundle: MobileL10n.bundle), format.title),
            systemImage: format.systemImage)
        }
        .disabled(store.isExportingData || selectedCategories.isEmpty)
        .accessibilityIdentifier("mobileDataExport.\(format.rawValue)")
      }
      if store.isExportingData {
        ProgressView(
          String(
            localized: "data_export.preparing", defaultValue: "Preparing export…",
            table: "Localizable", bundle: MobileL10n.bundle)
        )
        .font(LorvexDesign.Typography.tertiaryText)
      }
      if let exportItem {
        ShareLink(
          item: exportItem,
          preview: SharePreview("lorvex-export.\(exportItem.format.fileExtension)")
        ) {
          Label(
            String(
              format: String(
                localized: "data_export.share_format", defaultValue: "Share %@ Export",
                table: "Localizable", bundle: MobileL10n.bundle), exportItem.format.title),
            systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("mobileDataExport.share")
      }
    }
  }

  private func prepareExport(_ format: MobileDataExportFormat) async {
    guard let content = await store.exportData(format: format, categories: selectedCategories)
    else { return }
    exportItem = MobileDataExportTransferable(content: content, format: format)
  }
}
