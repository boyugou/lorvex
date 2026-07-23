import LorvexDomain

/// CloudKit slot conflicts whose current canonical fields require a typed join,
/// not an outer-envelope last-writer-wins choice.
public enum SemanticPushConflictKind: String, Sendable, Equatable {
  case taskRegisters
  case calendarBaseRegisters
  case calendarSeriesCutover
  case entityRedirect
}

/// One transport-facing classifier for every entity whose push conflict must be
/// consumed by the transactional sync core. Keeping this inventory beside the
/// payload contracts prevents the CloudKit adapter from growing a second,
/// incomplete copy of domain merge semantics.
public enum SemanticPushConflictRouting {
  public static func classify(
    client: SyncEnvelope, server: SyncEnvelope
  ) throws -> SemanticPushConflictKind? {
    guard client.entityType == server.entityType,
      client.entityId == server.entityId,
      server.payloadSchemaVersion <= LorvexVersion.payloadSchemaVersion
    else { return nil }

    let clientAcceptance = Capability.checkEnvelopeVersion(
      envelopePayloadVersion: client.payloadSchemaVersion,
      localMaxVersion: LorvexVersion.payloadSchemaVersion)
    let clientCurrentFieldsAreReadable =
      clientAcceptance == .parseFully || clientAcceptance == .parseForwardCompat
    guard clientCurrentFieldsAreReadable else { return nil }

    switch client.entityType {
    case .task:
      guard try isFullyKnownTaskUpsert(client), try isFullyKnownTaskUpsert(server)
      else { return nil }
      return .taskRegisters

    case .calendarEvent:
      guard try CalendarEventRegisterConflictRouting.isFullyKnownBaseUpsert(
        client, allowForwardCompatibleSchema: true),
        try CalendarEventRegisterConflictRouting.isFullyKnownBaseUpsert(server)
      else { return nil }
      return .calendarBaseRegisters

    case .calendarSeriesCutover:
      guard try isFullyKnownUpsert(client, kind: .calendarSeriesCutover),
        try isFullyKnownUpsert(server, kind: .calendarSeriesCutover)
      else { return nil }
      return .calendarSeriesCutover

    case .entityRedirect:
      // Redirects are deliberately held rather than partially promoted by Apply;
      // they therefore remain a current/current-only semantic collision.
      guard clientAcceptance == .parseFully,
        try isFullyKnownUpsert(client, kind: .entityRedirect),
        try isFullyKnownUpsert(server, kind: .entityRedirect)
      else { return nil }
      return .entityRedirect

    default:
      return nil
    }
  }

  private static func isFullyKnownUpsert(
    _ envelope: SyncEnvelope, kind: EntityKind
  ) throws -> Bool {
    guard envelope.entityType == kind, envelope.operation == .upsert else { return false }
    try SyncPayloadContractRegistry.validate(envelope)
    return true
  }

  private static func isFullyKnownTaskUpsert(_ envelope: SyncEnvelope) throws -> Bool {
    guard try isFullyKnownUpsert(envelope, kind: .task),
      case .object(let object)? = JSONValue.parse(envelope.payload),
      object["id"] == .string(envelope.entityId)
    else { return false }

    for key in [
      "content_version", "schedule_version", "lifecycle_version", "archive_version",
    ] {
      guard case .string(let raw)? = object[key],
        try Hlc.parseCanonical(raw) <= envelope.version
      else { return false }
    }
    return true
  }
}
