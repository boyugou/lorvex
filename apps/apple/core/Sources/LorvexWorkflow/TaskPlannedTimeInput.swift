import Foundation
import LorvexDomain
import LorvexStore

/// The `planned_start_time` / `planned_end_time` pair that task create and
/// update accept: `HH:MM` for the start, `HH:MM` or `24:00` for the end, and
/// the end after the start. The result is minutes since midnight.
enum TaskPlannedTimeInput {
  static func minutes(start startRaw: String, end endRaw: String) throws -> Range<Int64> {
    guard case .success(let start) = TimeOfDay.parse(startRaw).map(\.minutesOfDay) else {
      throw StoreError.validation("planned_start_time must be HH:MM, got '\(startRaw)'")
    }
    guard case .success(let end) = TimeOfDay.parseRangeEndMinutes(endRaw) else {
      throw StoreError.validation("planned_end_time must be HH:MM or 24:00, got '\(endRaw)'")
    }
    guard end > start else {
      throw StoreError.validation("planned_end_time must be after planned_start_time")
    }
    return Int64(start)..<Int64(end)
  }

  static let unpairedMessage =
    "planned_start_time and planned_end_time go together: set both, or clear both with null"

  static let missingDateMessage =
    "a planned time needs a planned date; set planned_date in the same call"
}
