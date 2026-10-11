import Foundation
import LorvexCore
import Testing

private func source(_ path: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

/// A fold header button, found by its accessibility identifier, and the
/// expression its open state is read from.
private struct FoldSite: Sendable, CustomTestStringConvertible {
  let file: String
  let identifier: String
  let isExpanded: String
  var testDescription: String { identifier }
}

private let foldSites = [
  FoldSite(
    file: "Sources/LorvexApple/Views/TodayColumn.swift", identifier: "today.done.toggle",
    isExpanded: "!store.isTodayDoneCollapsed"),
  FoldSite(
    file: "Sources/LorvexApple/Views/TodayScheduleSection.swift",
    identifier: "today.schedule.earlier.toggle", isExpanded: "showsPast"),
  FoldSite(
    file: "Sources/LorvexApple/Views/EventKitCalendarFilterPicker.swift",
    identifier: "settings.calendar.filterToggle", isExpanded: "expanded"),
  FoldSite(
    file: "Sources/LorvexMobile/MobileTodayPage.swift", identifier: "today.done.toggle",
    isExpanded: "!doneCollapsed"),
  FoldSite(
    file: "Sources/LorvexMobile/MobileTodayScheduleTimelineSection.swift",
    identifier: "today.schedule.earlier.toggle", isExpanded: "showsPast"),
  FoldSite(
    file: "Sources/LorvexMobile/MobileHabitArchivedSection.swift",
    identifier: "mobileHabits.archived.toggle", isExpanded: "!isCollapsed"),
  FoldSite(
    file: "Sources/LorvexMobile/MobileListArchivedSection.swift",
    identifier: "mobileTasks.archived.toggle", isExpanded: "!isCollapsed"),
]

@Test("The fold state words come from the LorvexCore catalog, not from their keys")
func foldStateWordsResolveFromTheCatalog() {
  let open = LorvexFoldState.accessibilityValue(isExpanded: true)
  let folded = LorvexFoldState.accessibilityValue(isExpanded: false)

  #expect(open != folded)
  #expect(!open.isEmpty && !folded.isEmpty)
  #expect(!open.hasPrefix("fold.state") && !folded.hasPrefix("fold.state"))
}

@Test("A fold header button hands VoiceOver its open state", arguments: foldSites)
private func foldHeaderCarriesItsState(_ site: FoldSite) throws {
  let text = try source(site.file)
  let anchor = try #require(text.range(of: "accessibilityIdentifier(\"\(site.identifier)\")"))
  let before = text[..<anchor.lowerBound].suffix(220)
  let after = text[anchor.upperBound...].prefix(120)

  #expect((before + after).contains(".lorvexFoldState(isExpanded: \(site.isExpanded))"))
}

@Test("The settings and task-lane fold headers use the shared state modifier")
func sharedFoldHeadersUseTheModifier() throws {
  for file in [
    "Sources/LorvexApple/Views/SettingsChrome.swift",
    "Sources/LorvexApple/Views/WorkspaceTaskViews.swift",
  ] {
    let text = try source(file)
    #expect(text.contains(".lorvexFoldState(isExpanded: isExpanded)"), "\(file)")
    #expect(!text.contains("common.expanded") && !text.contains("common.collapsed"), "\(file)")
  }
}
