import AppKit
import SwiftUI

/// Keeps the menu bar panel's top edge under the menu bar while its content
/// changes height.
///
/// The `.window`-style `MenuBarExtra` sizes its window to the SwiftUI content,
/// and AppKit resizes a window about its bottom-left corner. A panel that grows
/// is pushed back under the menu bar by the screen constraint, but one that
/// then shrinks (a section loads, a scope switches, a habit is checked in)
/// lowers its top edge instead, until the panel hangs mid-screen with its
/// bottom past the screen's edge.
///
/// The anchor records the top edge each time the panel opens (becomes key),
/// after the system has placed it under its status item, and puts the top edge
/// back there after every resize. The top never rises above the screen's
/// visible frame, which ends at the menu bar.
struct MenuBarPanelTopAnchor: NSViewRepresentable {
  func makeCoordinator() -> Coordinator { Coordinator() }

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
    private weak var window: NSWindow?
    private var anchoredTop: CGFloat?
    // `nonisolated(unsafe)`: deinit is nonisolated under strict concurrency,
    // and NotificationCenter token removal is itself thread-safe.
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    func attach(to window: NSWindow?) {
      guard let window, window !== self.window else { return }
      self.window = window
      removeObservers()
      if window.isVisible { anchoredTop = window.frame.maxY }
      let center = NotificationCenter.default
      observers = [
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) {
          [weak self] _ in
          // A turn later, once the system has placed the panel for this opening.
          DispatchQueue.main.async { MainActor.assumeIsolated { self?.recordTop() } }
        },
        center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) {
          [weak self] _ in
          MainActor.assumeIsolated { self?.restoreTop() }
        },
      ]
    }

    func recordTop() {
      guard let window else { return }
      anchoredTop = window.frame.maxY
    }

    private func restoreTop() {
      guard let window, var top = anchoredTop else { return }
      if let screen = window.screen {
        top = min(top, screen.visibleFrame.maxY)
      }
      guard abs(window.frame.maxY - top) > 0.5 else { return }
      window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
    }

    private func removeObservers() {
      for observer in observers {
        NotificationCenter.default.removeObserver(observer)
      }
      observers = []
    }

    deinit {
      for observer in observers {
        NotificationCenter.default.removeObserver(observer)
      }
    }
  }
}
