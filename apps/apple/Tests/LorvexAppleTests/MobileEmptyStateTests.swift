import Foundation
import Testing

@testable import LorvexMobile

private let mobileSourcesRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .appending(path: "Sources/LorvexMobile")

private func mobileSource(_ file: String) throws -> String {
  try String(contentsOf: mobileSourcesRoot.appending(path: file), encoding: .utf8)
}

@Suite("Mobile empty states")
struct MobileEmptyStateTests {
  @MainActor
  @Test("the search variant quotes the trimmed query and carries no action")
  func searchVariantQuotesQuery() {
    let state = MobileEmptyState.search(text: "  groceries ")
    #expect(state.icon == "magnifyingglass")
    #expect(state.title.contains("“groceries”"))
    #expect(state.message != nil)
    #expect(state.actionTitle == nil)
  }

  @Test("no List row renders ContentUnavailableView.search; only the calendar overlay does")
  func searchNoMatchRowsAreBounded() throws {
    let files = try FileManager.default.contentsOfDirectory(atPath: mobileSourcesRoot.path)
      .filter { $0.hasSuffix(".swift") }
    var offenders: [String] = []
    for file in files {
      if try mobileSource(file).contains("ContentUnavailableView.search(text:") {
        offenders.append(file)
      }
    }
    // The day grid floats its no-results state over the grid, not in a List row.
    #expect(offenders == ["MobileCalendarDayView.swift"])
  }

  @Test("catalog empty states point at the toolbar ＋ instead of repeating it")
  func catalogEmptyStatesDoNotRepeatToolbarAdd() throws {
    for file in [
      "MobileStoreTasksHomeView.swift",
      "MobileStoreHabitsView.swift", "MobileStoreMemoryView.swift",
    ] {
      let source = try mobileSource(file)
      #expect(!source.contains("ContentUnavailableView("), "\(file)")
      #expect(!source.contains("actionTitle:"), "\(file)")
      #expect(source.contains("MobileEmptyState"), "\(file)")
    }
  }
}

@Suite("Mobile settings sections")
struct MobileSettingsSectionsTests {
  /// Bodies of every `} footer: {` closure in `source`, up to the closure's
  /// closing brace at the section's indentation.
  private func footerBodies(in source: String) -> [String] {
    source.components(separatedBy: "} footer: {").dropFirst().map { chunk in
      chunk.components(separatedBy: "\n    }").first ?? chunk
    }
  }

  @Test("explanatory copy is a section footer, not a secondary-text row in the card")
  func descriptionsLiveInFooters() throws {
    let expectations: [(file: String, marker: String)] = [
      ("MobileSettingsSections.swift", "\"settings.badge.footer\""),
      ("MobileSettingsSections.swift", "\"settings.show_task_notes.footer\""),
      ("MobileSettingsSections.swift", "Text(modeDetail)"),
      ("MobileSettingsSections.swift", "\"settings.sync.delete_cloud.footer\""),
      ("MobileSettingsLanguageSection.swift", "\"settings.language.reopen_note\""),
      ("MobileStoreSettingsCalendarSection.swift", "\"settings.calendar.access.scope_detail\""),
      ("MobileStoreDataExportSection.swift", "\"data_export.description\""),
      ("MobileStoreDataImportSection.swift", "\"data_import.description\""),
      ("MobileStoreLocalDataResetSection.swift", "\"settings.reset_device.footer\""),
    ]
    for expectation in expectations {
      let footers = footerBodies(in: try mobileSource(expectation.file))
      #expect(
        footers.contains { $0.contains(expectation.marker) },
        "\(expectation.file) should render \(expectation.marker) in a footer")
    }
  }

  @Test("the Language group has no header repeating its only row")
  func languageGroupHasNoHeader() throws {
    let source = try mobileSource("MobileSettingsLanguageSection.swift")
    #expect(!source.contains("\"settings.section.language\""))
    #expect(!source.contains("} header: {"))
  }
}
