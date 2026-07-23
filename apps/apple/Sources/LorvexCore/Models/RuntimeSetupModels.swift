public struct SetupStatusSnapshot: Equatable, Sendable {
  public var setupCompleted: Bool
  public var setupState: String
  public var listCount: Int
  public var taskCount: Int
  public var defaultListID: String?
  public var workingHours: String?

  public init(
    setupCompleted: Bool,
    setupState: String,
    listCount: Int,
    taskCount: Int,
    defaultListID: String?,
    workingHours: String?
  ) {
    self.setupCompleted = setupCompleted
    self.setupState = setupState
    self.listCount = listCount
    self.taskCount = taskCount
    self.defaultListID = defaultListID
    self.workingHours = workingHours
  }
}
