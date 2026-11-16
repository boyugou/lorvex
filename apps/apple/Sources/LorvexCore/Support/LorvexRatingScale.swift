import SwiftUI

/// Five named choices with one selected value. Selecting that value again
/// clears it; an unanswered question never implies a neutral rating.
public struct LorvexRatingScale: View {
  @Binding public var value: Int?
  public var levelLabel: (Int) -> String
  public var accessibilityLabel: (Int) -> String
  public var identifierPrefix: String
  public var isEnabled: Bool

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var hoveredLevel: Int?

  public init(
    value: Binding<Int?>, levelLabel: @escaping (Int) -> String,
    accessibilityLabel: @escaping (Int) -> String, identifierPrefix: String,
    isEnabled: Bool = true
  ) {
    self._value = value
    self.levelLabel = levelLabel
    self.accessibilityLabel = accessibilityLabel
    self.identifierPrefix = identifierPrefix
    self.isEnabled = isEnabled
  }

  public var body: some View {
    Group {
      if dynamicTypeSize >= .xxLarge {
        VStack(spacing: LorvexDesign.Spacing.xs) {
          ForEach(1...5, id: \.self) { option($0, stacked: true) }
        }
      } else {
        RatingChoicesLayout(spacing: LorvexDesign.Spacing.xs) {
          ForEach(1...5, id: \.self) { option($0, stacked: false) }
        }
      }
    }
    .sensoryFeedback(.selection, trigger: value)
    .onChange(of: isEnabled) { _, enabled in
      if !enabled { hoveredLevel = nil }
    }
  }

  private func option(_ level: Int, stacked: Bool) -> some View {
    Button {
      lorvexAnimated(.snappy) { value = value == level ? nil : level }
    } label: {
      Group {
        if stacked {
          HStack(spacing: LorvexDesign.Spacing.s) {
            Text(levelLabel(level))
              .font(LorvexDesign.Typography.primaryText)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: LorvexDesign.Spacing.s)
            mark(level)
          }
        } else {
          VStack(spacing: LorvexDesign.Spacing.xs) {
            mark(level)
            Text(levelLabel(level))
              .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, LorvexDesign.Spacing.xs)
      .padding(.vertical, LorvexDesign.Spacing.sm)
      .frame(minHeight: stacked ? 44 : 60)
      .contentShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
    }
    .buttonStyle(
      RatingButtonStyle(selected: value == level, hovered: isEnabled && hoveredLevel == level))
    .disabled(!isEnabled)
    #if os(macOS) || os(iOS)
      .onHover { inside in
        lorvexAnimated(.easeOut(duration: 0.12)) {
          if inside && isEnabled { hoveredLevel = level }
          else if hoveredLevel == level { hoveredLevel = nil }
        }
      }
    #endif
    .accessibilityLabel(levelLabel(level))
    .accessibilityValue(accessibilityLabel(level))
    .accessibilityAddTraits(value == level ? .isSelected : [])
    .accessibilityIdentifier("\(identifierPrefix).\(level)")
  }

  private func mark(_ level: Int) -> some View {
    ZStack {
      Text(level, format: .number).opacity(value == level ? 0 : 1)
      Image(systemName: "checkmark").opacity(value == level ? 1 : 0)
    }
    .font(LorvexDesign.Typography.primaryText.weight(.semibold))
    .accessibilityHidden(true)
  }
}

private struct RatingButtonStyle: ButtonStyle {
  let selected: Bool
  let hovered: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(selected ? AnyShapeStyle(LorvexDesign.Palette.accent) : AnyShapeStyle(.primary))
      .background(
        selected ? LorvexDesign.Palette.selectionFill : LorvexDesign.Palette.insetFill,
        in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m)
      )
      .overlay {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.m)
          .strokeBorder(
            selected || hovered ? AnyShapeStyle(LorvexDesign.Palette.accent) : AnyShapeStyle(.secondary),
            lineWidth: selected ? 1.5 : 0.5)
      }
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

/// Keep words whole before choosing the number of equal-width columns.
private struct RatingChoicesLayout: Layout {
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    metrics(width: proposal.width, subviews: subviews).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
  ) {
    let fit = metrics(width: bounds.width, subviews: subviews)
    for (index, subview) in subviews.enumerated() {
      let column = index % fit.columns
      let offset = CGFloat(column) * (fit.cell.width + spacing)
      let x = bounds.minX + offset
      let y = bounds.minY + CGFloat(index / fit.columns) * (fit.cell.height + spacing)
      subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(fit.cell))
    }
  }

  private func metrics(width proposedWidth: CGFloat?, subviews: Subviews) -> Metrics {
    let idealWidth = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    let naturalWidth = idealWidth * CGFloat(subviews.count) + spacing * CGFloat(max(0, subviews.count - 1))
    let width = max(0, proposedWidth.flatMap { $0.isFinite ? $0 : nil } ?? naturalWidth)
    let columns = [5, 3, 2, 1].first {
      idealWidth * CGFloat($0) + spacing * CGFloat($0 - 1) <= width
    } ?? 1
    let cellWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    let cellHeight = subviews.map {
      $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
    }.max() ?? 0
    let rows = (subviews.count + columns - 1) / columns
    return Metrics(
      size: CGSize(width: width, height: CGFloat(rows) * cellHeight + CGFloat(max(0, rows - 1)) * spacing),
      columns: columns, cell: CGSize(width: cellWidth, height: cellHeight))
  }

  private struct Metrics {
    let size: CGSize
    let columns: Int
    let cell: CGSize
  }
}
