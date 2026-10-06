import AppKit
import LorvexCore
import SwiftUI

/// What the controller needs from the Quick Capture window, so it is tested
/// without AppKit.
@MainActor
protocol QuickCapturePresenting: AnyObject {
  var isPresented: Bool { get }
  /// Shows the window over whatever app is frontmost, ready to type.
  func present()
  func dismiss()
}

/// The window itself: a floating panel that takes the keyboard without making
/// Lorvex the active app, so the app the user came from stays frontmost behind
/// it and gets the focus back when the panel closes.
final class QuickCapturePanel: NSPanel {
  /// Called when the panel becomes the key window, the moment its text field
  /// can take keyboard focus.
  var onBecomeKey: (() -> Void)?
  /// Called when the panel stops being the key window: the user clicked or
  /// switched away.
  var onResignKey: (() -> Void)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func becomeKey() {
    super.becomeKey()
    onBecomeKey?()
  }

  override func resignKey() {
    super.resignKey()
    onResignKey?()
  }
}

/// Shows ``QuickCaptureCard`` in a ``QuickCapturePanel`` near the top of the
/// screen the pointer is on. The panel is made once and reused; its size follows
/// the content as the preview line comes and goes, with its top edge fixed.
@MainActor
final class QuickCapturePanelPresenter: QuickCapturePresenting {
  private let model: QuickCaptureModel
  private let store: AppStore
  private var panel: QuickCapturePanel?

  init(model: QuickCaptureModel, store: AppStore) {
    self.model = model
    self.store = store
  }

  var isPresented: Bool { panel?.isVisible ?? false }

  func present() {
    let panel = panel ?? makePanel()
    self.panel = panel
    place(panel)
    panel.makeKeyAndOrderFront(nil)
  }

  func dismiss() {
    panel?.orderOut(nil)
  }

  private func makePanel() -> QuickCapturePanel {
    let hostingView = NSHostingView(
      rootView: QuickCaptureCard(model: model) { [weak self] size in self?.fit(to: size) }
        .lorvexClockLocale()
        .lorvexProductTimeZone(from: store))
    // The window follows the content's reported size (`fit(to:)`); letting the
    // hosting view drive the window as well would feed the two back into each
    // other.
    hostingView.sizingOptions = []
    let panel = QuickCapturePanel(
      contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.title = QuickCaptureCopy.windowTitle
    panel.onBecomeKey = { [model] in model.requestFocus() }
    panel.onResignKey = { [weak self] in self?.dismiss() }
    panel.contentView = hostingView
    return panel
  }

  /// Hangs the panel from the upper fifth of the screen the pointer is on.
  private func place(_ panel: QuickCapturePanel) {
    let pointer = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return }
    let size = panel.frame.size
    let top = visible.maxY - visible.height * QuickCaptureMetrics.topInsetFraction
    panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: top - size.height))
  }

  /// Resizes the panel to the content, keeping its top edge and centre. While
  /// the panel is on screen the resize uses the system's window animation, and
  /// none under Reduce Motion.
  private func fit(to size: CGSize) {
    guard let panel, size.width > 0, size.height > 0 else { return }
    let current = panel.frame
    let fitted = NSRect(
      x: current.midX - size.width / 2, y: current.maxY - size.height,
      width: size.width, height: size.height)
    guard fitted != current else { return }
    panel.setFrame(fitted, display: true, animate: panel.isVisible && !lorvexReduceMotionEnabled)
  }
}
