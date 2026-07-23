import Foundation
import LorvexDomain

/// Lorvex custom URL scheme routes used for deep linking and notification payloads.
///
/// All cases produce URLs in the `lorvex://` scheme via `LorvexDeepLinkContract`.
///
/// This is the single entity-open resolver shared by the three continuation
/// surfaces — custom-URL deep links (`init?(url:)`), Handoff / Siri
/// `NSUserActivity` (`init?(activity:)`), and Spotlight result taps
/// (`init?(spotlightIdentifier:)`). Each surface decodes to the same enum, which
/// `AppStore.openDeepLinkRoute(_:)` / `MobileStore` then route through one
/// navigation path.
public enum LorvexDeepLinkRoute: Equatable, Sendable {
  public static let scheme = LorvexDeepLinkContract.scheme
  public static let openHost = LorvexDeepLinkContract.openHost
  public static let taskHost = LorvexDeepLinkContract.taskHost
  public static let listHost = LorvexDeepLinkContract.listHost
  public static let habitHost = LorvexDeepLinkContract.habitHost
  public static let reviewHost = LorvexDeepLinkContract.reviewHost

  case destination(SidebarSelection)
  case task(LorvexTask.ID)
  case list(String)
  case habit(String)
  case review(date: String)

  public init?(url: URL) {
    guard url.scheme == Self.scheme else { return nil }
    let host = url.host()?.lowercased()
    // The contract encodes an entire id as one percent-encoded path segment, so an
    // id containing "/" round-trips as %2F; decode the whole path as a unit rather
    // than via pathComponents (which would split on the decoded slash).
    let pathID = LorvexDeepLinkContract.decodedPathComponent(from: url)

    switch host {
    case Self.taskHost:
      guard let id = pathID, let validID = Self.validatedID(id) else { return nil }
      self = .task(validID)
    case Self.listHost:
      guard let id = pathID, let validID = Self.validatedID(id) else { return nil }
      self = .list(validID)
    case Self.habitHost:
      guard let id = pathID, let validID = Self.validatedID(id) else { return nil }
      self = .habit(validID)
    case Self.reviewHost:
      guard let date = pathID, let validDate = Self.validatedReviewDate(date) else { return nil }
      self = .review(date: validDate)
    case Self.openHost:
      guard let rawDestination = pathID,
        let destination = SidebarSelection.matching(rawDestination)
      else { return nil }
      self = .destination(destination)
    default:
      guard let rawDestination = host,
        let destination = SidebarSelection.matching(rawDestination)
      else { return nil }
      self = .destination(destination)
    }
  }

  /// Resolves a Handoff / Siri `NSUserActivity` to a route.
  ///
  /// Mirrors the activity types in `LorvexActivityType`: `openTask` → `.task`,
  /// `openList` → `.list`, `openDestination` → `.destination`. Returns nil for an
  /// unrecognised type or a missing / empty payload.
  public init?(activity: NSUserActivity) {
    switch activity.activityType {
    case LorvexActivityType.openTask:
      guard let id = activity.userInfo?[LorvexActivityKey.taskID] as? String,
        let validID = Self.validatedID(id)
      else { return nil }
      self = .task(validID)
    case LorvexActivityType.openList:
      guard let id = activity.userInfo?[LorvexActivityKey.listID] as? String,
        let validID = Self.validatedID(id)
      else { return nil }
      self = .list(validID)
    case LorvexActivityType.openDestination:
      guard let raw = activity.userInfo?[LorvexActivityKey.destination] as? String,
        let destination = SidebarSelection.matching(raw)
      else { return nil }
      self = .destination(destination)
    default:
      return nil
    }
  }

  /// Resolves a Spotlight `CSSearchableItem.uniqueIdentifier` to a route.
  ///
  /// The Spotlight document builders stamp every item with a prefixed identifier
  /// (`lorvex-task:<id>`, `lorvex-list:<id>`, `lorvex-habit:<id>`,
  /// `lorvex-review:<date>`, `lorvex-calendar-event:<id>`); this is the inverse,
  /// so a tapped result opens the indexed entity. A calendar event has no
  /// per-event detail route, so it opens the calendar workspace (matching the
  /// document's own deep link). Returns nil for an unknown prefix or an empty id.
  public init?(spotlightIdentifier identifier: String) {
    func id(after prefix: String) -> String? {
      guard identifier.hasPrefix(prefix) else { return nil }
      let value = String(identifier.dropFirst(prefix.count))
      return value.isEmpty ? nil : value
    }
    if id(after: "lorvex-calendar-event:") != nil { self = .destination(.calendar) }
    else if let value = id(after: "lorvex-task:"), let validID = Self.validatedID(value) {
      self = .task(validID)
    } else if let value = id(after: "lorvex-list:"), let validID = Self.validatedID(value) {
      self = .list(validID)
    } else if let value = id(after: "lorvex-habit:"), let validID = Self.validatedID(value) {
      self = .habit(validID)
    } else if let value = id(after: "lorvex-review:"),
      let validDate = Self.validatedReviewDate(value)
    {
      self = .review(date: validDate)
    } else { return nil }
  }

  public var url: URL {
    switch self {
    case .destination(let destination):
      LorvexDeepLinkContract.destinationURL(destination)
    case .task(let id):
      LorvexDeepLinkContract.taskURL(id)
    case .list(let id):
      LorvexDeepLinkContract.listURL(id)
    case .habit(let id):
      LorvexDeepLinkContract.habitURL(id)
    case .review(let date):
      LorvexDeepLinkContract.reviewURL(date: date)
    }
  }

  /// Maximum accepted length, in UTF-8 bytes, for a task/list/habit id carried
  /// in a route. Generous relative to a UUIDv7 (36 chars) so a legacy or
  /// imported id that isn't a canonical UUID still round-trips — the core's own
  /// by-id reads accept any non-empty string, so this is deliberately not a
  /// UUID-shape check. It exists only to stop a malformed external URL /
  /// activity / Spotlight identifier from carrying an unbounded string into
  /// navigation state.
  private static let maxIDLength = 512

  /// Validates an id decoded from an external URL, `NSUserActivity`, or
  /// Spotlight identifier before it becomes route state: trims surrounding
  /// whitespace, then rejects an empty result, a result containing a Unicode
  /// control character, or one longer than ``maxIDLength``. Returns the
  /// trimmed id, or nil to reject the whole route.
  private static func validatedID(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.utf8.count <= maxIDLength else { return nil }
    guard !trimmed.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
    else { return nil }
    return trimmed
  }

  /// Validates a `.review` route's date as a real calendar date in the
  /// canonical `YYYY-MM-DD` storage form, via the same ``LorvexDate`` parser
  /// every persisted date column is validated through — rather than accepting
  /// any nonempty string. Returns the canonical string, or nil to reject.
  private static func validatedReviewDate(_ raw: String) -> String? {
    guard case .success(let date) = LorvexDate.parse(raw) else { return nil }
    return date.asString
  }
}
