import Foundation
import GRDB
import LorvexDomain

extension CalendarTimelineQueries {

  /// Retrieve time ranges that block scheduling on a single `date`, derived
  /// from the same projected-occurrence stream as the timeline query. All-day
  /// events are excluded (they block the date, not a minute window).
  /// Ranges are deliberately not merged: every occurrence retains its own
  /// canonical/provider provenance for display and persisted focus blocks.
  /// Callers that pack tasks separately union only the occupancy spans. Sorted
  /// deterministically by `(start_minutes ASC, end_minutes DESC, source ASC,
  /// canonical_event_id ASC, title ASC)`.
  public static func getDayBlockingRanges(
    _ db: Database, date: String, anchorTimezone: String, accessMode: CalendarAiAccessMode
  ) throws -> [BlockingEventRange] {
    guard let queryDate = try? CalendarRecurrence.parseYmd(date) else {
      throw StoreError.validation("date: invalid YYYY-MM-DD")
    }

    let staleScopes = try providerStaleScopes(db)

    var items = try queryCanonicalTimeline(db, queryDate, queryDate, anchorTimezone)

    if accessMode.includesProvider {
      var providerItems = try queryProviderTimeline(db, queryDate, queryDate, anchorTimezone)
      if !accessMode.includesDetails {
        for i in providerItems.indices {
          redactProviderDetails(&providerItems[i])
        }
      }
      items.append(contentsOf: providerItems)
    }

    var ranges: [BlockingEventRange] = []
    for item in items {
      if let range = timelineItemToBlockingRange(item, queryDate, staleScopes) {
        ranges.append(range)
      }
    }

    ranges.sort { a, b in
      if a.startMinutes != b.startMinutes { return a.startMinutes < b.startMinutes }
      if a.endMinutes != b.endMinutes { return a.endMinutes > b.endMinutes }
      if a.source != b.source { return a.source.rawValue < b.source.rawValue }
      let aID = a.canonicalEventId ?? ""
      let bID = b.canonicalEventId ?? ""
      if aID != bID { return aID < bID }
      if a.title != b.title {
        return a.title.utf8.lexicographicallyPrecedes(b.title.utf8)
      }
      return !a.stale && b.stale
    }

    return ranges
  }

  static func timelineItemToBlockingRange(
    _ item: CalendarTimelineItem, _ queryDate: RDate, _ staleScopes: Set<ScopeKey>
  ) -> BlockingEventRange? {
    if item.allDay { return nil }

    guard let startDate = try? CalendarRecurrence.parseYmd(item.startDate.asString) else {
      return nil
    }
    let endDate: RDate
    if let ed = item.endDate, let parsed = try? CalendarRecurrence.parseYmd(ed.asString) {
      endDate = parsed
    } else {
      endDate = startDate
    }
    if startDate > queryDate || endDate < queryDate { return nil }

    let startMinutes: Int64
    if startDate < queryDate {
      startMinutes = 0
    } else {
      guard let st = item.startTime else { return nil }
      startMinutes = Int64(st.hour * 60 + st.minute)
    }

    let endMinutes: Int64
    if endDate > queryDate {
      endMinutes = 1440
    } else if let et = item.endTime {
      endMinutes = Int64(et.hour * 60 + et.minute)
    } else {
      // Timed event without explicit end_time: an RFC 5545 §3.6.1 point
      // event — zero-length, filtered out by the guard below.
      endMinutes = startMinutes
    }

    if endMinutes <= startMinutes || startMinutes >= 1440 { return nil }

    let stale: Bool
    if let kind = item.providerKind, let scope = item.providerScope {
      stale = staleScopes.contains(ScopeKey(kind: kind, scope: scope))
    } else {
      stale = false
    }

    return BlockingEventRange(
      source: item.source,
      // Persist the stable source-event address, not the expanded occurrence's
      // derived UI identity. Natural recurring occurrences have no row of their
      // own, so saving `item.id` would leave focus references that a later
      // series delete/cutover cannot enumerate or clean up.
      canonicalEventId: item.source == .canonical ? item.eventId : nil,
      title: item.title,
      startMinutes: max(startMinutes, 0),
      endMinutes: min(endMinutes, 1440),
      stale: stale)
  }

  /// `(provider_kind, provider_scope)` pairs whose last successful refresh is
  /// older than 24 hours. The cutoff uses `strftime('%Y-%m-%dT%H:%M:%fZ', …)`
  /// so the `T`-separated RFC 3339 `last_refresh_success_at` lex-compares
  /// correctly.
  static func providerStaleScopes(_ db: Database) throws -> Set<ScopeKey> {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT provider_kind, provider_scope FROM provider_scope_runtime_state \
        WHERE last_refresh_success_at IS NOT NULL \
          AND last_refresh_success_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-24 hours')
        """)
    var out: Set<ScopeKey> = []
    for row in rows {
      out.insert(ScopeKey(kind: row[0], scope: row[1]))
    }
    return out
  }

  /// `(provider_kind, provider_scope)` key for the stale-scope set.
  struct ScopeKey: Hashable {
    let kind: String
    let scope: String
  }
}
