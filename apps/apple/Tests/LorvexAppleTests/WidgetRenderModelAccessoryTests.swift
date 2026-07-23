import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@Test
func widgetRenderModelOptimizesAccessoryInlineForOneLine() {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 0),
    briefing: "Hidden in inline family",
    focusTasks: [
      widgetFocusTask(id: "task-inline", title: "One-line focus", priority: 1, estimatedMinutes: 10)
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
    family: .accessoryInline,
    statusText: "Updated now"
  )

  #expect(model.headline == "One-line focus")
  #expect(model.taskRows.isEmpty)
  #expect(model.focusCountText == "1 in focus")
  #expect(model.urlString == "lorvex://task/task-inline")
}

@Test
func widgetRenderModelAccessoryInlineLinksToFirstOpenTask() {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 2, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: [
      widgetFocusTask(
        id: "done-inline",
        title: "Completed inline task",
        status: LorvexTask.Status.completed.rawValue,
        priority: 1,
        estimatedMinutes: 20
      ),
      widgetFocusTask(id: "open-inline", title: "Open inline task", priority: 2, estimatedMinutes: 30),
    ]
  )
  let entry = WidgetTimelineEntry(
    date: Date(timeIntervalSince1970: 1_779_465_600),
    state: .snapshot(snapshot, freshness: .fresh(ageSeconds: 0)),
    refreshAfter: Date(timeIntervalSince1970: 1_779_467_400)
  )

  let model = WidgetRenderModelBuilder().model(
    entry: entry,
    family: .accessoryInline,
    statusText: "Updated now"
  )

  #expect(model.headline == "Open inline task")
  #expect(model.urlString == "lorvex://task/open-inline")
}
