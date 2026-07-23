import Foundation

public struct ExportTaskCalendarEventLink: Codable, Equatable, Sendable {
  public var taskID: String
  public var calendarEventID: String
  public var createdAt: String?
  public var updatedAt: String?

  public init(
    taskID: String,
    calendarEventID: String,
    createdAt: String? = nil,
    updatedAt: String? = nil
  ) {
    self.taskID = taskID
    self.calendarEventID = calendarEventID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public static let columns = ["taskID", "calendarEventID", "createdAt", "updatedAt"]

  public var csvRow: [String] {
    [taskID, calendarEventID, createdAt ?? "", updatedAt ?? ""]
  }
}
