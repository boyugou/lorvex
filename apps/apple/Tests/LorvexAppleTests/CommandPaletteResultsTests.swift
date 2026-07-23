import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

private func makeTask(id: String, title: String, notes: String = "", tags: [String] = [])
  -> LorvexTask
{
  LorvexTask(
    id: id,
    title: title,
    notes: notes,
    priority: .p2,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: tags
  )
}

@Test
func emptyQueryListsAllNavigationAndActionsWithoutTasksOrCapture() {
  let groups = CommandPaletteResults.groups(
    query: "   ",
    tasks: [makeTask(id: "1", title: "Write report")]
  )
  let titles = groups.map(\.title)
  #expect(titles == ["Navigation", "Actions"])

  let nav = groups.first { $0.title == "Navigation" }?.results ?? []
  #expect(nav.count == SidebarSelection.mainNavigationItems.count)
  #expect(nav.first == .navigate(.today))

  let actions = groups.first { $0.title == "Actions" }?.results ?? []
  #expect(actions.count == AppCommand.allCases.count)
}

@Test
func nonEmptyQueryLeadsWithNewTaskAndMatchesTasks() {
  let tasks = [
    makeTask(id: "1", title: "Write report"),
    makeTask(id: "2", title: "Buy milk"),
    makeTask(id: "3", title: "Report to manager", tags: ["work"]),
  ]
  let groups = CommandPaletteResults.groups(query: "report", tasks: tasks)

  #expect(groups.first?.title == "New Task")
  #expect(groups.first?.results == [.createTask(title: "report")])

  let taskGroup = groups.first { $0.title == "Tasks" }?.results ?? []
  #expect(
    taskGroup == [
      .openTask(id: "1", title: "Write report", subtitle: "P2 · Open"),
      .openTask(id: "3", title: "Report to manager", subtitle: "P2 · Open"),
    ])
}

@Test
func taskMatchesAreCappedAtTheResultLimit() {
  let tasks = (0..<20).map { makeTask(id: "\($0)", title: "alpha task \($0)") }
  let groups = CommandPaletteResults.groups(query: "alpha", tasks: tasks)
  let taskGroup = groups.first { $0.title == "Tasks" }?.results ?? []
  #expect(taskGroup.count == CommandPaletteResults.taskResultLimit)
}

@Test
func navigationFiltersByDestinationTitle() {
  let groups = CommandPaletteResults.groups(query: "calendar", tasks: [])
  let nav = groups.first { $0.title == "Navigation" }?.results ?? []
  #expect(nav == [.navigate(.calendar)])
  // No task matches and no task group when the pool is empty.
  #expect(!groups.contains { $0.title == "Tasks" })
}

@Test
func flatResultsConcatenatesEveryGroupInOrder() {
  let groups = CommandPaletteResults.groups(
    query: "report",
    tasks: [makeTask(id: "1", title: "Write report")]
  )
  let flat = CommandPaletteResults.flatResults(groups)
  #expect(flat.first == .createTask(title: "report"))
  #expect(flat.contains(.openTask(id: "1", title: "Write report", subtitle: "P2 · Open")))
  #expect(flat.count == groups.reduce(0) { $0 + $1.results.count })
}

@Test
func taskSubtitleSummarizesPriorityStatusAndDue() {
  let undated = makeTask(id: "1", title: "Write report")
  #expect(CommandPaletteResults.taskSubtitle(undated) == "P2 · Open")

  var dated = makeTask(id: "2", title: "Ship")
  dated.dueDate = Date(timeIntervalSince1970: 1_700_000_000)
  let subtitle = CommandPaletteResults.taskSubtitle(dated)
  #expect(subtitle.hasPrefix("P2 · Open · "))
}

@Test
func matchRangesFindAllCaseInsensitiveOccurrences() {
  let text = "Report on the report"
  let ranges = CommandPaletteResults.matchRanges(of: "report", in: text)
  #expect(ranges.count == 2)
  let matched = ranges.map { String(text[$0]) }
  #expect(matched == ["Report", "report"])
}

@Test
func matchRangesEmptyForBlankQueryOrNoMatch() {
  #expect(CommandPaletteResults.matchRanges(of: "   ", in: "Write report").isEmpty)
  #expect(CommandPaletteResults.matchRanges(of: "xyz", in: "Write report").isEmpty)
}
