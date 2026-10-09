#if os(macOS)
  import AppKit
  import LorvexCore
  import SwiftUI
  import Testing

  @testable import LorvexApple

  /// The glyph before a workspace header's title sits in a column of one width,
  /// so the titles of all workspaces start on one edge, whatever the width of
  /// their symbols.
  @MainActor
  @Suite struct WorkspaceHeaderGlyphTests {
    private static let face = LorvexDesign.Typography.sectionHeader
    private static let column = WorkspaceHeaderTitleMetrics.glyphColumnWidth

    /// The display scales a Mac draws at. A symbol's width rounds to the pixel
    /// grid, so it differs between them: the brain is 22 pt at 1x and 23 pt at
    /// 2x, and the checklist is 22 pt at 1x and 21.5 pt at 2x.
    private static let scales: [CGFloat] = [1, 2]

    /// The symbols the workspace headers draw: each workspace's sidebar symbol,
    /// and the folder a list without an icon of its own shows.
    private static let headerSymbols = SidebarSelection.allCases.map(\.systemImage) + ["folder"]

    private static func width(_ view: some View, scale: CGFloat) -> CGFloat {
      NSHostingController(rootView: view.environment(\.displayScale, scale))
        .sizeThatFits(in: CGSize(width: 10_000, height: 1_000))
        .width
    }

    private static func bareWidth(_ symbol: String, scale: CGFloat) -> CGFloat {
      width(Image(systemName: symbol).font(face), scale: scale)
    }

    private static func source(_ name: String) throws -> String {
      let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
      return try String(
        contentsOf: root.appending(path: "Sources/LorvexApple/Views/\(name).swift"), encoding: .utf8)
    }

    /// Guards the other tests: drawn at their own widths the workspace symbols
    /// differ, which is the drift the column removes.
    @Test func bareSymbolsDifferInWidth() {
      for scale in Self.scales {
        let widths = Set(Self.headerSymbols.map { Self.bareWidth($0, scale: scale) })
        #expect(widths.count > 1, "bare widths at \(scale)x: \(widths.sorted())")
      }
    }

    /// A title starts one glyph column and one gap after the header's leading
    /// edge, so equal columns put every title on one edge.
    @Test func everyWorkspaceSymbolFillsOneColumn() {
      for scale in Self.scales {
        for symbol in Self.headerSymbols {
          let glyph = Self.width(WorkspaceHeaderGlyph(icon: symbol), scale: scale)
          #expect(
            abs(glyph - Self.column) < 0.01,
            "\(symbol) takes \(glyph) pt at \(scale)x, the column is \(Self.column) pt")
        }
      }
    }

    /// The column is the glyph's frame; a workspace symbol wider than it would
    /// widen its own header's column and move that title off the shared edge.
    @Test func theColumnHoldsTheWidestWorkspaceSymbol() {
      for scale in Self.scales {
        for symbol in Self.headerSymbols {
          let glyph = Self.bareWidth(symbol, scale: scale)
          #expect(
            glyph <= Self.column,
            "\(symbol) is \(glyph) pt wide at \(scale)x, the column is \(Self.column) pt")
        }
      }
    }

    /// A list's own icon may be wider than the column; it widens its column
    /// instead of being cut off.
    @Test func aWiderIconWidensItsColumn() {
      let wide = "🍎🍎🍎"
      for scale in Self.scales {
        let natural = Self.width(Text(wide).font(Self.face), scale: scale)
        #expect(natural > Self.column)
        #expect(Self.width(WorkspaceHeaderGlyph(icon: wide), scale: scale) >= natural)
        #expect(Self.width(WorkspaceHeaderGlyph(icon: "🍎"), scale: scale) >= Self.column)
      }
    }

    /// The header's row draws its glyph through the column, and the inset
    /// Today borrows is the sum of what lies before a title: the chrome's
    /// padding, the column, and the row's gap.
    @Test func theTitleInsetIsTheChromePaddingTheColumnAndTheGap() throws {
      let header = try Self.source("WorkspaceTaskColumn")
      #expect(header.contains("WorkspaceHeaderGlyph(icon: icon)"))

      let expected = LorvexDesign.Spacing.l + Self.column + LorvexDesign.Spacing.s
      #expect(WorkspaceHeaderTitleMetrics.titleInset == expected)

      for chrome in ["struct WorkspaceReviewHeaderChrome", "struct WorkspaceDashboardHeaderChrome"] {
        let start = try #require(header.range(of: chrome), "\(chrome) is missing")
        #expect(
          header[start.upperBound...].prefix(400).contains(".padding(.horizontal, LorvexDesign.Spacing.l)"),
          "\(chrome) pads by Spacing.l")
      }

      let start = try #require(header.range(of: "struct WorkspaceHeaderIdentity"))
      let end = try #require(
        header.range(of: "extension WorkspaceHeaderIdentity", range: start.upperBound..<header.endIndex))
      #expect(
        header[start.upperBound..<end.lowerBound].contains(
          "HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {"))
    }

    /// Today's date line is its title and has no glyph beside it, so Today's
    /// column insets by the title inset to start the date on the same edge.
    @Test func todayInsetsItsColumnByTheTitleInset() throws {
      let today = try Self.source("TodayView")
      #expect(today.contains(".padding(.horizontal, WorkspaceHeaderTitleMetrics.titleInset)"))
    }
  }
#endif
