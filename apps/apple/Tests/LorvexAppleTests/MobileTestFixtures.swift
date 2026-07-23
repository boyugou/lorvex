import LorvexCore

func makeMobileTask(
  id: String,
  title: String,
  priority: LorvexTask.Priority,
  checklistItems: [TaskChecklistItem] = [],
  recurrence: TaskRecurrenceRule? = nil
) -> LorvexTask {
  LorvexTask(
    id: id,
    title: title,
    notes: "",
    priority: priority,
    status: .open,
    dueDate: nil,
    estimatedMinutes: 25,
    tags: [],
    checklistItems: checklistItems,
    recurrence: recurrence
  )
}
