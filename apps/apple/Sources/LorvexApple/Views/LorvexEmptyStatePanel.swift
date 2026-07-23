import LorvexCore
import SwiftUI

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
                HStack(spacing: 5) {
                  LorvexListIconView(
                    icon: chip.systemImage,
                    tint: chip.tint,
                    size: 14,
                    font: LorvexDesign.Typography.tertiaryText.weight(.medium)
                  )
                  Text(chip.title)
                    .lineLimit(1)
                }
                  .font(LorvexDesign.Typography.tertiaryText)
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, LorvexDesign.Spacing.s)
                  .padding(.vertical, LorvexDesign.Spacing.xs)
                  .background(chip.tint.opacity(0.12), in: Capsule())
              }
            }
          }

          action()
            .controlSize(.small)
        }
      }
      .padding(contentPadding)
      .frame(maxWidth: maxContentWidth, alignment: .leading)
      .background(panelBackground)
      .overlay(panelBorder)
      .accessibilityIdentifier("lorvex.emptyState.panel")
    }
    // Padding belongs inside the fill frame. If it is applied after the
    // maxHeight frame, the view reports "parent height + padding" to stacks and
    // can push sibling headers/editors out of clipped split-view panes.
    .padding(outerPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

  @ViewBuilder
  private var panelBackground: some View {
    switch style {
    case .panel:
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
        .fill(.thinMaterial)
    case .inline:
      Color.clear
    }
  }

  @ViewBuilder
  private var panelBorder: some View {
    switch style {
    case .panel:
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
        .stroke(.separator.opacity(0.55), lineWidth: 0.5)
    case .inline:
      EmptyView()
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
      Button {
        action.handler()
      } label: {
        Label(action.title, systemImage: action.systemImage)
      }
      .buttonStyle(action.style == .primary ? .lorvexPrimary : .lorvexSecondary)
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
