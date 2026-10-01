import SwiftUI

/// How a detail view is presented: as a screen of its own on the navigation
/// stack, or as the detail pane of a list+detail split, beside the list that
/// chose it.
///
/// A screen owns the navigation bar, so it names itself there and keeps its
/// actions in the toolbar. A pane shares the one bar with the list beside it:
/// the bar keeps the list's title and toolbar, and the pane shows its actions
/// in its own content.
enum MobileDetailPresentation: Sendable {
  case screen
  case pane
}

extension EnvironmentValues {
  /// The presentation of the enclosing detail view: `.screen` unless a
  /// list+detail split placed it in its detail pane.
  @Entry var mobileDetailPresentation: MobileDetailPresentation = .screen
}

extension View {
  /// The navigation title and toolbar items a detail view contributes when it
  /// is a screen of its own. In a split's detail pane they are left off, so the
  /// bar keeps the list's title and toolbar, and the pane shows its actions in
  /// its content instead.
  func mobileDetailScreenChrome<Items: ToolbarContent>(
    title: String,
    titleDisplayMode: ToolbarTitleDisplayMode = .automatic,
    @ToolbarContentBuilder toolbar: () -> Items
  ) -> some View {
    modifier(
      MobileDetailScreenChrome(title: title, titleDisplayMode: titleDisplayMode, items: toolbar()))
  }
}

private struct MobileDetailScreenChrome<Items: ToolbarContent>: ViewModifier {
  let title: String
  let titleDisplayMode: ToolbarTitleDisplayMode
  let items: Items
  @Environment(\.mobileDetailPresentation) private var presentation

  func body(content: Content) -> some View {
    switch presentation {
    case .screen:
      content
        .navigationTitle(title)
        .toolbarTitleDisplayMode(titleDisplayMode)
        .toolbar { items }
    case .pane:
      content
    }
  }
}
