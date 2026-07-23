import Foundation
import LorvexCore

/// Calendar presentation: a focused day timeline, the default week timeline,
/// or the month grid. `String`-backed so the workspace can persist the user's
/// choice via `@AppStorage`, matching how the Tasks workspace persists
/// `isTableMode`.
enum CalendarPresentationMode: String, Hashable, CaseIterable {
  case day
  case week
  case month
}
