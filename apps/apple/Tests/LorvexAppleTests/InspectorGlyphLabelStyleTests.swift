#if os(macOS)
  import AppKit
  import LorvexCore
  import SwiftUI
  import Testing

  @testable import LorvexApple

  /// The labels of the inspectors' panel titles and readings start their
  /// titles on one edge, whatever the width of their glyphs.
  @MainActor
  @Suite struct InspectorGlyphLabelStyleTests {
    private static let titleFont = LorvexDesign.Typography.primaryEmphasis
    private static let readingFont = LorvexDesign.Typography.tertiaryText

    /// The glyphs of the habit inspector's Progress, History and By Weekday
    /// titles and of the task inspector's Checklist and Notes titles.
    private static let titleGlyphs = [
      "chart.line.uptrend.xyaxis", "calendar", "chart.bar.xaxis", "checklist", "note.text",
    ]
    /// The glyphs of the Progress panel's four readings.
    private static let readingGlyphs = [
      "flame.fill", "trophy.fill", "checkmark.seal.fill", "chart.bar.fill",
    ]

    private static func size(_ view: some View) -> CGSize {
      NSHostingController(rootView: view)
        .sizeThatFits(in: CGSize(width: 10_000, height: 1_000))
    }

    private static func width(_ view: some View) -> CGFloat { size(view).width }

    /// How far into a label its title starts: the label's width less the
    /// title's own.
    private static func panelTitleStart(_ symbol: String) -> CGFloat {
      width(Label("Title", systemImage: symbol).labelStyle(.inspectorPanelTitle).font(titleFont))
        - width(Text("Title").font(titleFont))
    }

    private static func readingStart(_ symbol: String) -> CGFloat {
      width(Label("Title", systemImage: symbol).labelStyle(.inspectorReading).font(readingFont))
        - width(Text("Title").font(readingFont))
    }

    /// The same, for a label in the platform's own style.
    private static func plainStart(_ symbol: String, font: Font) -> CGFloat {
      width(Label("Title", systemImage: symbol).font(font)) - width(Text("Title").font(font))
    }

    private static func distinct(_ values: [CGFloat]) -> Int {
      Set(values.map { ($0 * 100).rounded() }).count
    }

    /// Guards the other tests: in the platform's own style the title follows
    /// its glyph's width, which is the drift the style removes.
    @Test func aPlainLabelStartsItsTitleAfterItsOwnGlyph() {
      #expect(Self.distinct(Self.readingGlyphs.map { Self.plainStart($0, font: Self.readingFont) }) > 1)
      #expect(Self.distinct(Self.titleGlyphs.map { Self.plainStart($0, font: Self.titleFont) }) > 1)
    }

    /// A title starts one column and one gap in from the label's leading edge.
    @Test func readingsStartTheirTitlesOnOneEdge() {
      let starts = Self.readingGlyphs.map { Self.readingStart($0) }
      let expected = InspectorGlyphColumn.reading + LorvexDesign.Spacing.s
      #expect(starts.allSatisfy { abs($0 - expected) < 0.01 }, "title starts \(starts), expected \(expected)")
    }

    @Test func panelTitlesStartOnOneEdge() {
      let starts = Self.titleGlyphs.map { Self.panelTitleStart($0) }
      let expected = InspectorGlyphColumn.panelTitle + LorvexDesign.Spacing.s
      #expect(starts.allSatisfy { abs($0 - expected) < 0.01 }, "title starts \(starts), expected \(expected)")
    }

    /// A reading's name that is wider than its room wraps to a second line, as
    /// it does in a narrow inspector or a long language, instead of being cut
    /// short or pushing the label wider.
    @Test func aLongReadingNameWrapsInsideItsRoom() {
      func label(_ title: String) -> some View {
        Label(title, systemImage: "flame.fill")
          .labelStyle(.inspectorReading)
          .font(Self.readingFont)
          .fixedSize(horizontal: false, vertical: true)
          .frame(width: 100)
      }
      let short = Self.size(label("Streak"))
      let long = Self.size(label("Current streak so far"))
      #expect(long.height >= short.height * 1.8, "one line is \(short.height) pt, wrapped is \(long.height) pt")
    }

    /// The column is the glyph's frame, so a glyph wider than it would overlap
    /// its title.
    @Test func theColumnsHoldTheWidestGlyphOfTheirFace() {
      for symbol in Self.titleGlyphs {
        let glyph = Self.width(Image(systemName: symbol).font(Self.titleFont))
        #expect(glyph <= InspectorGlyphColumn.panelTitle, "\(symbol) is \(glyph) pt wide")
      }
      for symbol in Self.readingGlyphs {
        let glyph = Self.width(Image(systemName: symbol).font(Self.readingFont))
        #expect(glyph <= InspectorGlyphColumn.reading, "\(symbol) is \(glyph) pt wide")
      }
    }

    private static func viewSource(_ name: String) throws -> String {
      let views = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/LorvexApple/Views")
      return try String(contentsOf: views.appending(path: "\(name).swift"), encoding: .utf8)
    }

    @Test func theHabitPanelsSetTheirGlyphLabelsInTheColumns() throws {
      for name in ["HabitProgressPanel", "HabitHistoryPanel", "HabitWeekdayPanel"] {
        #expect(try Self.viewSource(name).contains(".labelStyle(.inspectorPanelTitle)"), "\(name) title")
      }
      // The Progress panel's four readings share one reading label.
      #expect(try Self.viewSource("HabitProgressPanel").contains(".labelStyle(.inspectorReading)"))
    }

    /// The task inspector's Checklist and Notes titles are labels set in the
    /// same column, so they start their titles where the habit panels do.
    @Test func theTaskPanelsSetTheirTitlesInTheColumn() throws {
      for (name, titleKey) in [
        ("TaskDetailChecklistSection", "task_detail.checklist.title"),
        ("TaskDetailNotesSection", "task_detail.notes.title"),
      ] {
        let source = try Self.viewSource(name)
        let title = try #require(source.range(of: "\"\(titleKey)\""), "\(name) title")
        #expect(
          source[title.upperBound...].prefix(300).contains(".labelStyle(.inspectorPanelTitle)"),
          "\(name) title")
      }
    }
  }
#endif
