import LorvexDomain

/// Identifies calendar mutations whose CloudKit slot conflicts must be joined
/// through the base event's independent content and recurrence-topology
/// registers instead of resolved by the envelope's transport version alone.
public enum CalendarEventRegisterConflictRouting {
  /// Return whether an envelope is a base-event upsert whose current fields can
  /// be passed to the current runtime's grouped calendar merge.
  ///
  /// Future-schema snapshots are excluded by default because an unknown field's
  /// register ownership is unknowable until that schema is implemented. The
  /// transport conflict classifier may explicitly admit a one-version-ahead
  /// client: the current fields still require a semantic join, while payload
  /// shadow preserves the unknown fields. A future server remains excluded.
  /// The current payload contract is validated before classification so a
  /// malformed record can never opt into the specialized repair path merely by
  /// setting `series_id` to null.
  public static func isFullyKnownBaseUpsert(
    _ envelope: SyncEnvelope, allowForwardCompatibleSchema: Bool = false
  ) throws -> Bool {
    let acceptance = Capability.checkEnvelopeVersion(
      envelopePayloadVersion: envelope.payloadSchemaVersion,
      localMaxVersion: LorvexVersion.payloadSchemaVersion)
    guard envelope.entityType == .calendarEvent,
      envelope.operation == .upsert,
      acceptance == .parseFully
        || (allowForwardCompatibleSchema && acceptance == .parseForwardCompat)
    else { return false }

    try SyncPayloadContractRegistry.validate(envelope)
    guard case .object(let object)? = JSONValue.parse(envelope.payload),
      object["id"] == .string(envelope.entityId),
      object["series_id"] == .null,
      object["recurrence_instance_date"] == .null,
      object["occurrence_state"] == .null,
      case .string(let contentRaw)? = object["content_version"],
      case .string(let topologyRaw)? = object["recurrence_topology_version"]
    else { return false }

    let content = try Hlc.parseCanonical(contentRaw)
    let topology = try Hlc.parseCanonical(topologyRaw)
    guard content <= envelope.version, topology <= envelope.version else { return false }
    if case .string(let generationRaw)? = object["recurrence_generation"] {
      guard try Hlc.parseCanonical(generationRaw) <= envelope.version else { return false }
    }
    return true
  }
}
