import SwiftUI

extension View {
  func mobileCompactEditorSheetPresentation() -> some View {
    self
      // Editors use medium + large everywhere: medium keeps quick edits compact,
      // large gives dense forms room without switching entry-point behavior.
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
  }

  func mobileFullEditorSheetPresentation() -> some View {
    self
      // Deep editors use large everywhere because their content is navigational
      // or scroll-heavy and should not open as a cramped half sheet.
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
  }
}
