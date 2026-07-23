import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@Test
func widgetRenderModelBuildsMediumContentRowsAndCounts() {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 4, overdueCount: 1, dueTodayCount: 2),
    briefing: "Start with deep work.",
    focusTasks: [
      widgetFocusTask(id: "task-1", title: "First", priority: 1, estimatedMinutes: 25),
      widgetFocusTask(id: "task-2", title: "Second", priority: 2, estimatedMinutes: 15),
      widgetFocusTask(id: "task-3", title: "Third", priority: 3, estimatedMinutes: nil),
      widgetFocusTask(id: "task-4", title: "Fourth", priority: nil, estimatedMinutes: nil),
    ]
  )
  let entry = WidgetTimelineEntry(
    date: Date(timeIntervalSince1970: 1_779_465_600),
    state: .snapshot(snapshot, freshness: .fresh(ageSeconds: 60)),
    refreshAfter: Date(timeIntervalSince1970: 1_779_467_400)
  )

  let model = WidgetRenderModelBuilder().model(
    entry: entry,
    family: .systemMedium,
    statusText: "Updated now"
  )

  #expect(model.state == .content)
  #expect(model.headline == "Focus")
  #expect(model.subheadline == "Start with deep work.")
  #expect(model.focusCountText == "4 in focus")
  #expect(model.staleAgeLabel == nil)
  #expect(model.attentionCountText == "3 due")
  #expect(model.taskRows.map(\.id) == ["task-1", "task-2", "task-3"])
  #expect(model.taskRows.first?.metadata == "25 min · May 22, 2026")
  #expect(model.taskRows.first?.priorityLabel == "Priority 1")
  #expect(model.urlString == "lorvex://open/today")
  #expect(model.taskRows.first?.urlString == "lorvex://task/task-1")
}

@Test
func widgetRenderModelBuilderCachesDueDateDisplayFormatter() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appending(path: "Sources/LorvexWidgetKitSupport/WidgetRenderModelBuilder.swift"),
    encoding: .utf8
  )

  #expect(source.contains("static let mediumDueDateFormatter"))
  #expect(!source.contains("let formatter = DateFormatter()\\n    formatter.locale = .autoupdatingCurrent"))
}

@Test
func widgetRenderModelCarriesStaleAgeLabelForFocusWidgetBadge() {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: [widgetFocusTask(id: "task-1", title: "First", priority: 1, estimatedMinutes: 25)]
  )
  let entry = WidgetTimelineEntry(
    date: Date(timeIntervalSince1970: 1_779_472_800),
    state: .snapshot(snapshot, freshness: .stale(ageSeconds: 2 * 60 * 60)),
    refreshAfter: Date(timeIntervalSince1970: 1_779_473_100)
  )

  let model = WidgetRenderModelBuilder().model(
    entry: entry,
    family: .systemSmall,
    statusText: "Updated 2h ago"
  )

  #expect(model.state == .stale)
  #expect(model.staleAgeLabel == "2h ago")
}

@Test
func widgetRenderModelUsesEmptyAndFallbackStates() {
  let emptySnapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 0, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: []
  )
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let emptyEntry = WidgetTimelineEntry(
    date: now,
    state: .snapshot(emptySnapshot, freshness: .fresh(ageSeconds: 0)),
    refreshAfter: now.addingTimeInterval(30 * 60)
  )
  let fallbackEntry = WidgetTimelineEntry(
    date: now,
    state: .fallback(.init(reason: .missingFile, detail: "missing")),
    refreshAfter: now.addingTimeInterval(5 * 60)
  )
  let builder = WidgetRenderModelBuilder()

  let emptyModel = builder.model(entry: emptyEntry, family: .systemSmall, statusText: "Updated now")
  let fallbackModel = builder.model(
    entry: fallbackEntry,
    family: .systemSmall,
    statusText: "Open Lorvex to refresh"
  )

  #expect(emptyModel.state == .empty)
  #expect(emptyModel.subheadline == "No focus tasks yet.")
  #expect(emptyModel.taskRows.isEmpty)
  #expect(fallbackModel.state == .fallback)
  #expect(fallbackModel.headline == "Lorvex")
  #expect(fallbackModel.statusText == "Open Lorvex to refresh")
  #expect(fallbackModel.urlString == "lorvex://open/today")
}

@Test
func widgetRenderModelEscapesTaskDeepLinks() {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: [
      widgetFocusTask(id: "task with/slash", title: "Escaped task", priority: nil, estimatedMinutes: nil)
    ]
  )
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let entry = WidgetTimelineEntry(
    date: now,
    state: .snapshot(snapshot, freshness: .fresh(ageSeconds: 0)),
    refreshAfter: now.addingTimeInterval(30 * 60)
  )

  let model = WidgetRenderModelBuilder().model(
    entry: entry,
    family: .systemSmall,
    statusText: "Updated now"
  )

  #expect(model.taskRows.first?.urlString == "lorvex://task/task%20with%2Fslash")
}

@Test
func widgetRenderModelOmitsCompletedFocusTasksFromActionableRows() {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 2, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: [
      widgetFocusTask(
        id: "done-task",
        title: "Already completed",
        status: LorvexTask.Status.completed.rawValue,
        priority: 1,
        estimatedMinutes: 20
      ),
      widgetFocusTask(id: "open-task", title: "Still actionable", priority: 2, estimatedMinutes: 30),
    ]
  )
  let entry = WidgetTimelineEntry(
    date: Date(timeIntervalSince1970: 1_779_465_600),
    state: .snapshot(snapshot, freshness: .fresh(ageSeconds: 0)),
    refreshAfter: Date(timeIntervalSince1970: 1_779_467_400)
  )

  let model = WidgetRenderModelBuilder().model(
    entry: entry,
    family: .systemMedium,
    statusText: "Updated now"
  )

  #expect(model.state == .content)
  #expect(model.taskRows.map(\.id) == ["open-task"])
  #expect(model.taskRows.first?.title == "Still actionable")
}
