import Foundation
import LorvexDomain
@preconcurrency import CloudKit

/// Codec for the singleton generation-control record in the private default zone.
enum CloudSyncZoneEpochRecord {
  static let recordType = "LorvexZoneEpoch"
  static let recordName = "lorvex-zone-epoch"
  static let homeZoneID = CKRecordZone.default().zoneID

  static let protocolVersionField = "protocol_version"
  static let epochField = "epoch"
  static let stateField = "state"
  static let activeEpochField = "active_epoch"
  static let generationIDField = "generation_id"
  static let activeZoneField = "active_zone"
  static let readyWitnessField = "ready_witness"
  static let candidateGenerationIDField = "candidate_generation_id"
  static let candidateZoneField = "candidate_zone"
  static let rebuildIdentifierField = "rebuild_id"
  static let rebuildOwnerField = "rebuild_owner"
  static let rebuildPhaseField = "rebuild_phase"
  static let leaseActivityAtField = "lease_activity_at"
  static let retiredZonesField = "retired_zones_json"
  static let tombstoneCompactionCutoffField = "tombstone_compaction_cutoff"

  static let readyState = "ready"
  static let rebuildingState = "rebuilding"
  static let deletedState = "deleted"
  static let protocolVersion = 3

  static func recordID(zoneID: CKRecordZone.ID = homeZoneID) -> CKRecord.ID {
    CKRecord.ID(recordName: recordName, zoneID: zoneID)
  }

  static func makeRecord(zoneID: CKRecordZone.ID = homeZoneID) -> CKRecord {
    CKRecord(recordType: recordType, recordID: recordID(zoneID: zoneID))
  }

  static func generationState(from record: CKRecord) -> CloudSyncZoneGenerationState? {
    guard record.recordType == recordType,
      integer(record[protocolVersionField]) == protocolVersion,
      let epoch = integer(record[epochField]), epoch >= 0,
      epoch <= CloudSyncGenerationNaming.maximumGeneration,
      let state = record[stateField] as? String,
      let retired = retiredZoneNames(from: record)
    else { return nil }

    switch state {
    case readyState:
      guard integer(record[activeEpochField]) == epoch,
        let descriptor = readyDescriptor(from: record, epoch: epoch),
        decodedIdentifier(record[rebuildIdentifierField]) != nil,
        decodedIdentifier(record[rebuildOwnerField]) != nil,
        record[candidateGenerationIDField] == nil,
        record[candidateZoneField] == nil,
        record[rebuildPhaseField] == nil,
        record[leaseActivityAtField] == nil,
        !retired.contains(descriptor.zoneName)
      else { return nil }
      return .ready(
        descriptor: descriptor, retiredZoneNames: retired,
        modifiedAt: record.modificationDate)

    case rebuildingState:
      guard let identifier = decodedIdentifier(record[rebuildIdentifierField]),
        let owner = decodedIdentifier(record[rebuildOwnerField]),
        let generationID = decodedIdentifier(record[candidateGenerationIDField]),
        let candidateZone = zoneName(record[candidateZoneField]),
        CloudSyncGenerationNaming.isValidGenerationZoneName(
          candidateZone, epoch: epoch, generationID: generationID),
        let phaseRaw = record[rebuildPhaseField] as? String,
        let phase = CloudSyncZoneRebuildPhase(rawValue: phaseRaw),
        let leaseActivityAt = canonicalTimestamp(record[leaseActivityAtField])
      else { return nil }
      let previousActive: CloudSyncGenerationDescriptor?
      let activeValues = [
        record[activeEpochField], record[generationIDField],
        record[activeZoneField], record[readyWitnessField],
      ]
      if activeValues.allSatisfy({ $0 == nil }) {
        guard record[tombstoneCompactionCutoffField] == nil else { return nil }
        previousActive = nil
      } else {
        guard let activeEpoch = integer(record[activeEpochField]), activeEpoch >= 0,
          activeEpoch <= CloudSyncGenerationNaming.maximumGeneration,
          activeEpoch < epoch,
          let decoded = readyDescriptor(from: record, epoch: activeEpoch),
          decoded.zoneName != candidateZone
        else {
          return nil
        }
        previousActive = decoded
      }
      guard !retired.contains(candidateZone),
        previousActive.map({ !retired.contains($0.zoneName) }) ?? true
      else { return nil }
      return .rebuilding(
        lease: CloudSyncZoneRebuildLease(
          identifier: identifier, ownerIdentifier: owner, epoch: epoch,
          generationID: generationID, candidateZoneName: candidateZone),
        previousActive: previousActive, phase: phase, retiredZoneNames: retired,
        leaseActivityAt: leaseActivityAt)

    case deletedState:
      guard record[activeEpochField] == nil,
        record[generationIDField] == nil, record[activeZoneField] == nil,
        record[readyWitnessField] == nil,
        record[candidateGenerationIDField] == nil, record[candidateZoneField] == nil,
        record[rebuildIdentifierField] == nil, record[rebuildOwnerField] == nil,
        record[rebuildPhaseField] == nil,
        record[leaseActivityAtField] == nil
      else { return nil }
      guard record[tombstoneCompactionCutoffField] == nil else { return nil }
      return .deleted(
        deletionGeneration: epoch, retiredZoneNames: retired,
        modifiedAt: record.modificationDate)

    default:
      return nil
    }
  }

  static func stampRebuilding(
    _ lease: CloudSyncZoneRebuildLease,
    previousActive: CloudSyncGenerationDescriptor?,
    phase: CloudSyncZoneRebuildPhase,
    leaseActivityAt: Date,
    retiredZoneNames: [String],
    onto record: CKRecord
  ) {
    stampCommon(epoch: lease.epoch, state: rebuildingState, retiredZoneNames: retiredZoneNames, onto: record)
    stampActive(previousActive, onto: record)
    record[candidateGenerationIDField] = lease.generationID as CKRecordValue
    record[candidateZoneField] = lease.candidateZoneName as CKRecordValue
    record[rebuildIdentifierField] = lease.identifier as CKRecordValue
    record[rebuildOwnerField] = lease.ownerIdentifier as CKRecordValue
    record[rebuildPhaseField] = phase.rawValue as CKRecordValue
    record[leaseActivityAtField] =
      SyncTimestamp(date: leaseActivityAt).asString as CKRecordValue
    record[tombstoneCompactionCutoffField] =
      previousActive?.tombstoneCompactionCutoff as CKRecordValue?
  }

  static func stampReady(
    descriptor: CloudSyncGenerationDescriptor,
    completedLease: CloudSyncZoneRebuildLease,
    retiredZoneNames: [String],
    onto record: CKRecord
  ) {
    stampCommon(epoch: descriptor.epoch, state: readyState, retiredZoneNames: retiredZoneNames, onto: record)
    stampActive(descriptor, onto: record)
    record[candidateGenerationIDField] = nil
    record[candidateZoneField] = nil
    record[rebuildIdentifierField] = completedLease.identifier as CKRecordValue
    record[rebuildOwnerField] = completedLease.ownerIdentifier as CKRecordValue
    record[rebuildPhaseField] = nil
    record[leaseActivityAtField] = nil
    record[tombstoneCompactionCutoffField] =
      descriptor.tombstoneCompactionCutoff as CKRecordValue?
  }

  static func stampDeleted(
    deletionGeneration: Int, retiredZoneNames: [String], onto record: CKRecord
  ) {
    stampCommon(epoch: deletionGeneration, state: deletedState, retiredZoneNames: retiredZoneNames, onto: record)
    stampActive(nil, onto: record)
    record[candidateGenerationIDField] = nil
    record[candidateZoneField] = nil
    record[rebuildIdentifierField] = nil
    record[rebuildOwnerField] = nil
    record[rebuildPhaseField] = nil
    record[leaseActivityAtField] = nil
    record[tombstoneCompactionCutoffField] = nil
  }

  static func completedLease(from record: CKRecord) -> CloudSyncZoneRebuildLease? {
    guard case .ready(let descriptor, _, _) = generationState(from: record),
      let identifier = decodedIdentifier(record[rebuildIdentifierField]),
      let owner = decodedIdentifier(record[rebuildOwnerField])
    else { return nil }
    return CloudSyncZoneRebuildLease(
      identifier: identifier, ownerIdentifier: owner, epoch: descriptor.epoch,
      generationID: descriptor.generationID, candidateZoneName: descriptor.zoneName)
  }

  /// Replace only the bounded retirement ledger on an already validated state.
  /// Retired-zone cleanup must not synthesize or rewrite lease provenance.
  static func replaceRetiredZoneNames(_ names: [String], on record: CKRecord) {
    precondition(CloudSyncGenerationNaming.validatedRetiredZoneNames(names) != nil)
    record[retiredZonesField] = encodedRetiredZoneNames(names) as CKRecordValue
  }

  private static func stampCommon(
    epoch: Int, state: String, retiredZoneNames: [String], onto record: CKRecord
  ) {
    precondition(epoch >= 0 && epoch <= CloudSyncGenerationNaming.maximumGeneration)
    precondition(CloudSyncGenerationNaming.validatedRetiredZoneNames(retiredZoneNames) != nil)
    record[protocolVersionField] = protocolVersion as CKRecordValue
    record[epochField] = epoch as CKRecordValue
    record[stateField] = state as CKRecordValue
    record[retiredZonesField] = encodedRetiredZoneNames(retiredZoneNames) as CKRecordValue
  }

  private static func stampActive(
    _ descriptor: CloudSyncGenerationDescriptor?, onto record: CKRecord
  ) {
    record[activeEpochField] = descriptor?.epoch as CKRecordValue?
    record[generationIDField] = descriptor?.generationID as CKRecordValue?
    record[activeZoneField] = descriptor?.zoneName as CKRecordValue?
    record[readyWitnessField] = descriptor?.readyWitness as CKRecordValue?
  }

  private static func readyDescriptor(
    from record: CKRecord, epoch: Int
  ) -> CloudSyncGenerationDescriptor? {
    guard let generationID = decodedIdentifier(record[generationIDField]),
      let activeZone = zoneName(record[activeZoneField]),
      CloudSyncGenerationNaming.isValidGenerationZoneName(
        activeZone, epoch: epoch, generationID: generationID),
      let readyWitness = decodedIdentifier(record[readyWitnessField])
    else { return nil }
    let cutoff: String?
    if let raw = record[tombstoneCompactionCutoffField] {
      guard let value = raw as? String,
        let parsed = SyncTimestamp.parse(value), parsed.asString == value
      else { return nil }
      cutoff = value
    } else {
      cutoff = nil
    }
    return CloudSyncGenerationDescriptor(
      epoch: epoch, generationID: generationID, zoneName: activeZone,
      readyWitness: readyWitness, tombstoneCompactionCutoff: cutoff)
  }

  private static func integer(_ raw: CKRecordValue?) -> Int? {
    CloudSyncRecordValueCodec.nonnegativeInt(raw)
  }

  private static func canonicalTimestamp(_ raw: CKRecordValue?) -> Date? {
    guard let value = raw as? String,
      let timestamp = SyncTimestamp.parse(value),
      timestamp.asString == value
    else { return nil }
    return timestamp.date
  }

  private static func decodedIdentifier(_ raw: CKRecordValue?) -> String? {
    guard let value = raw as? String, CloudSyncGenerationNaming.isValidIdentifier(value) else {
      return nil
    }
    return value
  }

  private static func zoneName(_ raw: CKRecordValue?) -> String? {
    guard let value = raw as? String, CloudSyncGenerationNaming.isValidZoneName(value) else {
      return nil
    }
    return value
  }

  private static func encodedRetiredZoneNames(_ names: [String]) -> String {
    let data = try? JSONEncoder().encode(names)
    return data.map { String(decoding: $0, as: UTF8.self) } ?? "[]"
  }

  private static func retiredZoneNames(from record: CKRecord) -> [String]? {
    guard let raw = record[retiredZonesField] as? String,
      let data = raw.data(using: .utf8),
      let names = try? JSONDecoder().decode([String].self, from: data)
    else { return nil }
    return CloudSyncGenerationNaming.validatedRetiredZoneNames(names)
  }
}
