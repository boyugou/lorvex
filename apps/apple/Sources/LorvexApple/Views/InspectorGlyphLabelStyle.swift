import LorvexCore
import SwiftUI

/// The label of an inspector panel's title or of one of its readings: the glyph
/// centered in a column of one fixed width, so every sibling label's title
/// starts on one edge whatever its glyph's width. SF Symbols of one size differ
/// in width by several points (a flame is narrower than a seal), and a plain
/// `Label` starts each title after its own glyph.
///
/// The glyph sits on the title's first baseline, so a title that wraps, or one
/// that carries a caption beneath it, keeps its glyph beside the first line.
/// VoiceOver reads the title alone; the glyph is decoration. Use the shared
/// widths through ``SwiftUI/LabelStyle/inspectorPanelTitle`` and
/// ``SwiftUI/LabelStyle/inspectorReading``.
struct InspectorGlyphLabelStyle: LabelStyle {
  /// The width of the glyph column, at least as wide as the widest symbol the
  /// labels of one group set in their face.
  let glyphWidth: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      configuration.icon
        .frame(width: glyphWidth)
        .accessibilityHidden(true)
      configuration.title
    }
  }
}

extension LabelStyle where Self == InspectorGlyphLabelStyle {
  /// For the title of a panel, set in `Typography.primaryEmphasis`.
  static var inspectorPanelTitle: InspectorGlyphLabelStyle {
    InspectorGlyphLabelStyle(glyphWidth: InspectorGlyphColumn.panelTitle)
  }

  /// For the name of a reading inside a panel, set in `Typography.tertiaryText`.
  static var inspectorReading: InspectorGlyphLabelStyle {
    InspectorGlyphLabelStyle(glyphWidth: InspectorGlyphColumn.reading)
  }
}

/// The glyph column widths of ``InspectorGlyphLabelStyle``, one per face the
/// inspector sets a glyph label in. Each is the width of the widest symbol the
/// inspector uses in that face: 20 pt for the chart and checklist symbols at
/// the panel-title size, 16 pt for the bar-chart symbol at the reading size.
enum InspectorGlyphColumn {
  static let panelTitle: CGFloat = 20
  static let reading: CGFloat = 16
}
