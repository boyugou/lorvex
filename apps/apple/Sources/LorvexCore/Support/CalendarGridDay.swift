import Foundation

/// Day-clipped, lane-assigned representation of a timed event for one day
/// column. `startMin`/`endMin` are minutes-from-midnight within that column.
public struct CalendarGridTimedBlock: Identifiable, Equatable, Sendable {
  public let event: CalendarTimelineEvent
  public let startMin: Int
  public let endMin: Int
  public let lane: Int
  public let laneCount: Int
  /// Stable per-column identity (event id + day key), since a multi-day event
  /// yields one block per day it spans.
  public let id: String

  public init(
    event: CalendarTimelineEvent,
    startMin: Int,
    endMin: Int,
    lane: Int,
    laneCount: Int,
    id: String
  ) {
    self.event = event
    self.startMin = startMin
    self.endMin = endMin
    self.lane = lane
    self.laneCount = laneCount
    self.id = id
  }
}

/// All positioned + all-day content for a single visible day column.
public struct CalendarGridDay: Identifiable, Equatable, Sendable {
  public let date: Date
  /// `yyyy-MM-dd` key matching `CalendarTimelineEvent.startDate`.
  public let dayKey: String
  public let timedBlocks: [CalendarGridTimedBlock]
  public let allDayEvents: [CalendarTimelineEvent]
  public let scheduledTasks: [LorvexTask]
  public var id: String { dayKey }

  public init(
    date: Date,
    dayKey: String,
    timedBlocks: [CalendarGridTimedBlock],
    allDayEvents: [CalendarTimelineEvent],
    scheduledTasks: [LorvexTask]
  ) {
    self.date = date
    self.dayKey = dayKey
    self.timedBlocks = timedBlocks
    self.allDayEvents = allDayEvents
    self.scheduledTasks = scheduledTasks
  }
}
