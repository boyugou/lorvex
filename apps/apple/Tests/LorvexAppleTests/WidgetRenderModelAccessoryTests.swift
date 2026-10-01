import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@Test
func widgetRenderModelOptimizesAccessoryInlineForOneLine() {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(todayCount: 1, overdueCount: 0, dueTodayCount: 0),
    briefing: "Hidden in inline family",
    tasks: [
      widgetTodayTask(
        id: "task-inline", title: "One-line task",
        status: LorvexTask.Status.inProgress.rawValue, priority: 1, estimatedMinutes: 10)
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

  #expect(model.headline == "One-line task")
  #expect(model.taskRows.isEmpty)
  #expect(model.lead?.id == "task-inline")
  #expect(model.urlString == "lorvex://task/task-inline")
}

@Test
func widgetRenderModelAccessoryInlineLinksToFirstOpenTask() {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(todayCount: 1, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    tasks: [
      widgetTodayTask(
        id: "done-inline",
        title: "Completed inline task",
        status: LorvexTask.Status.completed.rawValue,
        priority: 1,
        estimatedMinutes: 20
      ),
      widgetTodayTask(
        id: "open-inline", title: "Open inline task",
        status: LorvexTask.Status.inProgress.rawValue, priority: 2, estimatedMinutes: 30),
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

@Test
func widgetRenderModelAccessoryInlineSaysWhatIsLeftWhenNoTaskLeads() {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(todayCount: 2, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    tasks: [
      widgetTodayTask(id: "a", title: "Untimed A", priority: 1, estimatedMinutes: 30),
      widgetTodayTask(id: "b", title: "Untimed B", priority: 2, estimatedMinutes: 90),
    ]
  )
  let entry = WidgetTimelineEntry(
    date: Date(timeIntervalSince1970: 1_779_465_600),
    state: .snapshot(snapshot, freshness: .fresh(ageSeconds: 0)),
    refreshAfter: Date(timeIntervalSince1970: 1_779_467_400)
  )

  let model = WidgetRenderModelBuilder().model(
    entry: entry, family: .accessoryInline, statusText: "Updated now")

  #expect(model.state == .content)
  #expect(model.lead == nil)
  #expect(model.dayLine == "2 left today · about 2 hr")
  #expect(model.urlString == LorvexDeepLinkContract.destinationURLString(.today))
  #expect(model.circularContent == .remaining(2))
}
