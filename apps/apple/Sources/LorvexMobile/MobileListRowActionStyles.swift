import LorvexCore
import SwiftUI

extension View {
  /// Paints a destructive `Button` that sits as a plain row in a `List` or
  /// `Form` — Cancel, Delete, Erase — fully red, icon included.
  ///
  /// See ``SwiftUI/View/mobileAccentRowStyle()`` for why an explicit color is
  /// needed at all. Here the specific gap is that the `destructive` button role
  /// recolors only the row's title, leaving the `Label`'s icon in the accent
  /// color, so the row reads as an ordinary blue action wearing red text.
  ///
  /// Only for rows the list draws itself. Swipe actions, context menus, and
  /// `Menu` items already render the role in full; a bordered button takes
  /// ``SwiftUI/View/mobileDestructiveBorderedStyle()`` instead.
  func mobileDestructiveRowStyle() -> some View {
    foregroundStyle(LorvexDesign.Palette.destructive)
  }

  /// Tints a destructive `Button` drawn in the bordered style — a detail
  /// page's or a batch bar's Delete — red, fill and label together.
  ///
  /// The root view tints the app with the accent color, and in the bordered
  /// style an explicit tint outranks the `destructive` role, so without this
  /// the button draws as an ordinary blue action next to its neighbors.
  func mobileDestructiveBorderedStyle() -> some View {
    tint(LorvexDesign.Palette.destructive)
  }

  /// Paints an ordinary action `Button` that sits as a plain row in a `List` or
  /// `Form` — Save, Add, Import — in the accent color, icon and title together.
  ///
  /// A row button takes its color from state SwiftUI applies to the title alone:
  /// disabling one leaves the title in the default text color while the `Label`'s
  /// icon stays accent-colored, so an unavailable row reads as a live one with a
  /// stray black title. Coloring the whole button keeps the two halves together
  /// and lets the disabled state dim them as one.
  ///
  /// Needed only on a row that can be disabled. A row that is always tappable
  /// already draws both halves in the accent color.
  func mobileAccentRowStyle() -> some View {
    foregroundStyle(LorvexDesign.Palette.accent)
  }
}
