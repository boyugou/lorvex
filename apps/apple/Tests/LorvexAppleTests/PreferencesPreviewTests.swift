import Foundation
import LorvexCore
import Testing

@Suite("Preferences + Setup preview-bridge")
struct PreferencesPreviewTests {
  @Test
  func getAllPreferencesSeedsDefaults() async throws {
    let core = try await makeSeededInMemoryCore()
    let snapshot = try await core.getAllPreferences()
    #expect(snapshot["working_hours"] != nil)
    #expect(snapshot["default_list_id"] != nil)
    #expect(snapshot["timezone"] != nil)
    // The preview dataset describes a store in active use, so setup is done.
    #expect(snapshot["setup_completed"] == "true")
  }

  @Test
  func getPreferenceReturnsSeedAndNilForUnknown() async throws {
    let core = try await makeSeededInMemoryCore()
    let theme = try await core.getPreference(key: "theme")
    #expect(theme == "\"system\"")
    let unknown = try await core.getPreference(key: "missing_key")
    #expect(unknown == nil)
  }

  @Test
  func setPreferencePersistsAndReturnsValue() async throws {
    let core = try await makeSeededInMemoryCore()
    let written = try await core.setPreference(key: "theme", value: "\"dark\"")
    #expect(written == "\"dark\"")
    let snapshot = try await core.getAllPreferences()
    #expect(snapshot["theme"] == "\"dark\"")
  }

  @Test
  func completeSetupMarksCompletedAndUpdatesPrefs() async throws {
    let core = try await makeSeededInMemoryCore()
    let snapshot = try await core.completeSetup(
      workingHours: #"{"start":"08:00","end":"16:00"}"#,
      defaultListID: LorvexPreviewSeedID.appleNativeList,
      timezone: "Europe/Berlin"
    )
    #expect(snapshot["setup_completed"] == "true")
    let storedWorkingHours = try #require(snapshot["working_hours"]?.data(using: .utf8))
    let decodedWorkingHours = try JSONDecoder().decode([String: String].self, from: storedWorkingHours)
    #expect(decodedWorkingHours == ["start": "08:00", "end": "16:00"])
    #expect(snapshot["default_list_id"] == "\"\(LorvexPreviewSeedID.appleNativeList)\"")
    // Stored preference values are raw JSON; the encoder may escape the
    // solidus, so compare the decoded string.
    let storedTimezone = try #require(snapshot["timezone"]?.data(using: .utf8))
    #expect(try JSONDecoder().decode(String.self, from: storedTimezone) == "Europe/Berlin")
  }

  @Test
  func preferenceWritesRejectMalformedTypedValues() async throws {
    let core = try makeInMemoryCore()

    await #expect(throws: (any Error).self) {
      _ = try await core.setPreference(key: "timezone", value: "Mars/Olympus_Mons")
    }
    await #expect(throws: (any Error).self) {
      _ = try await core.setPreference(key: "working_hours", value: "18:00-09:00")
    }
    await #expect(throws: (any Error).self) {
      _ = try await core.setPreference(key: "setup_completed", value: "yes")
    }
    #expect(try await core.getPreference(key: "timezone") == nil)
    #expect(try await core.getPreference(key: "working_hours") == nil)
    #expect(try await core.getPreference(key: "setup_completed") == nil)
  }

  @Test
  func setupCanonicalizesAndMaterializesTimezoneAuthority() async throws {
    let core = try makeInMemoryCore()
    let snapshot = try await core.completeSetup(
      workingHours: nil,
      defaultListID: nil,
      timezone: "  America/Los_Angeles  ")

    #expect(snapshot["timezone"] == "\"America/Los_Angeles\"")
    #expect(try await core.getSessionContext().timezone == "America/Los_Angeles")
    await #expect(throws: (any Error).self) {
      try await core.deletePreference(key: "timezone")
    }
  }

  @Test
  func getOverviewCompactReflectsPreviewTasks() async throws {
    let core = try await makeSeededInMemoryCore()
    let overview = try await core.getOverviewCompact()
    #expect(overview.topTasks.count <= 5)
    #expect(overview.stats.openCount >= overview.topTasks.count)
  }

  @Test
  func getSessionContextReportsStoreDevice() async throws {
    let core = try await makeSeededInMemoryCore()
    let context = try await core.getSessionContext()
    // The store mints its own device identity (a UUID), and the session
    // context reports the decoded timezone identifier, not the raw JSON.
    let deviceID = try #require(context.deviceID)
    #expect(UUID(uuidString: deviceID) != nil)
    #expect(context.syncBackend == "unknown")
    #expect(context.timezone == "America/Los_Angeles")
    #expect(context.workingHours != nil)
  }
}
