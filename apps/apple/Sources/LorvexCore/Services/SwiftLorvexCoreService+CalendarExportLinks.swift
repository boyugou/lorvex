import Foundation
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func exportCalendarICS(from: String?, to: String?) async throws -> String {
    return try read { db in
      // Resolve both defaults from one database-backed product-day snapshot.
      // The process/device timezone may differ from the synced Lorvex timezone,
      // and fixed 86,400-second arithmetic is not civil-day arithmetic at DST.
      let logicalToday = try WorkflowTimezone.todayYmdForConn(db)
      let resolvedFrom = from ?? logicalToday
      let resolvedTo = to
        ?? LorvexDateFormatters.ymdUTCAddingDays(logicalToday, days: 30)
        ?? logicalToday
      if case .failure(let error) = validateExportRange(from: resolvedFrom, to: resolvedTo) {
        throw LorvexCoreError.validation(
          field: nil, message: "Invalid ICS export range: \(error.description)")
      }
      let rows = try CalendarTimelineQueries.listCalendarEvents(
        db, from: resolvedFrom, to: resolvedTo, limit: 5000, offset: 0)
      var mastersByID: [String: CalendarEventRow] = [:]
      var standaloneRows: [CalendarEventRow] = []
      for row in rows {
        if let seriesID = row.seriesId {
          if mastersByID[seriesID] == nil {
            guard let master = try CalendarTimelineQueries.getCalendarEvent(db, id: seriesID),
              master.seriesId == nil,
              master.recurrence != nil
            else {
              throw LorvexCoreError.unsupportedOperation(
                "Calendar replacement '\(row.id)' has no exportable series master")
            }
            mastersByID[seriesID] = master
          }
        } else if row.recurrence != nil {
          mastersByID[row.id] = row
        } else {
          standaloneRows.append(row)
        }
      }

      var decisionsByMasterID = try CalendarTimelineQueries
        .listActiveCalendarOccurrenceDecisions(
          db, seriesIds: Array(mastersByID.keys))
      var componentRows = standaloneRows
      for master in mastersByID.values.sorted(by: Self.icsRowLess) {
        componentRows.append(master)
        let decisions = decisionsByMasterID[master.id] ?? []
        componentRows.append(
          contentsOf: decisions.filter { decision in
            decision.occurrenceState == .replacement
          }.sorted(by: Self.icsRowLess))
      }
      componentRows.sort(by: Self.icsRowLess)
      let ownershipByMasterID = try CalendarTimelineQueries.getCalendarSeriesOwnerships(
        db, baseEvents: Array(mastersByID.values))

      var icsEvents: [CalendarIcsEvent] = []
      icsEvents.reserveCapacity(componentRows.count)

      for row in componentRows {
        var uid: String?
        var recurrenceID: CalendarIcsRecurrenceID?
        var recurrence = row.recurrence
        var recurrenceExceptions = row.recurrenceExceptions

        if let seriesID = row.seriesId {
          guard row.occurrenceState == .replacement,
                let occurrenceDate = row.recurrenceInstanceDate
          else {
            continue
          }
          let master: CalendarEventRow
          if let cached = mastersByID[seriesID] {
            master = cached
          } else if let loaded = try CalendarTimelineQueries.getCalendarEvent(
            db, id: seriesID)
          {
            master = loaded
            mastersByID[seriesID] = loaded
          } else {
            throw LorvexCoreError.unsupportedOperation(
              "Calendar replacement '\(row.id)' has no exportable series master")
          }
          guard case let .success(originalDate) = LorvexDate.parse(occurrenceDate) else {
            throw LorvexCoreError.unsupportedOperation(
              "Calendar replacement '\(row.id)' has an invalid recurrence instance date")
          }
          uid = seriesID
          if master.allDay {
            recurrenceID = .date(originalDate)
          } else if let originalTime = master.startTime {
            recurrenceID = .dateTime(
              date: originalDate, time: originalTime, timezone: master.timezone)
          } else {
            throw LorvexCoreError.unsupportedOperation(
              "Calendar series '\(seriesID)' has no time for its timed recurrence instance")
          }
          recurrenceExceptions = nil
        } else if row.recurrence != nil {
          recurrence = try Self.effectiveExternalCalendarRecurrence(
            row: row, ownership: ownershipByMasterID[row.id])
          let decisions: [CalendarEventRow]
          if let cached = decisionsByMasterID[row.id] {
            decisions = cached
          } else {
            let loaded = try CalendarTimelineQueries.listActiveCalendarOccurrenceDecisions(
              db, seriesId: row.id)
            decisionsByMasterID[row.id] = loaded
            decisions = loaded
          }
          let cancelledDates = decisions.compactMap { decision -> String? in
            decision.occurrenceState == .cancelled ? decision.recurrenceInstanceDate : nil
          }
          recurrenceExceptions = try Self.icsExceptionJSON(cancelledDates)
        }

        let fields = CalendarIcsEventFields(
          id: row.id, uid: uid, recurrenceID: recurrenceID,
          title: row.title, description: row.description,
          recurrence: recurrence, recurrenceExceptions: recurrenceExceptions,
          startDate: row.startDate, startTime: row.startTime, endDate: row.endDate,
          endTime: row.endTime, allDay: row.allDay, location: row.location,
          timezone: row.timezone, createdAt: row.createdAt, updatedAt: row.updatedAt,
          sequence: 0)
        switch CalendarIcsEvent.make(fields) {
        case .success(let event): icsEvents.append(event)
        case .failure(let error):
          throw LorvexCoreError.unsupportedOperation(
            "Calendar event '\(row.id)' is not ICS-exportable: \(error)")
        }
      }
      switch exportCalendarIcs(icsEvents) {
      case .success(let ics): return ics
      case .failure(let error):
        throw LorvexCoreError.unsupportedOperation("ICS export failed: \(error.description)")
      }
    }
  }

  private static func icsExceptionJSON(_ dates: [String]) throws -> String? {
    guard !dates.isEmpty else { return nil }
    let data = try JSONEncoder().encode(dates)
    guard let json = String(data: data, encoding: .utf8) else {
      throw LorvexCoreError.unsupportedOperation(
        "Calendar cancellation dates could not be encoded for ICS export")
    }
    return json
  }

  private static func icsRowLess(_ lhs: CalendarEventRow, _ rhs: CalendarEventRow) -> Bool {
    if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
    switch (lhs.startTime, rhs.startTime) {
    case let (left?, right?):
      if left != right { return left < right }
    case (.some, nil): return true
    case (nil, .some): return false
    case (nil, nil): break
    }
    return lhs.id.utf8.lexicographicallyPrecedes(rhs.id.utf8)
  }
}
