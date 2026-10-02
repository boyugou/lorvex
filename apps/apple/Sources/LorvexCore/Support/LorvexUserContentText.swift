import SwiftUI

/// How text written by the user or the assistant is typeset.
///
/// SwiftUI typesets text by the rules of the interface language. Japanese line
/// breaking allows a break between a Latin letter and a digit, and at narrow
/// widths inside a Latin word, so under a Japanese interface "Review the Q3
/// planning doc" can wrap as "Review the Q" / "3 planning doc". Interface copy
/// is written for its language, but a title, a note, or a briefing is in
/// whatever language its author chose. So under a Japanese interface such text,
/// when it holds no Chinese, Japanese, or Korean characters, is typeset as
/// English, which breaks only between words. Text with those characters keeps
/// the interface's typesetting, so its ideographs keep the interface language's
/// forms. Chinese and Korean line breaking keep Latin words whole, so those
/// interfaces, like every other, keep the default.
public enum LorvexUserContentTypesetting {
  /// The language Latin user content is typeset in under a Japanese interface.
  static let latinLanguage = Locale.Language(identifier: "en")

  /// Whether the interface typesets with Japanese rules: the language the
  /// bundles resolved at launch is Japanese.
  static let interfaceIsJapanese = isJapanese(CoreL10n.bundle.preferredLocalizations.first)

  /// The language to typeset `content` in, or nil to keep the interface's.
  static func language(
    for content: some StringProtocol, interfaceIsJapanese: Bool = interfaceIsJapanese
  ) -> Locale.Language? {
    guard interfaceIsJapanese, !containsCJK(content) else { return nil }
    return latinLanguage
  }

  /// Whether `identifier`, a localization identifier, names Japanese.
  static func isJapanese(_ identifier: String?) -> Bool {
    identifier.map { Locale.Language(identifier: $0).languageCode == .japanese } ?? false
  }

  /// Whether `content` holds a Han ideograph, kana, Hangul, or CJK or
  /// full-width punctuation: text a Chinese, Japanese, or Korean writer typed.
  static func containsCJK(_ content: some StringProtocol) -> Bool {
    content.unicodeScalars.contains { scalar in
      let value = scalar.value
      return scalar.properties.isIdeographic
        || (0x3000...0x30FF).contains(value)  // CJK punctuation, Hiragana, Katakana
        || (0x31F0...0x31FF).contains(value)  // Katakana phonetic extensions
        || (0xFF00...0xFFEF).contains(value)  // full-width and half-width forms
        || (0x1100...0x11FF).contains(value)  // Hangul Jamo
        || (0x3130...0x318F).contains(value)  // Hangul compatibility Jamo
        || (0xAC00...0xD7AF).contains(value)  // Hangul syllables
    }
  }
}

extension Text {
  /// `content`, written by the user or the assistant, shown verbatim and
  /// typeset by the rules of its own script rather than the interface
  /// language's (``LorvexUserContentTypesetting``).
  public init(userContent content: String) {
    self = Text(verbatim: content).userContentTypesetting(content)
  }

  /// Rich `content`, written by the user or the assistant, typeset by the
  /// rules of its own script rather than the interface language's
  /// (``LorvexUserContentTypesetting``).
  public init(userContent content: AttributedString) {
    self = Text(content).userContentTypesetting(String(content.characters))
  }

  /// This text, which shows `content` written by the user or the assistant,
  /// typeset by the rules of `content`'s own script rather than the interface
  /// language's (``LorvexUserContentTypesetting``). For a text built from
  /// `content` another way, such as in the serif voice.
  public func userContentTypesetting(_ content: some StringProtocol) -> Text {
    let language = LorvexUserContentTypesetting.language(for: content)
    return typesettingLanguage(
      language ?? LorvexUserContentTypesetting.latinLanguage, isEnabled: language != nil)
  }
}

extension View {
  /// This view, which shows `content` written by the user or the assistant,
  /// typesets its text by the rules of `content`'s own script rather than the
  /// interface language's (``LorvexUserContentTypesetting``). For a view that
  /// is not a `Text`, such as a helper's `some View` wrapping one.
  public func userContentTypesetting(_ content: some StringProtocol) -> some View {
    let language = LorvexUserContentTypesetting.language(for: content)
    return typesettingLanguage(
      language ?? LorvexUserContentTypesetting.latinLanguage, isEnabled: language != nil)
  }
}
