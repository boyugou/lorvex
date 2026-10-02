import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func sharedSystemIntentRunnerCompletesSetupAndReadsOverview() async throws {
  let core = try await makeSeededInMemoryCore()
  let setupPreferences = try await LorvexSystemIntentRunner.completeSetup(
    workingHours: #"{"start":"09:00","end":"17:00"}"#, defaultListID: "inbox",
    timezone: "America/Los_Angeles", core: core)
  #expect(setupPreferences.values["setup_completed"] == "true")
  let overview = try await LorvexSystemIntentRunner.readOverview(core: core)
  #expect(!overview.date.isEmpty)
}
