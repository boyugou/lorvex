import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

private func makeTask(
  id: String, title: String, notes: String = "", aiNotes: String? = nil, tags: [String] = []
) -> LorvexTask {
  LorvexTask(
    id: id,
    title: title,
    notes: notes,
    aiNotes: aiNotes,
    priority: .p2,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: tags
  )
}

private func makeList(id: String, name: String) -> LorvexList {
  LorvexList(
    id: id, name: name, color: "#0A84FF", icon: "folder", description: nil,
    openCount: 0, totalCount: 0, updatedAt: "2026-09-29T00:00:00Z")
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
      .openTask(id: "1", title: "Write report", subtitle: nil),
      .openTask(id: "3", title: "Report to manager", subtitle: nil),
    ])
}

@Test
func aTaskWhoseOnlyMatchIsItsAssistantContextIsListed() {
  let tasks = [
    makeTask(id: "1", title: "Plan trip", aiNotes: "Prefers morning flights"),
    makeTask(id: "2", title: "Buy milk"),
  ]
  let groups = CommandPaletteResults.groups(query: "flights", tasks: tasks)
  let taskGroup = groups.first { $0.title == "Tasks" }?.results ?? []
  #expect(taskGroup == [.openTask(id: "1", title: "Plan trip", subtitle: nil)])
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
  #expect(flat.contains(.openTask(id: "1", title: "Write report", subtitle: nil)))
  #expect(flat.count == groups.reduce(0) { $0 + $1.results.count })
}

@Test
func taskSubtitleNamesTheListDueDayAndAnUnusualStatus() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
  let now = Date(timeIntervalSince1970: 1_790_000_000)
  let names = ["l1": "Apple Native"]

  let plain = makeTask(id: "1", title: "Write report")
  #expect(CommandPaletteResults.taskSubtitle(plain, listNames: names, now: now, timeZone: calendar.timeZone) == nil)

  var filed = makeTask(id: "2", title: "Ship")
  filed.listID = "l1"
  filed.dueDate = now
  #expect(
    CommandPaletteResults.taskSubtitle(filed, listNames: names, now: now, timeZone: calendar.timeZone)
      == "Apple Native · Due today")

  filed.status = .inProgress
  #expect(
    CommandPaletteResults.taskSubtitle(filed, listNames: names, now: now, timeZone: calendar.timeZone)
      == "Apple Native · Due today · In Progress")

  // A finished task says so instead of when it was due.
  filed.status = .completed
  #expect(
    CommandPaletteResults.taskSubtitle(filed, listNames: names, now: now, timeZone: calendar.timeZone)
      == "Apple Native · Completed")
}

@Test
func archivedListsNameTheirTasksButAreNotOfferedAsPlaces() {
  var archived = makeList(id: "old", name: "Old Projects")
  archived.archivedAt = "2026-09-01T00:00:00Z"
  var task = makeTask(id: "1", title: "Old report")
  task.listID = "old"
  let groups = CommandPaletteResults.groups(query: "old", tasks: [task], lists: [archived])
  #expect(!groups.contains { $0.title == "Lists" })
  let taskGroup = groups.first { $0.title == "Tasks" }?.results ?? []
  #expect(taskGroup == [.openTask(id: "1", title: "Old report", subtitle: "Old Projects")])
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

/// Return runs the first row, so a query that starts a destination's name is a
/// jump there rather than a task titled with it.
@Test
func queryThatBeginsADestinationLeadsWithTheJump() {
  let groups = CommandPaletteResults.groups(
    query: "hab", tasks: [makeTask(id: "1", title: "Habit tracker idea")])
  #expect(Array(groups.map(\.title).prefix(2)) == ["Navigation", "New Task"])
  #expect(CommandPaletteResults.flatResults(groups).first == .navigate(.habits))
}

@Test
func listsMatchByNameAndLeadWhenTheQueryBeginsOneOfItsWords() {
  let lists = [makeList(id: "l1", name: "Groceries"), makeList(id: "l2", name: "Apple Native")]
  let groups = CommandPaletteResults.groups(query: "nat", tasks: [], lists: lists)
  #expect(groups.first?.title == "Lists")
  #expect(
    groups.first?.results == [
      .openList(id: "l2", name: "Apple Native", icon: "folder", colorHex: "#0A84FF")
    ])
  #expect(groups.dropFirst().first?.title == "New Task")
}

@Test
func queryInsideANameLeadsWithCapture() {
  let groups = CommandPaletteResults.groups(
    query: "ple", tasks: [], lists: [makeList(id: "l1", name: "Apple Native")])
  #expect(groups.first?.title == "New Task")
  #expect(groups.contains { $0.title == "Lists" })
}

@Test
func listsAppearOnlyForATypedQuery() {
  let groups = CommandPaletteResults.groups(
    query: "  ", tasks: [], lists: [makeList(id: "l1", name: "Apple Native")])
  #expect(!groups.contains { $0.title == "Lists" })
}

@Test
func beginsNameOrWordIgnoresCaseAndDiacritics() {
  #expect(CommandPaletteResults.beginsNameOrWord("Habits", query: "HAB"))
  #expect(CommandPaletteResults.beginsNameOrWord("Apple Native", query: "nat"))
  #expect(CommandPaletteResults.beginsNameOrWord("Café Notes", query: "cafe"))
  #expect(!CommandPaletteResults.beginsNameOrWord("Apple Native", query: "tive"))
}

@Test
func finishedTaskRowsLeadWithACheck() {
  var done = makeTask(id: "1", title: "Report draft")
  done.status = .completed
  let open = makeTask(id: "2", title: "Report review")
  let groups = CommandPaletteResults.groups(query: "report", tasks: [done, open])
  let tasks = groups.first { $0.title == "Tasks" }?.results ?? []
  #expect(tasks.map(\.systemImage) == ["checkmark.circle", "circle"])
}
