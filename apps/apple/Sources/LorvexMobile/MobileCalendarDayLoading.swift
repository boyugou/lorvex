import Foundation

extension MobileCalendarDayView {
  /// Loads the timeline window when the visible date moves outside the safely
  /// loaded inner range. Reuses the store's windowed fetch; the initial load
  /// happens when no window exists.
  func ensureWindowLoaded() async {
    if let anchor = loadedAnchor,
      let gap = calendar.dateComponents([.day], from: anchor, to: visibleDate).day,
      abs(gap) <= 5 {
      return
    }
    loadedAnchor = visibleDate
    if weekMode {
      // Mid-week anchor, ten days each way: the visible week and both weeks a
      // swipe reveals are loaded before the finger moves.
      let midWeek = calendar.date(byAdding: .day, value: 3, to: visibleDate) ?? visibleDate
      await store.refreshCalendarTimeline(around: midWeek, radiusDays: 10)
    } else {
      await store.refreshCalendarTimeline(around: visibleDate)
    }
  }
}
