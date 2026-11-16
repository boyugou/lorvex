import GRDB
import LorvexDomain

extension ProviderRepo {
  /// Repair links whose old UID was proven unique by the EventKit adapter.
  /// Ambiguous UIDs keep their unresolved link rather than choosing a copy.
  public static func reassociateLegacyEventKitLinks(
    _ db: Database, events: [ProviderEventData], now: String
  ) throws {
    let aliases = Dictionary(grouping: events.filter { $0.previousEventKey != nil }) {
      $0.previousEventKey ?? ""
    }
    for (old, candidates) in aliases {
      guard let event = candidates.first, !old.isEmpty,
        Set(candidates.map(\.providerEventKey)).count == 1,
        old != event.providerEventKey, event.providerKind == ProviderKind.eventkit
      else { continue }
      try db.execute(
        sql: """
          INSERT OR IGNORE INTO task_provider_event_links
            (task_id, provider_kind, provider_scope, provider_event_key, created_at, updated_at)
          SELECT task_id, provider_kind, provider_scope, ?, created_at, ?
          FROM task_provider_event_links
          WHERE provider_kind = ? AND provider_scope = ? AND provider_event_key = ?
          """,
        arguments: [event.providerEventKey, now, event.providerKind, event.providerScope, old])
      try db.execute(
        sql: """
          DELETE FROM task_provider_event_links
          WHERE provider_kind = ? AND provider_scope = ? AND provider_event_key = ?
          """, arguments: [event.providerKind, event.providerScope, old])
    }
  }
}
