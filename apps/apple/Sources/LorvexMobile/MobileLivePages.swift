import Foundation

/// The rules the calendar pagers share for which of their pages hold content.
///
/// A paging `TabView` keeps the pages it has shown, and each pass over the view
/// asks every one of them for its content. A page that holds a month grid or a
/// time axis would make every pass cost more with each month or day the person
/// pages through. The pagers therefore list every page of their range, so a
/// page keeps one identity however far the person pages, and give content only
/// to the pages near the visible one; the others are empty placeholders that
/// cost nothing to keep.
enum MobileLivePages {
  /// How many pages on each side of the visible one hold content: enough that a
  /// swipe either way, and the one after it, finds its page already laid out.
  static let keptEachSide = 2

  /// Whether the page `offset` holds content while `visibleOffset` is visible.
  static func holdsContent(offset: Int, visibleOffset: Int) -> Bool {
    abs(offset - visibleOffset) <= keptEachSide
  }

  /// Whether a jump from the visible page to `target` slides with the page
  /// animation. Only a jump within the kept pages does: every page such a
  /// slide starts from or crosses holds content. A farther jump replaces the
  /// visible page at once, because the page it leaves would turn into an
  /// empty placeholder as the jump begins.
  static func slides(from visibleOffset: Int, to target: Int) -> Bool {
    abs(target - visibleOffset) <= keptEachSide
  }
}
