import AppIntents
import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing
import UniformTypeIdentifiers

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func reviewIntentPerformThrowsOnInvalidInputs() async throws {
  let amend = AmendLorvexDailyReviewIntent(date: "   ", summary: "Updated")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await amend.perform()
  }

  let history = ReadLorvexReviewHistoryIntent(limit: 0)
  await #expect(throws: LorvexCoreError.self) {
    _ = try await history.perform()
  }
}

// MARK: - SaveLorvexMemoryIntent

@Test
func saveMemoryIntentPerformThrowsOnBlankKey() async throws {
  let intent = SaveLorvexMemoryIntent(key: "   ", content: "Shortcut memory")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await intent.perform()
  }
}

@Test
func readDiagnosticsIntentPerformSucceeds() async throws {
  let intent = ReadLorvexRuntimeDiagnosticsIntent()
  try await withIsolatedAppIntentDatabase {
    _ = try await intent.perform()
  }
}

@Test
func systemContextIntentPerformSucceeds() async throws {
  try await withIsolatedAppIntentDatabase {
    _ = try await ReadLorvexPreferencesIntent().perform()
    _ = try await ReadLorvexPreferenceIntent(key: "timezone").perform()
    _ = try await SetLorvexPreferenceIntent(key: "theme", value: "\"system\"")
      .perform()
    // DeleteLorvexPreferenceIntent is destructive: it requests confirmation
    // before mutating, which throws without a system context. Its
    // confirmation-before-mutation behaviour is covered by
    // `destructiveIntentRequestsConfirmationBeforeMutating`.
    _ = try await CompleteLorvexSetupIntent(
      workingHours: #"{"start":"09:30","end":"17:30"}"#,
      defaultList: LorvexListEntity(id: "inbox", name: "", openCount: 0, totalCount: 0),
      timezone: "America/Los_Angeles"
    ).perform()
    _ = try await ReadLorvexOverviewIntent().perform()
    _ = try await ReadLorvexSessionContextIntent().perform()
  }
}

@Test
func exportDataIntentPerformSucceeds() async throws {
  let intent = ExportLorvexDataIntent(format: .json, entities: [.tasks, .lists])
  try await withIsolatedAppIntentDatabase {
    _ = try await intent.perform()
  }
}

@Test
func exportCalendarICSIntentPerformSucceeds() async throws {
  let intent = ExportLorvexCalendarICSIntent(from: nil, to: nil)
  try await withIsolatedAppIntentDatabase {
    _ = try await intent.perform()
  }
}

@Test
func exportIntentFilesCarryContentNamesAndTypes() throws {
  let json = LorvexExportIntentFileFactory.dataFile(content: #"{"tasks":[]}"#, format: .json)
  #expect(json.filename == "lorvex-export.json")
  #expect(json.type == .json)
  #expect(String(decoding: json.data, as: UTF8.self).contains(#""tasks""#))

  let csv = LorvexExportIntentFileFactory.dataFile(content: "id,title\n1,Plan", format: .csv)
  #expect(csv.filename == "lorvex-export.csv")
  #expect(csv.type == .commaSeparatedText)
  #expect(String(decoding: csv.data, as: UTF8.self).contains("Plan"))

  let ics = LorvexExportIntentFileFactory.calendarFile(content: "BEGIN:VCALENDAR\nEND:VCALENDAR")
  #expect(ics.filename == "lorvex-calendar.ics")
  #expect(ics.type == (UTType("com.apple.ical.ics") ?? .data))
  #expect(String(decoding: ics.data, as: UTF8.self).contains("BEGIN:VCALENDAR"))
}

@Test
func systemContextIntentPerformThrowsOnInvalidInputs() async throws {
  await #expect(throws: LorvexCoreError.self) {
    _ = try await ReadLorvexPreferenceIntent(key: "   ").perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await SetLorvexPreferenceIntent(key: "theme", value: "   ").perform()
  }
  // DeleteLorvexPreferenceIntent now confirms before validating/mutating, so a
  // blank key surfaces the confirmation gate rather than a core error; see
  // `destructiveIntentRequestsConfirmationBeforeMutating`.
}

@Test
func readMemoryIntentPerformThrowsOnBlankKey() async throws {
  let intent = ReadLorvexMemoryIntent(key: "   ")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await intent.perform()
  }
}

@Test
func deleteMemoryIntentPerformThrowsOnBlankKey() async throws {
  // Destructive intents confirm before validating input, so perform() surfaces
  // the confirmation gate (no system context in a unit test) rather than a core
  // error. Blank-key rejection is covered by the runner-level tests.
  let intent = DeleteLorvexMemoryIntent(key: "   ")
  await #expect(throws: (any Error).self) {
    _ = try await intent.perform()
  }
}

// MARK: - CompleteLorvexTaskIntent
