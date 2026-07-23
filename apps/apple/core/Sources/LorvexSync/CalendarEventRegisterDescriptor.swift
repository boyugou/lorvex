import LorvexDomain

/// Single field-ownership source for the independent base calendar registers.
/// Replay copies these groups, while outbox coalescing compares the same groups
/// before carrying local provenance onto a replacement payload.
enum CalendarEventRegisterDescriptor {
  static let contentFields = [
    "title", "description", "location", "url", "color",
    "event_type", "person_name", "attendees",
  ]

  static let topologyFields = [
    "start_date", "start_time", "end_date", "end_time", "all_day",
    "timezone", "recurrence", "recurrence_generation",
  ]

  static let contentSnapshotKeys = contentFields + ["content_version"]
  static let topologySnapshotKeys = topologyFields + ["recurrence_topology_version"]

  private static let baseIdentityAndMetadataKeys = [
    "id", "series_cutover_id", "series_id", "recurrence_instance_date", "occurrence_state",
    "created_at", "updated_at", "version",
  ]

  static func knownBasePayload(
    from source: [String: JSONValue]
  ) -> [String: JSONValue] {
    let knownKeys = Set(
      baseIdentityAndMetadataKeys + contentSnapshotKeys + topologySnapshotKeys)
    return source.filter { knownKeys.contains($0.key) }
  }

  static func snapshotsMatch(
    keys: [String], lhs: [String: JSONValue], rhs: [String: JSONValue]
  ) -> Bool {
    keys.allSatisfy { key in
      guard let left = lhs[key], let right = rhs[key] else { return false }
      return left == right
    }
  }
}
