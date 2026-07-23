import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func taskIntentRunnerHandlesMemoryExportAndSystemActions() async throws {
  let core = try await makeSeededInMemoryCore()

  let memory = try await LorvexTaskIntentRunner.saveMemory(
    key: " shortcut_context ",
    content: "  Created from App Shortcuts  ",
    core: core
  )
  #expect(memory.key == "shortcut_context")
  #expect(memory.content == "Created from App Shortcuts")

  let readMemory = try await LorvexTaskIntentRunner.readMemory(
    key: " shortcut_context ",
    core: core
  )
  #expect(readMemory == memory)

  let deletedKey = try await LorvexTaskIntentRunner.deleteMemory(
    key: " shortcut_context ",
    core: core
  )
  #expect(deletedKey == "shortcut_context")
  let postDeleteMemory = try await core.loadMemory()
  #expect(!postDeleteMemory.entries.contains { $0.key == "shortcut_context" })

  let preferences = try await LorvexTaskIntentRunner.readPreferences(core: core)
  #expect(preferences.values["theme"] == "\"system\"")
  let timezone = try await LorvexTaskIntentRunner.readPreference(key: " timezone ", core: core)
  #expect(timezone == "\"America/Los_Angeles\"")
  let preferenceValue = try await LorvexTaskIntentRunner.setPreference(
    key: " record_raw_input ",
    value: " true ",
    core: core
  )
  #expect(preferenceValue == "true")
  let setupPreferences = try await LorvexTaskIntentRunner.completeSetup(
    workingHours: #"{"start":"10:00","end":"18:00"}"#,
    defaultListID: "inbox",
    timezone: "America/Los_Angeles",
    core: core
  )
  #expect(setupPreferences.values["setup_completed"] == "true")
  let overview = try await LorvexTaskIntentRunner.readOverview(core: core)
  #expect(!overview.date.isEmpty)
  let sessionContext = try await LorvexTaskIntentRunner.readSessionContext(core: core)
  #expect(!sessionContext.date.isEmpty)

  let jsonExport = try await LorvexTaskIntentRunner.exportData(
    format: " json ",
    entities: [" tasks ", "lists"],
    core: core
  )
  #expect(jsonExport.contains("\"tasks\""))
  #expect(jsonExport.contains("\"lists\""))

  let icsExport = try await LorvexTaskIntentRunner.exportCalendarICS(
    from: nil,
    to: nil,
    core: core
  )
  #expect(icsExport.contains("BEGIN:VCALENDAR"))
  #expect(icsExport.contains("END:VCALENDAR"))

  let diagnostics = try await LorvexTaskIntentRunner.readRuntimeDiagnostics(core: core)
  #expect(diagnostics.setup.setupCompleted)
  #expect(diagnostics.sync.backend == "unknown")
  let setupStatus = try await LorvexTaskIntentRunner.readSetupStatus(core: core)
  #expect(setupStatus.setupCompleted)
  let syncStatus = try await LorvexTaskIntentRunner.readSyncStatus(core: core)
  #expect(syncStatus.backend == "unknown")
  // App Intent writes are user-initiated (ambient initiator `user`), so they are
  // correctly excluded from the assistant-only ai_changelog surface
  // (`AiChangelogActorFilter`). The read still succeeds; it simply does not
  // surface this runner's own user-attributed memory writes.
  let changelog = try await LorvexTaskIntentRunner.readAIChangelog(core: core)
  #expect(!changelog.entries.contains { $0.summary.contains("shortcut_context") })
  let recentLogs = try await LorvexTaskIntentRunner.readRecentLogs(core: core)
  #expect(recentLogs.redactionApplied)
  let guide = try await LorvexTaskIntentRunner.readGuide(core: core)
  #expect(guide.topic == "overview")
}
