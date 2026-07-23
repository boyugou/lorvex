import Foundation

/// Pure layout primitives for time-axis calendar grids (macOS week grid,
/// iPhone day / 3-day view). Free of SwiftUI so the interval-lane packing can
/// be unit-tested in isolation and shared across platform targets.
public enum CalendarGridLayout {
  /// One day-clipped, positioned interval awaiting lane assignment.
  ///
  /// `startMin`/`endMin` are minutes-from-midnight within a single day column
  /// (`0...1440`). Multi-day events are clipped per column before reaching the
  /// packer, so every interval here lives in exactly one day.
  public struct Interval: Equatable, Sendable {
    public let id: String
    public let startMin: Int
    public let endMin: Int

    public init(id: String, startMin: Int, endMin: Int) {
      self.id = id
      self.startMin = startMin
      self.endMin = endMin
    }
  }

  /// An interval with its lane assignment inside its overlap cluster.
  ///
  /// `lane` is the 0-based column index; `laneCount` is the number of parallel
  /// lanes in the cluster this interval belongs to. A block's horizontal slot
  /// is `lane / laneCount` wide, offset by `lane * (width / laneCount)`.
  public struct Placed: Equatable, Sendable {
    public let id: String
    public let startMin: Int
    public let endMin: Int
    public let lane: Int
    public let laneCount: Int

    public init(id: String, startMin: Int, endMin: Int, lane: Int, laneCount: Int) {
      self.id = id
      self.startMin = startMin
      self.endMin = endMin
      self.lane = lane
      self.laneCount = laneCount
    }
  }

  /// Assigns each interval to a side-by-side lane so overlapping intervals
  /// never share a lane.
  ///
  /// Contract:
  /// - Sort by start (ties broken by longer-first, then id) — O(n log n).
  /// - Intervals are grouped into clusters: a cluster is a maximal run whose
  ///   union forms one connected span (each new interval starts strictly
  ///   before the running max end of the cluster). A new interval that starts
  ///   at or after the cluster's max end opens a fresh cluster.
  /// - A new interval whose start `>=` the cluster's running max end opens a
  ///   fresh cluster. So touching neighbors (prev end == next start) land in
  ///   separate single-lane clusters and each render at full width —
  ///   equivalent to sharing one lane, since they never overlap.
  /// - Within a cluster, each interval takes the first lane whose previous
  ///   occupant ended `<= start`.
  /// - Every member of a cluster is stamped with that cluster's lane count, so
  ///   blocks in the same visual cluster render at equal width even if some
  ///   lanes are sparsely used.
  ///
  /// Zero-length intervals (`startMin == endMin`) are kept and treated as
  /// touching: they do not force a new lane against a neighbor ending at the
  /// same minute.
  public static func layoutLanes(_ intervals: [Interval]) -> [Placed] {
    guard !intervals.isEmpty else { return [] }

    let sorted = intervals.sorted { lhs, rhs in
      if lhs.startMin != rhs.startMin { return lhs.startMin < rhs.startMin }
      if lhs.endMin != rhs.endMin { return lhs.endMin > rhs.endMin }
      return lhs.id < rhs.id
    }

    var result: [Placed] = []
    result.reserveCapacity(sorted.count)

    // Accumulate one cluster at a time, flush when an interval starts at or
    // after the cluster's running max end.
    var clusterStartIndex = 0
    var clusterMaxEnd = sorted[0].endMin
    var laneEnds: [Int] = []  // per-lane last end minute, index == lane
    var assignments: [(interval: Interval, lane: Int)] = []

    func flushCluster() {
      let laneCount = laneEnds.count
      for entry in assignments {
        result.append(
          Placed(
            id: entry.interval.id,
            startMin: entry.interval.startMin,
            endMin: entry.interval.endMin,
            lane: entry.lane,
            laneCount: laneCount
          )
        )
      }
      assignments.removeAll(keepingCapacity: true)
      laneEnds.removeAll(keepingCapacity: true)
    }

    for index in sorted.indices {
      let interval = sorted[index]
      if index > clusterStartIndex && interval.startMin >= clusterMaxEnd {
        flushCluster()
        clusterStartIndex = index
        clusterMaxEnd = interval.endMin
      }

      // First lane whose occupant ended at or before this start.
      var assignedLane = -1
      for lane in laneEnds.indices where laneEnds[lane] <= interval.startMin {
        assignedLane = lane
        break
      }
      if assignedLane == -1 {
        assignedLane = laneEnds.count
        laneEnds.append(interval.endMin)
      } else {
        laneEnds[assignedLane] = interval.endMin
      }
      assignments.append((interval, assignedLane))
      clusterMaxEnd = max(clusterMaxEnd, interval.endMin)
    }
    flushCluster()

    return result
  }
}
