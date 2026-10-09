import Foundation
import Testing

private let mobileSources = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .appending(path: "Sources/LorvexMobile")

private func mobileSource(_ name: String) throws -> String {
  try String(contentsOf: mobileSources.appending(path: "\(name).swift"), encoding: .utf8)
}

/// The names, without extension, of the `LorvexMobile` source files whose text
/// contains `marker`.
private func mobileSourceNames(containing marker: String) throws -> [String] {
  let names = try FileManager.default.contentsOfDirectory(atPath: mobileSources.path)
    .filter { $0.hasSuffix(".swift") }
    .map { String($0.dropLast(".swift".count)) }
  return try names.filter { try mobileSource($0).contains(marker) }.sorted()
}

/// A sheet inherits the readable-width content margin of the screen that
/// presents it. The margin is sized from that screen's width (136 pt on each
/// side in a 1032 pt window), but a sheet is a card with a width of its own, so
/// under the inherited margin a form in a sheet 580 pt wide keeps a column of
/// 308 pt with empty gutters on both sides. Every list and form a sheet shows
/// returns to the system margins at the sheet's root.
@Suite("Mobile sheet margins")
struct MobileSheetMarginsSourceTests {
  @Test("the helper resets both the content margin and the environment margin")
  func helperResetsBothHalvesOfTheReadableWidth() throws {
    let text = try mobileSource("MobileReadableWidth")
    let helper = try #require(text.range(of: "func mobileSystemContentMargins() -> some View {"))
    let body = text[helper.upperBound...].prefix(160)

    // The content margin reaches lists and forms; the environment value is
    // what a ScrollView-rooted screen reads through
    // `mobileReadableScrollMargins()`.
    #expect(body.contains("contentMargins(.horizontal, nil, for: .scrollContent)"))
    #expect(body.contains(".environment(\\.mobileReadableMargin, nil)"))
  }

  @Test("every editor sheet goes back to the system margins in the shared presentation")
  func editorSheetsResetTheInheritedMargin() throws {
    let text = try mobileSource("MobileEditorSheetPresentation")
    let modifier = try #require(text.range(of: "private struct MobileEditorSheetPresentation"))
    let body = text[modifier.upperBound...]

    let reset = try #require(body.range(of: ".mobileSystemContentMargins()"))
    let detents = try #require(body.range(of: ".presentationDetents("))
    #expect(reset.lowerBound < detents.lowerBound)
  }

  @Test("a sheet that sets its own detents resets the margin itself")
  func sheetsWithTheirOwnDetentsResetTheInheritedMargin() throws {
    // The app root presents the setup wizard and capture outside every
    // readable-width screen, so only the sheets presented from inside a screen
    // need the reset. A new file that sets detents has to decide which it is.
    let customSheets = try mobileSourceNames(containing: ".presentationDetents(")
      .filter { $0 != "MobileEditorSheetPresentation" && $0 != "LorvexMobileStoreRootView" }
    #expect(customSheets == ["MobileDestructiveConfirmationSheet"])
    for name in customSheets {
      #expect(
        try mobileSource(name).contains(".mobileSystemContentMargins()"),
        "\(name) sets its own detents without returning to the system margins")
    }

    // The data import preview takes the system's default sheet, so nothing in
    // its presentation names it; its list resets the margin where it is built.
    let preview = try mobileSource("MobileStoreDataImportSection")
    let sheet = try #require(preview.range(of: "private struct MobileImportPreviewSheet"))
    #expect(preview[sheet.upperBound...].contains(".mobileSystemContentMargins()"))
  }

  @Test("the list+detail panes keep returning to the system margins")
  func splitPanesResetTheInheritedMargin() throws {
    let text = try mobileSource("MobileAdaptiveListDetail")
    #expect(text.contains(".mobileSystemContentMargins()"))
  }
}

/// With the inherited margin gone, a form row in an iPad sheet is about 500 pt
/// wide. The system's month grid stops growing at about 390 pt but its view
/// keeps the width of the row, so the months before and after the shown one
/// appear in the margins on both sides. The day editor holds the grid to a width
/// below that limit and centers it in the row.
@Suite("Mobile month grid width")
struct MobileMonthGridWidthSourceTests {
  @Test("the day editor caps the month grid below the width where the system stops growing it")
  func dayEditorCapsTheMonthGrid() throws {
    let text = try mobileSource("MobileTaskFieldEditor")

    let call = try #require(text.range(of: "monthCalendar(has: has, date: date, calendar: calendar)\n"))
    let modifiers = text[call.upperBound...].prefix(120)
    #expect(modifiers.contains(".frame(maxWidth: Self.monthCalendarMaxWidth)"))
    #expect(modifiers.contains(".frame(maxWidth: .infinity)"))

    let declaration = try #require(text.range(of: "monthCalendarMaxWidth: CGFloat = "))
    let cap = try #require(Int(text[declaration.upperBound...].prefix { $0.isNumber }))
    #expect(cap <= 390, "a wider cap lets the neighbouring months show beside the grid")
  }
}
