import SwiftUI

/// How a tile responds to a press: it fades while held. A tile that can't
/// take a tap draws that state itself, keeping its card and graying its
/// content or showing its finished state at full strength, where the plain
/// style would fade the whole tile, card included, so it reads as missing.
public struct LorvexTileButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.55 : 1)
      .reduceMotionAnimation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}
