import Foundation
import LorvexDomain

public struct CurrentFocusPlan: Equatable, Sendable {
  public var date: String
  public var taskIDs: [String]
  public var briefing: String?
  public var timezone: String?
  public var localChangeSequence: Int

  public init(
    date: String,
    taskIDs: [String],
    briefing: String?,
    timezone: String?,
    localChangeSequence: Int
  ) {
    self.date = date
    self.taskIDs = taskIDs
    self.briefing = briefing
    self.timezone = timezone
    self.localChangeSequence = localChangeSequence
  }
}

public struct FocusSchedule: Equatable, Sendable {
  public var date: String
  public var rationale: String?
  public var timezone: String?
  public var workingHours: FocusScheduleWorkingHours?
  public var totalMinutesAvailable: Int?
  public var calendarEventsCount: Int?
  public var blocks: [FocusScheduleBlock]
  public var slots: [FocusScheduleSlot]
  public var unscheduled: [FocusScheduleTask]

  public init(
    date: String,
    rationale: String? = nil,
    timezone: String? = nil,
    workingHours: FocusScheduleWorkingHours? = nil,
    totalMinutesAvailable: Int? = nil,
    calendarEventsCount: Int? = nil,
    blocks: [FocusScheduleBlock] = [],
    slots: [FocusScheduleSlot] = [],
    unscheduled: [FocusScheduleTask] = []
  ) {
    self.date = date
    self.rationale = rationale
    self.timezone = timezone
    self.workingHours = workingHours
    self.totalMinutesAvailable = totalMinutesAvailable
    self.calendarEventsCount = calendarEventsCount
    self.blocks = blocks
    self.slots = slots
    self.unscheduled = unscheduled
  }
}

public struct FocusScheduleWorkingHours: Equatable, Sendable {
  public var start: String
  public var end: String

  public init(start: String, end: String) {
    self.start = start
    self.end = end
  }
}

/// One ordered member of a focus schedule.
///
/// A block deliberately is not `Identifiable`: provider and freeform holds do
/// not carry durable external identities, and two legitimate rows can have the
/// same type, time, source, and title. UI collections therefore key blocks by
/// their schedule position, which is also the persisted child-row identity.
public struct FocusScheduleBlock: Equatable, Sendable {
  public var blockType: String
  public var startTime: String
  public var endTime: String
  public var taskID: String?
  public var calendarEventID: String?
  public var eventSource: FocusScheduleEventSource?
  public var title: String?

  public init(
    blockType: String,
    startTime: String,
    endTime: String,
    taskID: String? = nil,
    calendarEventID: String? = nil,
    eventSource: FocusScheduleEventSource? = nil,
    title: String? = nil
  ) {
    self.blockType = blockType
    self.startTime = startTime
    self.endTime = endTime
    self.taskID = taskID
    self.calendarEventID = calendarEventID
    self.eventSource = eventSource
    self.title = title
  }

  /// A focus-schedule block's role, classified from the `blockType` wire string.
  /// The proposer emits exactly `"task"`, `"event"`, and `"buffer"`; anything
  /// else is `.unknown` (forward-compatible — rendered as a neutral hold). This
  /// is the one place the wire strings are interpreted, so views switch on the
  /// case rather than re-comparing the raw string (and mislabeling, e.g.,
  /// buffers as calendar holds).
  public enum Kind: Equatable, Sendable {
    case task
    case calendarEvent
    case buffer
    case unknown
  }

  public var kind: Kind {
    switch blockType {
    case "task": return .task
    case "event": return .calendarEvent
    case "buffer": return .buffer
    default: return .unknown
    }
  }
}

public struct FocusScheduleSlot: Equatable, Sendable {
  public var task: FocusScheduleTask
  public var startTime: String
  public var endTime: String

  public init(task: FocusScheduleTask, startTime: String, endTime: String) {
    self.task = task
    self.startTime = startTime
    self.endTime = endTime
  }
}

public struct FocusScheduleTask: Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var status: String
  public var estimatedMinutes: Int?

  public init(id: String, title: String, status: String, estimatedMinutes: Int? = nil) {
    self.id = id
    self.title = title
    self.status = status
    self.estimatedMinutes = estimatedMinutes
  }
}
