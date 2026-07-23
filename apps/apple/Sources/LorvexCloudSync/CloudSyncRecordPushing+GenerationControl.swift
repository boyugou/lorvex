import Foundation
import LorvexDomain
@preconcurrency import CloudKit

extension CloudKitRecordPusher {
  public func currentZoneGenerationState() async throws -> CloudSyncZoneGenerationState? {
    guard let record = try await database.fetchRecord(
      with: CloudSyncZoneEpochRecord.recordID())
    else { return nil }
    guard let state = CloudSyncZoneEpochRecord.generationState(from: record) else {
      throw CloudSyncZoneEpochError.zoneEpochRecordUndecodable
    }
    return state
  }

  public func beginZoneRebuild(
    atLeast floor: Int, ownerIdentifier: String, allowFromDeleted: Bool,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncZoneRebuildLease {
    guard floor >= 0, floor <= CloudSyncGenerationNaming.maximumGeneration,
      CloudSyncGenerationNaming.isValidIdentifier(ownerIdentifier)
    else {
      throw CloudSyncZoneEpochError.zoneEpochRecordUndecodable
    }

    for _ in 0..<Self.maxZoneEpochCASAttempts {
      try await assertAccountBoundary(boundaryGuard)
      let existing = try await database.fetchRecord(
        with: CloudSyncZoneEpochRecord.recordID())
      try await assertAccountBoundary(boundaryGuard)

      let state: CloudSyncZoneGenerationState?
      if let existing {
        guard let decoded = CloudSyncZoneEpochRecord.generationState(from: existing) else {
          throw CloudSyncZoneEpochError.zoneEpochRecordUndecodable
        }
        state = decoded
      } else {
        state = nil
      }

      if case .deleted = state, !allowFromDeleted {
        throw CloudSyncZoneEpochError.zoneRecreationStillRequired
      }
      let serverNow = try await commitServerTime(boundaryGuard: boundaryGuard)

      var previousActive: CloudSyncGenerationDescriptor?
      var retired: [String]
      let currentEpoch: Int
      switch state {
      case nil:
        previousActive = nil
        retired = []
        currentEpoch = floor

      case .ready(let descriptor, let names, _):
        previousActive = descriptor
        retired = names
        currentEpoch = max(floor, descriptor.epoch)

      case .rebuilding(let current, let active, let phase, let names, let leaseActivityAt):
        if current.ownerIdentifier == ownerIdentifier {
          guard let existing else {
            throw CloudSyncZoneEpochError.zoneEpochRecordUndecodable
          }
          CloudSyncZoneEpochRecord.stampRebuilding(
            current, previousActive: active, phase: phase,
            leaseActivityAt: serverNow, retiredZoneNames: names, onto: existing)
          guard let saved = try await saveControlRecord(
            existing, boundaryGuard: boundaryGuard)
          else { continue }
          guard case .rebuilding(
            let savedLease, let savedActive, let savedPhase, let savedRetired,
            let savedActivity
          ) = CloudSyncZoneEpochRecord.generationState(from: saved),
            savedLease == current, savedActive == active, savedPhase == phase,
            savedRetired == names,
            savedActivity == SyncTimestamp(date: serverNow).date
          else {
            throw CloudSyncZoneEpochError.zoneRebuildSavedStateMismatch
          }
          return current
        }
        guard serverNow.timeIntervalSince(leaseActivityAt) >= Self.zoneRebuildTakeoverInterval
        else {
          throw CloudSyncZoneEpochError.zoneRebuildInProgress
        }
        previousActive = active
        retired = appendingUnique(current.candidateZoneName, to: names)
        currentEpoch = max(floor, current.epoch)

      case .deleted(let deletionGeneration, let names, _):
        previousActive = nil
        retired = names
        currentEpoch = max(floor, deletionGeneration)
      }

      guard currentEpoch < CloudSyncGenerationNaming.maximumGeneration else {
        throw CloudSyncZoneEpochError.zoneEpochExhausted
      }
      guard CloudSyncGenerationNaming.validatedRetiredZoneNames(retired) != nil else {
        throw CloudSyncZoneEpochError.retiredZoneLimitExceeded
      }
      let epoch = currentEpoch + 1
      let generationID = CloudSyncGenerationNaming.newGenerationID()
      let lease = CloudSyncZoneRebuildLease(
        identifier: CloudSyncGenerationNaming.newGenerationID(),
        ownerIdentifier: ownerIdentifier,
        epoch: epoch,
        generationID: generationID,
        candidateZoneName: CloudSyncGenerationNaming.newZoneName(
          epoch: epoch, generationID: generationID))
      let record = existing ?? CloudSyncZoneEpochRecord.makeRecord()
      CloudSyncZoneEpochRecord.stampRebuilding(
        lease, previousActive: previousActive, phase: .claimed,
        leaseActivityAt: serverNow, retiredZoneNames: retired, onto: record)

      guard let saved = try await saveControlRecord(
        record, boundaryGuard: boundaryGuard)
      else { continue }
      guard case .rebuilding(
        let savedLease, let savedActive, let phase, let savedRetired, let savedActivity
      ) =
        CloudSyncZoneEpochRecord.generationState(from: saved),
        savedLease == lease, savedActive == previousActive, phase == .claimed,
        savedRetired == retired,
        savedActivity == SyncTimestamp(date: serverNow).date
      else {
        throw CloudSyncZoneEpochError.zoneRebuildSavedStateMismatch
      }
      return lease
    }
    throw CloudSyncZoneEpochError.zoneEpochCASRetryLimitExceeded
  }

  public func restartZoneRebuild(
    _ lease: CloudSyncZoneRebuildLease,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncZoneRebuildLease {
    for _ in 0..<Self.maxZoneEpochCASAttempts {
      try await assertAccountBoundary(boundaryGuard)
      guard let control = try await database.fetchRecord(
        with: CloudSyncZoneEpochRecord.recordID())
      else { throw CloudSyncZoneEpochError.zoneRebuildLeaseLost }
      try await assertAccountBoundary(boundaryGuard)
      guard case .rebuilding(
        let current, let previousActive, _, let retired, _
      ) = CloudSyncZoneEpochRecord.generationState(from: control), current == lease else {
        throw CloudSyncZoneEpochError.zoneRebuildLeaseLost
      }
      guard lease.epoch < CloudSyncGenerationNaming.maximumGeneration else {
        throw CloudSyncZoneEpochError.zoneEpochExhausted
      }
      let nextRetired = appendingUnique(lease.candidateZoneName, to: retired)
      guard CloudSyncGenerationNaming.validatedRetiredZoneNames(nextRetired) != nil else {
        throw CloudSyncZoneEpochError.retiredZoneLimitExceeded
      }
      let generationID = CloudSyncGenerationNaming.newGenerationID()
      let replacement = CloudSyncZoneRebuildLease(
        identifier: CloudSyncGenerationNaming.newGenerationID(),
        ownerIdentifier: lease.ownerIdentifier, epoch: lease.epoch + 1,
        generationID: generationID,
        candidateZoneName: CloudSyncGenerationNaming.newZoneName(
          epoch: lease.epoch + 1, generationID: generationID))
      let serverNow = try await commitServerTime(boundaryGuard: boundaryGuard)
      CloudSyncZoneEpochRecord.stampRebuilding(
        replacement, previousActive: previousActive, phase: .claimed,
        leaseActivityAt: serverNow,
        retiredZoneNames: nextRetired, onto: control)
      guard let saved = try await saveControlRecord(
        control, boundaryGuard: boundaryGuard)
      else { continue }
      guard case .rebuilding(
        let savedLease, let savedPrevious, let phase, let savedRetired, let savedActivity
      ) = CloudSyncZoneEpochRecord.generationState(from: saved),
        savedLease == replacement, savedPrevious == previousActive,
        phase == .claimed, savedRetired == nextRetired,
        savedActivity == SyncTimestamp(date: serverNow).date
      else { throw CloudSyncZoneEpochError.zoneRebuildSavedStateMismatch }
      return replacement
    }
    throw CloudSyncZoneEpochError.zoneEpochCASRetryLimitExceeded
  }

  public func advanceZoneRebuildPhase(
    _ lease: CloudSyncZoneRebuildLease, to requestedPhase: CloudSyncZoneRebuildPhase,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    for _ in 0..<Self.maxZoneEpochCASAttempts {
      try await assertAccountBoundary(boundaryGuard)
      guard let record = try await database.fetchRecord(
        with: CloudSyncZoneEpochRecord.recordID())
      else { throw CloudSyncZoneEpochError.zoneRebuildLeaseLost }
      try await assertAccountBoundary(boundaryGuard)
      guard case .rebuilding(
        let current, let active, let currentPhase, let retired, _
      ) = CloudSyncZoneEpochRecord.generationState(from: record), current == lease else {
        throw CloudSyncZoneEpochError.zoneRebuildLeaseLost
      }
      guard phaseRank(requestedPhase) >= phaseRank(currentPhase) else {
        throw CloudSyncZoneEpochError.zoneRebuildSavedStateMismatch
      }
      let serverNow = try await commitServerTime(boundaryGuard: boundaryGuard)
      CloudSyncZoneEpochRecord.stampRebuilding(
        lease, previousActive: active, phase: requestedPhase,
        leaseActivityAt: serverNow, retiredZoneNames: retired, onto: record)
      guard let saved = try await saveControlRecord(
        record, boundaryGuard: boundaryGuard)
      else { continue }
      guard case .rebuilding(let savedLease, _, let phase, _, let savedActivity) =
        CloudSyncZoneEpochRecord.generationState(from: saved),
        savedLease == lease, phase == requestedPhase,
        savedActivity == SyncTimestamp(date: serverNow).date
      else { throw CloudSyncZoneEpochError.zoneRebuildSavedStateMismatch }
      return
    }
    throw CloudSyncZoneEpochError.zoneEpochCASRetryLimitExceeded
  }

  public func ensureZone(
    _ zoneID: CKRecordZone.ID, expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    guard zoneID == expectedZoneID(for: expectation) else {
      throw CloudSyncGenerationBoundaryCrossed()
    }
    try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
    let (saveResults, _) = try await database.modifyRecordZones(
      saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
    try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
    guard let result = saveResults[zoneID] else {
      throw CloudSyncZoneEnsureError.zoneSaveResultMissing
    }
    _ = try result.get()
  }

  public func ensureGenerationRoot(
    _ lease: CloudSyncZoneRebuildLease,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    let expectation = CloudSyncGenerationExpectation.rebuilding(lease)
    let record = CloudSyncGenerationRootRecord.makeRecord(lease: lease)
    try await saveImmutableGenerationMarker(
      record, expectation: expectation, boundaryGuard: boundaryGuard
    ) { CloudSyncGenerationRootRecord.matches($0, lease: lease) }
  }

  public func validateGenerationRoot(
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> Bool {
    guard context.matches(expectation) else {
      throw CloudSyncGenerationBoundaryCrossed()
    }
    try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
    let record = try await database.fetchRecord(
      with: CloudSyncGenerationRootRecord.recordID(zoneID: context.zoneID))
    try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
    guard let record else { return false }
    switch expectation {
    case .ready(let descriptor):
      // A ready descriptor is trustworthy only when the immutable root and seal
      // both carry the exact completed-lease provenance retained by the control
      // record. Descriptor-only checks otherwise accept a same-generation marker
      // with missing rebuild ownership or a malformed manifest.
      guard let control = try await database.fetchRecord(
        with: CloudSyncZoneEpochRecord.recordID())
      else { return false }
      try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
      guard case .ready(let current, _, _) =
        CloudSyncZoneEpochRecord.generationState(from: control),
        current == descriptor,
        let completedLease = CloudSyncZoneEpochRecord.completedLease(from: control),
        CloudSyncGenerationRootRecord.matches(record, lease: completedLease)
      else { return false }
      let seal = try await database.fetchRecord(
        with: CloudSyncGenerationSealRecord.recordID(zoneID: context.zoneID))
      try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
      guard let seal else { return false }
      guard let manifest = CloudSyncGenerationSealRecord.manifest(
        from: seal, lease: completedLease, witness: descriptor.readyWitness)
      else { return false }
      return manifest.tombstoneCompactionCutoff == descriptor.tombstoneCompactionCutoff
    case .rebuilding(let lease):
      return CloudSyncGenerationRootRecord.matches(record, lease: lease)
    case .previousActive(_, let descriptor):
      guard let rootProvenance = CloudSyncGenerationRootRecord.provenance(
        from: record, descriptor: descriptor)
      else { return false }
      let seal = try await database.fetchRecord(
        with: CloudSyncGenerationSealRecord.recordID(zoneID: context.zoneID))
      try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
      guard let seal,
        let sealProvenance = CloudSyncGenerationSealRecord.provenance(
          from: seal, descriptor: descriptor),
        sealProvenance == rootProvenance
      else { return false }
      return CloudSyncGenerationSealRecord.manifest(
        from: seal, descriptor: descriptor) != nil
    }
  }

  public func saveGenerationSeal(
    _ lease: CloudSyncZoneRebuildLease, readyWitness: String,
    manifest: CloudSyncGenerationManifest,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    guard CloudSyncGenerationNaming.isValidIdentifier(readyWitness) else {
      throw CloudSyncZoneEpochError.zoneRebuildSavedStateMismatch
    }
    let expectation = CloudSyncGenerationExpectation.rebuilding(lease)
    let record = try CloudSyncGenerationSealRecord.makeRecord(
      lease: lease, witness: readyWitness, manifest: manifest)
    try await saveImmutableGenerationMarker(
      record, expectation: expectation, boundaryGuard: boundaryGuard
    ) {
      CloudSyncGenerationSealRecord.matches(
        $0, lease: lease, witness: readyWitness, manifest: manifest)
    }
  }

  public func publishTraversalWitness(
    context: CloudSyncGenerationContext, expectation: CloudSyncGenerationExpectation,
    traversalIdentifier: String,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    guard context.matches(expectation) else { throw CloudSyncGenerationBoundaryCrossed() }
    let record = try CloudSyncTraversalWitnessRecord.makeRecord(
      context: context, traversalIdentifier: traversalIdentifier)
    try await saveImmutableGenerationMarker(
      record, expectation: expectation, boundaryGuard: boundaryGuard
    ) {
      CloudSyncTraversalWitnessRecord.matches(
        $0, context: context, traversalIdentifier: traversalIdentifier)
    }
  }

  public func deleteTraversalWitness(
    context: CloudSyncGenerationContext, expectation: CloudSyncGenerationExpectation,
    traversalIdentifier: String,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    guard context.matches(expectation),
      CloudSyncGenerationNaming.isValidIdentifier(traversalIdentifier)
    else { throw CloudSyncGenerationBoundaryCrossed() }
    let recordID = CloudSyncTraversalWitnessRecord.recordID(
      zoneID: context.zoneID, traversalIdentifier: traversalIdentifier)
    try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
    let (_, deleteResults) = try await database.modifyRecords(
      saving: [], deleting: [recordID], savePolicy: .ifServerRecordUnchanged,
      atomically: false)
    try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
    guard let result = deleteResults[recordID] else {
      throw CloudSyncZoneEpochError.generationMarkerMismatch
    }
    switch result {
    case .success:
      return
    case .failure(let error):
      guard zoneAlreadyGone(error) || (error as? CKError)?.code == .unknownItem else {
        throw error
      }
    }
  }

  public func completeZoneRebuild(
    _ lease: CloudSyncZoneRebuildLease, readyWitness: String,
    manifest: CloudSyncGenerationManifest,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncGenerationDescriptor {
    guard CloudSyncGenerationNaming.isValidIdentifier(readyWitness) else {
      throw CloudSyncZoneEpochError.zoneRebuildSavedStateMismatch
    }
    let descriptor = CloudSyncGenerationDescriptor(
      epoch: lease.epoch, generationID: lease.generationID,
      zoneName: lease.candidateZoneName, readyWitness: readyWitness,
      tombstoneCompactionCutoff: manifest.tombstoneCompactionCutoff)

    for _ in 0..<Self.maxZoneEpochCASAttempts {
      try await assertAccountBoundary(boundaryGuard)
      guard let control = try await database.fetchRecord(
        with: CloudSyncZoneEpochRecord.recordID())
      else { throw CloudSyncZoneEpochError.zoneRebuildLeaseLost }
      try await assertAccountBoundary(boundaryGuard)

      if case .ready(let current, _, _) =
        CloudSyncZoneEpochRecord.generationState(from: control),
        current == descriptor, CloudSyncZoneEpochRecord.completedLease(from: control) == lease
      {
        let readyExpectation = CloudSyncGenerationExpectation.ready(current)
        let readyContext = CloudSyncGenerationContext(
          accountIdentifier: "control-validation", descriptor: current)
        guard try await validateGenerationRoot(
          context: readyContext, expectation: readyExpectation,
          boundaryGuard: boundaryGuard)
        else { throw CloudSyncZoneEpochError.generationMarkerMismatch }
        guard let retention = try await readAuditRetentionMetadata(
          context: readyContext, expectation: readyExpectation,
          boundaryGuard: boundaryGuard),
          retention.canonicalDigest == manifest.retentionMetadataDigest
        else { throw CloudSyncZoneEpochError.generationMarkerMismatch }
        try await assertExpectation(
          readyExpectation, boundaryGuard: boundaryGuard)
        let seal = try await database.fetchRecord(
          with: CloudSyncGenerationSealRecord.recordID(zoneID: current.zoneID))
        try await assertExpectation(
          readyExpectation, boundaryGuard: boundaryGuard)
        guard let seal,
          CloudSyncGenerationSealRecord.matches(
            seal, lease: lease, witness: readyWitness, manifest: manifest)
        else { throw CloudSyncZoneEpochError.generationMarkerMismatch }
        return current
      }
      guard case .rebuilding(
        let current, let previousActive, let phase, let retired, _
      ) = CloudSyncZoneEpochRecord.generationState(from: control),
        current == lease, phase == .publishing
      else { throw CloudSyncZoneEpochError.zoneRebuildLeaseLost }

      let expectation = CloudSyncGenerationExpectation.rebuilding(lease)
      let context = CloudSyncGenerationContext(
        accountIdentifier: "control-validation", lease: lease)
      guard try await validateGenerationRoot(
        context: context, expectation: expectation, boundaryGuard: boundaryGuard)
      else { throw CloudSyncZoneEpochError.generationMarkerMismatch }
      guard let retention = try await readAuditRetentionMetadata(
        context: context, expectation: expectation,
        boundaryGuard: boundaryGuard),
        retention.canonicalDigest == manifest.retentionMetadataDigest
      else { throw CloudSyncZoneEpochError.generationMarkerMismatch }
      try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
      let seal = try await database.fetchRecord(
        with: CloudSyncGenerationSealRecord.recordID(zoneID: lease.candidateZoneID))
      try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
      guard let seal,
        CloudSyncGenerationSealRecord.matches(
          seal, lease: lease, witness: readyWitness, manifest: manifest)
      else { throw CloudSyncZoneEpochError.generationMarkerMismatch }

      var nextRetired = retired
      if let previousActive {
        nextRetired = appendingUnique(previousActive.zoneName, to: nextRetired)
      }
      guard CloudSyncGenerationNaming.validatedRetiredZoneNames(nextRetired) != nil else {
        throw CloudSyncZoneEpochError.retiredZoneLimitExceeded
      }
      CloudSyncZoneEpochRecord.stampReady(
        descriptor: descriptor, completedLease: lease,
        retiredZoneNames: nextRetired, onto: control)
      guard let saved = try await saveControlRecord(
        control, boundaryGuard: boundaryGuard)
      else { continue }
      guard case .ready(let savedDescriptor, let savedRetired, _) =
        CloudSyncZoneEpochRecord.generationState(from: saved),
        savedDescriptor == descriptor, savedRetired == nextRetired,
        CloudSyncZoneEpochRecord.completedLease(from: saved) == lease
      else { throw CloudSyncZoneEpochError.zoneRebuildSavedStateMismatch }
      return savedDescriptor
    }
    throw CloudSyncZoneEpochError.zoneEpochCASRetryLimitExceeded
  }

  public func publishGenerationWake(
    descriptor: CloudSyncGenerationDescriptor,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    let expectation = CloudSyncGenerationExpectation.ready(descriptor)
    try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
    let record = CloudSyncGenerationWakeRecord.makeRecord(descriptor: descriptor)
    let (saveResults, _) = try await database.modifyRecords(
      saving: [record], deleting: [], savePolicy: .changedKeys, atomically: false)
    try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
    guard let result = saveResults[record.recordID] else {
      throw CloudSyncZoneEpochError.generationMarkerMismatch
    }
    _ = try result.get()
  }

  public func markCloudDataDeleted(
    atLeast generationFloor: Int,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncZoneGenerationState {
    guard generationFloor >= 0,
      generationFloor <= CloudSyncGenerationNaming.maximumGeneration
    else {
      throw CloudSyncZoneEpochError.zoneEpochRecordUndecodable
    }
    for _ in 0..<Self.maxZoneEpochCASAttempts {
      try await assertAccountBoundary(boundaryGuard)
      let existing = try await database.fetchRecord(
        with: CloudSyncZoneEpochRecord.recordID())
      try await assertAccountBoundary(boundaryGuard)

      guard let existing else {
        // An explicit user deletion must also work for a genuinely fresh
        // account and recover parseable orphan generation zones after control-
        // record loss. Combine the caller's durable local authority floor with
        // every canonical epoch still visible in the private database, then CAS
        // create a terminal singleton strictly above that evidence.
        let zones = try await database.allRecordZones()
        try await assertAccountBoundary(boundaryGuard)
        let remoteFloor = zones.compactMap {
          CloudSyncGenerationNaming.generationEpoch(fromZoneName: $0.zoneID.zoneName)
        }.max() ?? 0
        let observedFloor = max(generationFloor, remoteFloor)
        guard observedFloor < CloudSyncGenerationNaming.maximumGeneration else {
          throw CloudSyncZoneEpochError.zoneEpochExhausted
        }
        let record = CloudSyncZoneEpochRecord.makeRecord()
        CloudSyncZoneEpochRecord.stampDeleted(
          deletionGeneration: observedFloor + 1,
          retiredZoneNames: [], onto: record)
        guard let saved = try await saveControlRecord(
          record, boundaryGuard: boundaryGuard)
        else { continue }
        guard let savedState = CloudSyncZoneEpochRecord.generationState(from: saved),
          case .deleted(let savedEpoch, let savedZones, _) = savedState,
          savedEpoch == observedFloor + 1, savedZones.isEmpty
        else { throw CloudSyncZoneEpochError.zoneRebuildSavedStateMismatch }
        return savedState
      }
      guard let state = CloudSyncZoneEpochRecord.generationState(from: existing) else {
        throw CloudSyncZoneEpochError.zoneEpochRecordUndecodable
      }
      if case .deleted = state { return state }

      let epoch: Int
      var zones: [String] = []
      switch state {
      case .ready(let active, _, _):
        guard active.epoch < CloudSyncGenerationNaming.maximumGeneration else {
          throw CloudSyncZoneEpochError.zoneEpochExhausted
        }
        let floor = max(active.epoch, generationFloor)
        guard floor < CloudSyncGenerationNaming.maximumGeneration else {
          throw CloudSyncZoneEpochError.zoneEpochExhausted
        }
        epoch = floor + 1
        zones = [active.zoneName]
      case .rebuilding(let lease, let active, _, _, _):
        guard lease.epoch < CloudSyncGenerationNaming.maximumGeneration else {
          throw CloudSyncZoneEpochError.zoneEpochExhausted
        }
        let floor = max(lease.epoch, generationFloor)
        guard floor < CloudSyncGenerationNaming.maximumGeneration else {
          throw CloudSyncZoneEpochError.zoneEpochExhausted
        }
        epoch = floor + 1
        zones = [lease.candidateZoneName]
        if let active { zones = appendingUnique(active.zoneName, to: zones) }
      case .deleted:
        return state
      }
      // `.deleted` is a namespace-wide command: maintenance enumerates and
      // removes every canonical Lorvex generation zone until a confirming pass
      // finds none. Retain only the immediately active/candidate names as crash
      // hints. Carrying the ordinary bounded retiree ledger forward would make
      // a full 32-entry ledger prevent the user from publishing the deletion
      // barrier at all, exactly when deletion is most important.
      let record = existing
      CloudSyncZoneEpochRecord.stampDeleted(
        deletionGeneration: epoch, retiredZoneNames: zones, onto: record)
      guard let saved = try await saveControlRecord(
        record, boundaryGuard: boundaryGuard)
      else { continue }
      guard case .deleted(let savedEpoch, let savedZones, _) =
        CloudSyncZoneEpochRecord.generationState(from: saved),
        savedEpoch == epoch, savedZones == zones
      else { throw CloudSyncZoneEpochError.zoneRebuildSavedStateMismatch }
      return CloudSyncZoneEpochRecord.generationState(from: saved)!
    }
    throw CloudSyncZoneEpochError.zoneEpochCASRetryLimitExceeded
  }

  public func deleteRetiredZone(
    zoneName: String, accountIdentifier _: String,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    guard CloudSyncGenerationNaming.isValidZoneName(zoneName) else {
      throw CloudSyncZoneEpochError.generationMarkerMismatch
    }
    try await assertAccountBoundary(boundaryGuard)
    guard let captured = try await currentZoneGenerationState() else {
      throw CloudSyncGenerationBoundaryCrossed()
    }
    guard captured.activeDescriptor?.zoneName != zoneName,
      candidateZoneName(in: captured) != zoneName
    else { throw CloudSyncGenerationBoundaryCrossed() }
    // `currentZoneGenerationState()` is an external suspension point. Recheck
    // the signed-in account immediately before the destructive CloudKit request
    // so an A→B switch cannot route this zone deletion into account B.
    try await assertAccountBoundary(boundaryGuard)

    let zoneID = CKRecordZone.ID(
      zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    let (_, deleteResults) = try await database.modifyRecordZones(
      saving: [], deleting: [zoneID])
    try await assertAccountBoundary(boundaryGuard)
    guard let result = deleteResults[zoneID] else {
      throw CloudSyncZoneDeleteError.zoneDeleteResultMissing
    }
    switch result {
    case .success:
      break
    case .failure(let error):
      guard zoneAlreadyGone(error) else { throw error }
    }

    guard let afterDelete = try await currentZoneGenerationState(),
      afterDelete.activeDescriptor?.zoneName != zoneName,
      candidateZoneName(in: afterDelete) != zoneName
    else { throw CloudSyncGenerationBoundaryCrossed() }
  }

  public func finalizeRetiredZoneDeletion(
    zoneName: String,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    guard CloudSyncGenerationNaming.isValidZoneName(zoneName) else {
      throw CloudSyncZoneEpochError.generationMarkerMismatch
    }
    try await removeRetiredZoneName(zoneName, boundaryGuard: boundaryGuard)
  }

  public func allRecordZones(
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CKRecordZone] {
    try await assertAccountBoundary(boundaryGuard)
    let zones = try await database.allRecordZones()
    try await assertAccountBoundary(boundaryGuard)
    return zones
  }

}

extension CloudKitRecordPusher {
  private func commitServerTime(
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> Date {
    try await assertAccountBoundary(boundaryGuard)
    let serverTime = try await serverClock.commitServerTime()
    try await assertAccountBoundary(boundaryGuard)
    guard serverTime.timeIntervalSinceReferenceDate.isFinite else {
      throw CloudSyncServerClockError.invalidSavedRecord
    }
    return serverTime
  }

  private func saveControlRecord(
    _ record: CKRecord, boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CKRecord? {
    try await assertAccountBoundary(boundaryGuard)
    let (saveResults, _) = try await database.modifyRecords(
      saving: [record], deleting: [],
      savePolicy: .ifServerRecordUnchanged, atomically: false)
    try await assertAccountBoundary(boundaryGuard)
    guard let result = saveResults[record.recordID] else {
      throw CloudSyncZoneEpochError.zoneEpochSaveResultMissing
    }
    switch result {
    case .success(let saved):
      return saved
    case .failure(let error):
      if let ckError = error as? CKError,
        ckError.code == .serverRecordChanged || ckError.code == .unknownItem
      {
        return nil
      }
      throw error
    }
  }

  private func saveImmutableGenerationMarker(
    _ record: CKRecord, expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?,
    matches: (CKRecord) -> Bool
  ) async throws {
    try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
    if let existing = try await database.fetchRecord(with: record.recordID) {
      try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
      guard matches(existing) else {
        throw CloudSyncZoneEpochError.generationMarkerMismatch
      }
      return
    }
    try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
    let (saveResults, _) = try await database.modifyRecords(
      saving: [record], deleting: [],
      savePolicy: .ifServerRecordUnchanged, atomically: false)
    try await assertExpectation(expectation, boundaryGuard: boundaryGuard)
    guard let result = saveResults[record.recordID] else {
      throw CloudSyncZoneEpochError.generationMarkerMismatch
    }
    switch result {
    case .success(let saved):
      guard matches(saved) else {
        throw CloudSyncZoneEpochError.generationMarkerMismatch
      }
    case .failure(let error):
      if let ckError = error as? CKError, ckError.code == .serverRecordChanged,
        let server = ckError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord,
        matches(server)
      {
        return
      }
      throw error
    }
  }

  private func assertExpectation(
    _ expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    try await assertAccountBoundary(boundaryGuard)
    guard expectation.matches(try await currentZoneGenerationState()) else {
      throw CloudSyncGenerationBoundaryCrossed()
    }
    try await assertAccountBoundary(boundaryGuard)
  }

  private func assertAccountBoundary(
    _ boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    guard await boundaryGuard?() ?? true else {
      throw CloudSyncAccountBoundaryCrossed()
    }
  }

  private func removeRetiredZoneName(
    _ zoneName: String, boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    for _ in 0..<Self.maxZoneEpochCASAttempts {
      try await assertAccountBoundary(boundaryGuard)
      guard let record = try await database.fetchRecord(
        with: CloudSyncZoneEpochRecord.recordID())
      else { throw CloudSyncGenerationBoundaryCrossed() }
      try await assertAccountBoundary(boundaryGuard)
      guard let state = CloudSyncZoneEpochRecord.generationState(from: record) else {
        throw CloudSyncZoneEpochError.zoneEpochRecordUndecodable
      }
      guard state.activeDescriptor?.zoneName != zoneName,
        candidateZoneName(in: state) != zoneName
      else { throw CloudSyncGenerationBoundaryCrossed() }
      guard state.retiredZoneNames.contains(zoneName) else { return }
      let remaining = state.retiredZoneNames.filter { $0 != zoneName }
      CloudSyncZoneEpochRecord.replaceRetiredZoneNames(remaining, on: record)
      guard try await saveControlRecord(record, boundaryGuard: boundaryGuard) != nil else {
        continue
      }
      return
    }
    throw CloudSyncZoneEpochError.zoneEpochCASRetryLimitExceeded
  }

  private func expectedZoneID(
    for expectation: CloudSyncGenerationExpectation
  ) -> CKRecordZone.ID {
    switch expectation {
    case .ready(let descriptor): descriptor.zoneID
    case .rebuilding(let lease): lease.candidateZoneID
    case .previousActive(_, let descriptor): descriptor.zoneID
    }
  }

  private func candidateZoneName(
    in state: CloudSyncZoneGenerationState
  ) -> String? {
    guard case .rebuilding(let lease, _, _, _, _) = state else { return nil }
    return lease.candidateZoneName
  }

  private func appendingUnique(_ zoneName: String, to names: [String]) -> [String] {
    names.contains(zoneName) ? names : names + [zoneName]
  }

  private func phaseRank(_ phase: CloudSyncZoneRebuildPhase) -> Int {
    switch phase {
    case .claimed: 0
    case .preparing: 1
    case .sealing: 2
    case .publishing: 3
    }
  }

  private func zoneAlreadyGone(_ error: any Error) -> Bool {
    guard let ckError = error as? CKError else { return false }
    return ckError.code == .zoneNotFound || ckError.code == .unknownItem
      || ckError.code == .userDeletedZone
  }
}
