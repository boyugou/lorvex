import LorvexCore
import SwiftUI

extension View {
  /// Keeps the text of a single-line field on one line.
  ///
  /// A macOS single-line field keeps the line breaks of a multi-line paste and
  /// draws the first line with a clipped sliver of the second, while the
  /// capture it feeds reads the text as one line. This rewrites the text as it
  /// arrives, each break read as a space
  /// (``LorvexCaptureParser/singleLine(_:)``), so the field shows what Return
  /// captures. Text without a break is never touched.
  func lorvexSingleLine(_ text: Binding<String>) -> some View {
    onChange(of: text.wrappedValue) { _, new in
      let line = LorvexCaptureParser.singleLine(new)
      if line != new { text.wrappedValue = line }
    }
  }
}
