import Foundation
import Testing

@testable import LorvexApple

/// The Memory list and the Calendar plan rail give each row a focus stop, and
/// ↑/↓/Home/End move that focus between rows through the shared movement math
/// (``WorkspaceTaskArrowKeyMovement``, tested on its own). A key press cannot be
/// sent headlessly, so these pin that each list wires its rows in.
@Suite("Arrow-key focus lists")
struct ArrowKeyFocusListsTests {
  private func source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appending(path: "Sources/LorvexApple/Views/\(path)"), encoding: .utf8)
  }

  @Test("Each list focuses its rows through the shared helper")
  func listsWireTheHelper() throws {
    for file in ["MemoryWorkspaceView.swift", "CalendarPlanRail.swift"] {
      let text = try source(file)
      #expect(text.contains(".lorvexArrowKeyFocus("), "\(file) wires its rows in")
      #expect(text.contains("@FocusState private var"), "\(file) holds the focus state")
    }
  }

  @Test("Arrow steps stop at the ends of a list instead of wrapping")
  func stopsAtTheEnds() {
    let ids = ["a", "b", "c"]
    #expect(WorkspaceTaskArrowKeyMovement.target(for: .previous, anchor: "a", orderedIDs: ids) == nil)
    #expect(WorkspaceTaskArrowKeyMovement.target(for: .next, anchor: "c", orderedIDs: ids) == nil)
    #expect(WorkspaceTaskArrowKeyMovement.target(for: .next, anchor: "a", orderedIDs: ids) == "b")
  }
}
