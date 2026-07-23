import Foundation

/// Native-backup value for one durable recurring-calendar lineage boundary.
/// Sync clocks are intentionally omitted: restore mints fresh local provenance,
/// while the deterministic identity, boundary date, and absorbing state are the
/// user-visible data contract.
public struct ExportCalendarSeriesCutover: Codable, Equatable, Sendable {
  public var id: String
  public var lineageRootId: String
  public var cutoverDate: String
  public var state: String

  public init(
    id: String, lineageRootId: String, cutoverDate: String, state: String
  ) {
    self.id = id
    self.lineageRootId = lineageRootId
    self.cutoverDate = cutoverDate
    self.state = state
  }

  static let columns = ["id", "lineageRootId", "cutoverDate", "state"]

  var csvRow: [String] { [id, lineageRootId, cutoverDate, state] }
}

/// Read-consistent native-backup unit for canonical calendar data. Boundaries
/// and event rows are loaded from one SQLite snapshot so an export can never
/// pair an event from one topology with cutovers from another.
public struct ExportCalendarBundle: Sendable {
  public var cutovers: [ExportCalendarSeriesCutover]
  public var events: [ExportCalendarEvent]

  public init(
    cutovers: [ExportCalendarSeriesCutover], events: [ExportCalendarEvent]
  ) {
    self.cutovers = cutovers
    self.events = events
  }
}

/// User-visible event-row counts from one atomic calendar restore. Internal
/// boundary rows deliberately do not inflate import progress or summaries.
public struct NativeCalendarImportResult: Equatable, Sendable {
  public var importedEvents: Int
  public var skippedEvents: Int

  public init(importedEvents: Int, skippedEvents: Int) {
    self.importedEvents = importedEvents
    self.skippedEvents = skippedEvents
  }
}
