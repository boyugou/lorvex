#if DEBUG && os(iOS)
  import LorvexMobile
  import UIKit

  /// Dev/QA only: with `-lorvexFrameProbe <scenario>:<label>`, the app performs
  /// one interaction itself, three seconds after its launch route has drawn,
  /// and measures how late its main thread delivered frames meanwhile
  /// (``DebugFrameProbe``, whose file is named after `<label>`).
  ///
  /// The app drives the interaction so that nothing else runs on its main
  /// thread while it is measured: a UI test's element lookups snapshot the
  /// accessibility tree on that thread, which the probe would count as the
  /// app's own stutter. The state each step sets is the state a tap sets.
  ///
  /// Scenarios:
  /// - `scroll`: moves the tallest list on screen to its end and back, three
  ///   times, at 2,500 points a second (a quick fling), for at most 18 seconds.
  /// - `tabs`: selects each tab in turn, three rounds, 0.8 s apart.
  /// - `taskDetail`: pushes the first task on Today and pops it, five times.
  /// - `capture`: presents the capture sheet and dismisses it, five times.
  @MainActor
  enum DebugInteractionDriver {
    static func runIfRequested(store: MobileStore) async {
      let args = CommandLine.arguments
      guard let index = args.firstIndex(of: "-lorvexFrameProbe"), index + 1 < args.count
      else { return }
      let parts = args[index + 1].split(separator: ":", maxSplits: 1).map(String.init)
      let scenario = parts[0]
      let label = parts.count > 1 ? parts[1] : scenario
      try? await Task.sleep(for: .seconds(3))
      let probe = DebugFrameProbe(label: label)
      let rate =
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first?
        .maximumFramesPerSecond ?? 60
      probe.begin(maximumFramesPerSecond: rate)
      switch scenario {
      case "scroll": await scroll()
      case "tabs": await switchTabs(store)
      case "taskDetail": await openTaskDetail(store)
      case "capture": await openCapture(store)
      default: NSLog("FRAMEPROBE unknown scenario %@", scenario)
      }
      // The last change finishes drawing.
      try? await Task.sleep(for: .seconds(1))
      probe.end()
    }

    private static func pause(_ seconds: Double) async {
      try? await Task.sleep(for: .seconds(seconds))
    }

    /// Moves the list by elapsed time rather than by step, so a late wake-up
    /// jumps the offset as a real fling would and the speed stays 2,500
    /// points a second.
    private static func scroll() async {
      guard let scrollView = DebugListScroller.tallestVisibleScrollView() else {
        NSLog("FRAMEPROBE no scrollable list on screen")
        return
      }
      let inset = scrollView.adjustedContentInset
      let top = -inset.top
      let bottom = scrollView.contentSize.height - scrollView.bounds.height + inset.bottom
      guard bottom > top else { return }
      let speed = 2_500.0
      let deadline = CACurrentMediaTime() + 18
      for _ in 0..<3 {
        for (from, to) in [(top, bottom), (bottom, top)] {
          let start = CACurrentMediaTime()
          let duration = abs(to - from) / speed
          while CACurrentMediaTime() - start < duration, CACurrentMediaTime() < deadline {
            let progress = (CACurrentMediaTime() - start) / duration
            let y = from + (to - from) * progress
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
            try? await Task.sleep(for: .milliseconds(4))
          }
          scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: to), animated: false)
          await pause(0.3)
        }
      }
    }

    private static func switchTabs(_ store: MobileStore) async {
      for _ in 0..<3 {
        for tab in [MobileTab.calendar, .tasks, .review, .today] {
          store.selectedTab = tab
          await pause(0.8)
        }
      }
    }

    private static func openTaskDetail(_ store: MobileStore) async {
      store.selectedTab = .today
      guard let id = store.snapshot.today.tasks.first?.id else {
        NSLog("FRAMEPROBE no task on Today")
        return
      }
      for _ in 0..<5 {
        store.routePath = [.task(id)]
        await pause(0.9)
        store.routePath = []
        await pause(0.9)
      }
    }

    private static func openCapture(_ store: MobileStore) async {
      for _ in 0..<5 {
        store.isPresentingCapture = true
        await pause(1.0)
        store.isPresentingCapture = false
        await pause(0.8)
      }
    }
  }
#endif
