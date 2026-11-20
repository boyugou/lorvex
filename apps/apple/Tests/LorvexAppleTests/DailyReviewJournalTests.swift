import AppKit
import LorvexCore
import SwiftUI
import Testing

@testable import LorvexApple

@MainActor
struct DailyReviewJournalTests {
  private func note(in view: NSView) -> NSTextView? {
    if let editor = view as? NSTextView,
      editor.accessibilityPlaceholderValue() == ReviewCalmCopy.notePrompt
    { return editor }
    for child in view.subviews {
      if let editor = note(in: child) { return editor }
    }
    return nil
  }

  @Test("Typing while another date loads stays on the visible date")
  func daySwitchKeepsInFlightEdits() async throws {
    let core = StubCoreService(preview: try makeInMemoryCore())
    let store = AppStore(core: core)
    await store.refresh()
    let today = store.selectedReviewDate
    let yesterday = try #require(LorvexDateFormatters.ymdUTCAddingDays(today, days: -1))
    let gate = ReviewGate()
    core.loadDailyReviewGate = { await gate.hold() }
    let navigation = Task { await store.selectReviewDay(yesterday) }
    await gate.waitUntilHeld()
    #expect(store.selectedReviewDate == today)
    store.dailyReviewSummaryDraft = "Before leaving today"
    core.loadDailyReviewGate = nil
    await gate.release()
    await navigation.value

    #expect(store.selectedReviewDate == yesterday)
    #expect(store.dailyReviewSummaryDraft.isEmpty)
    #expect(try await core.loadDailyReview(date: today)?.summary == "Before leaving today")
    #expect(try await core.loadDailyReview(date: yesterday) == nil)
  }

  @Test("The journal opens above the fold with nine habits and keeps its editor when resized")
  func reflectionOnFirstScreen() async throws {
    let core = try makeInMemoryCore()
    for index in 1...9 {
      _ = try await core.createHabit(name: "Habit \(index)", cue: nil, icon: nil, color: nil,
        targetCount: 1, cadence: .daily, milestoneTarget: nil)
    }
    let suite = "DailyReviewJournal.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AppStore(core: core, defaults: defaults)
    await store.refresh()
    let day = store.selectedReviewDate
    let host = NSHostingView(rootView: ReviewsWorkspaceView(store: store))
    let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1060, height: 570),
      styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    host.layoutSubtreeIfNeeded()
    let editor = try #require(note(in: host))
    editor.insertText("One thing worth remembering.", replacementRange: NSRange(location: 0, length: 0))
    #expect(store.dailyReviewSummaryDraft == editor.string)
    let selection = NSRange(location: 4, length: 5)
    editor.setSelectedRange(selection)

    for width in [1060, 700, 1060] {
      window.setContentSize(NSSize(width: width, height: 570))
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(50))
      let visibleEditor = try #require(note(in: host))
      #expect(visibleEditor === editor)
      #expect(visibleEditor.selectedRange() == selection)
      let scrollView = try #require(visibleEditor.enclosingScrollView)
      let frame = host.convert(scrollView.bounds, from: scrollView)
      #expect(frame.height >= 90)
      #expect(host.bounds.contains(frame), "Reflection is fully visible at \(width)pt.")
    }

    // Leaving before the debounce expires flushes to the old date.
    let yesterday = try #require(LorvexDateFormatters.ymdUTCAddingDays(day, days: -1))
    await store.selectReviewDay(yesterday)
    let saved = try await core.loadDailyReview(date: day)
    #expect(saved?.summary == "One thing worth remembering.")
    #expect(store.dailyReviewSummaryDraft.isEmpty)
    #expect(try await core.loadDailyReview(date: yesterday) == nil)
  }
}
