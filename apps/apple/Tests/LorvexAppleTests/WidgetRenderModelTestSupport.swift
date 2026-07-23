import LorvexWidgetKitSupport

func widgetFocusTask(
  id: String,
  title: String,
  status: String = "open",
  priority: Int?,
  estimatedMinutes: Int?
) -> WidgetSnapshot.FocusTask {
  .init(
    id: id,
    title: title,
    status: status,
    dueDate: "2026-05-22",
    priority: priority,
    listID: nil,
    estimatedMinutes: estimatedMinutes
  )
}
