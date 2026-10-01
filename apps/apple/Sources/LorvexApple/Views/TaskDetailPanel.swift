import LorvexCore
import SwiftUI

/// Shared chrome for task-detail inspector panels.
///
/// The inspector should read as one coherent desktop surface. Keeping the panel
/// material, border, radius, padding, and accessibility identifier here avoids
/// each task-detail section drifting into its own card style.
///
/// Inside a popover (``EnvironmentValues/taskDetailPanelInPopover``) the panel
/// draws no card and adds no padding: the popover is already the container and
/// pads its content, so a card there reads as a box nested in a box.
struct TaskDetailPanel<Content: View>: View {
  let accessibilityIdentifier: String
  var padding: CGFloat = LorvexDesign.Spacing.m
  var chrome: TaskDetailPanelChrome = .group
  @ViewBuilder let content: () -> Content
  @Environment(\.taskDetailPanelInPopover) private var inPopover

  var body: some View {
    content()
      .padding(inPopover ? 0 : padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(panelBackground)
      .overlay(panelBorder)
      .clipShape(TaskDetailPanelMetrics.shape)
      .accessibilityIdentifier(accessibilityIdentifier)
  }

  private var effectiveChrome: TaskDetailPanelChrome { inPopover ? .header : chrome }

  @ViewBuilder
  private var panelBackground: some View {
    switch effectiveChrome {
    case .group:
      TaskDetailPanelMetrics.shape
        .fill(.quaternary.opacity(0.055))
    case .header:
      Color.clear
    }
  }

  @ViewBuilder
  private var panelBorder: some View {
    switch effectiveChrome {
    case .group:
      TaskDetailPanelMetrics.shape
        .stroke(.separator.opacity(0.08), lineWidth: 0.5)
    case .header:
      EmptyView()
    }
  }
}

private enum TaskDetailPanelMetrics {
  static let shape = RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
}

extension EnvironmentValues {
  /// Whether task-detail panels are shown inside a popover, where they drop
  /// their card chrome and padding.
  @Entry var taskDetailPanelInPopover = false
}

enum TaskDetailPanelChrome {
  case group
  case header
}

/// Shared inline field chrome for task-detail inspector metadata.
///
/// Detail panels should not drift back into small default form controls. This
/// wrapper gives metadata rows the same label, padding, background, and compact
/// desktop rhythm whether they live in Scheduling, Recurrence, or Organization.
struct TaskDetailInlineField<Content: View>: View {
  let title: String
  let systemImage: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      label
      content()
    }
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.10), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .overlay {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
        .stroke(.separator.opacity(0.12), lineWidth: 0.5)
    }
  }

  private var label: some View {
    Label(title, systemImage: systemImage)
      .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
      .foregroundStyle(.secondary)
  }
}
