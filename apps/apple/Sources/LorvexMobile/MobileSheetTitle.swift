import LorvexCore
import SwiftUI

extension View {
  /// Titles a sheet whose navigation bar holds a text button on each side.
  ///
  /// The system's inline title gets only the space between the two buttons and
  /// cuts a longer title short with an ellipsis, and many translations ("Aufgabe
  /// bearbeiten", "Добавить напоминание") are longer than that space. The title
  /// is drawn at the system's inline size while it fits one line, then one text
  /// style smaller, and otherwise on two lines, so every word stays readable.
  /// The navigation title is still set, so VoiceOver and the app switcher name
  /// the sheet. Off iOS the sheet keeps the plain navigation title.
  func mobileSheetTitle(_ title: String) -> some View {
    #if os(iOS)
      return navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .principal) { MobileSheetTitleLabel(title: title) }
        }
    #else
      return navigationTitle(title)
    #endif
  }
}

#if os(iOS)
  /// The three title looks `mobileSheetTitle` steps through: the system inline
  /// size, the page-label size, and two lines of the page-label size. The bar
  /// takes its title's height from the title's own size, so the label is
  /// always two lines tall, and the one-line looks centre in it; a shorter
  /// area would cut the two-line look back to one truncated line. The text
  /// size is capped at the default so that height holds.
  private struct MobileSheetTitleLabel: View {
    let title: String

    var body: some View {
      ViewThatFits(in: .horizontal) {
        Text(verbatim: title).font(.headline).lineLimit(1)
        Text(verbatim: title).font(LorvexDesign.Typography.pageLabel).lineLimit(1)
        Text(verbatim: title).font(LorvexDesign.Typography.pageLabel)
          .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
      }
      .frame(height: 40)
      .dynamicTypeSize(...DynamicTypeSize.large)
      .accessibilityAddTraits(.isHeader)
    }
  }
#endif
