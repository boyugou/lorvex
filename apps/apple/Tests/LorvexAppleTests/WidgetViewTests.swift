import LorvexWidgetKitSupport
import LorvexWidgetViews
import SwiftUI
import Testing

@Test
func widgetViewMetricsMatchRenderFamilyRowBudgets() {
  #expect(LorvexWidgetViewMetrics.metrics(for: .accessoryInline).maxVisibleRows == 0)
  #expect(LorvexWidgetViewMetrics.metrics(for: .systemSmall).maxVisibleRows == 2)
  #expect(LorvexWidgetViewMetrics.metrics(for: .systemMedium).maxVisibleRows == 3)
  #expect(LorvexWidgetViewMetrics.metrics(for: .systemLarge).maxVisibleRows == 6)
  #expect(LorvexWidgetViewMetrics.metrics(for: .accessoryRectangular).maxVisibleRows == 2)
}

@Test
func widgetViewMetricsShowBriefingOnlyOnLarge() {
  // Only large has the vertical room for the briefing line above its rows. Medium
  // dropped it — with three rows + header + footer it overflowed the 158pt canvas,
  // and it merely restated the footer counts.
  #expect(!LorvexWidgetViewMetrics.metrics(for: .systemSmall).showsBriefing)
  #expect(!LorvexWidgetViewMetrics.metrics(for: .systemMedium).showsBriefing)
  #expect(LorvexWidgetViewMetrics.metrics(for: .systemLarge).showsBriefing)
  #expect(!LorvexWidgetViewMetrics.metrics(for: .accessoryInline).showsBriefing)
  #expect(!LorvexWidgetViewMetrics.metrics(for: .accessoryRectangular).showsBriefing)
}

@Test
func todayWidgetLayoutReportsHiddenTaskOverflow() {
  #expect(TodayWidgetLayout.rowLimit(for: .systemSmall) == 3)
  #expect(TodayWidgetLayout.rowLimit(for: .systemMedium) == 4)
  #expect(TodayWidgetLayout.rowLimit(for: .systemLarge) == 8)
  #expect(TodayWidgetLayout.hiddenTaskCount(total: 6, family: .systemSmall) == 3)
  #expect(TodayWidgetLayout.hiddenTaskCount(total: 6, family: .systemMedium) == 2)
  #expect(TodayWidgetLayout.hiddenTaskCount(total: 6, family: .systemLarge) == 0)
}

@Test
func todayWidgetLayoutFormatsFooterWithOverflow() {
  #expect(
    TodayWidgetLayout.footerText(completed: 2, totalOpen: 6, family: .systemSmall)
      == "2 completed · 6 open · 3 more"
  )
  #expect(
    TodayWidgetLayout.footerText(completed: 2, totalOpen: 4, family: .systemMedium)
      == "2 completed · 4 open"
  )
}

@Test
func habitsWidgetLayoutReportsHiddenHabitOverflow() {
  #expect(HabitsWidgetLayout.rowLimit(for: .systemSmall) == 3)
  #expect(HabitsWidgetLayout.rowLimit(for: .systemMedium) == 5)
  #expect(HabitsWidgetLayout.hiddenHabitCount(total: 8, family: .systemSmall) == 5)
  #expect(HabitsWidgetLayout.hiddenHabitCount(total: 8, family: .systemMedium) == 3)
  #expect(HabitsWidgetLayout.hiddenHabitCount(total: 3, family: .systemSmall) == 0)
}

@Test
func todayWidgetRowsDeepLinkToIndividualTasks() throws {
  let source = try appleSourceFile("Sources/LorvexWidgetViews/LorvexTodayWidgetView.swift")

  #expect(source.contains("Link(destination: task.taskURL)"))
  #expect(source.contains("TodayTaskRowView(task: task, interactive: isInteractive)"))
}

@Test
func interactiveWidgetTaskActionsUseSharedHitTargetButton() throws {
  let taskRowSource = try appleSourceFile("Sources/LorvexWidgetViews/LorvexWidgetTaskRowView.swift")
  let todaySource = try appleSourceFile("Sources/LorvexWidgetViews/LorvexTodayWidgetView.swift")

  #expect(taskRowSource.contains("struct WidgetActionButton<Intent: AppIntent>: View"))
  #expect(taskRowSource.contains(".frame(minWidth: 32, minHeight: 32)"))
  #expect(taskRowSource.contains(".contentShape(Rectangle())"))
  // Defer + complete both flow through the shared `WidgetActionButton` hit target,
  // never a raw `Button(intent:)`. (Defer is large-only, so its indentation
  // varies — assert the wrapper + intent rather than exact whitespace.)
  #expect(taskRowSource.contains("intent: WidgetDeferTaskIntent"))
  #expect(taskRowSource.contains("intent: WidgetCompleteTaskIntent"))
  #expect(todaySource.contains("WidgetActionButton(\n          intent: WidgetCompleteTaskIntent"))
  #expect(!taskRowSource.contains("Button(intent: Widget"))
  #expect(!todaySource.contains("Button(intent: Widget"))
}

@Test
func widgetStaleAgeLabelParticipatesInLayout() throws {
  let systemSource = try appleSourceFile("Sources/LorvexWidgetViews/LorvexWidgetSystemView.swift")
  let todaySource = try appleSourceFile("Sources/LorvexWidgetViews/LorvexTodayWidgetView.swift")
  let progressSource = try appleSourceFile("Sources/LorvexWidgetViews/LorvexProgressWidgetView.swift")
  let habitsSource = try appleSourceFile("Sources/LorvexWidgetViews/LorvexHabitsWidgetView.swift")

  #expect(systemSource.contains("WidgetStaleAgeLabel(staleAgeLabel)"))
  #expect(todaySource.contains("WidgetStaleAgeLabel(staleAgeLabel)"))
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
  ]

  for family in families {
    let model = WidgetRenderModel(
      family: family,
      state: .content,
      headline: "Today",
      subheadline: "Start with focus.",
      statusText: "Updated now",
      focusCountText: "1 Focus",
      attentionCountText: nil,
      taskRows: [
        WidgetTaskRenderRow(id: "task-1", title: "Write widget view", metadata: "25m", priorityLabel: "P1")
      ]
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
