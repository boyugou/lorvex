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

  let setupPreferences = try await LorvexTaskIntentRunner.completeSetup(
    workingHours: #"{"start":"10:00","end":"18:00"}"#,
    defaultListID: "inbox",
    timezone: "America/Los_Angeles",
    core: core
  )
  #expect(setupPreferences.values["setup_completed"] == "true")
  let overview = try await LorvexTaskIntentRunner.readOverview(core: core)
  #expect(!overview.date.isEmpty)

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
}
