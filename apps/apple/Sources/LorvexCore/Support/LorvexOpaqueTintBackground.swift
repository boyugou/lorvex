import SwiftUI

extension View {
  /// Fills `shape` behind the view with `tint` laid over an opaque base of the
  /// surrounding background style. The tint reads exactly as it would over
  /// that background, while whatever lies beneath the shape stays hidden: a
  /// calendar grid's hour lines and its now line pass under a block instead of
  /// through its text.
  public func lorvexOpaqueTintBackground<S: Shape>(_ tint: Color, in shape: S) -> some View {
    background {
      shape.fill(.background)
      shape.fill(tint)
    }
  }
}
