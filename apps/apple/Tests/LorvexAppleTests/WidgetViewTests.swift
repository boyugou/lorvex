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
  #expect(LorvexWidgetViewMetrics.metrics(for: .systemLarge).maxVisibleRows == 5)
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
func habitsWidgetLayoutReportsHiddenHabitOverflow() {
  // Three rows per column at the default text size: small shows 3, medium 6.
  #expect(HabitsWidgetLayout.shownCount(total: 8, family: .systemSmall) == 3)
  #expect(HabitsWidgetLayout.shownCount(total: 8, family: .systemMedium) == 6)
  #expect(HabitsWidgetLayout.hiddenHabitCount(total: 8, family: .systemSmall) == 5)
  #expect(HabitsWidgetLayout.hiddenHabitCount(total: 8, family: .systemMedium) == 2)
  #expect(HabitsWidgetLayout.hiddenHabitCount(total: 3, family: .systemSmall) == 0)
  // A larger text size fits fewer rows, and the footer counts the rest.
  #expect(HabitsWidgetLayout.shownCount(total: 8, family: .systemMedium, rows: 2) == 4)
  #expect(HabitsWidgetLayout.hiddenHabitCount(total: 8, family: .systemMedium, rows: 1) == 6)
  #expect(HabitsWidgetLayout.shownCount(total: 2, family: .systemMedium, rows: 1) == 2)
}

@Test
func habitsWidgetMediumSplitsIntoBalancedColumns() {
  // Habits that overflow one column go into two, the left one taking an odd
  // extra; fewer keep a single full-width column.
  #expect(HabitsWidgetLayout.columns([1, 2, 3], family: .systemMedium) == [[1, 2, 3]])
  #expect(HabitsWidgetLayout.columns([1, 2, 3, 4], family: .systemMedium) == [[1, 2], [3, 4]])
  #expect(HabitsWidgetLayout.columns([1, 2, 3, 4, 5], family: .systemMedium) == [[1, 2, 3], [4, 5]])
  #expect(HabitsWidgetLayout.columns([1, 2, 3, 4, 5, 6], family: .systemMedium) == [[1, 2, 3], [4, 5, 6]])
  #expect(HabitsWidgetLayout.columns([1, 2, 3], family: .systemMedium, rows: 2) == [[1, 2], [3]])
  #expect(HabitsWidgetLayout.columns([1, 2, 3], family: .systemSmall) == [[1, 2, 3]])
  #expect(HabitsWidgetLayout.columns([Int](), family: .systemMedium) == [[]])
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
  #expect(taskRowSource.contains(".frame(minWidth: 32, minHeight: 32)"))
  #expect(taskRowSource.contains(".contentShape(Rectangle())"))
  // A row's complete circle flows through the shared `WidgetActionButton` hit
  // target; the lead ring is its own full-diameter target (`Button(intent:)`
  // around `LorvexTaskRing` with a circular content shape), the only raw
  // intent button in the file.
  #expect(taskRowSource.contains("WidgetActionButton(\n          intent: WidgetCompleteTaskIntent"))
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
