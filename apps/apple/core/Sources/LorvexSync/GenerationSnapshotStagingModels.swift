import Foundation
import LorvexDomain

/// Exact local/remote lease identity for one immutable candidate generation.
public struct GenerationSnapshotBinding: Sendable, Equatable, Hashable {
  public let accountIdentifier: String
  public let databaseInstanceIdentifier: String
  public let candidateZoneName: String
  public let generation: Int
  public let generationIdentifier: String
  public let leaseIdentifier: String
  public let leaseOwnerIdentifier: String

  public init(
    accountIdentifier: String, databaseInstanceIdentifier: String,
    candidateZoneName: String, generation: Int,
    generationIdentifier: String, leaseIdentifier: String,
    leaseOwnerIdentifier: String
  ) throws {
    guard Self.validBounded(accountIdentifier, maximumBytes: 512),
      Self.validPrintableASCII(candidateZoneName, maximumBytes: 255),
      Self.validPrintableASCII(generationIdentifier, maximumBytes: 128),
      Self.validPrintableASCII(leaseIdentifier, maximumBytes: 128),
      Self.validPrintableASCII(leaseOwnerIdentifier, maximumBytes: 128),
      Self.validPrintableASCII(databaseInstanceIdentifier, maximumBytes: 128),
      leaseOwnerIdentifier == databaseInstanceIdentifier,
      generation >= 0, generation <= Int(Int32.max)
    else { throw GenerationSnapshotError.invalidBinding }
    self.accountIdentifier = accountIdentifier
    self.databaseInstanceIdentifier = databaseInstanceIdentifier
    self.candidateZoneName = candidateZoneName
    self.generation = generation
    self.generationIdentifier = generationIdentifier
    self.leaseIdentifier = leaseIdentifier
    self.leaseOwnerIdentifier = leaseOwnerIdentifier
  }

  static func validBounded(_ value: String, maximumBytes: Int) -> Bool {
    !value.isEmpty && value.utf8.count <= maximumBytes
  }

  static func validPrintableASCII(_ value: String, maximumBytes: Int) -> Bool {
    validBounded(value, maximumBytes: maximumBytes)
      && value.unicodeScalars.allSatisfy {
        $0.isASCII && $0.value >= 0x21 && $0.value <= 0x7e
      }
  }
}

/// Hard capture bounds applied before and during durable materialization.
public struct GenerationSnapshotCaptureLimits: Sendable, Equatable {
  public let maximumRecordCount: Int
  public let maximumTotalEncodedBytes: Int64

  public init(
    maximumRecordCount: Int = GenerationSnapshot.maximumRecordCount,
    maximumTotalEncodedBytes: Int64 = GenerationSnapshot.maximumTotalEncodedBytes
  ) throws {
    guard maximumRecordCount > 0,
      maximumRecordCount <= GenerationSnapshot.maximumRecordCount,
      maximumTotalEncodedBytes > 0,
      maximumTotalEncodedBytes <= GenerationSnapshot.maximumTotalEncodedBytes
    else { throw GenerationSnapshotError.invalidBinding }
    self.maximumRecordCount = maximumRecordCount
    self.maximumTotalEncodedBytes = maximumTotalEncodedBytes
  }

  public static let production = GenerationSnapshotCaptureLimits(
    uncheckedMaximumRecordCount: GenerationSnapshot.maximumRecordCount,
    uncheckedMaximumTotalEncodedBytes: GenerationSnapshot.maximumTotalEncodedBytes)

  private init(
    uncheckedMaximumRecordCount: Int,
    uncheckedMaximumTotalEncodedBytes: Int64
  ) {
    maximumRecordCount = uncheckedMaximumRecordCount
    maximumTotalEncodedBytes = uncheckedMaximumTotalEncodedBytes
  }
}

/// Crash-resumable upload and candidate-zone readback cursors.
public struct GenerationSnapshotProgress: Sendable, Equatable {
  public let uploadNextOrdinal: Int
  public let readbackPageIndex: Int
  public let readbackContinuationToken: Data?
  public let readbackWitnessObserved: Bool
  public let readbackComplete: Bool

  public init(
    uploadNextOrdinal: Int, readbackPageIndex: Int,
    readbackContinuationToken: Data?, readbackWitnessObserved: Bool,
    readbackComplete: Bool
  ) {
    self.uploadNextOrdinal = uploadNextOrdinal
    self.readbackPageIndex = readbackPageIndex
    self.readbackContinuationToken = readbackContinuationToken
    self.readbackWitnessObserved = readbackWitnessObserved
    self.readbackComplete = readbackComplete
  }
}

/// Durable header for one immutable generation capture and its verification state.
public struct GenerationSnapshotStaging: Sendable, Equatable {
  public let binding: GenerationSnapshotBinding
  public let manifest: GenerationSnapshotManifest
  public let progress: GenerationSnapshotProgress
  public let remoteManifest: GenerationSnapshotManifest?
  /// Server-derived recovery cutoff frozen with the immutable capture. `nil`
  /// means every tombstone was retained.
  public let tombstoneCompactionCutoff: String?
  public let createdAt: String

  public init(
    binding: GenerationSnapshotBinding, manifest: GenerationSnapshotManifest,
    progress: GenerationSnapshotProgress,
    remoteManifest: GenerationSnapshotManifest?,
    tombstoneCompactionCutoff: String? = nil, createdAt: String
  ) {
    self.binding = binding
    self.manifest = manifest
    self.progress = progress
    self.remoteManifest = remoteManifest
    self.tombstoneCompactionCutoff = tombstoneCompactionCutoff
    self.createdAt = createdAt
  }
}
