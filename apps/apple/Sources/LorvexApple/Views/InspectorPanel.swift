import LorvexCore
import SwiftUI

/// Shared chrome for the panels of the task and habit inspectors.
///
/// An inspector should read as one coherent desktop surface. Keeping the panel
/// material, border, radius, padding, and accessibility identifier here avoids
/// each inspector section drifting into its own card style.
///
/// The `.header` chrome (an inspector's title block) and a popover
/// (``EnvironmentValues/inspectorPanelInPopover``) draw no card and add no
/// padding. The inspector column or the popover already insets the content, so
/// padding there would indent a title block from the property rows beneath it,
/// and a card in a popover reads as a box nested in a box.
struct InspectorPanel<Content: View>: View {
  let accessibilityIdentifier: String
  var padding: CGFloat = LorvexDesign.Spacing.m
  var chrome: InspectorPanelChrome = .group
  @ViewBuilder let content: () -> Content
  @Environment(\.inspectorPanelInPopover) private var inPopover

  var body: some View {
    content()
      .padding(effectiveChrome == .header ? 0 : padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(panelBackground)
      .overlay(panelBorder)
      .clipShape(InspectorPanelMetrics.shape)
      .accessibilityIdentifier(accessibilityIdentifier)
  }

  private var effectiveChrome: InspectorPanelChrome { inPopover ? .header : chrome }

  @ViewBuilder
  private var panelBackground: some View {
    switch effectiveChrome {
    case .group:
      InspectorPanelMetrics.shape
        .fill(.quaternary.opacity(0.055))
    case .header:
      Color.clear
    }
  }

  @ViewBuilder
  private var panelBorder: some View {
    switch effectiveChrome {
    case .group:
      InspectorPanelMetrics.shape
        .stroke(.separator.opacity(0.08), lineWidth: 0.5)
    case .header:
      EmptyView()
    }
  }
}

private enum InspectorPanelMetrics {
  static let shape = RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
}

extension EnvironmentValues {
  /// Whether inspector panels are shown inside a popover, where they drop
  /// their card chrome and padding.
  @Entry var inspectorPanelInPopover = false
}

enum InspectorPanelChrome {
  case group
  case header
}

