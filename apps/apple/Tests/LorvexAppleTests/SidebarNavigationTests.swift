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
      "reviews",
      "habits",
      "memory",
      "lists",
    ])
}

@Test
func sidebarGroupsAreTheCalmCoreSubsetOfMainNavigation() {
  // The sidebar's groups show the day, the week, every task, the review, and
  // habits. Memory lives in the pinned footer instead and the Lists catalog has
  // no row; real user lists are rendered as dynamic sidebar sections that scope
  // task review.
  let grouped = SidebarSelection.sidebarGroups.flatMap(\.items)
  // No destination appears in two groups.
  #expect(Set(grouped).count == grouped.count)
  // Every sidebar destination is a real navigation item.
  #expect(Set(grouped).isSubset(of: Set(SidebarSelection.mainNavigationItems)))
  // The demoted fixed destination never reappears in the grouped sidebar.
  let demoted: Set<SidebarSelection> = [.lists, .memory]
  #expect(Set(grouped).isDisjoint(with: demoted))
  #expect(grouped == [.today, .calendar, .tasks, .reviews, .habits])
  #expect(SidebarSelection.mainNavigationItems.contains(.lists))
  #expect(SidebarSelection.mainNavigationItems.contains(.memory))
}

@Test
func macOSNavigationNamesDestinationsByWhatTheUserDoes() {
  // The sidebar says Plan, All Tasks, and Review; the shared English names stay
  // as search aliases for the command palette.
  #expect(String(localized: SidebarSelection.calendar.macOSLocalizedTitle) == "Calendar")
  #expect(String(localized: SidebarSelection.tasks.macOSLocalizedTitle) == "All Tasks")
  #expect(String(localized: SidebarSelection.reviews.macOSLocalizedTitle) == "Review")
  #expect(SidebarSelection.calendar.macOSDisplayTitle == "Calendar")
  #expect(SidebarSelection.today.macOSDisplayTitle == "Today")
  #expect(SidebarSelection.tasks.macOSDisplayTitle == "Tasks")
}

@Test
func sidebarNavigationShortcutsCoverCommandNumberRow() {
  // ⌘1–6 walk the sidebar top to bottom: Today, Plan, All Tasks, Review, and
  // Habits in the groups, then Memory in the pinned footer. The Lists catalog
  // has no sidebar row (lists are managed inline; the catalog is reached via
  // ⌘K), so it carries no numeric accelerator.
  #expect(SidebarSelection.today.navigationShortcut == "1")
  #expect(SidebarSelection.calendar.navigationShortcut == "2")
  #expect(SidebarSelection.tasks.navigationShortcut == "3")
  #expect(SidebarSelection.reviews.navigationShortcut == "4")
  #expect(SidebarSelection.habits.navigationShortcut == "5")
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
  #expect(!source.contains("reflectSection"))
  #expect(source.contains("destinationRows(.plan)"))
  #expect(source.contains("Text(item.macOSLocalizedTitle)"))
  #expect(source.contains("ForEach(store.orderedLists) { list in"))
  // Each row carries a distinct `SidebarRowSelection` tag so the single
  // selection binding disambiguates destinations and list scopes.
  #expect(source.contains(".tag(SidebarRowSelection.destination(item))"))
  #expect(source.contains(".tag(SidebarRowSelection.listScope(list.id))"))
  #expect(source.contains("var selectedRow: SidebarRowSelection?"))
  #expect(source.contains("func isSelected(_ row: SidebarRowSelection) -> Bool"))
  #expect(source.contains("private func navigate(to row: SidebarRowSelection)"))
  // A list row opens its scope through the store route the Lists catalog and
  // the command palette share.
  #expect(source.contains("store.openTaskListScope(id)"))
  // Plain destination navigation goes through navigateToWorkspace, which resets
  // the list scope (to nil) and clears the task selection.
  #expect(source.contains("store.navigateToWorkspace(destination)"))
  // Every row is one line: a list row carries its open count in the badge
  // and nothing beneath its name.
  #expect(source.contains("count: list.openCount > 0 ? list.openCount : nil,"))
  #expect(!source.contains("listScopeDetail"))
  #expect(!source.contains("scopeRowHeight"))
  #expect(!source.contains(#""sidebar.lists.scope_detail""#))
  #expect(!source.contains("SidebarDestinationRow("))
  #expect(!source.contains("SidebarUtilityFooterLabel("))
  #expect(!source.contains("func sidebarRowButton<Row: View>("))
}

@Test
func sidebarPinsMemoryAboveSettingsInTheFooter() throws {
  let source = try sidebarViewSource()
  // Memory is a footer row that shows its own selection while open, pinned
  // above Settings so a long run of lists never scrolls it away.
  let memory = try #require(source.range(of: "store.navigateToWorkspace(.memory)")?.lowerBound)
  let settings = try #require(source.range(of: "SettingsLink {")?.lowerBound)
  #expect(memory < settings)
  #expect(source.contains("SidebarFooterRow(isSelected: store.selection == .memory)"))
  #expect(source.contains(#".accessibilityIdentifier("sidebar.memory")"#))
}

@Test
func navigateMenuSetsTheUnnumberedCatalogApart() {
  // The numbered destinations run in sidebar order; the Lists catalog, with no
  // number, sits below them.
  let numbered = SidebarSelection.mainNavigationItems.filter { $0.navigationShortcut != nil }
  #expect(numbered == [.today, .calendar, .tasks, .reviews, .habits, .memory])
  #expect(numbered.compactMap(\.navigationShortcut) == ["1", "2", "3", "4", "5", "6"])
  #expect(SidebarSelection.mainNavigationItems.last == .lists)
}

@Test
func sidebarOrdersDestinationsBeforeTaskScopes() throws {
  let source = try sidebarViewSource()
  // The `sidebarList` body references the section builders in reading order, so
  // the first textual occurrence of each name pins the on-screen section order.
  let plan = try #require(source.range(of: "planSection")?.lowerBound)
  let lists = try #require(source.range(of: "listScopeSection")?.lowerBound)
  #expect(plan < lists)
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
