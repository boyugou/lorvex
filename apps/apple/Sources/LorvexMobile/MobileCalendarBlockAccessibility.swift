import LorvexCore
import SwiftUI

/// How a calendar block names its day to VoiceOver. In a grid of several days a
/// sighted reader tells which day a block belongs to by its column; VoiceOver
/// reads the blocks one after another and has no column to go by. A block in
/// such a grid therefore ends its label with its day's full date ("Standup from
/// 9:00 AM to 9:30 AM, Thursday, October 8, 2026"), and a one-day grid names no
/// day.
enum MobileCalendarBlockLabel {
  /// `label` followed by the full date of `date` in `calendar`'s time zone, or
  /// `label` alone when `date` is `nil`.
  static func appendingDay(_ label: String, of date: Date?, calendar: Calendar) -> String {
    guard let date else { return label }
    let day = LorvexDateFormatters.string(date, dateStyle: .full, timeZone: calendar.timeZone)
    return "\(label), \(day)"
  }
}

/// How a calendar surface that stands for one day names it to VoiceOver: the
/// week strip's buttons, the month grid's cells, and the headers over a time
/// grid's columns all say the same thing for the same day.
enum MobileCalendarDayName {
  /// The full date of `date` in `calendar`'s time zone ("Thursday, October 8,
  /// 2026"), after "Today," when `isToday`.
  static func spoken(_ date: Date, isToday: Bool, calendar: Calendar) -> String {
    let full = LorvexDateFormatters.string(date, dateStyle: .full, timeZone: calendar.timeZone)
    guard isToday else { return full }
    return String(
      format: String(
        localized: "calendar.week.today_prefix", defaultValue: "Today, %@", table: "Localizable",
        bundle: MobileL10n.bundle), full)
  }
}

private struct MobileCalendarPageReachableKey: EnvironmentKey {
  static let defaultValue = true
}

extension EnvironmentValues {
  /// Whether the pager page that holds a view is the page on screen. A pager
  /// keeps the pages beside the visible one laid out, and a pager narrower than
  /// its window (a day grid beside the iPad agenda) leaves the next page inside
  /// the window, where VoiceOver would read its days a second time.
  var mobileCalendarPageIsReachable: Bool {
    get { self[MobileCalendarPageReachableKey.self] }
    set { self[MobileCalendarPageReachableKey.self] = newValue }
  }
}

private struct MobileCalendarPageReachability: ViewModifier {
  let alsoHidden: Bool
  @Environment(\.mobileCalendarPageIsReachable) private var isReachable

  func body(content: Content) -> some View {
    content.accessibilityHidden(alsoHidden || !isReachable)
  }
}

extension View {
  /// Hides the view from VoiceOver while its pager page is not the visible one
  /// (``EnvironmentValues/mobileCalendarPageIsReachable``), and always when
  /// `hidden`.
  ///
  /// Each group of elements on a page applies this itself, never the page as a
  /// whole: an explicit "not hidden" on the page makes the all-day strip's empty
  /// drop-target cells, which hide themselves, reachable again as nameless
  /// stops.
  func mobileCalendarPageReachability(hidden: Bool = false) -> some View {
    modifier(MobileCalendarPageReachability(alsoHidden: hidden))
  }
}

extension MobileCalendarDayColumn {
  /// The sort priority VoiceOver orders a day's blocks by, higher first: the
  /// block that starts earliest reads first, and blocks that start together
  /// keep the grid's own order. Events and task blocks share one scale, so the
  /// day reads in time order whatever each block is.
  nonisolated static func accessibilitySortPriority(startMin: Int) -> Double {
    Double(24 * 60 - startMin)
  }
}
