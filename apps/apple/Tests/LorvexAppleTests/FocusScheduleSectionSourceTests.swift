import Foundation
import Testing

@Test
func focusScheduleSectionUsesScannableRowsAndLocalizedFallbacks() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/FocusScheduleSection.swift"),
    encoding: .utf8
  )

  #expect(source.contains("WorkspaceTaskSectionHeader("))
  #expect(source.contains(#".accessibilityIdentifier("focus.schedule.panel")"#))
  #expect(source.contains("FocusScheduleBlockRow(block: block)"))
  #expect(source.contains("ForEach(Array(schedule.blocks.enumerated()), id: \\.offset)"))
  #expect(source.contains("FocusScheduleUnscheduledRow(task: task)"))
  #expect(source.contains("schedule.blocks.count + schedule.unscheduled.count"))
  #expect(!source.contains("Section(title)"))
  #expect(source.contains(".font(LorvexDesign.Typography.tertiaryText.monospacedDigit().weight(.medium))"))
  #expect(source.contains("focus.schedule.block.fallback_title"))
  #expect(source.contains("focus.schedule.unscheduled.no_estimate"))
  #expect(source.contains("focus.schedule.unscheduled.estimated"))
}
