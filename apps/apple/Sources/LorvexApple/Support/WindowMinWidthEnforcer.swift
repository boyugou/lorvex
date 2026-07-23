import AppKit
import SwiftUI

/// Enforces the main window's dynamic minimum width at the AppKit level.
///
/// The window's content floor depends on which panes are visible: the base
/// two-pane minimum, plus the inspector's ideal width while a task is
/// selected. SwiftUI's `.windowResizability(.contentMinSize)` captures the
/// content minimum around window creation and does not re-clamp an already
/// open window when `.frame(minWidth:)` later changes — the content then
/// refuses to compress (correct) but the window stays narrow, clipping the
/// inspector and crushing the sidebar.
///
/// The coordinator owns the policy end to end, deliberately independent of
/// SwiftUI's render pipeline: it derives the floor straight from the store,
/// re-derives it through an Observation loop whenever the task selection
/// changes, and re-asserts it on every window resize (programmatic resizes
/// bypass `contentMinSize`, so the resize hook snaps the window back). When
/// the window sits below the floor it is grown in place, shifting left if the
/// screen's right edge has no room.
struct WindowMinWidthEnforcer: NSViewRepresentable {
  let store: AppStore

  func makeCoordinator() -> Coordinator { Coordinator(store: store) }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    let coordinator = context.coordinator
    DispatchQueue.main.async { [weak view] in coordinator.attach(to: view?.window) }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    let coordinator = context.coordinator
    DispatchQueue.main.async { [weak nsView] in coordinator.attach(to: nsView?.window) }
  }

  @MainActor
  final class Coordinator {
    private let store: AppStore
    private weak var window: NSWindow?
    // `nonisolated(unsafe)`: deinit is nonisolated under strict concurrency,
    // and NotificationCenter token removal is itself thread-safe.
    private nonisolated(unsafe) var resizeObserver: NSObjectProtocol?
    private var isObservingSelection = false

    init(store: AppStore) {
      self.store = store
    }

    /// The content-width floor for the current pane configuration.
    var desiredMinWidth: CGFloat {
      let base = LorvexWindowID.main.minimumContentSize.width
      // The inspector opens for either a selected task or a selected habit, so
      // both move the floor (ContentView raises minimumWindowWidth on both).
      guard store.selectedTaskID != nil || store.selectedHabitID != nil else { return base }
      return base + MainWindowLayoutMetrics.inspectorIdealWidth
    }

    func attach(to window: NSWindow?) {
      defer {
        armSelectionObservation()
        enforce()
      }
      guard let window, window !== self.window else { return }
      self.window = window
      if let resizeObserver {
        NotificationCenter.default.removeObserver(resizeObserver)
      }
      resizeObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didResizeNotification, object: window, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.enforce() }
      }
    }

    /// One continuous, self-re-arming Observation loop on the task selection —
    /// the input that moves the floor. Independent of SwiftUI re-rendering.
    private func armSelectionObservation() {
      guard !isObservingSelection else { return }
      isObservingSelection = true
      trackSelection()
    }

    private func trackSelection() {
      withObservationTracking {
        _ = store.selectedTaskID
        _ = store.selectedHabitID
      } onChange: { [weak self] in
        Task { @MainActor [weak self] in
          guard let self else { return }
          self.enforce()
          self.trackSelection()
        }
      }
    }

    func enforce() {
      guard let window else { return }
      // A 13" display can be narrower than the three-pane floor; never demand
      // more width than the screen can give, or the window outgrows the screen
      // and fights the user. The visible frame is the honest ceiling.
      var minWidth = desiredMinWidth
      if let screen = window.screen {
        minWidth = min(minWidth, screen.visibleFrame.width)
      }
      if window.contentMinSize.width != minWidth {
        window.contentMinSize.width = minWidth
      }
      let contentWidth = window.contentRect(forFrameRect: window.frame).width
      guard contentWidth < minWidth else { return }
      var frame = window.frame
      frame.size.width += minWidth - contentWidth
      // Grow leftward when the screen's right edge has no room.
      if let screen = window.screen, frame.maxX > screen.visibleFrame.maxX {
        frame.origin.x = max(screen.visibleFrame.minX, screen.visibleFrame.maxX - frame.width)
      }
      window.setFrame(frame, display: true)
    }

    deinit {
      if let resizeObserver {
        NotificationCenter.default.removeObserver(resizeObserver)
      }
    }
  }
}
