import LorvexCore
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
      .accessibilityHidden(true)
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
    Self.symbolName(for: icon)
  }

  /// The SF Symbol name a list icon names, or nil when the icon is an emoji or
  /// empty. List icons store either one; an all-ASCII value is a symbol name.
  static func symbolName(for icon: String?) -> String? {
    guard let icon, !icon.isEmpty, icon.unicodeScalars.allSatisfy(\.isASCII) else {
      return nil
    }
    return icon
  }
}

/// A list as a menu item: its symbol beside its name, or its emoji before the
/// name, since a menu item draws only an image as its icon.
struct LorvexListMenuLabel: View {
  let list: LorvexList

  var body: some View {
    if let symbol = LorvexListIconView.symbolName(for: list.icon) {
      Label(list.displayName, systemImage: symbol)
    } else if let emoji = list.icon, !emoji.isEmpty {
      Text(verbatim: "\(emoji) \(list.displayName)")
    } else {
      Label(list.displayName, systemImage: "list.bullet")
    }
  }
}
