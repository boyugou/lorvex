import AppKit
import Testing

@testable import LorvexApple

/// The menu bar panel once drifted down the screen: AppKit resizes a window
/// about its bottom-left corner, so each time the panel's content shrank its
/// top edge dropped away from the menu bar.
@MainActor
@Test
func menuBarPanelKeepsItsTopEdgeWhenItsContentShrinks() throws {
  let screen = try #require(NSScreen.main)
  let top = screen.visibleFrame.maxY
  let window = NSWindow(
    contentRect: NSRect(x: screen.visibleFrame.minX + 40, y: top - 600, width: 340, height: 600),
    styleMask: [.borderless], backing: .buffered, defer: true)
  window.isReleasedWhenClosed = false

  let anchor = MenuBarPanelTopAnchor.Coordinator()
  anchor.attach(to: window)
  anchor.recordTop()
  #expect(window.frame.maxY == top)

  var shrunk = window.frame
  shrunk.size.height = 320
  window.setFrame(shrunk, display: false)

  #expect(window.frame.height == 320)
  #expect(window.frame.maxY == top)
}
