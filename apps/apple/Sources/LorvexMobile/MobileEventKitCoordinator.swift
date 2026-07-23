import Foundation
import LorvexCore
import LorvexDomain
import LorvexStore

public protocol MobileEventKitCoordinating: Sendable {
  func requestAccess() async throws -> Bool
  func availableCalendars(enabled: Bool) async throws -> [EventKitCalendarDescriptor]
  func ingest(
    enabled: Bool,
    accessMode: CalendarAiAccessMode,
    calendarFilter: EventKitCalendarFilter,
    from: Date,
    to: Date,
    windowStart: String,
    windowEnd: String,
    requestAccess: Bool
  ) async throws -> Int
}

actor MobileEventKitCoordinator: MobileEventKitCoordinating {
  private let access: any MobileEventKitAccessing
  private let provider: any EventKitProviderServicing

  init(access: any MobileEventKitAccessing, provider: any EventKitProviderServicing) {
    self.access = access
    self.provider = provider
  }

  static func make(
    core: any LorvexCoreServicing,
    access: any MobileEventKitAccessing
  ) -> MobileEventKitCoordinator? {
    guard let provider = core as? any EventKitProviderServicing else { return nil }
    return MobileEventKitCoordinator(access: access, provider: provider)
  }

  func requestAccess() async throws -> Bool {
    try await access.requestAccess()
  }

  func availableCalendars(enabled: Bool) async throws -> [EventKitCalendarDescriptor] {
    guard enabled else { return [] }
    return try await access.availableCalendars()
  }

  func ingest(
    enabled: Bool,
    accessMode: CalendarAiAccessMode,
    calendarFilter: EventKitCalendarFilter,
    from: Date,
    to: Date,
    windowStart: String,
    windowEnd: String,
    requestAccess: Bool
  ) async throws -> Int {
    let signpost = LorvexSignpost.begin(.eventKitIngest)
    defer { LorvexSignpost.end(signpost) }
    guard enabled else {
      try provider.clearEventKitMirror()
      return 0
    }
    guard accessMode.includesProvider else {
      try provider.clearEventKitMirror()
      return 0
    }
    if requestAccess {
      guard try await access.requestAccess() else {
        throw MobileEventKitAccessError.readAccessDenied
      }
    } else if !access.isReadAuthorized() {
      try provider.clearEventKitMirror()
      throw MobileEventKitAccessError.readAccessDenied
    }
    let fetched = try await access.fetchEvents(
      start: from,
      end: to,
      calendarFilter: calendarFilter
    )
    let rows = EventKitIngest.providerRows(
      from: fetched,
      scope: SwiftLorvexCoreService.eventKitScope,
      accessMode: accessMode
    )
    return try provider.ingestEventKitEvents(
      rows,
      builtAtMode: accessMode,
      windowStart: windowStart,
      windowEnd: windowEnd
    )
  }
}
