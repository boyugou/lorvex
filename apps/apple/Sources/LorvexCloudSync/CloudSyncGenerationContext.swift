import Foundation
import LorvexSync
@preconcurrency import CloudKit

/// Immutable identity of one complete CloudKit entity-zone generation.
public struct CloudSyncGenerationDescriptor: Sendable, Equatable, Codable {
  public static let rootRecordName = "lorvex-generation-root"

  public var epoch: Int
  public var generationID: String
  public var zoneName: String
  public var readyWitness: String
  /// Server-derived delete-recovery horizon frozen into this generation.
  /// A peer may union local state only after a server-timestamped terminal
  /// traversal proves it covered this instant; otherwise it adopts the ready
  /// generation authoritatively.
  public var tombstoneCompactionCutoff: String?

  public init(
    epoch: Int, generationID: String, zoneName: String, readyWitness: String,
    tombstoneCompactionCutoff: String? = nil
  ) {
    self.epoch = epoch
    self.generationID = generationID
    self.zoneName = zoneName
    self.readyWitness = readyWitness
    self.tombstoneCompactionCutoff = tombstoneCompactionCutoff
  }

  public var zoneID: CKRecordZone.ID {
    CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
  }
}

/// Account-qualified generation captured for one sync operation.
public struct CloudSyncGenerationContext: Sendable, Equatable {
  public var accountIdentifier: String
  public var epoch: Int
  public var generationID: String
  public var zoneName: String
  public var rebuildIdentifier: String?
  public var rebuildOwnerIdentifier: String?
  /// Present only for a published ready generation. A rebuilding candidate has
  /// no witness until its terminal seal is durably written and published.
  public var readyWitness: String?
  public var tombstoneCompactionCutoff: String?

  public init(accountIdentifier: String, descriptor: CloudSyncGenerationDescriptor) {
    self.accountIdentifier = accountIdentifier
    self.epoch = descriptor.epoch
    self.generationID = descriptor.generationID
    self.zoneName = descriptor.zoneName
    self.readyWitness = descriptor.readyWitness
    self.tombstoneCompactionCutoff = descriptor.tombstoneCompactionCutoff
    self.rebuildIdentifier = nil
    self.rebuildOwnerIdentifier = nil
  }

  public init(accountIdentifier: String, lease: CloudSyncZoneRebuildLease) {
    self.accountIdentifier = accountIdentifier
    self.epoch = lease.epoch
    self.generationID = lease.generationID
    self.zoneName = lease.candidateZoneName
    self.readyWitness = nil
    self.tombstoneCompactionCutoff = nil
    self.rebuildIdentifier = lease.identifier
    self.rebuildOwnerIdentifier = lease.ownerIdentifier
  }

  public var zoneID: CKRecordZone.ID {
    CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
  }

  var rebuildLease: CloudSyncZoneRebuildLease? {
    guard let rebuildIdentifier, let rebuildOwnerIdentifier else { return nil }
    return CloudSyncZoneRebuildLease(
      identifier: rebuildIdentifier, ownerIdentifier: rebuildOwnerIdentifier,
      epoch: epoch, generationID: generationID, candidateZoneName: zoneName)
  }

  /// Exact local cursor witness. A candidate has no published ready witness,
  /// so its rebuild id scopes the ephemeral readback cursor instead.
  var checkpointWitness: String {
    if let readyWitness { return readyWitness }
    return "rebuild:\(rebuildIdentifier ?? "invalid")"
  }

  func matches(_ expectation: CloudSyncGenerationExpectation) -> Bool {
    switch expectation {
    case .ready(let descriptor):
      return self == CloudSyncGenerationContext(
        accountIdentifier: accountIdentifier, descriptor: descriptor)
    case .rebuilding(let lease):
      return self == CloudSyncGenerationContext(
        accountIdentifier: accountIdentifier, lease: lease)
    case .previousActive(_, let descriptor):
      return self == CloudSyncGenerationContext(
        accountIdentifier: accountIdentifier, descriptor: descriptor)
    }
  }
}

/// Durable phase of one candidate-zone rebuild.
public enum CloudSyncZoneRebuildPhase: String, Codable, Sendable, Equatable {
  case claimed
  case preparing
  case sealing
  case publishing
}

/// Exact remote lease and candidate namespace for one rebuild attempt.
public struct CloudSyncZoneRebuildLease: Sendable, Equatable {
  public var identifier: String
  public var ownerIdentifier: String
  public var epoch: Int
  public var generationID: String
  public var candidateZoneName: String

  public init(
    identifier: String, ownerIdentifier: String, epoch: Int,
    generationID: String, candidateZoneName: String
  ) {
    self.identifier = identifier
    self.ownerIdentifier = ownerIdentifier
    self.epoch = epoch
    self.generationID = generationID
    self.candidateZoneName = candidateZoneName
  }

  public var candidateZoneID: CKRecordZone.ID {
    CKRecordZone.ID(zoneName: candidateZoneName, ownerName: CKCurrentUserDefaultName)
  }
}

/// Fleet-visible authority for Lorvex CloudKit generations.
public enum CloudSyncZoneGenerationState: Sendable, Equatable {
  case ready(
    descriptor: CloudSyncGenerationDescriptor,
    retiredZoneNames: [String],
    modifiedAt: Date?
  )
  case rebuilding(
    lease: CloudSyncZoneRebuildLease,
    previousActive: CloudSyncGenerationDescriptor?,
    phase: CloudSyncZoneRebuildPhase,
    retiredZoneNames: [String],
    leaseActivityAt: Date
  )
  case deleted(
    deletionGeneration: Int,
    retiredZoneNames: [String],
    modifiedAt: Date?
  )

  /// Source-compatible constructor for deterministic fixtures that do not
  /// model CloudKit's server-owned modification timestamp.
  public static func ready(
    descriptor: CloudSyncGenerationDescriptor,
    retiredZoneNames: [String]
  ) -> Self {
    .ready(
      descriptor: descriptor,
      retiredZoneNames: retiredZoneNames,
      modifiedAt: nil)
  }

  public var epoch: Int {
    switch self {
    case .ready(let descriptor, _, _): descriptor.epoch
    case .rebuilding(let lease, _, _, _, _): lease.epoch
    case .deleted(let deletionGeneration, _, _): deletionGeneration
    }
  }

  public var retiredZoneNames: [String] {
    switch self {
    case .ready(_, let names, _), .rebuilding(_, _, _, let names, _), .deleted(_, let names, _):
      names
    }
  }

  public var activeDescriptor: CloudSyncGenerationDescriptor? {
    switch self {
    case .ready(let descriptor, _, _): descriptor
    case .rebuilding(_, let previousActive, _, _, _): previousActive
    case .deleted: nil
    }
  }

  public func isExactReady(_ descriptor: CloudSyncGenerationDescriptor) -> Bool {
    guard case .ready(let current, _, _) = self else { return false }
    return current == descriptor
  }

  public func isExactRebuild(_ lease: CloudSyncZoneRebuildLease) -> Bool {
    guard case .rebuilding(let current, _, _, _, _) = self else { return false }
    return current == lease
  }
}

/// Deterministic validation and generation-zone naming.
enum CloudSyncGenerationNaming {
  /// Shared with the durable traversal/generation schema. CloudKit control must
  /// reject a value before publishing it if the local proof layer cannot store
  /// the same generation.
  static let maximumGeneration = CloudTraversalBoundary.maxGeneration
  static let zonePrefix = "LorvexData-"
  static let maxIdentifierBytes = 128
  static let maxZoneNameBytes = 255
  /// A hard fleet-visible bound prevents an indefinitely failing account from
  /// growing the singleton metadata without limit. Normal maintenance deletes
  /// retirees every cycle; 32 leaves ample room for repeated crash/takeover
  /// recovery while keeping the control record tiny.
  static let retiredZoneLimit = 32

  static func newGenerationID() -> String {
    UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
  }

  static func newZoneName(epoch: Int, generationID: String) -> String {
    "\(zonePrefix)e\(epoch)-\(generationID)"
  }

  static func isValidIdentifier(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= maxIdentifierBytes
      && value.utf8.allSatisfy { (0x21...0x7e).contains($0) }
  }

  static func isValidZoneName(_ value: String) -> Bool {
    value.hasPrefix(zonePrefix) && value.utf8.count <= maxZoneNameBytes
      && value.utf8.allSatisfy { (0x21...0x7e).contains($0) }
  }

  /// Generation zones are protocol identities, not arbitrary custom-zone
  /// labels. Retired-ledger entries intentionally use the weaker shape check
  /// above because an older build may have minted them, but every live lease or
  /// descriptor must compose exactly from its epoch and generation id.
  static func isValidGenerationZoneName(
    _ value: String, epoch: Int, generationID: String
  ) -> Bool {
    epoch >= 0 && epoch <= maximumGeneration
      && isValidIdentifier(generationID) && isValidZoneName(value)
      && value == newZoneName(epoch: epoch, generationID: generationID)
  }

  /// Recover the monotonic epoch encoded by a canonical generation-zone name.
  /// Used only when an explicit deletion must reconstruct a missing control
  /// singleton from the remaining private-database namespaces.
  static func generationEpoch(fromZoneName value: String) -> Int? {
    let marker = "\(zonePrefix)e"
    guard value.hasPrefix(marker) else { return nil }
    let suffix = value.dropFirst(marker.count)
    guard let separator = suffix.firstIndex(of: "-") else { return nil }
    let epochRaw = suffix[..<separator]
    let generationID = String(suffix[suffix.index(after: separator)...])
    guard !epochRaw.isEmpty, epochRaw.allSatisfy(\.isNumber),
      let epoch = Int(epochRaw), epoch >= 0,
      isValidGenerationZoneName(value, epoch: epoch, generationID: generationID)
    else { return nil }
    return epoch
  }

  static func isValidDigest(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
  }

  static func validatedRetiredZoneNames(_ names: [String]) -> [String]? {
    guard names.count <= retiredZoneLimit, Set(names).count == names.count,
      names.allSatisfy(isValidZoneName)
    else { return nil }
    return names
  }
}

/// A request completed across a generation transition and must not affect local
/// confirmation, retry, cache, or apply state.
public struct CloudSyncGenerationBoundaryCrossed: Error, Sendable, Equatable {
  public init() {}
}

/// Exact fleet-visible control state required by one CloudKit request.
public enum CloudSyncGenerationExpectation: Sendable, Equatable {
  case ready(CloudSyncGenerationDescriptor)
  case rebuilding(CloudSyncZoneRebuildLease)
  /// The immutable predecessor may be read/drained while the exact replacement
  /// lease is rebuilding. Writes remain forbidden; this exists solely for the
  /// claimant's two terminal drains around candidate construction.
  case previousActive(
    lease: CloudSyncZoneRebuildLease, descriptor: CloudSyncGenerationDescriptor)

  func matches(_ state: CloudSyncZoneGenerationState?) -> Bool {
    guard let state else { return false }
    switch self {
    case .ready(let descriptor): return state.isExactReady(descriptor)
    case .rebuilding(let lease): return state.isExactRebuild(lease)
    case .previousActive(let lease, let descriptor):
      guard case .rebuilding(let current, let active, _, _, _) = state else { return false }
      return current == lease && active == descriptor
    }
  }
}
