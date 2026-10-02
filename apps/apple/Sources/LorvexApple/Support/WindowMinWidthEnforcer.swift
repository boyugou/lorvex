import AppKit
import SwiftUI

/// Enforces the main window's dynamic minimum width at the AppKit level.
///
/// The window's content floor depends on which columns are visible
/// (``MainWindowLayout/minimumContentWidth(inspectorOpen:)``): the workspace,
/// the sidebar while it shows, and the inspector while a task, habit, or Today
/// event is selected, capped at the screen's width. SwiftUI's
/// `.windowResizability(.contentMinSize)` captures the content minimum around
/// window creation and does not re-clamp an already open window when
/// `.frame(minWidth:)` later changes — the content then refuses to compress
/// (correct) but the window stays narrow, clipping the inspector and crushing
/// the sidebar.
///
/// The coordinator owns the policy end to end, deliberately independent of
/// SwiftUI's render pipeline: it derives the floor straight from the store and
/// the layout, re-derives it through an Observation loop whenever the columns
/// change, and re-asserts it on every window resize (programmatic resizes
/// bypass `contentMinSize`, so the resize hook snaps the window back). When
/// the window sits below the floor it is grown in place, shifting left if the
/// screen's right edge has no room. It also reports the width of the window's
/// screen to the layout, when the window first attaches, moves to another
/// screen, or the screens change, since that width decides whether the
/// inspector has to take the sidebar's place.
struct WindowMinWidthEnforcer: NSViewRepresentable {
  let store: AppStore
  let layout: MainWindowLayout

  func makeCoordinator() -> Coordinator { Coordinator(store: store, layout: layout) }

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
    private let layout: MainWindowLayout
    /// The visible width of the screen a window is on; tests substitute a
    /// fixed width so they do not depend on the machine's displays.
    private let screenWidth: @MainActor (NSWindow) -> CGFloat?
    private weak var window: NSWindow?
    // `nonisolated(unsafe)`: deinit is nonisolated under strict concurrency,
    // and NotificationCenter token removal is itself thread-safe.
    private nonisolated(unsafe) var windowObservers: [NSObjectProtocol] = []
    private var isObservingFloor = false

    init(
      store: AppStore,
      layout: MainWindowLayout,
      screenWidth: @escaping @MainActor (NSWindow) -> CGFloat? = { $0.screen?.visibleFrame.width }
    ) {
      self.store = store
      self.layout = layout
      self.screenWidth = screenWidth
    }

    /// The content-width floor for the columns on screen.
    var desiredMinWidth: CGFloat {
      layout.minimumContentWidth(inspectorOpen: store.isMainInspectorOpen)
    }

    func attach(to window: NSWindow?) {
      defer {
        armFloorObservation()
        reportScreen()
        enforce()
      }
      guard let window, window !== self.window else { return }
      self.window = window
      removeWindowObservers()
      let center = NotificationCenter.default
      windowObservers = [
        center.addObserver(
          forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.enforce() }
        },
        center.addObserver(
          forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.reportScreen() }
        },
        center.addObserver(
          forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.reportScreen() }
        },
      ]
    }

    /// Tells the layout how wide the window's screen is. A change of width
    /// re-fits the columns, which moves the floor and so re-enforces it
    /// through the Observation loop.
    private func reportScreen() {
      var width: CGFloat?
      if let window { width = screenWidth(window) }
      layout.screenDidChange(width: width, inspectorOpen: store.isMainInspectorOpen)
    }

    /// One continuous, self-re-arming Observation loop on the floor's inputs
    /// (whether the inspector is open, whether the sidebar shows, and the
    /// screen's width). Independent of SwiftUI re-rendering.
    private func armFloorObservation() {
      guard !isObservingFloor else { return }
      isObservingFloor = true
      trackFloor()
    }

    private func trackFloor() {
      withObservationTracking {
        _ = desiredMinWidth
      } onChange: { [weak self] in
        Task { @MainActor [weak self] in
          guard let self else { return }
          self.enforce()
          self.trackFloor()
        }
      }
    }

    func enforce() {
      guard let window else { return }
      // Never demand more width than the screen can give, or the window
      // outgrows the screen and fights the user. The layout caps the floor
      // at the width it was last told; the live width is the honest ceiling.
      var minWidth = desiredMinWidth
      if let width = screenWidth(window) {
        minWidth = min(minWidth, width)
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

    private func removeWindowObservers() {
      for observer in windowObservers {
        NotificationCenter.default.removeObserver(observer)
      }
      windowObservers = []
    }

    deinit {
      for observer in windowObservers {
        NotificationCenter.default.removeObserver(observer)
      }
    }
  }
}
