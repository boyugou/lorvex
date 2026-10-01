import LorvexCore
import SwiftUI

/// Width-responsive list+detail container for the iPad regular-width workspaces.
///
/// iPad portrait is still `horizontalSizeClass == .regular`, so size class alone
/// cannot tell a roomy landscape canvas apart from a cramped portrait one. This
/// view measures the actual available width and picks a layout from it:
///
/// - **Wide** (`width >= widthThreshold`, landscape / full-screen iPad): the
///   side-by-side `HStack { list · Divider · detail-or-placeholder }`. The
///   detail is told it is a pane (`mobileDetailPresentation`), so the bar
///   keeps the list's title and toolbar and the detail shows its actions in
///   its own content.
/// - **Narrow** (portrait, Split View, Slide Over): the `list` full-width;
///   selecting a row pushes `detail` onto the enclosing navigation stack via
///   `navigationDestination(item:)`, and the system back button pops it (which
///   clears the selection).
///
/// The container always sits inside a navigation stack: a tab's own stack, or
/// the Tasks stack that pushed the workspace from the Tasks home. It never
/// opens a `NavigationStack` of its own, around the list or around the
/// detail: a stack nested inside a pushed destination leaves the enclosing
/// stack's push undone (the workspace never appears), whether the nested
/// stack exists from the destination's first, zero-size evaluation or only
/// once a selection arrives. The width is read from a `GeometryReader`, which
/// reports what the container proposes and never what either layout wants;
/// the token sizes it reports for a transition's zero-size pass and an
/// ideal-size pass are ignored, and until a real width arrives the size class
/// picks the layout, so a screen beneath a push, which only ever sees those
/// passes, keeps the layout its window calls for instead of swapping in the
/// narrow one, which would push its selection a second time.
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
  /// list is full-width and the detail is pushed onto the enclosing stack.
  static var widthThreshold: CGFloat { 700 }

  @Binding var selection: ID?
  private let list: List
  private let detail: (ID) -> Detail
  private let placeholder: Placeholder
  /// The last real width measured, or nil before the first real layout.
  @State private var measuredWidth: CGFloat?
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

  /// Widths below this are a token evaluation, not a layout: the zero a
  /// navigation transition proposes to a screen beneath the top one, the
  /// zero-size first pass of a pushed screen, or the ten points a
  /// `GeometryReader` reports for an ideal-size pass. They are never stored.
  private static var tokenWidth: CGFloat { 100 }

  private var isWide: Bool {
    guard let measuredWidth else { return horizontalSizeClass == .regular }
    return measuredWidth >= Self.widthThreshold
  }

  var body: some View {
    // Measured on the reader's content, which is sized to the proposal, not
    // on a layer in a stack beside the layouts: a stack proposes its union to
    // that layer, so under an ideal-size pass it measured the wide layout's
    // own ideal width, a real-looking value that swapped in the narrow layout.
    GeometryReader { proxy in
      Group {
        if isWide {
          wideBody
        } else {
          narrowBody
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
        guard width >= Self.tokenWidth else { return }
        measuredWidth = width
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
          detail(selection)
        } else {
          placeholder
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .environment(\.mobileDetailPresentation, .pane)
      // Both panes sit on the same grouped background so the divider is the
      // only seam; a bare detail column would otherwise read as a white sheet
      // beside the grouped list.
      .background(LorvexDesign.Palette.groupedBackground)
    }
    // The Tasks home caps its own content at a readable width through scroll
    // content margins, and a workspace pushed from it inherits them. Each
    // pane here is already narrower than that cap, so the panes go back to
    // the system margins or the list's rows would be squeezed into a third
    // of their column.
    .contentMargins(.horizontal, nil, for: .scrollContent)
    .environment(\.mobileReadableMargin, nil)
  }

  private var narrowBody: some View {
    list
      .navigationDestination(item: $selection) { id in
        detail(id)
      }
  }
}
