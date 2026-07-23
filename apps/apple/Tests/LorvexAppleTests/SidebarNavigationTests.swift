import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

@Test
func mainNavigationItemsMatchMacCommandOrder() {
  #expect(
    SidebarSelection.mainNavigationItems.map(\.rawValue) == [
      "today",
      "calendar",
      "tasks",
      "lists",
      "habits",
      "reviews",
      "memory",
    ])
}

@Test
func sidebarGroupsAreTheCalmCoreSubsetOfMainNavigation() {
  // The sidebar shows the calm core plus Memory (the assistant-context surface);
  // the Lists catalog stays out of the fixed primary nav. Real user lists are
  // rendered as dynamic sidebar sections that scope task review.
  let grouped = SidebarSelection.sidebarGroups.flatMap(\.items)
  // No destination appears in two groups.
  #expect(Set(grouped).count == grouped.count)
  // Every sidebar destination is a real navigation item.
  #expect(Set(grouped).isSubset(of: Set(SidebarSelection.mainNavigationItems)))
  // The demoted fixed destination never reappears in the grouped sidebar.
  let demoted: Set<SidebarSelection> = [.lists]
  #expect(Set(grouped).isDisjoint(with: demoted))
  // The calm core plus Memory, in order.
  #expect(grouped == [.today, .calendar, .tasks, .habits, .reviews, .memory])
  #expect(SidebarSelection.mainNavigationItems.contains(.lists))
}

@Test
func macOSNavigationPresentationNamesCalendarPlainly() {
  #expect(SidebarSelection.calendar.title == "Calendar")
  #expect(SidebarSelection.calendar.macOSDisplayTitle == "Calendar")
  #expect(String(localized: SidebarSelection.calendar.macOSLocalizedTitle) == "Calendar")
  #expect(!String(localized: SidebarSelection.calendar.macOSLocalizedTitle).contains("Upcoming"))
  #expect(SidebarSelection.today.macOSDisplayTitle == "Today")
  #expect(SidebarSelection.tasks.macOSDisplayTitle == "Tasks")
}

@Test
func sidebarNavigationShortcutsCoverCommandNumberRow() {
  // ⌘1–6 walk the macOS navigation destinations top-to-bottom (Today · Calendar ·
  // Tasks · Habits · Reviews · Memory). The Lists catalog has no sidebar row (lists
  // are managed inline; the catalog is reached via ⌘K), so it carries no numeric
  // accelerator.
  #expect(SidebarSelection.today.navigationShortcut == "1")
  #expect(SidebarSelection.calendar.navigationShortcut == "2")
  #expect(SidebarSelection.tasks.navigationShortcut == "3")
  #expect(SidebarSelection.habits.navigationShortcut == "4")
  #expect(SidebarSelection.reviews.navigationShortcut == "5")
  #expect(SidebarSelection.memory.navigationShortcut == "6")
  #expect(SidebarSelection.lists.navigationShortcut == nil)
}

@Test
func sidebarRowsUseDistinctListSelectionTags() throws {
  let source = try sidebarViewSource()
  // The source list is a native `List(selection:)`, so keyboard navigation,
  // arrow-key traversal, type-select, and inactive-window desaturation come for
  // free; selection *is* navigation via the binding.
  #expect(source.contains("List(selection: sidebarSelection)"))
  #expect(source.contains(".listStyle(.sidebar)"))
  #expect(!source.contains("ScrollView {"))
  #expect(source.contains("planSection"))
  #expect(source.contains("listScopeSection"))
  #expect(source.contains("reflectSection"))
  #expect(source.contains("destinationRows(.plan)"))
  #expect(source.contains("destinationRows(.reflect)"))
  #expect(source.contains("Text(item.macOSLocalizedTitle)"))
  #expect(source.contains("ForEach(store.orderedLists) { list in"))
  // Each row carries a distinct `SidebarRowSelection` tag so the single
  // selection binding disambiguates destinations and list scopes.
  #expect(source.contains(".tag(SidebarRowSelection.destination(item))"))
  #expect(source.contains(".tag(SidebarRowSelection.listScope(list.id))"))
  #expect(source.contains("var selectedRow: SidebarRowSelection?"))
  #expect(source.contains("func isSelected(_ row: SidebarRowSelection) -> Bool"))
  #expect(source.contains("private func navigate(to row: SidebarRowSelection)"))
  #expect(source.contains("store.setTaskWorkspaceListScope(id)"))
  // Plain destination navigation goes through navigateToWorkspace, which resets
  // the list scope (to nil) and clears the task selection.
  #expect(source.contains("store.navigateToWorkspace(destination)"))
  #expect(source.contains("SidebarListRow("))
  #expect(source.contains("minHeight: SidebarMetrics.scopeRowHeight"))
  #expect(source.contains("detail: listScopeDetail(for: list)"))
  #expect(source.contains("func listScopeDetail(for list: LorvexList) -> String"))
  #expect(!source.contains(#""sidebar.lists.scope_detail""#))
  #expect(!source.contains("SidebarDestinationRow("))
  #expect(!source.contains("SidebarUtilityFooterLabel("))
  #expect(!source.contains("func sidebarRowButton<Row: View>("))
}

@Test
func sidebarOrdersTaskScopesBeforeReflectionSurfaces() throws {
  let source = try sidebarViewSource()
  // The `sidebarList` body references the section builders in reading order, so
  // the first textual occurrence of each name pins the on-screen section order.
  let plan = try #require(source.range(of: "planSection")?.lowerBound)
  let lists = try #require(source.range(of: "listScopeSection")?.lowerBound)
  let reflect = try #require(source.range(of: "reflectSection")?.lowerBound)
  #expect(plan < lists)
  #expect(lists < reflect)
}

private func sidebarViewSource() throws -> String {
  // The sidebar view is split across SidebarView.swift and its list-section
  // extension; assertions span both, so the "source" is their concatenation.
  let viewsDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "Sources/LorvexApple/Views")
  let main = try String(contentsOf: viewsDir.appending(path: "SidebarView.swift"), encoding: .utf8)
  let listSection = try String(contentsOf: viewsDir.appending(path: "SidebarListSection.swift"), encoding: .utf8)
  return main + "\n" + listSection
}
