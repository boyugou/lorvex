import SwiftUI

extension Binding where Value: Sendable {
  /// A binding to the value held by an optional source, or nil while the source
  /// is empty. A sheet that edits a draft held in an optional unwraps it with
  /// this, so clearing the draft is what closes the sheet.
  ///
  /// SwiftUI's own failable `Binding(_:)` force-unwraps the source on every
  /// read. A sheet that is closing still reads its bindings in one more update
  /// pass (a focus change is enough), so clearing the source to close the sheet
  /// traps. This binding answers those late reads with the value the source
  /// held when the binding was made, and ignores a write once the source is
  /// empty so a late write cannot bring a cleared value back.
  init?(unwrapping base: Binding<Value?>) {
    guard let held = base.wrappedValue else { return nil }
    self.init(
      get: { base.wrappedValue ?? held },
      set: { newValue in
        guard base.wrappedValue != nil else { return }
        base.wrappedValue = newValue
      })
  }
}
