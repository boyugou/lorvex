import SwiftUI

extension View {
  /// Medium and large detents for an editor sheet: medium keeps a quick edit
  /// compact, large gives a denser form room without switching entry-point
  /// behavior. At accessibility text sizes the sheet opens at large only.
  ///
  /// `cardHeight` replaces the medium detent for a sheet that shows as a card
  /// in a regular-width window. There medium is a card about 360 pt tall while
  /// the keyboard is up, which cuts the end of a long form once its text runs
  /// tall, as Telugu and Tamil do. Pass the height in points the form needs at
  /// the default text size; the detent grows with Dynamic Type, and the system
  /// limits it to the room above the keyboard.
  func mobileCompactEditorSheetPresentation(cardHeight: CGFloat? = nil) -> some View {
    mobileEditorSheetPresentation(opensFullHeight: false, cardHeight: cardHeight)
  }

  /// Large only, for deep editors whose content is navigational or
  /// scroll-heavy and should not open as a cramped half sheet.
  func mobileFullEditorSheetPresentation() -> some View {
    mobileEditorSheetPresentation(opensFullHeight: true)
  }

  /// The compact presentation, or the full one when `opensFullHeight` is true;
  /// for a sheet whose content decides which it needs.
  func mobileEditorSheetPresentation(
    opensFullHeight: Bool, cardHeight: CGFloat? = nil
  ) -> some View {
    modifier(MobileEditorSheetPresentation(opensFullHeight: opensFullHeight, cardHeight: cardHeight))
  }
}

/// The detents an editor sheet offers. A half-height sheet shows too little of
/// its content once text is at an accessibility size, so those sizes open at
/// large only, whatever the sheet asked for. Otherwise a sheet that shows as a
/// card takes `cardHeight` scaled by `textScale` as its first detent, and any
/// other sheet takes medium.
enum MobileEditorSheetDetents {
  nonisolated static func detents(
    opensFullHeight: Bool, isAccessibilitySize: Bool, cardHeight: CGFloat?, textScale: CGFloat
  ) -> Set<PresentationDetent> {
    if opensFullHeight || isAccessibilitySize { return [.large] }
    if let cardHeight { return [.height(cardHeight * textScale), .large] }
    return [.medium, .large]
  }
}

/// Detents and drag indicator shared by every editor sheet.
private struct MobileEditorSheetPresentation: ViewModifier {
  let opensFullHeight: Bool
  let cardHeight: CGFloat?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

  func body(content: Content) -> some View {
    content
      .presentationDetents(
        MobileEditorSheetDetents.detents(
          opensFullHeight: opensFullHeight, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
          cardHeight: cardHeight, textScale: textScale)
      )
      .presentationDragIndicator(.visible)
  }
}
