import Foundation

/// Positions for a manually ordered set of rows after a reorder, chosen so
/// that as few rows as possible change.
///
/// Each list and each habit syncs as one record, the newer copy replacing the
/// older whole. A reorder that renumbered every row after the moved one would
/// send all of them, each replacing whatever another device had changed in it
/// meanwhile (a rename, an archive, a new goal). Rows keep their positions
/// here unless they have to move, and a moved row takes a position between its
/// new neighbors, so dragging one row sends one record.
public enum ReorderPositions {
  /// The distance between rows when positions are assigned afresh, and the
  /// step a row placed after the last one takes. It leaves room for later
  /// moves to land between two neighbors.
  public static let spacing: Int64 = 1024

  /// The positions the rows should have, given `current`, the stored position
  /// of each row in its new order. The result is strictly increasing, and
  /// equals `current` wherever a row can stay.
  ///
  /// The rows that stay are a longest run of the new order whose positions
  /// already increase. Every other row goes between the staying rows around
  /// it. When two of those are too close for the rows between them, or the
  /// stored positions are out of range, every row is renumbered `spacing`
  /// apart, which happens once for a set that has never had gaps.
  public static func assign(_ current: [Int64]) -> [Int64] {
    let count = current.count
    guard count > 1 else { return current }
    guard current.allSatisfy({ $0 >= 0 && $0 <= Int64.max / 2 }) else { return spaced(count) }

    var stays = [Bool](repeating: false, count: count)
    for index in longestIncreasingRun(current) { stays[index] = true }

    var result = current
    var index = 0
    while index < count {
      guard !stays[index] else {
        index += 1
        continue
      }
      var end = index
      while end < count, !stays[end] { end += 1 }
      let rows = Int64(end - index)
      let lower: Int64 = index > 0 ? result[index - 1] : -1
      if end < count {
        let room = current[end] - lower
        guard room > rows else { return spaced(count) }
        let step = room / (rows + 1)
        for offset in 0..<(end - index) {
          result[index + offset] = lower + step * Int64(offset + 1)
        }
      } else {
        for offset in 0..<(end - index) {
          result[index + offset] = lower + spacing * Int64(offset + 1)
        }
      }
      index = end
    }
    return result
  }

  /// `count` positions `spacing` apart, starting at `spacing`.
  static func spaced(_ count: Int) -> [Int64] {
    (0..<count).map { Int64($0 + 1) * spacing }
  }

  /// The indices of a longest subsequence of `values` that strictly increases.
  static func longestIncreasingRun(_ values: [Int64]) -> [Int] {
    guard !values.isEmpty else { return [] }
    var length = [Int](repeating: 1, count: values.count)
    var previous = [Int](repeating: -1, count: values.count)
    var best = 0
    for index in values.indices {
      for earlier in 0..<index
      where values[earlier] < values[index] && length[earlier] + 1 > length[index] {
        length[index] = length[earlier] + 1
        previous[index] = earlier
      }
      if length[index] > length[best] { best = index }
    }
    var run: [Int] = []
    var cursor = best
    while cursor >= 0 {
      run.append(cursor)
      cursor = previous[cursor]
    }
    return run.reversed()
  }
}
