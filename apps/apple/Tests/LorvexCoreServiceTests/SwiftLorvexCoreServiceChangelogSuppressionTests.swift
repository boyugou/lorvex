import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

/// The `ai_changelog_retention_policy = off` "never store" kill switch, verified
/// through the real mutation choke point (`writeChangelogRow`): under `.off` a
/// mutation still commits but writes NO audit row; under the default `.maximum`
/// policy it does (guarding Core Design Rule 2). Existing suites assert the
/// maximum-policy audit contract broadly; this pins the opt-out.
final class SwiftLorvexCoreServiceChangelogSuppressionTests: XCTestCase {

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexCoreServiceTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  private func count(_ service: SwiftLorvexCoreService, _ sql: String) throws -> Int {
    try service.read { db in try Int.fetchOne(db, sql: sql) ?? -1 }
  }

  private func setPolicy(
    _ service: SwiftLorvexCoreService, _ policy: ChangelogRetentionPolicy
  ) async throws {
    _ = try await service.setPreference(
      key: PreferenceKeys.prefAiChangelogRetentionPolicy, value: policy.wireValue)
  }

  func testDefaultPolicyLogsChangelogRow() async throws {
    let service = try makeService()
    _ = try await service.createTask(TaskCreateDraft(title: "A"))
    XCTAssertGreaterThan(try count(service, "SELECT COUNT(*) FROM ai_changelog"), 0)
  }

  func testOffPolicySuppressesChangelogRowButStillMutates() async throws {
    let service = try makeService()
    try await setPolicy(service, .off)

    _ = try await service.createTask(TaskCreateDraft(title: "hidden"))

    // The mutation committed...
    XCTAssertEqual(try count(service, "SELECT COUNT(*) FROM tasks"), 1)
    // ...but no audit row (or entities) was written — including the policy flip
    // itself, which becomes self-suppressing once the value is stored.
    XCTAssertEqual(try count(service, "SELECT COUNT(*) FROM ai_changelog"), 0)
    XCTAssertEqual(try count(service, "SELECT COUNT(*) FROM ai_changelog_entities"), 0)
  }

  func testOffPolicyImmediatelyPurgesExistingLogWithoutSync() async throws {
    let service = try makeService()
    // Accumulate real audit history under the default (maximum) policy.
    _ = try await service.createTask(TaskCreateDraft(title: "one"))
    _ = try await service.createTask(TaskCreateDraft(title: "two"))
    XCTAssertGreaterThan(try count(service, "SELECT COUNT(*) FROM ai_changelog"), 0)

    // Choosing "off" must clear the existing log immediately. No sync cycle runs
    // in this test, so the sync-apply retention sweep never fires — the purge has
    // to happen on the preference write itself, or the "clears existing entries"
    // promise silently never fires when Cloud Sync is idle/disabled.
    try await setPolicy(service, .off)

    XCTAssertEqual(try count(service, "SELECT COUNT(*) FROM ai_changelog"), 0)
    XCTAssertEqual(try count(service, "SELECT COUNT(*) FROM ai_changelog_entities"), 0)
  }

  func testReenablingPolicyResumesLogging() async throws {
    let service = try makeService()
    try await setPolicy(service, .off)
    _ = try await service.createTask(TaskCreateDraft(title: "hidden"))
    XCTAssertEqual(try count(service, "SELECT COUNT(*) FROM ai_changelog"), 0)

    // Turning logging back on is itself audited, and later mutations audit again.
    try await setPolicy(service, .maximum)
    _ = try await service.createTask(TaskCreateDraft(title: "visible"))
    XCTAssertGreaterThan(try count(service, "SELECT COUNT(*) FROM ai_changelog"), 0)
  }
}
