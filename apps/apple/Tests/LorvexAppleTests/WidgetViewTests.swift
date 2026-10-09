import LorvexWidgetKitSupport
import LorvexWidgetViews
import SwiftUI
import Testing

@Test
func widgetViewMetricsMatchRenderFamilyRowBudgets() {
  // The rows are the tasks after the lead; small and the glance families only
  // say how many follow.
  #expect(LorvexWidgetViewMetrics.metrics(for: .accessoryInline).maxVisibleRows == 0)
  #expect(LorvexWidgetViewMetrics.metrics(for: .systemSmall).maxVisibleRows == 0)
  #expect(LorvexWidgetViewMetrics.metrics(for: .systemMedium).maxVisibleRows == 2)
  #expect(LorvexWidgetViewMetrics.metrics(for: .systemLarge).maxVisibleRows == 6)
  #expect(LorvexWidgetViewMetrics.metrics(for: .accessoryRectangular).maxVisibleRows == 1)
}

@Test
func widgetViewMetricsShowBriefingOnlyOnLarge() {
  // Only large has the vertical room for the briefing line above its rows; on
  // medium the lead block, two rows, and the foot line fill the 158pt canvas.
  #expect(!LorvexWidgetViewMetrics.metrics(for: .systemSmall).showsBriefing)
  #expect(!LorvexWidgetViewMetrics.metrics(for: .systemMedium).showsBriefing)
  #expect(LorvexWidgetViewMetrics.metrics(for: .systemLarge).showsBriefing)
  #expect(!LorvexWidgetViewMetrics.metrics(for: .accessoryInline).showsBriefing)
  #expect(!LorvexWidgetViewMetrics.metrics(for: .accessoryRectangular).showsBriefing)
}

@Test
func habitsWidgetGridHasTwoColumnsOnSmallAndFourOnMedium() {
  #expect(HabitsWidgetLayout.columnCount(family: .systemSmall) == 2)
  #expect(HabitsWidgetLayout.columnCount(family: .systemMedium) == 4)
  #expect(HabitsWidgetLayout.maxRows == 2)
}

@Test
func habitsWidgetTilesKeepHabitOrderWhenEveryHabitFits() {
  let habits = [gridHabit("a", done: true), gridHabit("b"), gridHabit("c", done: true)]
  #expect(HabitsWidgetLayout.tiles(habits, capacity: 4) == habits.map { .habit($0) })
  #expect(HabitsWidgetLayout.tiles(habits, capacity: 3) == habits.map { .habit($0) })
  #expect(HabitsWidgetLayout.tiles([], capacity: 4).isEmpty)
}

@Test
func habitsWidgetOverflowCountsTheRestAndShowsHabitsLeftFirst() {
  // Six habits in four tiles: three habits and a tile counting the other
  // three. The habits not yet done take the tiles first, each group in order.
  let habits = [
    gridHabit("a", done: true), gridHabit("b"), gridHabit("c", done: true),
    gridHabit("d"), gridHabit("e"), gridHabit("f"),
  ]
  #expect(
    HabitsWidgetLayout.tiles(habits, capacity: 4)
      == [.habit(habits[1]), .habit(habits[3]), .habit(habits[4]), .more(3)])
  // Every habit done: they keep their order behind the count.
  let done = habits.map { gridHabit($0.id, done: true) }
  #expect(
    HabitsWidgetLayout.tiles(done, capacity: 4)
      == [.habit(done[0]), .habit(done[1]), .habit(done[2]), .more(3)])
  // A single tile only counts.
  #expect(HabitsWidgetLayout.tiles(habits, capacity: 1) == [.more(6)])
}

private func gridHabit(_ id: String, done: Bool = false) -> WidgetSnapshot.HabitSummary {
  WidgetSnapshot.HabitSummary(id: id, name: id, icon: nil, completedToday: done ? 1 : 0, target: 1)
}

@Test
func todayWidgetLeadAndRowsDeepLinkToIndividualTasks() throws {
  let source = try appleSourceFile("Sources/LorvexWidgetViews/LorvexWidgetTaskRowView.swift")

  #expect(source.contains("link(lead.urlString)"))
  #expect(source.contains("Link(destination: url) { label }"))
}

@Test
func interactiveWidgetTaskActionsUseSharedHitTargetButton() throws {
  let taskRowSource = try appleSourceFile("Sources/LorvexWidgetViews/LorvexWidgetTaskRowView.swift")

  #expect(taskRowSource.contains("struct WidgetActionButton<Intent: AppIntent>: View"))
  // The hit target is a row high, growing with the row's text, and as wide as
  // it is high unless a caller sets its width.
  #expect(
    taskRowSource.contains(
      "@ScaledMetric(relativeTo: WidgetType.rowTextStyle) private var height = widgetRowHeight"))
  #expect(taskRowSource.contains(".frame(width: width ?? height, height: height, alignment: alignment)"))
  #expect(taskRowSource.contains(".contentShape(Rectangle())"))
  // A row's complete circle flows through the shared `WidgetActionButton` hit
  // target; the lead ring is its own full-diameter target (`Button(intent:)`
  // around `LorvexTaskRing` with a circular content shape), the only raw
  // intent button in the file.
  #expect(taskRowSource.contains("WidgetActionButton(\n        intent: WidgetCompleteTaskIntent"))
  #expect(
    taskRowSource.contains(
      "Button(intent: WidgetCompleteTaskIntent(taskID: lead.id, title: lead.title))"))
  #expect(taskRowSource.contains(".contentShape(Circle())"))
  #expect(taskRowSource.components(separatedBy: "Button(intent: Widget").count == 2)
}

@Test
func widgetStaleAgeLabelParticipatesInLayout() throws {
  // The Today widget's Home Screen families share one foot line
  // (`WidgetFootLine`), which is where their stale capsule lives.
  let footSource = try appleSourceFile("Sources/LorvexWidgetViews/LorvexWidgetTaskRowView.swift")
  let systemSource = try appleSourceFile("Sources/LorvexWidgetViews/LorvexWidgetSystemView.swift")
  let smallSource = try appleSourceFile("Sources/LorvexWidgetViews/LorvexWidgetSmallView.swift")
  let progressSource = try appleSourceFile("Sources/LorvexWidgetViews/LorvexProgressWidgetView.swift")
  let habitsSource = try appleSourceFile("Sources/LorvexWidgetViews/LorvexHabitsWidgetView.swift")

  #expect(footSource.contains("WidgetStaleAgeLabel(staleAgeLabel)"))
  #expect(systemSource.contains("WidgetFootLine(model: model"))
  #expect(smallSource.contains("WidgetFootLine(model: model"))
  #expect(progressSource.contains("WidgetStaleAgeLabel(staleAgeLabel)"))
  #expect(habitsSource.contains("WidgetStaleAgeLabel(staleAgeLabel)"))
}

@Test
func theFootLineFactsReadInTheSecondaryStyle() throws {
  // The facts count the tasks the widget does not list and the ones done, so
  // they are at least secondary text like the Habits widget's count; the
  // tertiary style is for marks a reader can skip (about 2.5:1 on a dark
  // widget). Only the span from the facts text to its modifiers is inspected,
  // so the tertiary dots elsewhere in the file are not matched.
  let source = try appleSourceFile("Sources/LorvexWidgetViews/LorvexWidgetTaskRowView.swift")
  let footStart = try #require(source.firstRange(of: "struct WidgetFootLine"))
  let afterFoot = source[footStart.upperBound...]
  let factsStart = try #require(afterFoot.firstRange(of: "Text(facts)"))
  let modifiers = afterFoot[factsStart.upperBound...].prefix(120)

  #expect(modifiers.contains(".foregroundStyle(.secondary)"))
  #expect(!modifiers.contains(".tertiary"))
}

@Test
func theUnavailableStatusLineReadsInTheSecondaryColor() throws {
  // The status line under an unavailable widget's message carries the
  // instruction ("Open Lorvex to refresh"), so it is at least secondary text
  // like the message above it; the tertiary style is for marks a reader can
  // skip (about 2.5:1 on a dark widget).
  let source = try appleSourceFile("Sources/LorvexWidgetViews/LorvexWidgetSystemView.swift")
  let statusStart = try #require(source.firstRange(of: "Text(model.statusText)"))
  let modifiers = source[statusStart.upperBound...].prefix(120)

  #expect(modifiers.contains(".foregroundStyle(Color.secondary)"))
  #expect(!modifiers.contains(".tertiary"))
}

@Test
@MainActor
func lorvexWidgetViewCanBeInstantiatedForAllFamilies() {
  let families: [WidgetFamilyKind] = [
    .systemSmall,
    .systemMedium,
    .systemLarge,
    .accessoryInline,
    .accessoryRectangular,
    .accessoryCircular,
  ]

  for family in families {
    let model = WidgetRenderModel(
      family: family,
      state: .content,
      headline: "Today",
      subheadline: "",
      statusText: "Updated now",
      completedCount: 1,
      lead: WidgetLeadRender(
        id: "task-1", title: "Write widget view", line: "Until 10:45 AM",
        shortLine: "Until 10:45 AM", progress: 0.6, isRunning: true, minutesLeft: 12,
        isOverdue: false, urlString: "lorvex://task/task-1"),
      taskRows: [WidgetTaskRenderRow(id: "task-2", title: "Next one", metadata: "11:00 AM")],
      upcomingCount: 1
    )
    _ = LorvexWidgetView(model: model)
  }
}

private func appleSourceFile(_ relativePath: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let url = root.appendingPathComponent(relativePath)
  return try String(contentsOf: url, encoding: .utf8)
}
