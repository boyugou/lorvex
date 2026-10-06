#if os(macOS)
  import AppKit
  @testable import LorvexCore
  import SwiftUI
  import Testing

  @testable import LorvexApple

  /// The Quick Capture group in Settings › General.
  @MainActor
  struct SettingsQuickCaptureSectionTests {
    @Test func theFooterSeparatesAnOffShortcutFromAChosenOneAndAClaimedOne() {
      let off = SettingsQuickCaptureFooter.caption(for: .off)
      let chosen = SettingsQuickCaptureFooter.caption(for: .controlOptionSpace)
      let claimed = SettingsQuickCaptureFooter.unavailableCaption

      #expect(Set([off, chosen, claimed]).count == 3)
      for caption in [off, chosen, claimed] {
        #expect(!caption.isEmpty)
      }
      for shortcut in QuickCaptureShortcut.allCases where shortcut != .off {
        #expect(SettingsQuickCaptureFooter.caption(for: shortcut) == chosen)
      }
    }

    /// Settings › General is hosted in a window that is never shown while the
    /// shortcut moves through each footer state: off, chosen, and refused by
    /// the system. A crash in the page's view tree ends the test run, so
    /// reaching the end is the assertion.
    @Test func theGeneralPageRendersThroughEveryFooterState() async throws {
      let store = AppStore(
        core: try await makeSeededInMemoryCore(),
        taskSearchIndexer: NoopTaskSearchIndexer(),
        widgetSnapshotPublisher: NoopWidgetSnapshotPublisher())
      let suiteName = "SettingsQuickCaptureSectionTests.\(UUID().uuidString)"
      let defaults = try #require(UserDefaults(suiteName: suiteName))
      defer { defaults.removePersistentDomain(forName: suiteName) }
      let settings = AppSettingsStore(defaults: defaults)

      let hosting = NSHostingView(
        rootView: LorvexSettingsWindowView(settings: settings, store: store))
      let window = NSWindow(
        contentRect: NSRect(x: -20_000, y: -20_000, width: 860, height: 640),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = hosting
      defer { window.contentView = nil }

      func settle() async throws {
        for _ in 0..<6 {
          hosting.layoutSubtreeIfNeeded()
          try await Task.sleep(for: .milliseconds(50))
        }
      }

      try await settle()
      settings.quickCaptureShortcut = .controlOptionSpace
      try await settle()
      settings.quickCaptureShortcutIsAvailable = false
      try await settle()
      settings.quickCaptureShortcut = .off
      settings.quickCaptureShortcutIsAvailable = true
      try await settle()

      #expect(hosting.fittingSize.height > 0)
    }
  }
#endif
