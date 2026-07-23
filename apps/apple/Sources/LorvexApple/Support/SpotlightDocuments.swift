@preconcurrency import CoreSpotlight
import Foundation
import LorvexCore
import UniformTypeIdentifiers

/// A Spotlight searchable item for a task.
///
/// Privacy: only low-sensitivity identifying text is written to the system
/// index — the task title and, as a structured attribute, the due date. The
/// high-sensitivity free text (notes, `ai_notes`, checklist item text) and the
/// user's tags are deliberately NOT indexed, so search-by-title stays useful
/// without exposing a task's contents to the system-wide index.
struct SpotlightTaskDocument: Equatable, Sendable {
  static let domainIdentifier = "lorvex.tasks"
  static let identifierPrefix = "lorvex-task:"

  var identifier: String
  var title: String
  var dueDate: Date?

  init(task: LorvexTask) {
    identifier = Self.identifierPrefix + task.id
    title = task.title
    dueDate = task.dueDate
  }

  var searchableItem: CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .text)
    attributes.title = title
    attributes.dueDate = dueDate
    attributes.contentURL = deepLink
    attributes.relatedUniqueIdentifier = deepLink.absoluteString
    return CSSearchableItem(
      uniqueIdentifier: identifier,
      domainIdentifier: Self.domainIdentifier,
      attributeSet: attributes
    )
  }

  var deepLink: URL {
    LorvexDeepLinkRoute.task(String(identifier.dropFirst(Self.identifierPrefix.count))).url
  }
}
