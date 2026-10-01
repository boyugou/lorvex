import Foundation

/// Day-clipped, lane-assigned representation of a timed event for one day
/// column. `startMin`/`endMin` are minutes-from-midnight within that column.
public struct CalendarGridTimedBlock: Identifiable, Equatable, Sendable {
  public let event: CalendarTimelineEvent
  public let startMin: Int
  public let endMin: Int
  /// The minute the block is drawn to: `endMin`, or a later minute when the
  /// block is shorter than the grid's minimum height and nothing starts within
  /// that window below it. Geometry only; the times the block reports and its
  /// gestures act on are `startMin`/`endMin`.
  public let drawnEndMin: Int
  public let lane: Int
  public let laneCount: Int
  /// Stable per-column identity (event id + day key), since a multi-day event
  /// yields one block per day it spans.
  public let id: String

  public init(
    event: CalendarTimelineEvent,
    startMin: Int,
    endMin: Int,
    drawnEndMin: Int? = nil,
    lane: Int,
    laneCount: Int,
    id: String
  ) {
    self.event = event
    self.startMin = startMin
    self.endMin = endMin
    self.drawnEndMin = drawnEndMin ?? endMin
    self.lane = lane
    self.laneCount = laneCount
    self.id = id
  }
}

/// A timed task placed on the time axis of one day column: the task, its time
/// on that day in minutes from midnight, and the overlap lane it shares with
/// the day's timed events.
public struct CalendarGridTaskBlock: Identifiable, Equatable, Sendable {
  public let task: LorvexTask
  public let startMin: Int
  public let endMin: Int
  /// The minute the block is drawn to: `endMin`, or a later minute when the
  /// block is shorter than the grid's minimum height and nothing starts within
  /// that window below it. Geometry only; the times the block reports and its
  /// gestures act on are `startMin`/`endMin`.
  public let drawnEndMin: Int
  public let lane: Int
  public let laneCount: Int
  /// Stable per-column identity (task id + day key).
  public let id: String

  public init(
    task: LorvexTask,
    startMin: Int,
    endMin: Int,
    drawnEndMin: Int? = nil,
    lane: Int,
    laneCount: Int,
    id: String
  ) {
    self.task = task
    self.startMin = startMin
    self.endMin = endMin
    self.drawnEndMin = drawnEndMin ?? endMin
    self.lane = lane
    self.laneCount = laneCount
    self.id = id
  }

  public var minutes: Int { endMin - startMin }

  /// True once the task is completed: the block stays on the grid as the day's
  /// record but no longer counts as load.
  public var isDone: Bool { task.status == .completed }
}

/// All positioned + all-day content for a single visible day column.
public struct CalendarGridDay: Identifiable, Equatable, Sendable {
  public let date: Date
  /// `yyyy-MM-dd` key matching `CalendarTimelineEvent.startDate`.
  public let dayKey: String
  public let timedBlocks: [CalendarGridTimedBlock]
  public let allDayEvents: [CalendarTimelineEvent]
  /// Tasks planned (or, unplanned, due) on this day without a time on it; the
  /// all-day strip draws them as pills.
  public let scheduledTasks: [LorvexTask]
  /// The day's timed tasks, in the same lanes as `timedBlocks`.
  public let taskBlocks: [CalendarGridTaskBlock]
  public var id: String { dayKey }

  public init(
    date: Date,
    dayKey: String,
    timedBlocks: [CalendarGridTimedBlock],
    allDayEvents: [CalendarTimelineEvent],
    scheduledTasks: [LorvexTask],
    taskBlocks: [CalendarGridTaskBlock] = []
  ) {
    self.date = date
    self.dayKey = dayKey
    self.timedBlocks = timedBlocks
    self.allDayEvents = allDayEvents
    self.scheduledTasks = scheduledTasks
    self.taskBlocks = taskBlocks
  }

  /// True when nothing sits on the time axis or in the all-day strip.
  public var isEmpty: Bool {
    timedBlocks.isEmpty && taskBlocks.isEmpty && allDayEvents.isEmpty && scheduledTasks.isEmpty
  }

  /// The first minute any positioned block starts, events and tasks alike.
  public var earliestBlockStart: Int? {
    (timedBlocks.map(\.startMin) + taskBlocks.map(\.startMin)).min()
  }
}
