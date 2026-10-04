import SwiftUI

/// The scrolling column of the task and habit inspectors: an
/// ``InspectorColumn`` in a vertical scroll view that carries the window's
/// toolbar inset inside its content.
///
/// An inspector reaches up under the window's toolbar, so its content has to
/// start below the toolbar's height (the top safe area). Left to the scroll
/// view, that height becomes a content inset. AppKit counts the inset when it
/// decides whether the always-visible scroll bar is needed; SwiftUI compares
/// the document's height with the view's height alone. A document whose height
/// falls between the two measures is laid out for the pane's full width, and
/// the scroll bar that then appears covers its right edge, cutting short every
/// card and control that reaches it. Padding the document by the safe area
/// itself makes both measures agree, so the content always takes the width the
/// scroll bar leaves. The scroll bar keeps the same top margin, so its track
/// still starts below the toolbar instead of running under it.
struct InspectorScrollView<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        InspectorColumn(content: content)
          .padding(.top, proxy.safeAreaInsets.top)
      }
      .contentMargins(.top, proxy.safeAreaInsets.top, for: .scrollIndicators)
      .ignoresSafeArea(.container, edges: .top)
    }
  }
}
