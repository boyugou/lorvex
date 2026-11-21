#if DEBUG
  import AppKit
  import LorvexCore

  /// Drives the app's regular SwiftUI Window scene using the in-memory preview store.
  /// AppKit enforces uniqueness of its search item when the window actually lays out.
  @MainActor
  enum LorvexWorkspaceSearchCheck {
    static func runIfRequested(store: AppStore) {
      guard CommandLine.arguments.contains("-uiPreviewSearchScene") else { return }
      Task {
        do {
          try await run(store)
          print("Workspace search navigation passed.")
          exit(EXIT_SUCCESS)
        } catch {
          FileHandle.standardError.write(Data("Workspace search navigation failed: \(error)\n".utf8))
          exit(EXIT_FAILURE)
        }
      }
    }

    private struct Failure: Error, CustomStringConvertible {
      let description: String
      init(_ description: String) { self.description = description }
    }

    private static func wait(_ expectation: String, until ready: () -> Bool) async throws {
      for _ in 0..<80 {
        if ready() { return }
        try await Task.sleep(for: .milliseconds(50))
      }
      throw Failure(expectation)
    }

    private static var mainWindow: NSWindow? {
      NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == LorvexWindowID.main.rawValue }
    }

    private static func searchFields(in window: NSWindow) -> [NSSearchField] {
      (window.toolbar?.visibleItems ?? []).compactMap { ($0 as? NSSearchToolbarItem)?.searchField }
    }

    private static func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags, in window: NSWindow)
      throws -> NSEvent
    {
      guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
        characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
      else { throw Failure("Could not create key event.") }
      return event
    }

    private static func run(_ store: AppStore) async throws {
      try await wait("Expected the regular main window.") { mainWindow?.toolbar != nil }
      guard let window = mainWindow else { throw Failure("Main window closed.") }

      // Alternate between a search owner and its absence while the toolbar is still animating.
      for delay in [35, 180, 65] {
        for page in [SidebarSelection.calendar, .today, .calendar, .reviews, .tasks, .memory, .habits, .lists] {
          store.navigateToWorkspace(page)
          try await Task.sleep(for: .milliseconds(delay))
        }
      }

      for page in SidebarSelection.allCases {
        store.navigateToWorkspace(page)
        let prompt = store.workspaceSearchPrompt(for: page)
        try await wait("Unexpected search field in \(page.rawValue).") {
          searchFields(in: window).map(\.placeholderString) == (prompt.map { [$0] } ?? [])
        }
      }
      guard let list = store.lists?.lists.first(where: { $0.id != LorvexListNaming.inboxID })
      else { throw Failure("Missing sample list.") }
      store.openTaskListScope(list.id)
      try await wait("Expected the selected list's search prompt.") {
        searchFields(in: window).first?.placeholderString == store.workspaceSearchPrompt(for: .tasks)
      }

      for page in [SidebarSelection.calendar, .memory, .reviews] {
        store.navigateToWorkspace(page)
        try await Task.sleep(for: .milliseconds(350))
        let find = try key("f", code: 3, modifiers: .command, in: window)
        guard NSApp.mainMenu?.performKeyEquivalent(with: find) == true else { throw Failure("Find command unavailable.") }
        let target: SidebarSelection = page == .reviews ? .tasks : page
        try await wait("Find did not focus \(target.rawValue).") {
          let fields = searchFields(in: window)
          guard let editor = fields.first?.currentEditor() else { return false }
          return fields.count == 1 && store.selection == target && window.firstResponder === editor
        }
        guard let editor = window.firstResponder as? NSTextView else { throw Failure("Expected the field editor.") }
        editor.insertText("venue", replacementRange: editor.selectedRange())
        try await wait("Search did not receive typed text.") { store.searchText == "venue" }
        window.sendEvent(try key("\u{1B}", code: 53, modifiers: [], in: window))
        try await wait("Escape did not clear the query.") { store.searchText.isEmpty }
      }
    }
  }
#endif
