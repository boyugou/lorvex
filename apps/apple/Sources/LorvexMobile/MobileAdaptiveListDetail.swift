import SwiftUI

/// Width-responsive list+detail container for the iPad regular-width workspaces.
///
/// iPad portrait is still `horizontalSizeClass == .regular`, so size class alone
/// cannot tell a roomy landscape canvas apart from a cramped portrait one. This
/// view measures the actual available width and picks a layout from it:
///
/// - **Wide** (`width >= widthThreshold`, landscape / full-screen iPad): the
///   side-by-side `HStack { list · Divider · detail-or-placeholder }`. The
///   detail column is hosted in its own `NavigationStack` so the detail's
///   toolbar and title render in the detail pane's bar instead of merging into
///   the list's.
/// - **Narrow** (portrait, Split View, Slide Over): a `NavigationStack` showing
///   the `list` full-width; selecting a row pushes `detail` via
///   `navigationDestination(item:)`, and the system back button pops it (which
///   clears the selection).
///
/// A single `selection` binding drives both modes, so rotating wide↔narrow keeps
/// the selection and renders the detail in whichever shape the new width calls
/// for. The threshold is `700pt`: an iPad in portrait is ~768pt wide, which is
/// too narrow for a usable list+detail split once the outer shell sidebar is
/// also on screen, so portrait falls into the narrow (pushed-detail) layout
/// while landscape (~1024pt+) and full-screen multitasking stay side-by-side.
@MainActor
struct MobileAdaptiveListDetail<ID: Hashable, List: View, Detail: View, Placeholder: View>: View {
  /// Width at or above which the side-by-side layout is used; below it, the
  /// list is full-width and the detail is pushed onto a `NavigationStack`.
  static var widthThreshold: CGFloat { 700 }

  @Binding var selection: ID?
  private let list: List
  private let detail: (ID) -> Detail
  private let placeholder: Placeholder

  /// Sensible list width for the wide (side-by-side) layout. Mirrors the
  /// constraints the hand-rolled Tasks split used so rows keep their density.
  private let listMinWidth: CGFloat = 320
  private let listIdealWidth: CGFloat = 380
  private let listMaxWidth: CGFloat = 460

  init(
    selection: Binding<ID?>,
    @ViewBuilder list: () -> List,
    @ViewBuilder detail: @escaping (ID) -> Detail,
    @ViewBuilder placeholder: () -> Placeholder
  ) {
    self._selection = selection
    self.list = list()
    self.detail = detail
    self.placeholder = placeholder()
  }

  var body: some View {
    GeometryReader { geo in
      if geo.size.width >= Self.widthThreshold {
        wideBody
      } else {
        narrowBody
      }
    }
  }

  private var wideBody: some View {
    HStack(spacing: 0) {
      list
        .frame(minWidth: listMinWidth, idealWidth: listIdealWidth, maxWidth: listMaxWidth)

      Divider()

      Group {
        if let selection {
          // Host the detail column in its own navigation container so the
          // detail's toolbar and title render in the detail pane's own bar,
          // rather than merging into the list's nav bar (which would leave it
          // ambiguous which pane a bar-level action targets). Mirrors
          // `narrowBody`, where the pushed detail is likewise inside a
          // `NavigationStack`.
          NavigationStack {
            detail(selection)
          }
        } else {
          placeholder
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var narrowBody: some View {
    NavigationStack {
      list
        .navigationDestination(item: $selection) { id in
          detail(id)
        }
    }
  }
}
