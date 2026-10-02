@preconcurrency import CoreSpotlight
import Foundation
import LorvexCore
import UniformTypeIdentifiers

/// A Spotlight searchable item for a list.
///
/// Privacy: only the list name is indexed. The free-text list description is
/// deliberately not written to the system index.
struct SpotlightListDocument: Equatable, Sendable {
  static let domainIdentifier = "lorvex.lists"
  static let identifierPrefix = "lorvex-list:"

  var identifier: String
  var title: String

  init(list: LorvexList) {
    identifier = Self.identifierPrefix + list.id
    title = list.displayName
  }

  var searchableItem: CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .content)
    attributes.title = title
    attributes.contentURL = deepLink
    return CSSearchableItem(
      uniqueIdentifier: identifier,
      domainIdentifier: Self.domainIdentifier,
      attributeSet: attributes
    )
  }

  var deepLink: URL {
    LorvexDeepLinkRoute.list(String(identifier.dropFirst(Self.identifierPrefix.count))).url
  }
}

/// A Spotlight searchable item for a habit.
///
/// Privacy: only the habit name is indexed. The free-text cue is deliberately
/// not written to the system index.
struct SpotlightHabitDocument: Equatable, Sendable {
  static let domainIdentifier = "lorvex.habits"
  static let identifierPrefix = "lorvex-habit:"

  var identifier: String
  var title: String

  init(habit: LorvexHabit) {
    identifier = Self.identifierPrefix + habit.id
    title = habit.name
  }

  var searchableItem: CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .content)
    attributes.title = title
    attributes.contentURL = deepLink
    return CSSearchableItem(
      uniqueIdentifier: identifier,
      domainIdentifier: Self.domainIdentifier,
      attributeSet: attributes
    )
  }

  var deepLink: URL {
    LorvexDeepLinkRoute.habit(String(identifier.dropFirst(Self.identifierPrefix.count))).url
  }
}

/// A Spotlight searchable item for a daily review.
///
/// Privacy: only the date-based title ("Daily Review Sep 29, 2026", the day in
/// the user's language) is indexed. The review summary — a highly personal
/// free-text reflection — is deliberately not written to the system index.
struct SpotlightDailyReviewDocument: Equatable, Sendable {
  static let domainIdentifier = "lorvex.reviews"
  static let identifierPrefix = "lorvex-review:"

  var identifier: String
  var title: String

  init(review: DailyReviewEntry) {
    identifier = Self.identifierPrefix + review.date
    // The review's day is a calendar day, not an instant: read and written in
    // UTC so it never shifts across the device's time zone.
    let day =
      LorvexDateFormatters.ymdUTC.date(from: review.date).map {
        LorvexDateFormatters.string($0, dateStyle: .medium, timeZone: .gmt)
      } ?? review.date
    title = String(
      localized: "spotlight.daily_review.title", defaultValue: "Daily Review \(day)", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  var searchableItem: CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .content)
    attributes.title = title
    attributes.contentURL = deepLink
    return CSSearchableItem(
      uniqueIdentifier: identifier,
      domainIdentifier: Self.domainIdentifier,
      attributeSet: attributes
    )
  }

  var deepLink: URL {
    LorvexDeepLinkRoute.review(
      date: String(identifier.dropFirst(Self.identifierPrefix.count))
    ).url
  }
}

/// A Spotlight searchable item for a calendar event.
///
/// Privacy: only the event title is indexed. The event time summary, location,
/// source, and other metadata are deliberately not written to the system index.
struct SpotlightCalendarEventDocument: Equatable, Sendable {
  static let domainIdentifier = "lorvex.calendar-events"
  static let identifierPrefix = "lorvex-calendar-event:"

  var identifier: String
  var title: String

  init(event: CalendarTimelineEvent) {
    // Expanded occurrence ids are transient render identity and churn whenever
    // recurrence generation changes. This title-only, calendar-level document
    // represents the durable source event or series segment instead.
    identifier = Self.identifierPrefix + event.eventID
    title = event.title
  }

  var searchableItem: CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .content)
    attributes.title = title
    attributes.contentURL = deepLink
    return CSSearchableItem(
      uniqueIdentifier: identifier,
      domainIdentifier: Self.domainIdentifier,
      attributeSet: attributes
    )
  }

  var deepLink: URL {
    LorvexDeepLinkRoute.destination(.calendar).url
  }
}
