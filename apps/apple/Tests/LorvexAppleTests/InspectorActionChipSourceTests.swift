import Foundation
import Testing

private func source(_ path: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

private let taskActions = "Sources/LorvexApple/Views/TaskDetailActionsSection.swift"
private let habitActions = "Sources/LorvexApple/Views/HabitDetailActions.swift"

@Test("The task and habit inspectors draw their overflow menu with the shared action chip")
func inspectorOverflowMenusWearTheSharedChip() throws {
  let chip = #"InspectorActionChip(systemImage: "ellipsis", title: nil)"#
  let task = try source(taskActions)
  let habit = try source(habitActions)
  #expect(task.contains(chip))
  #expect(habit.contains(chip))

  // The face lives in the chip's own file; neither inspector draws one.
  #expect(try source("Sources/LorvexApple/Views/InspectorActionChip.swift").contains("struct InspectorActionChip: View"))
  #expect(!task.contains("private func headerChip"))

  // A menu wears the chip through the plain button style. The system's
  // bordered style draws its own fill and tints the label with the accent.
  for (name, text, identifier) in [
    ("task", task, #".accessibilityIdentifier("task.detail.more")"#),
    ("habit", habit, #".accessibilityIdentifier("habit.detail.more")"#),
  ] {
    let end = try #require(text.range(of: identifier), "\(name) overflow menu")
    let menu = String(text[..<end.lowerBound].suffix(700))
    let chipRange = try #require(menu.range(of: chip), "\(name) overflow menu")
    let style = menu[chipRange.upperBound...]
    #expect(style.contains(".menuStyle(.button)"), "\(name) overflow menu")
    #expect(style.contains(".buttonStyle(.plain)"), "\(name) overflow menu")
    #expect(style.contains(".menuIndicator(.hidden)"), "\(name) overflow menu")
    #expect(!style.contains(".buttonStyle(.bordered)"), "\(name) overflow menu")
    // The chip is its symbol alone, so the menu names itself for VoiceOver.
    #expect(style.contains(".accessibilityLabel("), "\(name) overflow menu")
  }
}

@Test("An inspector action row sizes itself to its tallest control, which the chip then matches")
func inspectorActionRowsSizeToTheirContent() throws {
  let sizing = ".fixedSize(horizontal: false, vertical: true)"
  for (name, path, identifier) in [
    ("task", taskActions, #".accessibilityIdentifier("task.detail.header.actions")"#),
    ("habit", habitActions, #".accessibilityIdentifier("habit.detail.actions")"#),
  ] {
    let text = try source(path)
    let end = try #require(text.range(of: identifier), "\(name) action row")
    #expect(text[..<end.lowerBound].suffix(160).contains(sizing), "\(name) action row")
  }
}
