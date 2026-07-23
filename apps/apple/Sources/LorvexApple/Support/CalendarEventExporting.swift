import Foundation
import LorvexCore

/// Prefix embedded in `EKEvent.notes` to mark a Lorvex-originated event in the
/// dedicated Lorvex calendar. The Lorvex event ID follows the prefix on the
/// same line. Used as a device-independent breadcrumb (and a resolution
/// fallback) for write-back edit/delete.
let lorvexCalendarEventPrefix = "lorvex-event-id:"

/// Status surface for the EventKit integration shown in Settings. `operation`
/// names the most recent operation (`eventkit-import` / `eventkit-export` /
/// `eventkit-update` / `eventkit-delete`).
struct CalendarIntegrationReport: Equatable, Sendable {
  enum Status: Equatable, Sendable {
    case notStarted
    case succeeded
    case skipped
    case failed
  }

  var status: Status
  var operation: String
  var eventCount: Int
  var eventID: CalendarTimelineEvent.ID?
  var errorMessage: String?

  static var notStarted: CalendarIntegrationReport {
    CalendarIntegrationReport(
      status: .notStarted, operation: "none", eventCount: 0, eventID: nil, errorMessage: nil)
  }

  static func succeeded(
    operation: String, eventCount: Int, eventID: CalendarTimelineEvent.ID? = nil
  ) -> CalendarIntegrationReport {
    CalendarIntegrationReport(
      status: .succeeded, operation: operation, eventCount: eventCount, eventID: eventID,
      errorMessage: nil)
  }

  static func skipped(operation: String) -> CalendarIntegrationReport {
    CalendarIntegrationReport(
      status: .skipped, operation: operation, eventCount: 0, eventID: nil, errorMessage: nil)
  }

  static func failed(operation: String, error: any Error) -> CalendarIntegrationReport {
    CalendarIntegrationReport(
      status: .failed, operation: operation, eventCount: 0, eventID: nil,
      errorMessage: error.localizedDescription)
  }
}
