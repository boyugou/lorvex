@preconcurrency import CoreSpotlight
import Foundation
import LorvexCore

struct SpotlightItemBatch: @unchecked Sendable {
  let items: [CSSearchableItem]
}

struct SpotlightDefaultsStore: @unchecked Sendable {
  let defaults: UserDefaults
}

struct SpotlightIndexBackend: @unchecked Sendable {
  let addItems: (SpotlightItemBatch) async throws -> Void
  let deleteIdentifiers: ([String]) async throws -> Void
  let deleteDomains: ([String]) async throws -> Void

  static func live(
    index: CSSearchableIndex = CSSearchableIndex(
      name: SpotlightDomainIndexer.indexName,
      protectionClass: SpotlightDomainIndexer.protectionClass)
  ) -> Self {
    Self(
      addItems: { batch in
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          index.indexSearchableItems(batch.items) { error in
            if let error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume()
            }
          }
        }
      },
      deleteIdentifiers: { identifiers in
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          index.deleteSearchableItems(withIdentifiers: identifiers) { error in
            if let error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume()
            }
          }
        }
      },
      deleteDomains: { domains in
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          index.deleteSearchableItems(withDomainIdentifiers: domains) { error in
            if let error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume()
            }
          }
        }
      })
  }
}

/// An app-owned CoreSpotlight index that replaces a domain's contents
/// non-destructively.
///
/// Uses `CSSearchableIndex(name:protectionClass:)` with
/// `.completeUntilFirstUserAuthentication` — the indexed content is only
/// readable after the device is first unlocked following a boot. This is the
/// deliberate production alternative to `CSSearchableIndex.default()`, which
/// Apple documents as providing no data protection and as being for
/// prototyping only.
///
/// `replace(domain:items:)` indexes the new items FIRST, then deletes only the
/// identifiers that were indexed for that domain previously but are absent now.
/// Because items are keyed by a stable `uniqueIdentifier`, re-indexing updates
/// them in place, so a failure while indexing leaves the previous corpus intact
/// instead of emptying the domain — the failure mode of the delete-then-index
/// ordering. The per-domain identifier set is persisted (in `UserDefaults`), so
/// items removed while the app was closed are still pruned on the next run.
actor SpotlightDomainIndexer {
  static let indexName = "lorvex-content"
  static let protectionClass: FileProtectionType = .completeUntilFirstUserAuthentication

  private let backend: SpotlightIndexBackend
  private let defaults: UserDefaults
  private var indexedIdentifiers: [String: Set<String>] = [:]

  init(
    defaultsStore: SpotlightDefaultsStore = SpotlightDefaultsStore(defaults: .standard),
    backend: SpotlightIndexBackend = .live()
  ) {
    self.backend = backend
    defaults = defaultsStore.defaults
  }

  func replace(domain: String, items: [CSSearchableItem]) async throws {
    let newIdentifiers = Set(items.map(\.uniqueIdentifier))
    let previous = indexedIdentifiers[domain] ?? loadPersisted(domain)

    // An empty canonical domain is also the factory-reset/clean-install case.
    // Delete it by domain, not by the persisted identifier ledger: production
    // installation deliberately clears defaults before the new app launches,
    // so that ledger may be gone while CoreSpotlight still holds old content.
    if items.isEmpty {
      try await backend.deleteDomains([domain])
      persist([], forDomain: domain)
      indexedIdentifiers[domain] = []
      return
    }

    try await backend.addItems(SpotlightItemBatch(items: items))
    let stale = previous.subtracting(newIdentifiers)
    if !stale.isEmpty {
      try await backend.deleteIdentifiers(Array(stale))
    }
    if previous != newIdentifiers {
      persist(newIdentifiers, forDomain: domain)
    }
    indexedIdentifiers[domain] = newIdentifiers
  }

  private func persistedKey(_ domain: String) -> String { "spotlight.indexedIdentifiers.\(domain)" }

  private func loadPersisted(_ domain: String) -> Set<String> {
    Set(defaults.stringArray(forKey: persistedKey(domain)) ?? [])
  }

  private func persist(_ identifiers: Set<String>, forDomain domain: String) {
    if identifiers.isEmpty {
      defaults.removeObject(forKey: persistedKey(domain))
    } else {
      defaults.set(Array(identifiers), forKey: persistedKey(domain))
    }
  }
}

struct SpotlightTaskSearchIndexer: TaskSearchIndexing {
  private let indexer: SpotlightDomainIndexer

  init(indexer: SpotlightDomainIndexer = SpotlightDomainIndexer()) {
    self.indexer = indexer
  }

  func replaceIndexedTasks(_ tasks: [LorvexTask]) async throws {
    let items = tasks.map { SpotlightTaskDocument(task: $0).searchableItem }
    try await indexer.replace(domain: SpotlightTaskDocument.domainIdentifier, items: items)
  }
}

struct SpotlightContentSearchIndexer: ContentSearchIndexing {
  private let indexer: SpotlightDomainIndexer

  init(indexer: SpotlightDomainIndexer = SpotlightDomainIndexer()) {
    self.indexer = indexer
  }

  func replaceIndexedLists(_ lists: [LorvexList]) async throws {
    let items = lists.map { SpotlightListDocument(list: $0).searchableItem }
    try await indexer.replace(domain: SpotlightListDocument.domainIdentifier, items: items)
  }

  func replaceIndexedHabits(_ habits: [LorvexHabit]) async throws {
    let items = habits.map { SpotlightHabitDocument(habit: $0).searchableItem }
    try await indexer.replace(domain: SpotlightHabitDocument.domainIdentifier, items: items)
  }

  func replaceIndexedDailyReview(_ review: DailyReviewEntry?) async throws {
    let items = review.map { [SpotlightDailyReviewDocument(review: $0).searchableItem] } ?? []
    try await indexer.replace(domain: SpotlightDailyReviewDocument.domainIdentifier, items: items)
  }

  func replaceIndexedCalendarEvents(_ events: [CalendarTimelineEvent]) async throws {
    let items = events.map { SpotlightCalendarEventDocument(event: $0).searchableItem }
    try await indexer.replace(domain: SpotlightCalendarEventDocument.domainIdentifier, items: items)
  }
}
