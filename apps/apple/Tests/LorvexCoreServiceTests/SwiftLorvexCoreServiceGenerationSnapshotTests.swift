import Foundation
import XCTest

@testable import LorvexCore
@testable import LorvexSync

final class SwiftLorvexCoreServiceGenerationSnapshotTests: XCTestCase {
  func testConcreteServiceOwnsDurableCapturePagingProgressAndFinalization() throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let account = "service-generation-account"
    let sourceZone = "LorvexData-service-source"
    let candidateZone = "LorvexData-service-candidate"
    let cloudBinding = try service.claimCloudTraversalAccount(
      accountIdentifier: account)
    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: account, zoneName: sourceZone)
    let authorization = try service.authorizeAuditRetentionCandidateGeneration(
      forAccountIdentifier: account, candidateZoneName: candidateZone)
    let binding = try GenerationSnapshotBinding(
      accountIdentifier: account,
      databaseInstanceIdentifier: cloudBinding.databaseInstanceIdentifier,
      candidateZoneName: candidateZone, generation: 3,
      generationIdentifier: "service-generation-3",
      leaseIdentifier: "service-generation-lease",
      leaseOwnerIdentifier: cloudBinding.databaseInstanceIdentifier)

    let captured = try service.captureCandidateGenerationSnapshot(
      binding: binding, authorization: authorization)
    XCTAssertGreaterThanOrEqual(captured.manifest.recordCount, 0)
    let page = try service.stagedGenerationSnapshotPage(
      binding: binding, offset: 0)
    XCTAssertEqual(page.manifest, captured.manifest)
    let advanced = try service.advanceGenerationSnapshotUploadProgress(
      binding: binding, expectedNextOrdinal: 0,
      nextOrdinal: page.envelopes.count)
    XCTAssertEqual(
      advanced.progress.uploadNextOrdinal, page.envelopes.count)

    let witnesses = try page.envelopes.map(GenerationSnapshot.witness(for:))
    let readBack = try service.recordGenerationSnapshotReadbackPage(
      binding: binding, expectedPageIndex: 0, witnesses: witnesses,
      deletedRecordNames: [], continuationToken: Data([0x01]),
      observedTraversalWitness: true, terminal: true)
    XCTAssertEqual(readBack.remoteManifest, captured.manifest)
    XCTAssertEqual(
      try service.currentGenerationSnapshotStaging()?.binding, binding)

    try service.finalizePublishedGenerationSnapshot(binding: binding)
    XCTAssertNil(try service.generationSnapshotStaging(binding: binding))
    XCTAssertEqual(try service.auditRetentionActiveZoneName(), candidateZone)
    XCTAssertEqual(
      try service.enrolledZoneEpoch(forAccountIdentifier: account),
      binding.generation,
      "the publishing database must atomically enroll in the generation it proved")
  }

  func testConcreteServiceDiscardsCandidateAndPreservesSourceRouting() throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let account = "service-generation-discard-account"
    let sourceZone = "LorvexData-service-discard-source"
    let candidateZone = "LorvexData-service-discard-candidate"
    let cloudBinding = try service.claimCloudTraversalAccount(
      accountIdentifier: account)
    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: account, zoneName: sourceZone)
    let authorization = try service.authorizeAuditRetentionCandidateGeneration(
      forAccountIdentifier: account, candidateZoneName: candidateZone)
    let binding = try GenerationSnapshotBinding(
      accountIdentifier: account,
      databaseInstanceIdentifier: cloudBinding.databaseInstanceIdentifier,
      candidateZoneName: candidateZone, generation: 4,
      generationIdentifier: "service-generation-4",
      leaseIdentifier: "service-generation-discard-lease",
      leaseOwnerIdentifier: cloudBinding.databaseInstanceIdentifier)
    _ = try service.captureCandidateGenerationSnapshot(
      binding: binding, authorization: authorization)

    try service.discardGenerationSnapshot(binding: binding)

    XCTAssertNil(try service.currentGenerationSnapshotStaging())
    XCTAssertEqual(try service.auditRetentionActiveZoneName(), sourceZone)
  }
}
