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
    await store.refreshCalendarTimeline(around: visibleDate)
  }
}
