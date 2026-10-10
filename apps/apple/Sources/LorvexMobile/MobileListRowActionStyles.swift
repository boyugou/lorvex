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
  /// Only for rows the list draws itself. Context menus and `Menu` items
  /// already render the role in full; a bordered button takes
  /// ``SwiftUI/View/mobileDestructiveBorderedStyle()`` instead, and a swipe
  /// action ``SwiftUI/View/mobileDestructiveSwipeStyle()``.
  func mobileDestructiveRowStyle() -> some View {
    foregroundStyle(LorvexDesign.Palette.destructive)
  }

  /// Colors a swipe action that deletes red.
  ///
  /// A swipe action inherits the root view's accent tint, and that tint
  /// outranks the `destructive` role, so a Delete would draw as a blue circle.
  ///
  /// A button that deletes at once keeps the `destructive` role next to this
  /// tint: the role collapses the row as the action runs and lets a full swipe
  /// perform it. A button that only raises a confirmation takes the tint
  /// alone. A destructive swipe button collapses its row the moment it is
  /// tapped, and a confirmation dialog attached to that row closes with it
  /// before it can show.
  func mobileDestructiveSwipeStyle() -> some View {
    tint(LorvexDesign.Palette.destructive)
  }

  /// Draws a swipe action in the system's neutral gray, for an action that is
  /// neither the row's main action nor a deletion — Archive, Skip Today.
  ///
  /// A swipe action inherits the root view's accent tint and draws blue;
  /// clearing the tint gives the default gray circle, which keeps the accent
  /// for the actions that are the row's own (Edit, Complete).
  func mobileNeutralSwipeStyle() -> some View {
    tint(nil)
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
