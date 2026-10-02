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

/// A screen wide enough for the sidebar, the workspace, and the inspector.
private let wideScreenWidth: CGFloat = 1920

/// The visible width of a 13-inch display at a larger text size, narrower than
/// the three columns' 1320pt.
private let narrowScreenWidth: CGFloat = 1147

/// A coordinator that sees every window on a screen `screenWidth` wide, so the
/// tests do not depend on the displays of the machine running them.
@MainActor
private func makeCoordinator(
  store: AppStore, layout: MainWindowLayout = MainWindowLayout(), screenWidth: CGFloat
) -> WindowMinWidthEnforcer.Coordinator {
  WindowMinWidthEnforcer.Coordinator(store: store, layout: layout, screenWidth: { _ in screenWidth })
}

/// The floor with the sidebar showing: the two-column base, plus the
/// inspector's ideal width while it is open.
private func sidebarFloor(inspectorOpen: Bool) -> CGFloat {
  LorvexWindowID.main.minimumContentSize.width
    + (inspectorOpen ? MainWindowLayoutMetrics.inspectorIdealWidth : 0)
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

  let coordinator = makeCoordinator(store: store, screenWidth: wideScreenWidth)
  coordinator.attach(to: window)

  let base = sidebarFloor(inspectorOpen: false)
  #expect(window.contentMinSize.width == base)

  // Selecting a task raises the floor by the inspector's ideal width and
  // grows the too-narrow window on the spot.
  store.selectedTaskID = store.today.tasks.first?.id ?? "task-1"
  let expected = sidebarFloor(inspectorOpen: true)
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

  let coordinator = makeCoordinator(store: store, screenWidth: wideScreenWidth)
  coordinator.attach(to: window)
  let expected = sidebarFloor(inspectorOpen: true)
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

  let coordinator = makeCoordinator(store: store, screenWidth: wideScreenWidth)
  coordinator.attach(to: window)
  let raised = sidebarFloor(inspectorOpen: true)
  _ = await eventually { window.contentMinSize.width == raised }

  store.selectedTaskID = nil
  let base = sidebarFloor(inspectorOpen: false)
  let lowered = await eventually { window.contentMinSize.width == base }
  #expect(lowered, "closing the inspector returns the floor to the base minimum")
  // The window itself keeps its size — only the floor moves.
  #expect(window.contentRect(forFrameRect: window.frame).width >= raised)
}

@MainActor
@Test
func enforcerGivesTheSidebarsPlaceToTheInspectorOnANarrowScreen() async throws {
  let store = try await makeStore("WindowMinWidthEnforcer.narrow.\(UUID().uuidString)")
  await store.refresh()
  store.selectedTaskID = nil
  let window = makeWindow(width: 1000)
  defer { window.close() }

  let layout = MainWindowLayout()
  let coordinator = makeCoordinator(store: store, layout: layout, screenWidth: narrowScreenWidth)
  coordinator.attach(to: window)
  #expect(layout.screenWidth == narrowScreenWidth)

  // ContentView reports the inspector opening; on a screen without room for
  // three columns the sidebar hides, and the floor is the workspace plus the
  // inspector, which the screen holds.
  store.selectedTaskID = store.today.tasks.first?.id ?? "task-1"
  layout.inspectorDidChange(isOpen: true)
  #expect(layout.columnVisibility == .detailOnly)
  let expected = MainWindowLayout.columnsWidth(sidebar: false, inspector: true)
  #expect(expected <= narrowScreenWidth)
  let fitted = await eventually {
    window.contentMinSize.width == expected
      && window.contentRect(forFrameRect: window.frame).width >= expected
  }
  #expect(fitted, "the window must hold the workspace and the inspector")

  // Closing the inspector shows the sidebar again at the two-column floor.
  store.selectedTaskID = nil
  layout.inspectorDidChange(isOpen: false)
  #expect(layout.columnVisibility == .all)
  let restored = await eventually {
    window.contentMinSize.width == sidebarFloor(inspectorOpen: false)
  }
  #expect(restored)
}
