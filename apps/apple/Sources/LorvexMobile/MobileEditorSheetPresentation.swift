import SwiftUI

extension View {
  /// Medium and large detents for an editor sheet: medium keeps a quick edit
  /// compact, large gives a denser form room without switching entry-point
  /// behavior. At accessibility text sizes the sheet opens at large only.
  func mobileCompactEditorSheetPresentation() -> some View {
    mobileEditorSheetPresentation(opensFullHeight: false)
  }

  /// Large only, for deep editors whose content is navigational or
  /// scroll-heavy and should not open as a cramped half sheet.
  func mobileFullEditorSheetPresentation() -> some View {
    mobileEditorSheetPresentation(opensFullHeight: true)
  }

  /// The compact presentation, or the full one when `opensFullHeight` is true;
  /// for a sheet whose content decides which it needs.
  func mobileEditorSheetPresentation(opensFullHeight: Bool) -> some View {
    modifier(MobileEditorSheetPresentation(opensFullHeight: opensFullHeight))
  }
}

/// Detents and drag indicator shared by every editor sheet. A half-height
/// sheet shows too little of its content once text is at an accessibility
/// size, so those sizes open at large only, whatever the sheet asked for.
private struct MobileEditorSheetPresentation: ViewModifier {
  let opensFullHeight: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func body(content: Content) -> some View {
    content
      .presentationDetents(
        opensFullHeight || dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
      )
      .presentationDragIndicator(.visible)
  }
}
