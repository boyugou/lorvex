import NaturalLanguage
import SwiftUI
import Synchronization

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

/// The title of a compact calendar block, one in a lane narrower than
/// ``LorvexDesign/CalendarMetrics/compactLaneWidth``: small, wrapping onto as
/// many lines as the block is tall, then truncated, with no time beside it.
/// A finished task's title is struck through and secondary. A block that an
/// overlap has narrowed below ``LorvexCalendarCompactTitleFit/minimumLegibleEms``
/// draws no title, since a letter or two a line reads as noise; its color and
/// place on the time axis remain, and the block still opens and speaks its
/// full label.
///
/// Lines break between words: when the title's longest word is wider than the
/// block ("Roadmap" in a phone week's 40pt lane), the face shrinks just
/// enough for that word to fit one line, down to
/// ``LorvexCalendarCompactTitleFit/minimumScale``, rather than splitting the
/// word across lines. A word still wider than the block at that size is not
/// split either: the title then takes a single line that ends in an ellipsis
/// ("Quarte…"). Thai, Lao, Myanmar, and Khmer mark no word boundary, so the
/// words are the dictionary words the system's own line breaking keeps whole
/// ("การประชุม", not a spaced run). A title in Chinese, Japanese, or Korean,
/// which wraps between its own characters, keeps wrapping over as many lines
/// as the block is tall.
public struct LorvexCalendarCompactBlockTitle: View {
  private let title: String
  private let isDone: Bool
  @State private var width: CGFloat = 0
  /// ``LorvexDesign/CalendarMetrics/compactBlockText``'s size, scaled with
  /// the text.
  @ScaledMetric(relativeTo: .caption2) private var baseSize: CGFloat = 11

  public init(_ title: String, isDone: Bool = false) {
    self.title = title
    self.isDone = isDone
  }

  public var body: some View {
    Text(userContent: title)
      // Scaled with the text through baseSize, then fitted to the block.
      .font(.system(size: fittedSize, weight: LorvexDesign.CalendarMetrics.blockTitleWeight).width(.condensed))  // lorvex-design-token: allow
      .strikethrough(isDone)
      .foregroundStyle(isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
      .lineLimit(
        LorvexCalendarCompactTitleFit.splitsAWord(title: title, size: baseSize, width: width) ? 1 : nil
      )
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .opacity(LorvexCalendarCompactTitleFit.isLegible(width: width, size: baseSize) ? 1 : 0)
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
  }

  private var fittedSize: CGFloat {
    baseSize * LorvexCalendarCompactTitleFit.scale(title: title, size: baseSize, width: width)
  }
}

/// How far a compact block's title face shrinks so its longest word fits the
/// block's width on one line, and how narrow a block may get before it draws
/// no title.
enum LorvexCalendarCompactTitleFit {
  /// The smallest scale a title takes; a word still too wide at this size
  /// breaks as it would have.
  static let minimumScale: CGFloat = 0.8

  /// Points of the block's width the measurement leaves to the text
  /// layout's own line padding and rounding, so a word measured to fit does
  /// fit.
  static let layoutAllowance: CGFloat = 2

  /// The narrowest text area, in multiples of the face's size, in which a
  /// title is drawn: about four letters. A phone week's day holds one lane of
  /// about 40pt of text, two overlapping blocks leave each about 16pt, and
  /// three about 8pt, where a title can only break letter by letter. A Mac
  /// week in a 1440pt window holds about 43pt of text in each of three lanes,
  /// and about 31pt in a window of 1100pt.
  static let minimumLegibleEms: CGFloat = 2.2

  /// Whether a text area `width` wide shows its title in a face of `size`. An
  /// unmeasured (zero) width does not, so the title appears with its first
  /// measurement rather than flashing in a lane too narrow for it.
  static func isLegible(width: CGFloat, size: CGFloat) -> Bool {
    width >= minimumLegibleEms * size
  }

  /// 1 while the longest word of `title` fits `width` at `size`, otherwise
  /// the scale that makes it fit, no smaller than ``minimumScale``. An
  /// unmeasured (zero) width keeps the full size.
  static func scale(title: String, size: CGFloat, width: CGFloat) -> CGFloat {
    guard width > 0 else { return 1 }
    let room = width - layoutAllowance
    let widest = words(in: title).map { wordWidth($0.text, size: size) }.max() ?? 0
    guard widest > room else { return 1 }
    return max(minimumScale, room / widest)
  }

  /// Whether a word of `title` is still wider than `width` once the face has
  /// shrunk to ``minimumScale``, so that setting the title over several lines
  /// would split that word between letters. An unmeasured (zero) width is
  /// never too narrow. Chinese, Japanese, and Korean text never counts: it is
  /// meant to break wherever the line ends.
  static func splitsAWord(title: String, size: CGFloat, width: CGFloat) -> Bool {
    guard width > 0 else { return false }
    let room = width - layoutAllowance
    return words(in: title).contains { word in
      !word.wrapsBetweenCharacters && wordWidth(word.text, size: size) * minimumScale > room
    }
  }

  /// A run of a title that a line should not break inside, unless it is text
  /// that wraps between its own characters.
  struct Word {
    let text: String
    let wrapsBetweenCharacters: Bool
  }

  /// The words of `title`: the runs between spaces, with a run in a script that
  /// marks no word boundary (Thai, Lao, Myanmar, Khmer) cut into the
  /// dictionary words the system breaks lines between, and a run that holds
  /// Chinese, Japanese, or Korean kept whole and marked as wrapping between
  /// characters.
  static func words(in title: String) -> [Word] {
    title.split(whereSeparator: \.isWhitespace).flatMap { run -> [Word] in
      if LorvexUserContentTypesetting.containsCJK(run) {
        return [Word(text: String(run), wrapsBetweenCharacters: true)]
      }
      guard marksNoWordBoundary(run) else {
        return [Word(text: String(run), wrapsBetweenCharacters: false)]
      }
      return dictionaryWords(in: String(run)).map { Word(text: $0, wrapsBetweenCharacters: false) }
    }
  }

  /// Whether `run` holds a character of Thai, Lao, Myanmar, or Khmer.
  private static func marksNoWordBoundary(_ run: Substring) -> Bool {
    run.unicodeScalars.contains { scalar in
      (0x0E00...0x0EFF).contains(scalar.value)  // Thai, Lao
        || (0x1000...0x109F).contains(scalar.value)  // Myanmar
        || (0x1780...0x17FF).contains(scalar.value)  // Khmer
    }
  }

  /// The dictionary words of `run`, from the system's word tokenizer; the run
  /// itself when the tokenizer finds none. A block redraws as its lane
  /// resizes, so the segmentation of a title is kept.
  private static func dictionaryWords(in run: String) -> [String] {
    if let cached = dictionaryWordCache.withLock({ $0[run] }) { return cached }
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = run
    var found: [String] = []
    tokenizer.enumerateTokens(in: run.startIndex..<run.endIndex) { range, _ in
      found.append(String(run[range]))
      return true
    }
    let words = found.isEmpty ? [run] : found
    dictionaryWordCache.withLock { cache in
      if cache.count >= dictionaryWordCacheLimit { cache.removeAll() }
      cache[run] = words
    }
    return words
  }

  private static let dictionaryWordCache = Mutex<[String: [String]]>([:])
  private static let dictionaryWordCacheLimit = 512

  /// The word's width in the title face (`LorvexDesign.CalendarMetrics
  /// .blockTitleWeight`, condensed). The watch draws no calendar grid, so it
  /// takes a per-letter estimate.
  private static func wordWidth(_ word: String, size: CGFloat) -> CGFloat {
    #if os(macOS)
      let font = NSFont.systemFont(ofSize: size, weight: .semibold, width: .condensed)
      return ceil((word as NSString).size(withAttributes: [.font: font]).width)
    #elseif os(iOS)
      let font = UIFont.systemFont(ofSize: size, weight: .medium, width: .condensed)
      return ceil((word as NSString).size(withAttributes: [.font: font]).width)
    #else
      return ceil(CGFloat(word.count) * size * 0.5)
    #endif
  }
}
