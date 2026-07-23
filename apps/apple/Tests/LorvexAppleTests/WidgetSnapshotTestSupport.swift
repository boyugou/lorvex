import Foundation
import LorvexCore

func makePublisherWidgetTask(
  id: String,
  title: String,
  priority: LorvexTask.Priority,
  status: LorvexTask.Status = .open,
  dueDate: Date?,
  estimatedMinutes: Int?
) -> LorvexTask {
  LorvexTask(
    id: id,
    title: title,
    notes: "",
    priority: priority,
    status: status,
    dueDate: dueDate,
    estimatedMinutes: estimatedMinutes,
    tags: []
  )
}
