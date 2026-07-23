import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func loadCalendarTimeline(from: String, to: String) async throws
    -> CalendarTimelineSnapshot
  {
    try read { db in
      let anchorTimezone = try WorkflowTimezone.activeTimezoneName(db) ?? TimeZone.current.identifier
      // Honor the effective calendar AI-access tier so a busy/off read redacts
      // provider detail even if a full-detail row somehow survives at rest —
      // defense in depth behind ingest-time redaction + downgrade purge. Read
      // inside the same transaction; a malformed persisted tier fails the read
      // (fail closed) rather than leaking full detail.
      let accessMode = try DeviceStateRepo.readCalendarAiAccessMode(db)
      let items = try CalendarTimelineQueries.getCalendarTimeline(
        db, from: from, to: to, accessMode: accessMode, anchorTimezone: anchorTimezone)
      return CalendarTimelineSnapshot(
        from: from,
        to: to,
        events: items.map(SwiftLorvexCalendarDeserializers.event),
        truncated: false,
        nextOffset: nil)
    }
  }

  public func searchCalendarEvents(
    query: String,
    from: String?,
    to: String?,
    limit: Int?,
    offset: Int
  ) async throws -> [CalendarTimelineEvent] {
    try read { db in
      let pageSize = min(max(1, limit ?? 50), 500)
      let startAt = max(0, offset)
      // Over-fetch so the requested page still fills after dropping `offset`:
      // the global top-(offset+pageSize) rows are contained in each source's own
      // top-(offset+pageSize), so a per-source cap of that bound is safe. Capped
      // to keep a large offset from asking the store for an unbounded scan.
      let cap = UInt32(min(startAt + pageSize, 5000))
      let predicate = CalendarSearchPredicate(query: query, from: from, to: to)

      let canonicalRows = try CalendarTimelineQueries.searchCalendarEvents(
        db, predicate: predicate, limit: cap)
      var events: [CalendarTimelineEvent] = canonicalRows.map(
        SwiftLorvexCalendarDeserializers.event)

      // The AI calendar timeline includes the provider/EventKit mirror, so
      // search does too — but only at the full-detail tier. Read the effective
      // calendar AI-access tier in the same transaction (fail closed on a
      // malformed value). `off` contributes no provider data; `busy_only` would
      // redact every hit to a bare "Busy" occupancy row, so a title / location /
      // person LIKE scan over it is both meaningless AND a match/no-match oracle
      // over detail the tier forbids — so the provider merge is skipped entirely
      // below full detail (mirroring how the timeline gates provider inclusion).
      // Merged hits are re-sorted by (start_date, start_time NULLS LAST, id) and
      // the cap re-applied below.
      let accessMode = try DeviceStateRepo.readCalendarAiAccessMode(db)
      if accessMode.includesDetails {
        let providerItems = try CalendarTimelineQueries.searchProviderCalendarEvents(
          db, predicate: predicate, limit: cap)
        events.append(contentsOf: providerItems.map(SwiftLorvexCalendarDeserializers.event))
      }

      events.sort { lhs, rhs in
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        switch (lhs.startTime, rhs.startTime) {
        case let (l?, r?):
          if l != r { return l < r }
        case (.some, nil):
          return true
        case (nil, .some):
          return false
        case (nil, nil):
          break
        }
        return lhs.id < rhs.id
      }
      return Array(events.dropFirst(startAt).prefix(pageSize))
    }
  }
}
