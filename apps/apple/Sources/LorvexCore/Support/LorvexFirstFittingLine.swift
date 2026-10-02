import SwiftUI

/// One line that shows the first of up to four phrasings that fits its width,
/// in the order given, longest first, and the last phrasing when none fits.
/// A narrow slot such as a Lock Screen widget or a watch complication thereby
/// shortens its wording in a long language instead of cutting a word off.
///
/// `line` draws one phrasing with its font and style. The candidates are
/// spelled out one by one rather than built with a `ForEach`, which has crashed
/// inside `ViewThatFits` on SwiftUI's asynchronous renderer.
public struct LorvexFirstFittingLine<Line: View>: View {
  private let choices: [String]
  private let line: (String) -> Line

  public init(_ choices: [String], @ViewBuilder line: @escaping (String) -> Line) {
    self.choices = Array(choices.prefix(4))
    self.line = line
  }

  public var body: some View {
    ViewThatFits(in: .horizontal) {
      if let choice = choice(0) { line(choice) }
      if let choice = choice(1) { line(choice) }
      if let choice = choice(2) { line(choice) }
      if let choice = choice(3) { line(choice) }
    }
  }

  private func choice(_ index: Int) -> String? {
    choices.indices.contains(index) ? choices[index] : nil
  }
}
