import Foundation
import LorvexCore
import SwiftUI
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

  @Test("no List row renders ContentUnavailableView.search; only the calendar overlays do")
  func searchNoMatchRowsAreBounded() throws {
    let files = try FileManager.default.contentsOfDirectory(atPath: mobileSourcesRoot.path)
      .filter { $0.hasSuffix(".swift") }
    var offenders: [String] = []
    for file in files {
      if try mobileSource(file).contains("ContentUnavailableView.search(text:") {
        offenders.append(file)
      }
    }
    // The time grid and the month grid float their no-results state over the
    // grid, not in a List row.
    #expect(offenders.sorted() == ["MobileCalendarDayView.swift", "MobileCalendarMonthView.swift"])
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

  @MainActor
  @Test("a message that points at the toolbar ＋ draws that ＋, and only it, in the accent color")
  func toolbarAddMessageAccentsOnlyThePlus() {
    let message = "Tap ＋ to start a habit you want to build."
    let accented = MobileEmptyState.accentingAddSymbol(in: message)
    #expect(String(accented.characters) == message)
    let runs = accented.runs.filter { $0.foregroundColor != nil }
    #expect(runs.count == 1)
    #expect(runs.first.map { String(accented[$0.range].characters) } == "＋")
    #expect(runs.first?.foregroundColor == LorvexDesign.Palette.accent)
    #expect(MobileEmptyState.accentingAddSymbol(in: "No plus here.").runs.allSatisfy { $0.foregroundColor == nil })
  }

  @MainActor
  @Test("every shipped translation of the two toolbar-pointing messages holds exactly one ＋ to accent")
  func toolbarPointingMessagesHoldOnePlusInEveryLanguage() throws {
    let keys = ["habits.empty.no_active.message", "memory.empty.message"]
    for language in AppLanguage.selectable.map(\.rawValue) {
      let bundle = try #require(
        MobileL10n.bundle.url(forResource: language, withExtension: "lproj")
          .flatMap { Bundle(url: $0) },
        "the Mobile bundle has no \(language).lproj")
      for key in keys {
        let message = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        #expect(message != key, "\(language) has no \(key)")
        let accented = MobileEmptyState.accentingAddSymbol(in: message)
        #expect(String(accented.characters) == message, "\(language) \(key)")
        let runs = accented.runs.filter { $0.foregroundColor != nil }
        #expect(runs.count == 1, "\(language) \(key)")
        #expect(
          runs.first.map { String(accented[$0.range].characters) } == "＋", "\(language) \(key)")
      }
    }
  }

  @Test("the Habits and Memory rows mark their ＋ as the toolbar's; the Tasks home row, whose ＋ is the tab bar's, does not")
  func onlyToolbarPointingRowsAreMarked() throws {
    for file in [
      "MobileStoreHabitSection.swift", "MobileStoreHabitsView.swift", "MobileStoreMemoryView.swift",
    ] {
      #expect(try mobileSource(file).contains("pointsAtToolbarAdd: true"), "\(file)")
    }
    #expect(!(try mobileSource("MobileStoreTasksHomeView.swift")).contains("pointsAtToolbarAdd"))
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
