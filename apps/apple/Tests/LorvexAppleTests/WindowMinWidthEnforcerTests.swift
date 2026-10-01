import AppKit
import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// The dynamic window-width floor, tested against a real (never-shown)
/// NSWindow. These pin the behavior end to end at the AppKit level —
/// deliberately not through SwiftUI, whose resizability plumbing does not
/// re-clamp open windows when the content minimum changes.
@MainActor
private func makeWindow(width: CGFloat) -> NSWindow {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
    styleMask: [.titled, .resizable],
    backing: .buffered,
    defer: true
  )
  window.isReleasedWhenClosed = false
  return window
}

@MainActor
private func makeStore(_ suiteName: String) async throws -> AppStore {
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  return AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
}

/// The floor the enforcer actually applies for `window`: the pane-derived
/// minimum, clamped to the screen's visible width exactly as
/// `WindowMinWidthEnforcer.Coordinator.enforce()` clamps it. Without the clamp
/// the three-pane floor (1000 + 320) exceeds a 13" display, and the enforcer
/// deliberately never demands more width than the screen can give.
@MainActor
private func enforcedFloor(for window: NSWindow, inspectorOpen: Bool) -> CGFloat {
  var width = LorvexWindowID.main.minimumContentSize.width
  if inspectorOpen { width += MainWindowLayoutMetrics.inspectorIdealWidth }
  if let screen = window.screen { width = min(width, screen.visibleFrame.width) }
  return width
}

/// Poll until `condition` holds (the Observation onChange hop is async).
@MainActor
private func eventually(
  _ condition: @MainActor () -> Bool, timeout: TimeInterval = 2
) async -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if condition() { return true }
    try? await Task.sleep(nanoseconds: 20_000_000)
  }
  return condition()
}

@MainActor
@Test
func enforcerRaisesFloorAndGrowsWindowWhenTaskSelected() async throws {
  let store = try await makeStore("WindowMinWidthEnforcer.grow.\(UUID().uuidString)")
  await store.refresh()
  store.selectedTaskID = nil
  let window = makeWindow(width: 1000)
  defer { window.close() }

  let coordinator = WindowMinWidthEnforcer.Coordinator(store: store)
  coordinator.attach(to: window)

  let base = enforcedFloor(for: window, inspectorOpen: false)
  #expect(window.contentMinSize.width == base)

  // Selecting a task raises the floor by the inspector's ideal width and
  // grows the too-narrow window on the spot.
  store.selectedTaskID = store.today.tasks.first?.id ?? "task-1"
  let expected = enforcedFloor(for: window, inspectorOpen: true)
  let grew = await eventually {
    window.contentMinSize.width == expected
      && window.contentRect(forFrameRect: window.frame).width >= expected
  }
  #expect(grew, "window must re-clamp and grow when the inspector opens")
}

@MainActor
@Test
func enforcerSnapsBackAfterResizeBelowFloor() async throws {
  let store = try await makeStore("WindowMinWidthEnforcer.snap.\(UUID().uuidString)")
  await store.refresh()
  store.selectedTaskID = store.today.tasks.first?.id ?? "task-1"
  let window = makeWindow(width: 1400)
  defer { window.close() }

  let coordinator = WindowMinWidthEnforcer.Coordinator(store: store)
  coordinator.attach(to: window)
  let expected = enforcedFloor(for: window, inspectorOpen: true)
  _ = await eventually { window.contentMinSize.width == expected }

  // Programmatic resizes bypass contentMinSize; the resize hook must snap
  // the window back to the floor.
  window.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600), display: false)
  let snapped = await eventually {
    window.contentRect(forFrameRect: window.frame).width >= expected
  }
  #expect(snapped, "a sub-floor resize must immediately grow back")
}

@MainActor
@Test
func enforcerLowersFloorWhenSelectionClears() async throws {
  let store = try await makeStore("WindowMinWidthEnforcer.lower.\(UUID().uuidString)")
  await store.refresh()
  store.selectedTaskID = store.today.tasks.first?.id ?? "task-1"
  let window = makeWindow(width: 1400)
  defer { window.close() }

  let coordinator = WindowMinWidthEnforcer.Coordinator(store: store)
  coordinator.attach(to: window)
  let raised = enforcedFloor(for: window, inspectorOpen: true)
  _ = await eventually { window.contentMinSize.width == raised }

  store.selectedTaskID = nil
  let base = enforcedFloor(for: window, inspectorOpen: false)
  let lowered = await eventually { window.contentMinSize.width == base }
  #expect(lowered, "closing the inspector returns the floor to the base minimum")
  // The window itself keeps its size — only the floor moves.
  #expect(window.contentRect(forFrameRect: window.frame).width >= raised)
}
