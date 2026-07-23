import SwiftUI

struct LorvexListIconView: View {
  enum Background {
    case none
    case roundedSquare(size: CGFloat, opacity: Double, cornerRadius: CGFloat)
  }

  let icon: String?
  let tint: Color
  let size: CGFloat
  let font: Font
  let background: Background

  init(
    icon: String?,
    tint: Color,
    size: CGFloat,
    font: Font,
    background: Background = .none
  ) {
    self.icon = icon
    self.tint = tint
    self.size = size
    self.font = font
    self.background = background
  }

  var body: some View {
    content
      .font(font)
      .frame(width: size, height: size)
      .background(backgroundView)
  }

  @ViewBuilder
  private var content: some View {
    if let systemImageName {
      Image(systemName: systemImageName)
        .foregroundStyle(tint)
    } else if let icon, !icon.isEmpty {
      Text(icon)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    } else {
      Image(systemName: "folder")
        .foregroundStyle(tint)
    }
  }

  @ViewBuilder
  private var backgroundView: some View {
    switch background {
    case .none:
      EmptyView()
    case .roundedSquare(let size, let opacity, let cornerRadius):
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(tint.opacity(opacity))
        .frame(width: size, height: size)
    }
  }

  private var systemImageName: String? {
    guard let icon, !icon.isEmpty, icon.unicodeScalars.allSatisfy(\.isASCII) else {
      return nil
    }
    return icon
  }
}
