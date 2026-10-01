@preconcurrency import CloudKit
import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync

/// What the transport does with one record CloudKit rejected with
/// `serverRecordChanged`.
///
/// CloudKit's change tag is a write barrier, not the conflict authority; the
/// envelope's HLC and Core's typed joins are. Each outcome says how the
/// rejected outbox rows and the server record are consumed.
enum CloudSyncConflictOutcome: Equatable {
  /// Server and client carry the same mutation. Confirm the outbox rows and
  /// cache the server record's system fields.
  case confirm
  /// The server's envelope is newer. Apply it locally, confirm the outbox
  /// rows, and cache the server record's system fields after that commit.
  case applyServer(SyncEnvelope)
  /// The local envelope is newer. Cache the server record's system fields and
  /// send the record again, now on top of the current change tag.
  case resave
  /// The contenders need Core's transactional join (typed register merge,
  /// equal-HLC contenders, a redirect delete, or a corrupt server slot).
  case collision(OutboundCollisionKind)
  /// The server holds a schema-ahead record this build cannot apply. Park it
  /// and hold the local intent until a build that understands it arrives.
  case park(RawEnvelopeFields)
  /// The slot cannot be reconciled; record a per-record failure.
  case fail(String)
}

/// Classifies a `serverRecordChanged` rejection from the client record that
/// was sent and the server record CloudKit returned.
///
/// The order matters. Structural mismatches fail first. A server payload that
/// violates the payload manifest is a corrupt slot for Core to repair. A
/// schema-ahead server record is parked before any HLC comparison, so an older
/// build's clock advantage can never overwrite fields it does not understand.
/// Current-schema typed joins are routed to Core. Only then does the outer HLC
/// decide between confirm, apply, and resave.
enum CloudSyncConflictClassifier {
  static func classify(client: CKRecord, server: CKRecord) -> CloudSyncConflictOutcome {
    guard server.recordType == CloudSyncEnvelopeRecord.recordType,
      client.recordType == CloudSyncEnvelopeRecord.recordType,
      server.recordID == client.recordID
    else { return .fail("serverRecordChanged returned a foreign or mismatched record slot") }
    guard CloudSyncEnvelopeRecord.hasIdenticalEnvelopeIdentity(client, server) else {
      return .fail("serverRecordChanged returned a foreign embedded entity identity")
    }
    guard let localVersion = CloudSyncEnvelopeRecord.versionString(from: client),
      (try? Hlc.parseCanonical(localVersion)) != nil
    else { return .fail("serverRecordChanged returned an invalid client version") }
    let serverVersion = CloudSyncEnvelopeRecord.versionString(from: server) ?? ""
    let clientOutcome = CloudSyncEnvelopeRecord.decode(client)
    let serverOutcome = CloudSyncEnvelopeRecord.decode(server)

    if case .decoded(let serverEnvelope) = serverOutcome {
      let violations: [String]
      do {
        violations = try SyncPayloadTransportValidation.violations(for: serverEnvelope)
      } catch {
        return .fail("server payload validation failed: \(error)")
      }
      if !violations.isEmpty {
        if serverEnvelope.entityType == .entityRedirect, serverEnvelope.operation == .delete {
          return .collision(.entityRedirectDelete(serverEnvelope: serverEnvelope))
        }
        return .collision(.corruptServerSlot(serverVersionFloor: serverEnvelope.version))
      }
    }
    if case .unknownEntityType(let raw) = serverOutcome { return .park(raw) }

    if case .decoded(let clientEnvelope) = clientOutcome,
      case .decoded(let serverEnvelope) = serverOutcome
    {
      do {
        if try SyncMutationSemantics.isExactSemanticReplay(clientEnvelope, serverEnvelope) {
          return .confirm
        }
        if serverEnvelope.payloadSchemaVersion > LorvexVersion.payloadSchemaVersion {
          return .park(Self.raw(serverEnvelope))
        }
        if clientEnvelope.entityType == .entityRedirect, clientEnvelope.operation == .upsert,
          serverEnvelope.entityType == .entityRedirect, serverEnvelope.operation == .delete
        {
          return .collision(.entityRedirectDelete(serverEnvelope: serverEnvelope))
        }
        if let kind = try SemanticPushConflictRouting.classify(
          client: clientEnvelope, server: serverEnvelope)
        {
          return .collision(.semanticMerge(kind: kind, serverEnvelope: serverEnvelope))
        }
      } catch {
        return .fail("semantic conflict classification failed: \(error)")
      }
    }

    switch resolveCloudSyncPushConflict(localVersion: localVersion, serverVersion: serverVersion) {
    case .equalConfirm:
      switch (clientOutcome, serverOutcome) {
      case (.decoded, .decoded(let serverEnvelope)):
        // An exact replay returned above, so equal HLCs here carry different
        // content: two writers reused one HLC.
        return .collision(.equalVersion(serverEnvelope: serverEnvelope))
      case (_, .corrupt):
        return .collision(
          .corruptServerSlot(serverVersionFloor: try? Hlc.parseCanonical(serverVersion)))
      case (_, .foreign):
        return .fail("equal-version conflict returned a foreign server record")
      default:
        return .fail("equal-version conflict returned an invalid client record")
      }
    case .serverWinsConfirmAndApply:
      switch serverOutcome {
      case .decoded(let serverEnvelope):
        return .applyServer(serverEnvelope)
      case .corrupt:
        return .collision(
          .corruptServerSlot(serverVersionFloor: try? Hlc.parseCanonical(serverVersion)))
      case .unknownEntityType(let raw):
        return .park(raw)
      case .foreign:
        return .fail("server-wins conflict returned a foreign server record")
      }
    case .localWinsResaveOntoServer:
      return .resave
    case .corruptServerSlot:
      return .collision(.corruptServerSlot(serverVersionFloor: nil))
    }
  }

  private static func raw(_ envelope: SyncEnvelope) -> RawEnvelopeFields {
    RawEnvelopeFields(
      entityType: envelope.entityType.asString,
      entityId: envelope.entityId,
      operation: envelope.operation.asString,
      version: envelope.version.description,
      payloadSchemaVersion: envelope.payloadSchemaVersion,
      payload: envelope.payload,
      deviceId: envelope.deviceId)
  }
}
