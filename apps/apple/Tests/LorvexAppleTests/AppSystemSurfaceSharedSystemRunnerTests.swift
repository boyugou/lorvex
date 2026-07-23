import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func sharedSystemIntentRunnerReadsSystemPreferencesSetupAndDiagnostics() async throws {
  let core = try await makeSeededInMemoryCore()
  let preferences = try await LorvexSystemIntentRunner.readPreferences(core: core)
  #expect(preferences.values["theme"] == "\"system\"")
  let timezone = try await LorvexSystemIntentRunner.readPreference(key: " timezone ", core: core)
  #expect(timezone == "\"America/Los_Angeles\"")
  let preferenceValue = try await LorvexSystemIntentRunner.setPreference(
    key: " record_raw_input ", value: " true ", core: core)
  #expect(preferenceValue == "true")
  let setupPreferences = try await LorvexSystemIntentRunner.completeSetup(
    workingHours: #"{"start":"09:00","end":"17:00"}"#, defaultListID: "inbox",
    timezone: "America/Los_Angeles", core: core)
  #expect(setupPreferences.values["setup_completed"] == "true")
  let overview = try await LorvexSystemIntentRunner.readOverview(core: core)
  #expect(!overview.date.isEmpty)
  let sessionContext = try await LorvexSystemIntentRunner.readSessionContext(core: core)
  #expect(!sessionContext.date.isEmpty)
  let setupStatus = try await LorvexSystemIntentRunner.readSetupStatus(core: core)
  #expect(setupStatus.setupCompleted)
  let syncStatus = try await LorvexSystemIntentRunner.readSyncStatus(core: core)
  #expect(syncStatus.backend == "unknown")
  let changelog = try await LorvexSystemIntentRunner.readAIChangelog(core: core)
  #expect(!changelog.entries.isEmpty)
  let recentLogs = try await LorvexSystemIntentRunner.readRecentLogs(core: core)
  #expect(recentLogs.redactionApplied)
  let guide = try await LorvexSystemIntentRunner.readGuide(core: core)
  #expect(!guide.suggestedActions.isEmpty)
}
