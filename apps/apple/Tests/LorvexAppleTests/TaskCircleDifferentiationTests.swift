import Foundation
import Testing

@testable import LorvexCore

#if canImport(AppKit)
  import AppKit
#endif

// A task row's circle carries the priority by tint. With Differentiate Without
// Color on, an open task's circle also marks the priority inside the ring.

private let priorities: [LorvexTask.Priority] = [.p1, .p2, .p3]

private func task(_ priority: LorvexTask.Priority, _ status: LorvexTask.Status) -> LorvexTask {
  LorvexTask(
    id: "t", title: "Write the brief", notes: "", priority: priority, status: status, dueDate: nil,
    plannedDate: nil, plannedTime: nil, estimatedMinutes: nil, tags: [])
}

@Test
func anOpenTaskMarksItsPriorityInsideTheCircleOnRequest() {
  for status in [LorvexTask.Status.open, .inProgress] {
    #expect(task(.p1, status).statusCircleGlyph(differentiatingPriority: true) == "exclamationmark.circle")
    #expect(task(.p2, status).statusCircleGlyph(differentiatingPriority: true) == "circle")
    #expect(task(.p3, status).statusCircleGlyph(differentiatingPriority: true) == "arrow.down.circle")
  }
}

@Test
func withoutTheSettingEveryOpenCircleIsThePlainRing() {
  for priority in priorities {
    #expect(task(priority, .open).statusCircleGlyph(differentiatingPriority: false) == "circle")
    #expect(task(priority, .open).statusCircleGlyph == "circle")
  }
}

@Test
func aResolvedOrParkedTaskKeepsItsOwnGlyphWhateverItsPriority() {
  for priority in priorities {
    for status in [LorvexTask.Status.completed, .cancelled, .someday] {
      let task = task(priority, status)
      #expect(task.statusCircleGlyph(differentiatingPriority: true) == task.statusCircleGlyph)
    }
  }
}

@Test
func eachPriorityHasItsOwnMarkedGlyph() {
  #expect(Set(priorities.map { $0.circleGlyph(differentiating: true) }).count == priorities.count)
  #expect(Set(priorities.map { $0.circleGlyph(differentiating: false) }) == ["circle"])
}

#if canImport(AppKit)
  @Test
  func everyCircleGlyphIsARealSystemSymbol() {
    for priority in priorities {
      for differentiating in [false, true] {
        let name = priority.circleGlyph(differentiating: differentiating)
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
      }
    }
  }
#endif

private func swiftSources(under directory: String) throws -> [(path: String, text: String)] {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let base = root.appending(path: directory)
  let files = try #require(
    FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
  return try files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.map {
    ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8))
  }
}

@Test
func noSurfaceDrawsTheCircleGlyphWithoutTheSettingInMind() throws {
  // The app's rows, the detail pages and the menu bar panel draw the circle
  // through `LorvexTaskStatusCircle`, which reads the setting; only the core
  // defines the glyph and style it composes.
  for directory in ["Sources/LorvexApple", "Sources/LorvexMobile"] {
    for (path, text) in try swiftSources(under: directory) {
      #expect(!text.contains("statusCircleGlyph"), "\(path)")
      #expect(!text.contains("statusCircleStyle"), "\(path)")
    }
  }
}

@Test
func theCircleViewReadsTheSettingAndComposesTheCoreGlyph() throws {
  let circle = try #require(
    try swiftSources(under: "Sources/LorvexCore/Support").first { $0.path == "LorvexTaskStatusCircle.swift" })
  #expect(circle.text.contains("@LorvexDifferentiateWithoutColor private var differentiateWithoutColor"))
  #expect(circle.text.contains("task.statusCircleGlyph(differentiatingPriority: differentiateWithoutColor)"))
  #expect(circle.text.contains("task.statusCircleStyle"))
}

@Test
func aParkedTaskCircleIsTheSomedayGrayNotAHierarchicalStyle() throws {
  // A hierarchical `.secondary` style takes its level from the tint of the
  // control around the circle: inside the borderless completion button it draws
  // accent blue at half strength (about 2:1 on the card). The someday gray is a
  // plain color, so the moon stays gray in every container.
  let presentation = try #require(
    try swiftSources(under: "Sources/LorvexCore/Models").first {
      $0.path == "TaskStatusPresentation.swift"
    })
  #expect(presentation.text.contains("case .someday: AnyShapeStyle(LorvexDesign.Palette.someday)"))
  #expect(!presentation.text.contains("case .someday: AnyShapeStyle(.secondary)"))
}

@Test
func everyTaskRowCirclePassesThroughTheSharedView() throws {
  let expected: [(directory: String, file: String, uses: Int)] = [
    ("Sources/LorvexApple/Views", "LorvexTaskRow.swift", 1),
    ("Sources/LorvexApple/Views", "MenuBarTaskRow.swift", 1),
    ("Sources/LorvexApple/Views", "TaskDetailHeaderSection.swift", 1),
    ("Sources/LorvexApple/Views", "TaskDetailDependenciesSection.swift", 1),
    ("Sources/LorvexMobile", "MobileTaskRows.swift", 2),
    ("Sources/LorvexMobile", "MobileTaskDependenciesSection.swift", 1),
  ]
  for (directory, file, uses) in expected {
    let source = try #require(try swiftSources(under: directory).first { $0.path == file })
    #expect(source.text.components(separatedBy: "LorvexTaskStatusCircle(task:").count == uses + 1, "\(file)")
  }
}

@Test
func theWidgetAndWatchCirclesFollowTheSetting() throws {
  for (directory, file, uses) in [
    ("Sources/LorvexWidgetViews", "LorvexWidgetTaskRowView.swift", 1),
    ("Sources/LorvexWidgetViews", "LorvexWidgetSmallView.swift", 1),
    ("Sources/LorvexWatch", "LorvexWatchTaskRow.swift", 1),
  ] {
    let source = try #require(try swiftSources(under: directory).first { $0.path == file })
    #expect(source.text.contains("@LorvexDifferentiateWithoutColor private var differentiateWithoutColor"), "\(file)")
    #expect(
      source.text.components(separatedBy: "circleGlyph(differentiating: differentiateWithoutColor)").count
        == uses + 1, "\(file)")
  }
}
