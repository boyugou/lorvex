import Foundation
import SwiftUI
import Testing

@testable import LorvexApple

// The View menu's Calendar commands drive the same state as the toolbar: the
// Day/Week/Month presentation, the jump back to today, and the Unplanned Tasks
// rail.

private func source(_ path: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

@Test
func eachCalendarModeNamesItselfAndItsJumpBackToToday() {
  #expect(CalendarPresentationMode.allCases.map(\.title) == ["Day", "Week", "Month"])
  #expect(
    CalendarPresentationMode.allCases.map(\.currentPeriodTitle)
      == ["Today", "This Week", "This Month"])
}

@Test
func theRailCommandIsNamedByWhatChoosingItDoes() {
  #expect(CalendarViewCommands.planRailTitle(isShown: false) == "Show Unplanned Tasks")
  #expect(CalendarViewCommands.planRailTitle(isShown: true) == "Hide Unplanned Tasks")
}

@Test
func theContextCarriesTheWorkspacesLiveState() {
  final class State {
    var mode = CalendarPresentationMode.week
    var showsRail = false
    var jumps = 0
  }
  let state = State()
  let context = LorvexCalendarCommandContext(
    mode: Binding(get: { state.mode }, set: { state.mode = $0 }),
    showsPlanRail: Binding(get: { state.showsRail }, set: { state.showsRail = $0 }),
    isViewingCurrent: false,
    jumpToCurrent: { state.jumps += 1 })

  context.mode.wrappedValue = .month
  context.showsPlanRail.wrappedValue.toggle()
  context.jumpToCurrent()

  #expect(state.mode == .month)
  #expect(state.showsRail)
  #expect(state.jumps == 1)
}

@Test
func theViewMenuHoldsTheCalendarCommandsBesideTheSidebarToggle() throws {
  let commands = try source("Sources/LorvexApple/App/LorvexAppCommands.swift")
  let group = try #require(commands.range(of: "CommandGroup(replacing: .sidebar)"))
  let body = commands[group.upperBound...].prefix(120)
  #expect(body.contains("SidebarVisibilityCommandButton()"))
  #expect(body.contains("CalendarViewCommands()"))

  let workspace = try source("Sources/LorvexApple/Views/CalendarWorkspaceView.swift")
  let publish = try #require(workspace.range(of: ".focusedSceneValue("))
  let published = workspace[publish.upperBound...].prefix(260)
  #expect(published.contains("\\.lorvexCalendarCommandContext"))
  #expect(published.contains("mode: $mode, showsPlanRail: $showsPlanRail"))
  #expect(published.contains("isViewingCurrent: isViewingCurrent"))
  #expect(published.contains("jumpToCurrent: jumpToCurrent"))
}

@Test
func theCalendarCommandsStayOffEveryKeyOtherMenusUse() throws {
  let commands = try source("Sources/LorvexApple/Support/LorvexCalendarCommandContext.swift")
  #expect(commands.contains(#".keyboardShortcut("t", modifiers: [.command])"#))
  #expect(commands.contains(#".keyboardShortcut("u", modifiers: [.command, .option])"#))
  #expect(commands.contains(".disabled(context.isViewingCurrent)"))
  // The commands exist only while a window shows the Calendar.
  #expect(commands.contains("if let context {"))
}
