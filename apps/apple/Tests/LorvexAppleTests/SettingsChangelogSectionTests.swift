#if os(macOS)
  import AppKit
  import GRDB
  @testable import LorvexCore
  import SwiftUI
  import Testing

  @testable import LorvexApple

  /// Opening Settings › Diagnostics loads the stored log retention into the
  /// AI Changelog group's picker. That load once counted as a choice whenever
  /// the stored policy was not the default, so every appearance of the pane
  /// saved the policy again: a synced preference write and an `ai_changelog`
  /// row each time. The section is hosted in an offscreen window, which is
  /// never shown, so its load runs as it does in Settings.
  @MainActor
  @Test func settingsChangelogSectionSavesNothingWhenItAppears() async throws {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core)
    #expect(await store.saveChangelogRetentionPolicy(.days(30)))
    func changelogRows() throws -> Int {
      try core.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0 }
    }
    let before = try changelogRows()

    let hosting = NSHostingView(
      rootView: Form { SettingsChangelogSection(store: store) }.formStyle(.grouped))
    let window = NSWindow(
      contentRect: NSRect(x: -20_000, y: -20_000, width: 640, height: 300),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    defer { window.contentView = nil }
    for _ in 0..<20 {
      hosting.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(50))
    }

    #expect(try changelogRows() == before)
  }
#endif
