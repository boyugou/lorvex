import Foundation
import LorvexDomain

/// A malformed or mismatched durable CloudKit traversal boundary. Every case is
/// fail-closed: treating unreadable state as absent could authorize outbound
/// work before a restored database has observed the complete remote history.
public enum CloudTraversalStateError: Error, Sendable, Equatable, CustomStringConvertible {
  case invalidAccountIdentifier
  case invalidZoneIdentifier
  case invalidDatabaseInstanceIdentifier
  case invalidTraversalIdentifier
  case invalidGenerationIdentifier
  case invalidReadyWitness
  case invalidGeneration
  case invalidPageIndex
  case invalidContinuationToken
  case invalidTimestamp
  case malformedStoredState
  case unsupportedBackend
  case transactionRequired
  case databaseInstanceMismatch
  case databaseInstanceRotationNotDetected
  case noAccountBinding
  case accountBoundaryMismatch(expected: String, actual: String)
  case accountBindingCompareAndSwapFailed
  case staleGeneration(current: Int, attempted: Int)
  case generationDescriptorConflict(generation: Int)
  case generationZoneReuse
  case generationRootMismatch
  case readyWitnessMismatch
  case traversalWitnessMismatch
  case baselineProofIncomplete
  case baselineWitnessRequired
  case noDurableIncrementalCursor
  case noActiveTraversal
  case traversalBoundaryMismatch
  case traversalModeMismatch
  case pageSequenceMismatch(expected: Int, actual: Int)
  case continuationMismatch

  public var description: String {
    switch self {
    case .invalidAccountIdentifier: return "CloudKit account identifier is empty or oversized"
    case .invalidZoneIdentifier: return "CloudKit zone identifier is empty or oversized"
    case .invalidDatabaseInstanceIdentifier:
      return "physical database instance identifier is empty or oversized"
    case .invalidTraversalIdentifier: return "CloudKit traversal identifier is empty or oversized"
    case .invalidGenerationIdentifier: return "CloudKit generation identifier is malformed"
    case .invalidReadyWitness: return "CloudKit ready witness is malformed"
    case .invalidGeneration: return "CloudKit traversal generation is outside the supported range"
    case .invalidPageIndex: return "CloudKit traversal page index is outside the supported range"
    case .invalidContinuationToken: return "CloudKit continuation token is empty or oversized"
    case .invalidTimestamp: return "CloudKit traversal timestamp is not canonical UTC RFC 3339"
    case .malformedStoredState: return "durable CloudKit traversal state is malformed"
    case .unsupportedBackend:
      return "this backend does not support durable CloudKit traversal state"
    case .transactionRequired: return "durable CloudKit traversal mutations require a transaction"
    case .databaseInstanceMismatch:
      return "durable CloudKit traversal state belongs to a different physical database"
    case .databaseInstanceRotationNotDetected:
      return "the physical database instance identifier has not rotated"
    case .noAccountBinding: return "the database is not bound to an iCloud account"
    case .accountBoundaryMismatch(let expected, let actual):
      return "database is bound to account \(expected), not \(actual)"
    case .accountBindingCompareAndSwapFailed:
      return "the durable iCloud account binding changed before adoption committed"
    case .staleGeneration(let current, let attempted):
      return "CloudKit generation \(attempted) is older than durable generation \(current)"
    case .generationDescriptorConflict(let generation):
      return "CloudKit generation \(generation) is already bound to another exact descriptor"
    case .generationZoneReuse:
      return "a CloudKit zone, generation root, or ready witness was reused across generations"
    case .generationRootMismatch: return "the observed generation root does not match the traversal"
    case .readyWitnessMismatch: return "the observed generation seal does not match the traversal"
    case .traversalWitnessMismatch:
      return "the observed per-traversal witness does not match the active traversal"
    case .baselineProofIncomplete:
      return "baseline traversal ended before all required remote witnesses were observed"
    case .baselineWitnessRequired:
      return "incremental CloudKit traversal requires a completed baseline witness"
    case .noDurableIncrementalCursor:
      return "incremental CloudKit traversal has no durable starting cursor"
    case .noActiveTraversal: return "no matching durable CloudKit traversal is active"
    case .traversalBoundaryMismatch:
      return "CloudKit traversal account, zone, generation, or identifier changed"
    case .traversalModeMismatch: return "CloudKit traversal mode changed before completion"
    case .pageSequenceMismatch(let expected, let actual):
      return "CloudKit traversal expected page \(expected), received \(actual)"
    case .continuationMismatch:
      return "a CloudKit traversal carries a different continuation token"
    }
  }
}

/// Fleet-visible generation and physical custom-zone identity observed before
/// a traversal starts. Both values remain fixed through every fetched page.
public struct CloudTraversalBoundary: Sendable, Equatable, Hashable {
  public static let maxAccountIdentifierBytes = 512
  public static let maxZoneIdentifierBytes = 255
  public static let maxGenerationIdentifierBytes = 128
  public static let maxReadyWitnessBytes = 128
  public static let maxGeneration = Int(Int32.max)

  public let accountIdentifier: String
  public let zoneIdentifier: String
  public let generation: Int
  public let generationIdentifier: String
  public let readyWitness: String
  /// Server-time cutoff baked into this immutable ready generation. `nil`
  /// means the generation omitted no confirmed tombstones.
  public let tombstoneCompactionCutoff: String?

  public init(
    accountIdentifier: String, zoneIdentifier: String, generation: Int,
    generationIdentifier: String, readyWitness: String,
    tombstoneCompactionCutoff: String? = nil
  ) throws {
    guard Self.validBounded(accountIdentifier, maximumBytes: Self.maxAccountIdentifierBytes) else {
      throw CloudTraversalStateError.invalidAccountIdentifier
    }
    guard Self.validBounded(zoneIdentifier, maximumBytes: Self.maxZoneIdentifierBytes),
      zoneIdentifier.unicodeScalars.allSatisfy({
        $0.isASCII && $0.value >= 0x20 && $0.value <= 0x7e
      })
    else { throw CloudTraversalStateError.invalidZoneIdentifier }
    guard generation >= 0, generation <= Self.maxGeneration else {
      throw CloudTraversalStateError.invalidGeneration
    }
    guard
      Self.validOpaqueIdentifier(
        generationIdentifier, maximumBytes: Self.maxGenerationIdentifierBytes)
    else { throw CloudTraversalStateError.invalidGenerationIdentifier }
    guard Self.validOpaqueIdentifier(readyWitness, maximumBytes: Self.maxReadyWitnessBytes) else {
      throw CloudTraversalStateError.invalidReadyWitness
    }
    if let tombstoneCompactionCutoff {
      guard let parsed = SyncTimestamp.parse(tombstoneCompactionCutoff),
        parsed.asString == tombstoneCompactionCutoff
      else { throw CloudTraversalStateError.invalidTimestamp }
    }
    self.accountIdentifier = accountIdentifier
    self.zoneIdentifier = zoneIdentifier
    self.generation = generation
    self.generationIdentifier = generationIdentifier
    self.readyWitness = readyWitness
    self.tombstoneCompactionCutoff = tombstoneCompactionCutoff
  }

  static func validBounded(_ value: String, maximumBytes: Int) -> Bool {
    !value.isEmpty && value.utf8.count <= maximumBytes
  }

  static func validOpaqueIdentifier(_ value: String, maximumBytes: Int) -> Bool {
    validBounded(value, maximumBytes: maximumBytes)
      && value.unicodeScalars.allSatisfy {
        $0.isASCII && $0.value >= 0x21 && $0.value <= 0x7e
      }
  }
}

/// Exact descriptor metadata observed in one fetched page after transport has
/// validated each reserved CloudKit record's type, zone, and generation fields.
/// Values remain optional because the three records can land on different pages.
public struct CloudTraversalPageObservation: Sendable, Equatable {
  public let generationRootIdentifier: String?
  public let readyWitness: String?
  public let traversalWitnessIdentifier: String?
  public let traversalWitnessServerTime: String?

  public static let none = CloudTraversalPageObservation(
    generationRootIdentifier: nil, readyWitness: nil,
    traversalWitnessIdentifier: nil, traversalWitnessServerTime: nil,
    validated: ())

  public init(
    generationRootIdentifier: String? = nil, readyWitness: String? = nil,
    traversalWitnessIdentifier: String? = nil,
    traversalWitnessServerTime: String? = nil
  ) throws {
    if let generationRootIdentifier,
      !CloudTraversalBoundary.validOpaqueIdentifier(
        generationRootIdentifier,
        maximumBytes: CloudTraversalBoundary.maxGenerationIdentifierBytes)
    {
      throw CloudTraversalStateError.invalidGenerationIdentifier
    }
    if let readyWitness,
      !CloudTraversalBoundary.validOpaqueIdentifier(
        readyWitness, maximumBytes: CloudTraversalBoundary.maxReadyWitnessBytes)
    {
      throw CloudTraversalStateError.invalidReadyWitness
    }
    if let traversalWitnessIdentifier,
      !CloudTraversalBoundary.validOpaqueIdentifier(
        traversalWitnessIdentifier, maximumBytes: 128)
    {
      throw CloudTraversalStateError.invalidTraversalIdentifier
    }
    if let traversalWitnessServerTime {
      guard traversalWitnessIdentifier != nil,
        let parsed = SyncTimestamp.parse(traversalWitnessServerTime),
        parsed.asString == traversalWitnessServerTime
      else { throw CloudTraversalStateError.invalidTimestamp }
    }
    self.init(
      generationRootIdentifier: generationRootIdentifier, readyWitness: readyWitness,
      traversalWitnessIdentifier: traversalWitnessIdentifier,
      traversalWitnessServerTime: traversalWitnessServerTime, validated: ())
  }

  private init(
    generationRootIdentifier: String?, readyWitness: String?,
    traversalWitnessIdentifier: String?, traversalWitnessServerTime: String?,
    validated: Void
  ) {
    self.generationRootIdentifier = generationRootIdentifier
    self.readyWitness = readyWitness
    self.traversalWitnessIdentifier = traversalWitnessIdentifier
    self.traversalWitnessServerTime = traversalWitnessServerTime
  }
}

/// Whether a traversal starts from the beginning of a zone or from a previously
/// committed change token. Only `baseline` can establish a full-history proof.
public enum CloudTraversalMode: String, Sendable, Equatable, Hashable {
  case baseline
  case incremental
}

/// A validated traversal start. The private initializer makes the baseline's
/// nil-token origin and the incremental traversal's nonempty origin explicit.
public struct CloudTraversalStart: Sendable, Equatable {
  public let mode: CloudTraversalMode
  public let changeToken: Data?

  public static let baseline = CloudTraversalStart(mode: .baseline, changeToken: nil)

  public static func incremental(from changeToken: Data) throws -> CloudTraversalStart {
    try CloudTraversalTokenBounds.validate(changeToken)
    return CloudTraversalStart(mode: .incremental, changeToken: changeToken)
  }

  private init(mode: CloudTraversalMode, changeToken: Data?) {
    self.mode = mode
    self.changeToken = changeToken
  }
}

enum CloudTraversalTokenBounds {
  static let maxBytes = 256 * 1_024

  static func validate(_ value: Data) throws {
    guard !value.isEmpty, value.count <= maxBytes else {
      throw CloudTraversalStateError.invalidContinuationToken
    }
  }
}

/// One fetched page's durable cursor outcome. A nonterminal page must carry a
/// nonempty opaque token. A baseline terminal page may have no final token; an
/// incremental terminal is further required by storage to return one.
public struct CloudTraversalPageCommit: Sendable, Equatable {
  public static let maxPageIndex = 1_000_000
  public static let maxContinuationTokenBytes = CloudTraversalTokenBounds.maxBytes

  public let pageIndex: Int
  public let continuationToken: Data?
  public let moreComing: Bool
  public let observation: CloudTraversalPageObservation

  public init(
    pageIndex: Int, continuationToken: Data?, moreComing: Bool,
    observation: CloudTraversalPageObservation = .none
  ) throws {
    guard pageIndex >= 0, pageIndex <= Self.maxPageIndex else {
      throw CloudTraversalStateError.invalidPageIndex
    }
    if let continuationToken {
      try CloudTraversalTokenBounds.validate(continuationToken)
    } else if moreComing {
      throw CloudTraversalStateError.invalidContinuationToken
    }
    self.pageIndex = pageIndex
    self.continuationToken = continuationToken
    self.moreComing = moreComing
    self.observation = observation
  }
}

public struct CloudTraversalAccountBinding: Sendable, Equatable {
  public let accountIdentifier: String
  public let databaseInstanceIdentifier: String
  public let boundAt: String
}

/// Result of the single transactional boundary used before an explicit iCloud
/// account adoption. `previousAccountIdentifier` is retained only so the core
/// can invalidate account-scoped enrollment state for the lineage it replaced.
public struct CloudTraversalAccountAdoption: Sendable, Equatable {
  public let previousAccountIdentifier: String?
  public let binding: CloudTraversalAccountBinding
}

public struct CloudTraversalProgress: Sendable, Equatable {
  public let boundary: CloudTraversalBoundary
  public let databaseInstanceIdentifier: String
  public let traversalIdentifier: String
  public let mode: CloudTraversalMode
  public let startingChangeToken: Data?
  public let observedGenerationRoot: Bool
  public let observedReadyWitness: Bool
  public let observedTraversalWitness: Bool
  public let observedTraversalWitnessServerTime: String?
  public let nextPageIndex: Int
  public let continuationToken: Data?
  public let startedAt: String
  public let updatedAt: String
}

/// Proof that a baseline explicitly started from nil and reached a terminal
/// page in the same transactions as all page effects.
public struct CloudTraversalCompletion: Sendable, Equatable {
  public let boundary: CloudTraversalBoundary
  public let databaseInstanceIdentifier: String
  public let traversalIdentifier: String
  public let completedPageCount: Int
  public let finalChangeToken: Data?
  public let completedAt: String
}

/// The latest terminal incremental cursor. This is useful for resumption but is
/// never a substitute for `CloudTraversalCompletion`'s full-history proof.
public struct CloudTraversalIncrementalCursor: Sendable, Equatable {
  public let boundary: CloudTraversalBoundary
  public let databaseInstanceIdentifier: String
  public let traversalIdentifier: String
  public let completedPageCount: Int
  public let changeToken: Data
  public let completedAt: String
}

public struct CloudTraversalState: Sendable, Equatable {
  public let progress: CloudTraversalProgress?
  public let baselineWitness: CloudTraversalCompletion?
  public let incrementalCursor: CloudTraversalIncrementalCursor?

  public init(
    progress: CloudTraversalProgress?, baselineWitness: CloudTraversalCompletion?,
    incrementalCursor: CloudTraversalIncrementalCursor?
  ) {
    self.progress = progress
    self.baselineWitness = baselineWitness
    self.incrementalCursor = incrementalCursor
  }
}

public enum CloudTraversalCommitResult: Sendable, Equatable {
  case continuationRecorded(CloudTraversalProgress)
  case baselineCompleted(CloudTraversalCompletion)
  case incrementalCompleted(CloudTraversalIncrementalCursor)
  case alreadyRecorded
  case alreadyBaselineCompleted(CloudTraversalCompletion)
  case alreadyIncrementalCompleted(CloudTraversalIncrementalCursor)
}

/// Transaction-local decision made before a fetched page is allowed to mutate
/// domain or authoritative-staging state. A replayed page is identified before
/// any of its effects run, so diagnostic logs, conflict repairs, and other
/// non-row side effects cannot be emitted twice.
public enum CloudTraversalPageDisposition: Sendable, Equatable {
  case new
  case alreadyRecorded
  case alreadyBaselineCompleted(CloudTraversalCompletion)
  case alreadyIncrementalCompleted(CloudTraversalIncrementalCursor)
}
