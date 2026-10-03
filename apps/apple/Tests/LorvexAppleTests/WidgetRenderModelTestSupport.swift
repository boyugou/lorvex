import LorvexWidgetKitSupport

func widgetTodayTask(
  id: String,
  title: String,
  status: String = "open",
  dueDate: String? = "2026-05-22",
  priority: Int?,
  estimatedMinutes: Int?,
  scheduledStart: String? = nil,
  scheduledEnd: String? = nil,
  isBlocked: Bool = false
) -> WidgetSnapshot.TodayTask {
  .init(
    id: id,
    title: title,
    status: status,
    dueDate: dueDate,
    priority: priority,
    listID: nil,
    estimatedMinutes: estimatedMinutes,
    scheduledStart: scheduledStart,
    scheduledEnd: scheduledEnd,
    isBlocked: isBlocked
  )
}
