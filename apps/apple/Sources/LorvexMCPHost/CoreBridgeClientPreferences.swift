import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func getAllPreferences() async throws -> Value {
    Self.preferencesValue(from: try await service.getAllPreferences())
  }

  func getPreference(key: String) async throws -> Value {
    let value = try await service.getPreference(key: key)
    return .object([
      "key": .string(key),
      "value": SecurityFencing.fencePreferenceValue(
        key: key, value: value.map(Self.jsonStringValue(_:)) ?? .null),
    ])
  }

  func setPreference(key: String, value: String) async throws -> Value {
    let stored = try await service.setPreference(key: key, value: value)
    return .object([
      "key": .string(key),
      "value": SecurityFencing.fencePreferenceValue(
        key: key, value: Self.jsonStringValue(stored)),
    ])
  }

  func completeSetup(workingHours: String?, defaultListID: String?, timezone: String?) async throws
    -> Value
  {
    let snapshot = try await service.completeSetup(
      workingHours: workingHours, defaultListID: defaultListID, timezone: timezone)
    return Self.preferencesValue(from: snapshot)
  }

  func loadOverviewCompact() async throws -> Value {
    Self.overviewCompactValue(from: try await service.getOverviewCompact())
  }
}
