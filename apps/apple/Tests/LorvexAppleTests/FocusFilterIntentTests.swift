@testable import LorvexApple
@testable import LorvexSystemIntents
import AppIntents
import Foundation
import LorvexCore
import Testing

@Test("a Focus filter with no lists chosen narrows nothing")
func lorvexFocusFilterWithoutListsMeansInactive() async throws {
  let root = focusFilterIntentTempDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = FocusFilterStore(
    managedDatabasePath: root.appendingPathComponent("db.sqlite").path)
  _ = try await store.save(FocusFilterConfiguration(listIDs: ["work"]))

  let intent = LorvexFocusFilterIntent()
  intent.lists = nil
  let observedAtRepublish = IntentLockedBox<FocusFilterConfiguration?>(nil)

  try await intent.apply(store: store) {
    observedAtRepublish.set(try await store.load())
  }

  #expect(try await store.load() == .inactive)
  #expect(observedAtRepublish.value == .inactive)
}

@Test("an active Focus transition persists its chosen lists before republishing")
func lorvexFocusFilterListsPersistBeforeRepublish() async throws {
  let root = focusFilterIntentTempDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = FocusFilterStore(
    managedDatabasePath: root.appendingPathComponent("db.sqlite").path)

  let intent = LorvexFocusFilterIntent()
  intent.lists = [
    LorvexFocusFilterListEntity(id: "work", name: "Work"),
    LorvexFocusFilterListEntity(id: "deleted", name: ""),
  ]
  let observedAtRepublish = IntentLockedBox<FocusFilterConfiguration?>(nil)

  try await intent.apply(store: store) {
    observedAtRepublish.set(try await store.load())
  }

  let expected = FocusFilterConfiguration(listIDs: ["work", "deleted"])
  #expect(try await store.load() == expected)
  #expect(observedAtRepublish.value == expected)
  #expect(expected.isActive)
}

@Test("the shipping iOS project hosts the Focus filter only in an App Intents extension")
func focusFilterHasDedicatedExtensionWiring() throws {
  let project = try String(
    contentsOfFile: "Config/XcodeGen/project.yml", encoding: .utf8)
  #expect(project.contains("LorvexFocusFilterExtension:"))
  #expect(project.contains("type: extensionkit-extension"))
  #expect(project.contains("- LorvexFocusFilterIntent.swift"))
  #expect(project.contains("- target: LorvexFocusFilterExtension"))

  let infoData = try Data(contentsOf: URL(fileURLWithPath:
    "Config/LorvexFocusFilterExtension-Info.plist"))
  let info = try #require(
    PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any])
  let attributes = try #require(info["EXAppExtensionAttributes"] as? [String: Any])
  #expect(attributes["EXExtensionPointIdentifier"] as? String == "com.apple.appintents-extension")

  let entitlementsData = try Data(contentsOf: URL(fileURLWithPath:
    "Config/LorvexFocusFilterExtension.entitlements"))
  let entitlements = try #require(
    PropertyListSerialization.propertyList(from: entitlementsData, format: nil)
      as? [String: Any])
  #expect(
    entitlements["com.apple.security.application-groups"] as? [String]
      == [LorvexProductMetadata.appGroupIdentifier])
}

private final class IntentLockedBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Value

  init(_ value: Value) { stored = value }

  var value: Value {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  func set(_ value: Value) {
    lock.lock()
    stored = value
    lock.unlock()
  }
}

private func focusFilterIntentTempDirectory() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "lorvex-focus-filter-intent-\(UUID().uuidString)", isDirectory: true)
}
