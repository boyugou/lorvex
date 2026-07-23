import LorvexCore
import LorvexSync

extension CloudSyncEngineCoordinator {
  func traversalBoundary(
    _ context: CloudSyncGenerationContext
  ) throws -> CloudTraversalBoundary {
    guard let readyWitness = context.readyWitness else {
      throw CloudSyncGenerationBoundaryCrossed()
    }
    return try CloudTraversalBoundary(
      accountIdentifier: context.accountIdentifier,
      zoneIdentifier: context.zoneName, generation: context.epoch,
      generationIdentifier: context.generationID,
      readyWitness: readyWitness,
      tombstoneCompactionCutoff: context.tombstoneCompactionCutoff)
  }

  func accountBoundaryGuard(
    accountIdentifier expected: String
  ) -> @Sendable () async -> Bool {
    let reader = accountIdentifier
    return { await reader.currentAccountIdentifier() == expected }
  }

  func generationBoundaryGuard(
    accountIdentifier expected: String,
    expectation: CloudSyncGenerationExpectation
  ) -> @Sendable () async -> Bool {
    let reader = accountIdentifier
    let pusher = pusher
    return {
      guard await reader.currentAccountIdentifier() == expected,
        let state = try? await pusher.currentZoneGenerationState(),
        expectation.matches(state)
      else { return false }
      return await reader.currentAccountIdentifier() == expected
    }
  }

  func requiredDatabaseIdentifier(
    _ sync: any EnvelopeSyncServicing
  ) throws -> String {
    guard let identifier = try sync.databaseInstanceIdentifier(),
      CloudSyncGenerationNaming.isValidIdentifier(identifier)
    else { throw CloudTraversalStateError.invalidDatabaseInstanceIdentifier }
    return identifier
  }
}
