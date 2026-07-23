import MCP

extension ToolRegistry {
  func allPreferencesPayload() async throws -> Value {
    try await coreBridge.getAllPreferences()
  }

  func preferencePayload(key: String) async throws -> Value {
    try await coreBridge.getPreference(key: key)
  }

  func setPreferencePayload(key: String, value: String) async throws -> Value {
    try await coreBridge.setPreference(key: key, value: value)
  }

  func completeSetupPayload(
    workingHours: String?,
    defaultListID: String?,
    timezone: String?
  ) async throws -> Value {
    try await coreBridge.completeSetup(
      workingHours: workingHours,
      defaultListID: defaultListID,
      timezone: timezone
    )
  }

  func overviewCompactPayload() async throws -> Value {
    try await coreBridge.loadOverviewCompact()
  }
}
