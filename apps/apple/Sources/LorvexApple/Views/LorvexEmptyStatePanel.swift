import LorvexCore
import SwiftUI

/// The shared empty state: an icon tile, a title, a message, optional chips,
/// and an optional action. The `.panel` style is a card sized to its content
/// and centered in the space its host offers; the `.inline` style is a
/// borderless block on the leading edge, for states inside a list or form.
///
/// Either style fills the height it is offered and never asks for more. A
/// split view sizes its columns by probing their content at widths near zero,
/// where the wrapped message reports a height of one character per line; a
/// minimum height of zero keeps that probe from making the pane, and with it
/// the window, taller than the screen. Hosts can therefore place the view
/// directly in a stack under a header, or over a scroll view as an overlay.
struct LorvexEmptyStatePanel<Action: View>: View {
  let title: String
  let message: String
  let systemImage: String
  let tint: Color
  let style: LorvexEmptyStatePanelStyle
  let chips: [LorvexEmptyStateChip]
  @ViewBuilder let action: () -> Action

  init(
    title: String,
    message: String,
    systemImage: String,
    tint: Color = .accentColor,
    style: LorvexEmptyStatePanelStyle = .panel,
    chips: [LorvexEmptyStateChip] = [],
    @ViewBuilder action: @escaping () -> Action
  ) {
    self.title = title
    self.message = message
    self.systemImage = systemImage
    self.tint = tint
    self.style = style
    self.chips = chips
    self.action = action
  }

  var body: some View {
    VStack {
      Group {
        switch style {
        case .panel:
          content.lorvexInsetPanel(padding: contentPadding, hugsContent: true)
        case .inline:
          content.padding(contentPadding)
        }
      }
      .frame(maxWidth: maxContentWidth, alignment: contentAlignment)
      .accessibilityIdentifier("lorvex.emptyState.panel")
    }
    // Padding belongs inside the fill frame. If it is applied after the
    // maxHeight frame, the view reports "parent height + padding" to stacks and
    // can push sibling headers/editors out of clipped split-view panes. With
    // both a minimum and a maximum, the frame takes exactly the height it is
    // offered instead of its content's height when that is larger.
    .padding(outerPadding)
    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
  }

  private var content: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      ZStack {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
          .fill(tint.opacity(0.12))
        LorvexListIconView(
          icon: systemImage,
          tint: tint,
          size: 24,
          font: .system(size: 18, weight: .semibold)
        )
      }
      .frame(width: iconSize, height: iconSize)

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
          Text(title)
            .font(LorvexDesign.Typography.primaryEmphasis)
          Text(message)
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if !chips.isEmpty {
          LorvexFlowLayout(spacing: LorvexDesign.Spacing.xs, lineSpacing: LorvexDesign.Spacing.xs) {
            ForEach(chips) { chip in
              LorvexChip(chip.title, systemImage: chip.systemImage, tint: chip.tint)
            }
          }
        }

        action()
          .controlSize(.small)
      }
    }
  }

  private var iconSize: CGFloat {
    switch style {
    case .panel: 44
    case .inline: 36
    }
  }

  private var contentPadding: CGFloat {
    switch style {
    case .panel: LorvexDesign.Spacing.l
    case .inline: LorvexDesign.Spacing.m
    }
  }

  /// A panel hugs its content and centers in the pane, so a short message
  /// does not sit in a wide, mostly empty card; an inline state keeps the
  /// leading edge of the rows around it.
  private var contentAlignment: Alignment {
    switch style {
    case .panel: .center
    case .inline: .leading
    }
  }

  private var maxContentWidth: CGFloat {
    switch style {
    case .panel: 640
    case .inline: 360
    }
  }

  private var outerPadding: CGFloat {
    switch style {
    case .panel: LorvexDesign.Spacing.xl
    case .inline: LorvexDesign.Spacing.l
    }
  }
}

struct LorvexEmptyStateModel {
  let title: String
  let message: String
  let systemImage: String
  let tint: Color
  var style: LorvexEmptyStatePanelStyle = .panel
  var chips: [LorvexEmptyStateChip] = []
  var action: LorvexEmptyStateAction?
}

struct LorvexEmptyStateAction {
  let title: String
  let systemImage: String
  var style: LorvexEmptyStateActionStyle = .secondary
  let handler: () -> Void
}

enum LorvexEmptyStateActionStyle {
  case primary
  case secondary
}

struct LorvexEmptyStateActionSlot: View {
  let action: LorvexEmptyStateAction?

  var body: some View {
    if let action {
      let button = Button {
        action.handler()
      } label: {
        Label(action.title, systemImage: action.systemImage)
      }
      switch action.style {
      case .primary: button.buttonStyle(.borderedProminent)
      case .secondary: button.buttonStyle(.bordered)
      }
    }
  }
}

enum LorvexEmptyStatePanelStyle {
  case panel
  case inline
}

extension LorvexEmptyStatePanel where Action == LorvexEmptyStateActionSlot {
  init(model: LorvexEmptyStateModel) {
    self.init(
      title: model.title,
      message: model.message,
      systemImage: model.systemImage,
      tint: model.tint,
      style: model.style,
      chips: model.chips
    ) {
      LorvexEmptyStateActionSlot(action: model.action)
    }
  }
}

extension LorvexEmptyStatePanel where Action == EmptyView {
  init(
    title: String,
    message: String,
    systemImage: String,
    tint: Color = .accentColor,
    style: LorvexEmptyStatePanelStyle = .panel,
    chips: [LorvexEmptyStateChip] = []
  ) {
    self.init(
      title: title,
      message: message,
      systemImage: systemImage,
      tint: tint,
      style: style,
      chips: chips,
      action: { EmptyView() }
    )
  }
}

struct LorvexEmptyStateChip: Identifiable {
  let id = UUID()
  let title: String
  let systemImage: String
  let tint: Color
}
