import LorvexCore
import SwiftUI

/// The width and insets of an inspector's content: at most 500 pt wide, so a
/// wide inspector keeps its rows readable instead of stretching them.
enum InspectorColumnMetrics {
  static let maxContentWidth: CGFloat = 500
  static let horizontalPadding: CGFloat = LorvexDesign.Spacing.m
  static let topPadding: CGFloat = LorvexDesign.Spacing.m
  static let bottomPadding: CGFloat = LorvexDesign.Spacing.xl
}

/// The column the task and habit inspectors lay their content in: bounded to
/// ``InspectorColumnMetrics/maxContentWidth``, pinned to the top leading
/// corner, and inset by the shared padding, so both inspectors start their
/// content at the same place.
struct InspectorColumn<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .frame(maxWidth: InspectorColumnMetrics.maxContentWidth, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .padding(.horizontal, InspectorColumnMetrics.horizontalPadding)
      .padding(.top, InspectorColumnMetrics.topPadding)
      .padding(.bottom, InspectorColumnMetrics.bottomPadding)
  }
}
