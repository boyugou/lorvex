import Foundation
import LorvexCore
import LorvexStore

protocol MobileEventKitAccessing: Sendable {
  func requestAccess() async throws -> Bool
  func isReadAuthorized() -> Bool
  func availableCalendars() async throws -> [EventKitCalendarDescriptor]
  func fetchEvents(
    start: Date,
    end: Date,
    calendarFilter: EventKitCalendarFilter
  ) async throws -> [EventKitFetchedEvent]
}

enum MobileEventKitAccessError: LocalizedError, Equatable, Sendable {
  case readAccessDenied

  var errorDescription: String? {
    switch self {
    case .readAccessDenied: "Calendar read access denied."
    }
  }
}
