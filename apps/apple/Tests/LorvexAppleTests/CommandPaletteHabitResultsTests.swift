import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

private func paletteHabit(
  id: String, name: String, cue: String? = nil, icon: String? = "figure.run"
) -> LorvexHabit {
  LorvexHabit(
    id: id, name: name, icon: icon, color: "#34C759", cue: cue, frequencyType: "daily",
    targetCount: 1, completionsToday: 0, totalCompletions: 0, completionRate30d: 0,
    archived: false)
}

private func habitIDs(_ groups: [CommandPaletteGroup]) -> [String] {
  groups.first { $0.title == "Habits" }?.results.compactMap {
    if case .openHabit(let id, _, _, _, _) = $0 { id } else { nil }
  } ?? []
}

@Test("A typed query lists habits whose name or cue it finds, and a habit never leads")
func paletteHabitsMatchNameOrCueAndNeverLead() {
  let habits = [
    paletteHabit(id: "run", name: "Morning run", cue: "After coffee"),
    paletteHabit(id: "read", name: "Read", cue: "Before bed"),
    paletteHabit(id: "stretch", name: "Stretch", cue: "After the run"),
  ]

  let byName = CommandPaletteResults.groups(query: "morning", tasks: [], habits: habits)
  let byCue = CommandPaletteResults.groups(query: "after", tasks: [], habits: habits)

  #expect(byName.map(\.title) == ["New Task", "Habits"])
  #expect(habitIDs(byName) == ["run"])
  #expect(habitIDs(byCue) == ["run", "stretch"])
}

@Test("A palette with nothing typed lists no habits")
func paletteWithNothingTypedListsNoHabits() {
  let groups = CommandPaletteResults.groups(
    query: "", tasks: [], habits: [paletteHabit(id: "run", name: "Run")])

  #expect(!groups.contains { $0.title == "Habits" })
}

@Test("The palette lists at most three habits, in the habits' own order")
func paletteHabitsAreCapped() {
  let habits = (1...5).map { paletteHabit(id: "h\($0)", name: "Walk \($0)") }

  let groups = CommandPaletteResults.groups(query: "walk", tasks: [], habits: habits)

  #expect(CommandPaletteResults.habitResultLimit == 3)
  #expect(habitIDs(groups) == ["h1", "h2", "h3"])
}

@Test("Habits follow the tasks and come before the events")
func paletteHabitsSitBetweenTasksAndEvents() {
  let task = LorvexTask(
    id: "t1", title: "Walk the dog", notes: "", aiNotes: nil, priority: .p2, status: .open,
    dueDate: nil, estimatedMinutes: nil, tags: [])
  let event = CalendarTimelineEvent(
    id: "e1", title: "Walk with Sam", source: "test", editable: true, startDate: "2026-06-12",
    startTime: "09:00", endDate: "2026-06-12", endTime: nil, allDay: false, location: nil,
    color: nil, eventType: "event", timezone: nil, isRecurring: false)

  let groups = CommandPaletteResults.groups(
    query: "walk", tasks: [task], habits: [paletteHabit(id: "walk", name: "Walk")],
    events: [event], todayKey: "2026-06-10")

  #expect(groups.map(\.title) == ["New Task", "Tasks", "Habits", "Events"])
}

@Test("A habit result is titled by the habit, shows its cue, and wears the repeat symbol")
func paletteHabitResultIsTitledByTheHabit() {
  let groups = CommandPaletteResults.groups(
    query: "run", tasks: [],
    habits: [paletteHabit(id: "run", name: "Morning run", cue: "After coffee")])
  let result = CommandPaletteResults.flatResults(groups).last

  #expect(
    result
      == .openHabit(
        id: "run", name: "Morning run", icon: "figure.run", colorHex: "#34C759",
        cue: "After coffee"))
  #expect(result?.id == "habit.run")
  #expect(result?.localizedTitle == "Morning run")
  #expect(result?.systemImage == "repeat.circle")
  #expect(groups.last?.localizedTitle == String(localized: SidebarSelection.habits.macOSLocalizedTitle))
}

@Test("A habit with an empty cue shows no second line")
func paletteHabitWithAnEmptyCueHasNoSecondLine() {
  let groups = CommandPaletteResults.groups(
    query: "run", tasks: [], habits: [paletteHabit(id: "run", name: "Run", cue: "")])

  #expect(
    CommandPaletteResults.flatResults(groups).last
      == .openHabit(id: "run", name: "Run", icon: "figure.run", colorHex: "#34C759", cue: nil))
}

@Test("Choosing a habit opens it in the Habits workspace through the shared route")
func paletteHabitOpensThroughTheHabitRoute() throws {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources/LorvexApple/Views/CommandPaletteView.swift")
  let text = try String(contentsOf: url, encoding: .utf8)

  let open = try #require(text.range(of: "case .openHabit(let id, _, _, _, _):"))
  let call = try #require(text.range(of: "store.applyRouteNavigation(.habit(id))"))
  #expect(open.upperBound <= call.lowerBound)
  #expect(text.distance(from: open.upperBound, to: call.lowerBound) < 40)
}

@MainActor
@Test("The habit route selects the habit in the Habits workspace")
func habitRouteSelectsTheHabitInTheHabitsWorkspace() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.selection = .today

  store.applyRouteNavigation(.habit("habit-1"))

  #expect(store.selection == .habits)
  #expect(store.selectedHabitID == "habit-1")
}
