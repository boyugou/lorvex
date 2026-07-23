import Foundation
import Testing

@testable import LorvexApple

@Test
func appLayoutStateResetClearsMainNavigationSplitViewAutosaveFrames() throws {
  let suiteName = "AppLayoutStateResetTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer {
    defaults.removePersistentDomain(forName: suiteName)
  }

  let staleKey = "NSSplitView Subview Frames main-AppWindow-1, SidebarNavigationSplitView"
  let narrowWindowFrameKey = "NSWindow Frame main-AppWindow-1"
  defaults.set(["0.000000, 0.000000, 148.000000, 692.000000, NO, NO"], forKey: staleKey)
  defaults.set("363 153 980 692 0 0 1512 949 ", forKey: narrowWindowFrameKey)
  defaults.set("calendar", forKey: "navigation.selection")
  defaults.set(true, forKey: "setupCompleted")

  AppLayoutStateReset.removeStaleMainWindowAutosaveState(defaults: defaults)

  #expect(defaults.object(forKey: staleKey) == nil)
  #expect(defaults.object(forKey: narrowWindowFrameKey) == nil)
  #expect(defaults.string(forKey: "navigation.selection") == "calendar")
  #expect(defaults.bool(forKey: "setupCompleted"))
  #expect(defaults.bool(forKey: "layoutStateReset.mainThreePane.v6"))
}

@Test
func appLayoutStateResetRunsOnlyOnceSoUserResizesArePreserved() throws {
  let suiteName = "AppLayoutStateResetTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer {
    defaults.removePersistentDomain(forName: suiteName)
  }

  AppLayoutStateReset.removeStaleMainWindowAutosaveState(defaults: defaults)

  let laterWindowFrameKey = "NSWindow Frame main-AppWindow-1"
  defaults.set("200 120 1280 760 0 0 1512 949 ", forKey: laterWindowFrameKey)

  AppLayoutStateReset.removeStaleMainWindowAutosaveState(defaults: defaults)

  #expect(defaults.string(forKey: laterWindowFrameKey) == "200 120 1280 760 0 0 1512 949 ")
}

@Test
func appLayoutStateResetDoesNotReadContainerPreferenceFilesOnLaunch() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let resetSource = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Support/AppLayoutStateReset.swift"),
    encoding: .utf8
  )
  let bootstrapSource = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/App/LorvexAppleBootstrap.swift"),
    encoding: .utf8
  )

  #expect(!resetSource.contains("homeDirectoryForCurrentUser"))
  #expect(!resetSource.contains("Data(contentsOf:"))
  #expect(!resetSource.contains("write(to:"))
  #expect(!resetSource.contains("defaultContainerPreferencesURL"))
  #expect(!bootstrapSource.contains("containerPreferencesURL"))
}
