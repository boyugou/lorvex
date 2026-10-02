import SwiftUI

#if os(macOS)
  import AppKit
#endif

extension LorvexDesign.Typography {
  /// The assistant's serif voice, at the sizes it speaks in. Text takes it
  /// through ``SwiftUI/Text/init(_:serifVoice:)``, which picks the face for each
  /// script in the string.
  public enum SerifVoice: Sendable {
    /// The sentence that opens a page (a review, the iPhone week).
    case pageSentence
    /// The same sentence in a compact panel (the macOS menu bar), one step
    /// smaller so it stays a sentence at 320 points wide.
    case panelSentence
    /// The assistant at metadata size, for one-line reasons under a row;
    /// italic in Latin text.
    case assistantSecondary
    /// The assistant's briefing on the large Today widget, at the size of the
    /// widget's task rows; italic in Latin text.
    case widgetBriefing

    /// New York at this voice's size and weight.
    var latinFont: Font {
      switch self {
      case .pageSentence:
        #if os(macOS)
          Font.system(.largeTitle, design: .serif).weight(.semibold)
        #else
          Font.system(.title, design: .serif).weight(.semibold)
        #endif
      case .panelSentence:
        Font.system(.title3, design: .serif).weight(.semibold)
      case .assistantSecondary:
        Font.system(.callout, design: .serif).italic()
      case .widgetBriefing:
        #if os(macOS)
          Font.system(.body, design: .serif).italic()
        #else
          Font.system(.subheadline, design: .serif).italic()
        #endif
      }
    }

    #if os(macOS)
      /// The serif Han face for the app's language, so its characters take that
      /// language's forms and punctuation: Songti TC for Traditional Chinese,
      /// with punctuation centered in its box; Hiragino Mincho for Japanese,
      /// which also draws kana; Songti SC for Simplified Chinese and every
      /// other language. Each pair is the bold face, then the regular one.
      static var cjkFaces: (bold: String, regular: String) {
        switch CoreL10n.bundle.preferredLocalizations.first {
        case "zh-Hant": ("STSongti-TC-Bold", "STSongti-TC-Regular")
        case "ja": ("HiraMinProN-W6", "HiraMinProN-W3")
        default: ("STSongti-SC-Bold", "STSongti-SC-Regular")
        }
      }

      /// The app language's serif Han face (``cjkFaces``) at the size New
      /// York is set at for this voice, bold where New York is semibold.
      var cjkFont: Font {
        switch self {
        case .pageSentence:
          Font.custom(Self.cjkFaces.bold, size: NSFont.preferredFont(forTextStyle: .largeTitle).pointSize)
        case .panelSentence:
          Font.custom(Self.cjkFaces.bold, size: NSFont.preferredFont(forTextStyle: .title3).pointSize)
        case .assistantSecondary:
          Font.custom(Self.cjkFaces.regular, size: NSFont.preferredFont(forTextStyle: .callout).pointSize)
        case .widgetBriefing:
          Font.custom(Self.cjkFaces.regular, size: NSFont.preferredFont(forTextStyle: .body).pointSize)
        }
      }
    #endif
  }
}

extension Text {
  /// `string`, already localized, in the assistant's serif voice.
  ///
  /// Latin text is set in New York. New York has no CJK glyphs, and on macOS
  /// its fallback for them, Songti, lays the full-width marks (。，、？！：) out
  /// one and a half ems wide, which reads as a stray space after every Chinese
  /// clause. So on macOS the CJK runs are set in Songti directly, where each
  /// mark keeps its own em, while the digits, Latin words, and spaces between
  /// them stay in New York: the faces the fallback would pick, without the gap.
  /// CJK runs stay upright where the Latin voice is italic, since Chinese has no
  /// italic. iOS falls back from New York to PingFang, whose marks keep their
  /// width, so there the whole string is set in New York.
  public init(_ string: String, serifVoice voice: LorvexDesign.Typography.SerifVoice) {
    #if os(macOS)
      var attributed = AttributedString()
      for run in LorvexSerifRuns.split(string) {
        var piece = AttributedString(run.text)
        piece.font = run.isCJK ? voice.cjkFont : voice.latinFont
        attributed += piece
      }
      self.init(attributed)
    #else
      self = Text(string).font(voice.latinFont)
    #endif
  }
}

/// A string cut into alternating runs of CJK text and everything else, so each
/// can be set in its own face (``SwiftUI/Text/init(_:serifVoice:)``).
enum LorvexSerifRuns {
  struct Run: Equatable {
    var text: String
    var isCJK: Bool
  }

  /// "你完成了 1 项任务。" becomes "你完成了", " 1 ", "项任务。"; a string with no
  /// CJK characters is one run.
  static func split(_ string: String) -> [Run] {
    var runs: [Run] = []
    for character in string {
      let isCJK = character.unicodeScalars.first.map(Self.isCJK) ?? false
      if let last = runs.indices.last, runs[last].isCJK == isCJK {
        runs[last].text.append(character)
      } else {
        runs.append(Run(text: String(character), isCJK: isCJK))
      }
    }
    return runs
  }

  /// Ideographs, kana, and the CJK and full-width punctuation blocks. Curly
  /// quotes, dashes, and the middle dot are shared with Latin text and stay out.
  static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
    scalar.properties.isIdeographic
      || (0x3000...0x30FF).contains(scalar.value)
      || (0xFF00...0xFFEF).contains(scalar.value)
  }
}
