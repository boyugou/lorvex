import Foundation
import GRDB

extension ProviderRepo {
  /// Replace observations inside the fetched instant window, retaining cached
  /// occurrences outside it. Missing series clear only their in-window slots:
  /// an empty week is authoritative too, not permission to invent a recurrence.
  /// Call inside the ingest transaction, before upserting the returned rows.
  public static func reconcileOccurrenceInstants(
    _ db: Database, events: [ProviderEventData], providerKind: String, scope: String,
    window: DateInterval, now: String
  ) throws -> [ProviderEventData] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT provider_event_key, recurrence, occurrence_instants
        FROM provider_calendar_events
        WHERE provider_kind = ? AND provider_scope = ? AND occurrence_instants IS NOT NULL
          AND last_seen_at <= ?
        """, arguments: [providerKind, scope, now])
    let fetchedKeys = Set(events.map(\.providerEventKey))
    var retained: [String: [ProviderOccurrenceInstant]] = [:]
    for row in rows {
      let key: String = row[0]
      guard let json: String = row[2], let old = ProviderOccurrenceInstant.decode(json) else {
        continue
      }
      let outside = old.filter { occurrence in
        if let end = occurrence.end, end > occurrence.start {
          return end <= window.start || occurrence.start >= window.end
        }
        return occurrence.start < window.start || occurrence.start >= window.end
      }
      retained[key] = outside
      if !fetchedKeys.contains(key), outside != old {
        if (row[1] as String?) == nil {
          try deleteProviderEvent(
            db, providerKind: providerKind, providerScope: scope,
            providerEventKey: key)
          continue
        }
        try db.execute(
          sql: """
            UPDATE provider_calendar_events SET occurrence_instants = ?, last_seen_at = ?
            WHERE provider_kind = ? AND provider_scope = ? AND provider_event_key = ?
            """,
          arguments: [ProviderOccurrenceInstant.encode(outside), now, providerKind, scope, key])
      }
    }
    return events.map { event in
      guard event.recurrence != nil, let json = event.occurrenceInstants,
        let incoming = ProviderOccurrenceInstant.decode(json)
      else { return event }
      var merged = event
      // An occurrence moved into this window replaces the old observation of
      // the same source slot even if the old instant was outside the window.
      let exclusions =
        event.recurrenceExceptions.flatMap {
          try? JSONDecoder().decode([String].self, from: Data($0.utf8))
        } ?? []
      let incomingDates = Set(incoming.map(\.date)).union(exclusions)
      let outside = (retained[event.providerEventKey] ?? []).filter {
        !incomingDates.contains($0.date)
      }
      merged.occurrenceInstants = ProviderOccurrenceInstant.encode(outside + incoming)
      return merged
    }
  }
}
