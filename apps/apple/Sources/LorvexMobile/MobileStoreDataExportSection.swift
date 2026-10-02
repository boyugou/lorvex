import LorvexCore
import SwiftUI

/// Settings › Data Export: the full-table export of the chosen categories as
/// JSON, CSV, or ZIP, then the calendar export as an `.ics` file. Each export
/// is two steps, because a share link needs its file up front: the export
/// button prepares the file, then a share link offers it.
struct MobileStoreDataExportSection: View {
  @Bindable var store: MobileStore
  @State private var exportItem: MobileDataExportTransferable?
  @State private var calendarExportItem: MobileCalendarICSTransferable?
  @State private var selectedCategories: Set<LorvexDataExportCategory> = Set(
    LorvexDataExportCategory.allCases)

  private static var categoriesTitle: String {
    String(
      localized: "data_export.categories", defaultValue: "Categories", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// "All", "None", or how many of the categories are chosen ("7 of 10").
  private var selectionSummary: String {
    let total = LorvexDataExportCategory.allCases.count
    switch selectedCategories.count {
    case total:
      return String(
        localized: "data_export.categories.all", defaultValue: "All", table: "Localizable",
        bundle: MobileL10n.bundle)
    case 0:
      return String(
        localized: "data_export.categories.none", defaultValue: "None", table: "Localizable",
        bundle: MobileL10n.bundle)
    case let count:
      return String(
        localized: "data_export.categories.some", defaultValue: "\(count) of \(total)",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  var body: some View {
    Section {
      NavigationLink {
        Form {
          ExportCategoryPicker(
            selection: $selectedCategories,
            idPrefix: "mobileDataExport",
            selectAllLabel: String(
              localized: "data_export.select_all", defaultValue: "Select All", table: "Localizable",
              bundle: MobileL10n.bundle),
            selectNoneLabel: String(
              localized: "data_export.select_none", defaultValue: "Select None",
              table: "Localizable", bundle: MobileL10n.bundle))
        }
        .navigationTitle(Self.categoriesTitle)
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
      } label: {
        LabeledContent {
          Text(selectionSummary)
        } label: {
          Label(Self.categoriesTitle, systemImage: "square.stack.3d.up")
        }
      }
      .accessibilityIdentifier("mobileDataExport.categories")

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
        .mobileAccentRowStyle()
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
    } header: {
      Text(
        String(
          localized: "settings.section.data_export", defaultValue: "Data Export",
          table: "Localizable", bundle: MobileL10n.bundle))
    } footer: {
      Text(
        String(
          localized: "data_export.description",
          defaultValue:
            "Full-table export of the categories you select, as JSON, CSV, or a ZIP package.",
          table: "Localizable", bundle: MobileL10n.bundle))
    }

    Section {
      Button {
        Task {
          if let ics = await store.exportCalendarICS() {
            calendarExportItem = MobileCalendarICSTransferable(content: ics)
          }
        }
      } label: {
        Label(
          String(
            localized: "settings.calendar_export.action", defaultValue: "Export Calendar",
            table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "calendar")
      }
      .mobileAccentRowStyle()
      .disabled(store.isExportingCalendarICS)
      .accessibilityIdentifier("mobileDataExport.calendar")
      if let calendarExportItem {
        ShareLink(
          item: calendarExportItem,
          preview: SharePreview("lorvex-calendar.ics", image: Image(systemName: "calendar"))
        ) {
          Label(
            String(
              localized: "settings.calendar_export.share", defaultValue: "Share Calendar",
              table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("mobileDataExport.calendar.share")
      }
    } footer: {
      Text(
        String(
          localized: "settings.calendar_export.footer",
          defaultValue: "Your events from today through the next 30 days, as an .ics file other calendar apps can import.",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
  }

  private func prepareExport(_ format: MobileDataExportFormat) async {
    guard let content = await store.exportData(format: format, categories: selectedCategories)
    else { return }
    exportItem = MobileDataExportTransferable(content: content, format: format)
  }
}
