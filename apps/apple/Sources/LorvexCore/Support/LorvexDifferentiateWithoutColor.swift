import SwiftUI

/// Whether a surface should say in shape or words what its color says, as the
/// system's Differentiate Without Color setting asks. A view declares
///
///     @LorvexDifferentiateWithoutColor private var differentiateWithoutColor
///
/// and reads the same answer as `@Environment(\.accessibilityDifferentiateWithoutColor)`,
/// except in a DEBUG preview run launched with `-lorvexDifferentiateWithoutColor`,
/// where it is always true. SwiftUI exposes the system value read-only, and a
/// headless capture must not change the Mac's or the simulator's own settings, so
/// the launch argument is the only way to review these cues in a capture.
@propertyWrapper
public struct LorvexDifferentiateWithoutColor: DynamicProperty {
  @Environment(\.accessibilityDifferentiateWithoutColor) private var system

  public init() {}

  public var wrappedValue: Bool { system || Self.isPinned }

  /// True in a DEBUG run launched with `-lorvexDifferentiateWithoutColor`;
  /// always false in release builds.
  public static let isPinned: Bool = {
    #if DEBUG
      return ProcessInfo.processInfo.arguments.contains("-lorvexDifferentiateWithoutColor")
    #else
      return false
    #endif
  }()
}
