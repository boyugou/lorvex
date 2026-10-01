import SwiftUI

/// What a day's review sentence says, in order, before any wording. Each
/// platform words the parts with its own copy table, so the macOS and iPhone
/// reviews never disagree about what the day was.
public enum LorvexReviewSentence {
  public enum Part: Equatable, Sendable {
    /// Nothing happened: no tasks, events, due work, or habits.
    case quiet
    case finished(Int)
    case nothingFinished
    /// Tasks due that day that are still open.
    case stillDue(Int)
    case habitsAll
    case habitsSome(kept: Int, total: Int)
    case habitsNone
  }

  public static func parts(_ summary: DayReviewSummary) -> [Part] {
    if summary.completedCount == 0, summary.dueOpenCount == 0, summary.eventCount == 0,
      summary.habitsTotal == 0
    {
      return [.quiet]
    }
    var parts: [Part] = [summary.completedCount > 0 ? .finished(summary.completedCount) : .nothingFinished]
    if summary.dueOpenCount > 0 { parts.append(.stillDue(summary.dueOpenCount)) }
    if summary.habitsTotal > 0 {
      switch summary.habitsCompleted {
      case summary.habitsTotal...: parts.append(.habitsAll)
      case 0: parts.append(.habitsNone)
      default: parts.append(.habitsSome(kept: summary.habitsCompleted, total: summary.habitsTotal))
      }
    }
    return parts
  }

  /// Joins the worded sentences of a day or week review as their language
  /// writes them: a space after a sentence that ends in Western punctuation
  /// ("You finished 3 tasks. 1 due task is still open."), nothing after a
  /// full-width mark, whose glyph already carries the gap
  /// ("你完成了 3 项任务。还有 1 项到期任务没完成。").
  public static func join(_ sentences: [String]) -> String {
    sentences.reduce(into: "") { text, sentence in
      guard !sentence.isEmpty else { return }
      if let last = text.last, !fullWidthSentenceEnds.contains(last) { text.append(" ") }
      text.append(sentence)
    }
  }

  private static let fullWidthSentenceEnds: Set<Character> = ["。", "！", "？", "」", "』", "）"]
}

/// A one-tap 1–5 rating drawn as five dots that grow from left to right, with
/// the two ends named under it ("Rough" … "Great"). An unchosen dot is a hollow
/// ring in the secondary style, so the empty scale reads as five places to tap
/// rather than five faint marks; the chosen dot and the ones before it fill
/// with the accent, and tapping the chosen dot again clears the rating. Under
/// a pointer, the empty rings up to the hovered one turn accent, previewing
/// the rating a click sets without drawing any dot half-filled. The dots grow
/// with the text size, as far as their row has room.
///
/// With a `levelWord`, the level under the pointer, else the chosen one, is
/// named under its own dot ("Okay") in place of the two end names, so every
/// step of the scale reads as a word rather than a position; the word sits at
/// the leading edge under the first dot and the trailing edge under the last,
/// so it never runs past the scale. VoiceOver reads the word with each dot.
public struct LorvexDotScale: View {
  @Binding public var value: Int?
  public var lowLabel: String
  public var highLabel: String
  /// Formats the accessibility label for one dot, given its value 1–5.
  public var dotLabel: (Int) -> String
  /// Names one level 1–5 ("Rough" … "Great"); nil keeps only the end names.
  public var levelWord: ((Int) -> String)?
  public var identifierPrefix: String
  public var isEnabled: Bool

  @State private var hoveredLevel: Int?
  /// How much the text size has grown the footnote style, which the dots
  /// follow so the scale keeps pace with its end labels.
  @ScaledMetric(relativeTo: .footnote) private var textScale: CGFloat = 1

  public init(
    value: Binding<Int?>, lowLabel: String, highLabel: String, dotLabel: @escaping (Int) -> String,
    levelWord: ((Int) -> String)? = nil, identifierPrefix: String, isEnabled: Bool = true
  ) {
    self._value = value
    self.lowLabel = lowLabel
    self.highLabel = highLabel
    self.dotLabel = dotLabel
    self.levelWord = levelWord
    self.identifierPrefix = identifierPrefix
    self.isEnabled = isEnabled
  }

  private static let sizes: [CGFloat] = [12, 16, 20, 24, 28]
  /// The most the dots grow: the largest then measures 49 pt, which still fits
  /// its fifth of the narrowest iPhone's row.
  private static let maxDotScale: CGFloat = 1.75

  private func dotSize(_ level: Int) -> CGFloat {
    Self.sizes[level - 1] * min(textScale, Self.maxDotScale)
  }

  public var body: some View {
    VStack(spacing: LorvexDesign.Spacing.xs) {
      HStack(spacing: 0) {
        ForEach(1...5, id: \.self) { level in
          Button {
            withAnimation(.snappy) { value = value == level ? nil : level }
          } label: {
            dot(level)
              .frame(width: dotSize(level), height: dotSize(level))
              .frame(maxWidth: .infinity, minHeight: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(!isEnabled)
          #if os(macOS) || os(iOS)
            .onHover { inside in
              withAnimation(.easeOut(duration: 0.12)) {
                if inside {
                  hoveredLevel = level
                } else if hoveredLevel == level {
                  hoveredLevel = nil
                }
              }
            }
          #endif
          .accessibilityLabel(accessibilityLabel(level))
          .accessibilityAddTraits(value == level ? .isSelected : [])
          .accessibilityIdentifier("\(identifierPrefix).\(level)")
        }
      }
      ZStack {
        HStack {
          Text(lowLabel)
          Spacer()
          Text(highLabel)
        }
        .foregroundStyle(.secondary)
        .opacity(namedLevel == nil ? 1 : 0)
        if let namedLevel, let levelWord {
          HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { level in
              Text(level == namedLevel ? levelWord(level) : "")
                .fontWeight(.medium)
                .foregroundStyle(isEnabled ? AnyShapeStyle(LorvexDesign.Palette.accent) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: wordAlignment(level))
            }
          }
          .accessibilityIdentifier("\(identifierPrefix).word")
        }
      }
      .font(LorvexDesign.Typography.tertiaryText)
      .accessibilityHidden(true)
    }
    .sensoryFeedback(.selection, trigger: value)
  }

  /// The level named under the scale: the hovered one, else the chosen one.
  private var namedLevel: Int? {
    guard levelWord != nil else { return nil }
    if isEnabled, let hoveredLevel { return hoveredLevel }
    return value
  }

  private func wordAlignment(_ level: Int) -> Alignment {
    switch level {
    case 1: .leading
    case 5: .trailing
    default: .center
    }
  }

  private func accessibilityLabel(_ level: Int) -> String {
    guard let levelWord else { return dotLabel(level) }
    return "\(dotLabel(level)), \(levelWord(level))"
  }

  @ViewBuilder
  private func dot(_ level: Int) -> some View {
    if (value ?? 0) >= level {
      Circle().fill(LorvexDesign.Palette.accent)
    } else if isEnabled, let hoveredLevel, hoveredLevel >= level {
      Circle().strokeBorder(LorvexDesign.Palette.accent, lineWidth: 1.5)
    } else {
      Circle().strokeBorder(.secondary, lineWidth: 1.5)
    }
  }
}
