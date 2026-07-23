import Foundation
import LorvexDomain

public struct ExportCurrentFocus: Codable, Sendable {
  public var date: String
  public var briefing: String?
  public var timezone: String?
  public var taskIDs: [String]
  public var createdAt: String?
  public var updatedAt: String?

  public init(
    date: String,
    briefing: String? = nil,
    timezone: String? = nil,
    taskIDs: [String] = [],
    createdAt: String? = nil,
    updatedAt: String? = nil
  ) {
    self.date = date
    self.briefing = briefing
    self.timezone = timezone
    self.taskIDs = taskIDs
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  static let columns = ["date", "briefing", "timezone", "taskIDs", "createdAt", "updatedAt"]
  var csvRow: [String] {
    [date, briefing ?? "", timezone ?? "", taskIDs.joined(separator: "|"), createdAt ?? "", updatedAt ?? ""]
  }
}

public struct ExportFocusSchedule: Codable, Sendable {
  public var date: String
  public var rationale: String?
  public var timezone: String?
  public var blocks: [ExportFocusScheduleBlock]
  public var createdAt: String?
  public var updatedAt: String?

  public init(
    date: String,
    rationale: String? = nil,
    timezone: String? = nil,
    blocks: [ExportFocusScheduleBlock] = [],
    createdAt: String? = nil,
    updatedAt: String? = nil
  ) {
    self.date = date
    self.rationale = rationale
    self.timezone = timezone
    self.blocks = blocks
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  static let columns = ["date", "rationale", "timezone", "blocks", "createdAt", "updatedAt"]
  var csvRow: [String] {
    let data = (try? JSONEncoder().encode(blocks)) ?? Data()
    let encodedBlocks = String(data: data, encoding: .utf8) ?? ""
    return [date, rationale ?? "", timezone ?? "", encodedBlocks, createdAt ?? "", updatedAt ?? ""]
  }
}

public struct ExportFocusScheduleBlock: Codable, Sendable, Equatable {
  public var position: Int
  public var blockType: String
  public var startMinutes: Int
  public var endMinutes: Int
  public var taskID: String?
  public var calendarEventID: String?
  public var eventSource: FocusScheduleEventSource?
  public var title: String?

  public init(
    position: Int,
    blockType: String,
    startMinutes: Int,
    endMinutes: Int,
    taskID: String? = nil,
    calendarEventID: String? = nil,
    eventSource: FocusScheduleEventSource? = nil,
    title: String? = nil
  ) {
    self.position = position
    self.blockType = blockType
    self.startMinutes = startMinutes
    self.endMinutes = endMinutes
    self.taskID = taskID
    self.calendarEventID = calendarEventID
    self.eventSource = eventSource
    self.title = title
  }
}
