public struct TaskChecklistItem: Identifiable, Equatable, Hashable, Sendable {
  public var id: String
  public var taskID: String
  public var position: Int
  public var text: String
  public var completedAt: String?
  public var createdAt: String?
  public var updatedAt: String?

  public init(
    id: String,
    taskID: String,
    position: Int,
    text: String,
    completedAt: String?,
    createdAt: String? = nil,
    updatedAt: String? = nil
  ) {
    self.id = id
    self.taskID = taskID
    self.position = position
    self.text = text
    self.completedAt = completedAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct TaskReminder: Identifiable, Equatable, Sendable {
  public var id: String
  public var reminderAt: String
  public var status: String?
  public var dismissedAt: String?
  public var cancelledAt: String?
  public var createdAt: String?
  public var originalLocalTime: String?
  public var originalTz: String?

  public init(
    id: String,
    reminderAt: String,
    status: String?,
    dismissedAt: String? = nil,
    cancelledAt: String? = nil,
    createdAt: String? = nil,
    originalLocalTime: String? = nil,
    originalTz: String? = nil
  ) {
    self.id = id
    self.reminderAt = reminderAt
    self.status = status
    self.dismissedAt = dismissedAt
    self.cancelledAt = cancelledAt
    self.createdAt = createdAt
    self.originalLocalTime = originalLocalTime
    self.originalTz = originalTz
  }
}
