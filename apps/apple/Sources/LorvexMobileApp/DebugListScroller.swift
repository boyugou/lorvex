#if DEBUG && os(iOS)
  import UIKit

  /// Dev/QA only: when `-lorvexScrollListTo middle` or `end` is passed, the
  /// tallest scrollable list on screen is scrolled to its middle or its end a
  /// few seconds after launch, so a headless capture shows the rows below the
  /// fold of a list taller than the screen, such as the one
  /// `-lorvexSeedStressData` seeds. SwiftUI's default scroll anchor does not move
  /// a `List`, so this sets the backing scroll view's offset directly. A list
  /// that fits on screen stays where it is.
  @MainActor
  enum DebugListScroller {
    static func scrollIfRequested() async {
      let args = CommandLine.arguments
      guard let index = args.firstIndex(of: "-lorvexScrollListTo"), index + 1 < args.count,
        args[index + 1] == "middle" || args[index + 1] == "end"
      else { return }
      let toEnd = args[index + 1] == "end"
      // The screen draws a moment after launch and its rows settle a little
      // later, so the list is scrolled twice.
      for delay in [4.0, 2.0] {
        try? await Task.sleep(for: .seconds(delay))
        guard let scrollView = tallestVisibleScrollView() else { continue }
        let inset = scrollView.adjustedContentInset
        let top = -inset.top
        let bottom = scrollView.contentSize.height - scrollView.bounds.height + inset.bottom
        guard bottom > top else { continue }
        scrollView.setContentOffset(
          CGPoint(x: scrollView.contentOffset.x, y: toEnd ? bottom : (top + bottom) / 2),
          animated: false)
      }
    }

    /// The on-screen vertical scroll view with the most content, ignoring
    /// small nested ones such as a horizontal row of chips.
    private static func tallestVisibleScrollView() -> UIScrollView? {
      var best: UIScrollView?
      func visit(_ view: UIView) {
        if let scrollView = view as? UIScrollView, !scrollView.isHidden, scrollView.window != nil,
          scrollView.bounds.width > 300, scrollView.bounds.height > 300,
          scrollView.contentSize.height > scrollView.bounds.height,
          scrollView.contentSize.height > (best?.contentSize.height ?? 0)
        {
          best = scrollView
        }
        view.subviews.forEach(visit)
      }
      for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
        scene.windows.forEach(visit)
      }
      return best
    }
  }
#endif
