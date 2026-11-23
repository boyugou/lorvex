import SwiftUI

/// The part of the week grid's scroll geometry that decides where its time
/// axis stands: how far the axis can scroll and how far it is scrolled.
struct CalendarTimeAxisGeometry: Equatable {
  /// How far the axis can scroll; zero while the scroll view has no size or
  /// shows every hour.
  var scrollableHeight: CGFloat
  /// How far the axis is scrolled from its top.
  var offset: CGFloat

  init(scrollableHeight: CGFloat, offset: CGFloat) {
    self.scrollableHeight = scrollableHeight
    self.offset = offset
  }

  init(_ geometry: ScrollGeometry) {
    scrollableHeight =
      geometry.containerSize.height > 0
      ? max(0, geometry.contentSize.height - geometry.containerSize.height) : 0
    offset = geometry.contentOffset.y + geometry.contentInsets.top
  }

  /// The offset that puts `hour` at the top of the axis. When the axis cannot
  /// scroll that far, the offset is the last whole hour it can reach, so a
  /// window tall enough to show the rest of the day still stops on an hour
  /// line rather than part-way through an hour.
  static func offset(forHour hour: Int, hourHeight: CGFloat, scrollableHeight: CGFloat) -> CGFloat {
    guard hourHeight > 0 else { return 0 }
    let lastHour = Int(max(0, scrollableHeight) / hourHeight)
    return CGFloat(min(max(0, hour), lastHour)) * hourHeight
  }
}

/// Where a grid's time axis stands, and the scrolls the grid asks of it.
///
/// The grid puts the axis on its anchor hour when it opens and keeps it there
/// until the person scrolls: while the anchor moves (the clock passing an
/// hour, the day's blocks loading) and while the scroll view changes size. A
/// new range of days puts it on the anchor hour again wherever it stands.
///
/// One request does not place the axis. A scroll view drops a scroll asked of
/// it before it has a size, for a size that does not hold, and during the
/// layout pass that reports its size, and a window sizes the scroll view more
/// than once as it opens. So while a placement is under way the tracker
/// answers each geometry report with another request, until a report shows
/// the axis on the hour or ``requestBudget`` requests in a row have gone
/// unanswered.
///
/// It is a reference outside view state because it changes on every frame of
/// a scroll and nothing draws from it.
@MainActor
final class CalendarTimeAxisTracker {
  /// A scroll the grid asks of the axis.
  struct Request: Equatable {
    let offset: CGFloat
    /// True for a scroll the person watches happen on a grid that is already
    /// placed. A request made while a placement is under way is not animated,
    /// and the grid makes it one turn of the main actor later, outside the
    /// layout pass that reported the geometry.
    let isAnimated: Bool
  }

  /// How many requests in a row one placement makes without seeing the axis
  /// arrive. The bound stops a placement that can never land from asking on
  /// every report.
  static let requestBudget = 4

  private(set) var geometry = CalendarTimeAxisGeometry(scrollableHeight: 0, offset: 0)
  /// The offset the grid last asked for, or nil before its first request.
  private(set) var placedOffset: CGFloat?
  /// The requests left in the placement under way; zero when none is.
  private var requestsLeft = requestBudget

  /// Whether the grid is still putting the axis on its hour.
  var isPlacing: Bool { requestsLeft > 0 }

  /// Whether the axis stands where the grid last put it, which it does until
  /// the person scrolls it or the scroll view moves it to fit a new size.
  var isWherePlaced: Bool { wasPlaced(at: geometry.offset) }

  /// Takes the scroll view's report of the axis's geometry and returns the
  /// scroll to ask for, if any.
  func geometryChanged(
    to axis: CalendarTimeAxisGeometry, anchorHour: Int, hourHeight: CGFloat
  ) -> Request? {
    let previous = geometry
    geometry = axis
    guard axis.scrollableHeight > 0 else { return nil }
    // A new size under an axis the person has not scrolled: the hour it stood
    // on may no longer be the one it can reach, and a size reported while a
    // window opens may not have been the one that holds.
    if !isPlacing, axis.scrollableHeight != previous.scrollableHeight, wasPlaced(at: previous.offset) {
      requestsLeft = Self.requestBudget
    }
    guard isPlacing else { return nil }
    let target = CalendarTimeAxisGeometry.offset(
      forHour: anchorHour, hourHeight: hourHeight, scrollableHeight: axis.scrollableHeight)
    placedOffset = target
    guard abs(axis.offset - target) >= 1 else {
      requestsLeft = 0
      return nil
    }
    requestsLeft -= 1
    return Request(offset: target, isAnimated: false)
  }

  /// The person scrolled the axis, which ends a placement under way: where
  /// the axis stands is theirs.
  func personScrolled() {
    requestsLeft = 0
  }

  /// The anchor hour moved. The axis follows it unless the person has
  /// scrolled it away from where the grid put it.
  func anchorMoved(toHour hour: Int, hourHeight: CGFloat) -> Request? {
    guard isPlacing || isWherePlaced else { return nil }
    return place(onHour: hour, hourHeight: hourHeight)
  }

  /// The grid shows another range of days, or what its days hold gave it
  /// another hour to open on. The axis goes there wherever it stands.
  func rangeChanged(anchorHour: Int, hourHeight: CGFloat) -> Request? {
    place(onHour: anchorHour, hourHeight: hourHeight)
  }

  /// A request that puts the axis on `hour`, or nil when it is already there
  /// or the scroll view has no size yet, in which case its first geometry
  /// report places the axis. A request made while a placement is under way
  /// does not count against the budget: no report may follow a dropped
  /// request, so this is what restarts a placement that stopped short.
  private func place(onHour hour: Int, hourHeight: CGFloat) -> Request? {
    guard geometry.scrollableHeight > 0 else { return nil }
    let target = CalendarTimeAxisGeometry.offset(
      forHour: hour, hourHeight: hourHeight, scrollableHeight: geometry.scrollableHeight)
    placedOffset = target
    guard abs(geometry.offset - target) >= 1 else { return nil }
    return Request(offset: target, isAnimated: !isPlacing)
  }

  private func wasPlaced(at offset: CGFloat) -> Bool {
    guard let placedOffset else { return false }
    return abs(offset - placedOffset) < 1
  }
}
