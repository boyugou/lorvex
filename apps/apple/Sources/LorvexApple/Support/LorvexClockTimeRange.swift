import Foundation
import LorvexCore

/// The hyphen-joined display range for an event's start/end clock times, each
/// rendered in the user's 12-/24-hour preference via the shared
/// ``lorvexClockTimeLabel(_:)``.
func lorvexClockTimeRange(start: String?, end: String?) -> String {
  [start, end].compactMap { $0 }.map(lorvexClockTimeLabel).joined(separator: "-")
}
