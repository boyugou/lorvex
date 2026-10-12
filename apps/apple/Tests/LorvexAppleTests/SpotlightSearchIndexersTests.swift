import CoreSpotlight
import Foundation
import XCTest

@testable import LorvexApple

private actor SpotlightBackendRecorder {
  private(set) var addedIdentifiers: [[String]] = []
  private(set) var deletedIdentifiers: [[String]] = []
  private(set) var deletedDomains: [[String]] = []

  func recordAdded(_ items: [CSSearchableItem]) {
    addedIdentifiers.append(items.map(\.uniqueIdentifier))
  }

  func recordDeletedIdentifiers(_ identifiers: [String]) {
    deletedIdentifiers.append(identifiers)
  }

  func recordDeletedDomains(_ domains: [String]) {
    deletedDomains.append(domains)
  }
}

final class SpotlightSearchIndexersTests: XCTestCase {
  func testEmptyReplacementDeletesWholeDomainWithoutPersistedIdentifierLedger() async throws {
    let suiteName = "SpotlightSearchIndexersTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let recorder = SpotlightBackendRecorder()
    let backend = SpotlightIndexBackend(
      addItems: { await recorder.recordAdded($0.items) },
      deleteIdentifiers: { await recorder.recordDeletedIdentifiers($0) },
      deleteDomains: { await recorder.recordDeletedDomains($0) })
    let indexer = SpotlightDomainIndexer(
      defaultsStore: SpotlightDefaultsStore(defaults: defaults), backend: backend)

    try await indexer.replace(domain: "lorvex.tasks", items: [])

    let deletedDomains = await recorder.deletedDomains
    let deletedIdentifiers = await recorder.deletedIdentifiers
    let addedIdentifiers = await recorder.addedIdentifiers
    XCTAssertEqual(deletedDomains, [["lorvex.tasks"]])
    XCTAssertTrue(deletedIdentifiers.isEmpty)
    XCTAssertTrue(addedIdentifiers.isEmpty)
    XCTAssertNil(defaults.object(forKey: "spotlight.indexedIdentifiers.lorvex.tasks"))
  }

  private func item(_ id: String, title: String) -> CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .content)
    attributes.title = title
    return CSSearchableItem(
      uniqueIdentifier: id, domainIdentifier: "lorvex.tasks", attributeSet: attributes)
  }

  func testReplaceAddsOnlyTheItemsThatChangedSinceTheLastReplace() async throws {
    let suiteName = "SpotlightSearchIndexersTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let recorder = SpotlightBackendRecorder()
    let backend = SpotlightIndexBackend(
      addItems: { await recorder.recordAdded($0.items) },
      deleteIdentifiers: { await recorder.recordDeletedIdentifiers($0) },
      deleteDomains: { await recorder.recordDeletedDomains($0) })
    let indexer = SpotlightDomainIndexer(
      defaultsStore: SpotlightDefaultsStore(defaults: defaults), backend: backend)

    try await indexer.replace(
      domain: "lorvex.tasks", items: [item("a", title: "One"), item("b", title: "Two")])
    // Nothing changed: nothing is written.
    try await indexer.replace(
      domain: "lorvex.tasks", items: [item("a", title: "One"), item("b", title: "Two")])
    // One title changed and one item is new: only those two are written.
    try await indexer.replace(
      domain: "lorvex.tasks",
      items: [item("a", title: "One"), item("b", title: "Two, edited"), item("c", title: "Three")])
    // An item left the list: it is deleted and nothing is added.
    try await indexer.replace(
      domain: "lorvex.tasks",
      items: [item("a", title: "One"), item("b", title: "Two, edited")])

    let added = await recorder.addedIdentifiers
    let deleted = await recorder.deletedIdentifiers
    XCTAssertEqual(added, [["a", "b"], ["b", "c"]])
    XCTAssertEqual(deleted, [["c"]])
  }
}
