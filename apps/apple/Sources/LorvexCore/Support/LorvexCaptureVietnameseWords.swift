import Foundation

extension LorvexCaptureVocabulary {
  // How the Vietnamese patterns spell Vietnamese words, the key a matched word is
  // looked up by, and the numbers written as words. The vocabulary is
  // ``vietnamese``.

  // MARK: - Boundaries and the text around a match

  /// A word boundary for Vietnamese words: no Latin letter, digit, or combining
  /// mark on that side. A tone mark typed as a separate combining character is
  /// part of the word it follows.
  static let vietnameseStart = #"(?<![\p{Latin}\p{N}\p{M}])"#
  static let vietnameseEnd = #"(?![\p{Latin}\p{N}\p{M}])"#

  /// What may follow a day of the month or a month written alone: no digit or
  /// percent sign, and no decimal fraction or time. The colon goes last in its
  /// set, since ICU reads a set that opens with "[:" as a POSIX class name.
  static let vietnameseNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// How many characters before and after a match the readers that judge a match
  /// by its surroundings look at. A bounded look keeps the time a line takes
  /// linear in its length.
  static let vietnameseContextLength = 60

  /// The text of the line just before `match`: at most
  /// ``vietnameseContextLength`` characters, ending where the match starts.
  static func vietnameseTextBefore(_ match: Match) -> String {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return "" }
    let from =
      match.source.index(start, offsetBy: -vietnameseContextLength, limitedBy: match.source.startIndex)
      ?? match.source.startIndex
    return String(match.source[from..<start])
  }

  /// The text of the line just after `match`: at most
  /// ``vietnameseContextLength`` characters, starting where the match ends.
  static func vietnameseTextAfter(_ match: Match) -> String {
    guard let end = Range(match.result.range, in: match.source)?.upperBound else { return "" }
    return String(match.source[end...].prefix(vietnameseContextLength))
  }

  /// Whether `pattern` matches somewhere in `text`.
  static func vietnameseFinds(_ pattern: String, in text: String) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(pattern) else { return false }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  // MARK: - Spelling

  /// The spellings of a letter that carries marks ("ế", "ờ", "ạ"), or nil for a
  /// letter without any, with its base letter.
  ///
  /// The forms are the composed letter, the base letter followed by its marks as
  /// separate combining characters ("e" + U+0302 + U+0301), each mark composed
  /// with the base while the others stay separate (the vowel letter "ê" followed by
  /// the acute accent, as an input method that composes the vowel mark first
  /// writes it), and the marks in the opposite order.
  private static func vietnameseMarkedForms(of scalar: Unicode.Scalar) -> (forms: [String], base: String)? {
    let letter = String(scalar)
    let parts = Array(letter.decomposedStringWithCanonicalMapping.unicodeScalars)
    guard parts.count > 1 else { return nil }
    let base = String(parts[0])
    let marks = parts.dropFirst().map { String($0) }
    var forms = [letter, parts.map { String($0) }.joined()]
    if marks.count > 1 {
      for index in marks.indices {
        let composed = (base + marks[index]).precomposedStringWithCanonicalMapping
        guard composed.unicodeScalars.count == 1 else { continue }
        let rest = marks.enumerated().filter { $0.offset != index }.map { $0.element }
        forms.append(composed + rest.joined())
      }
      forms.append(base + marks.reversed().joined())
    }
    // Swift compares strings by canonical equivalence, which would drop the
    // decomposed spellings as copies of the composed one, so the forms are
    // compared by their code points.
    var seen = Set<[UInt32]>()
    return (forms.filter { seen.insert($0.unicodeScalars.map(\.value)).inserted }, base)
  }

  /// The pattern for one word written in lowercase with its Vietnamese marks.
  ///
  /// A word is read in one of three spellings: with every mark ("tối", "đêm"),
  /// with every mark but the stroke of "đ" written as "d" ("dêm"), or with no mark
  /// at all ("toi", "dem"), which is how a line typed without tone marks and
  /// vowel marks spells it. A word with some marks and not others is no spelling
  /// of it: "đem" (to bring) is not "đêm" (night) and "tôi" (I) is not "tối"
  /// (evening) or "tới" (next). A letter's marks may be typed composed or as
  /// separate combining characters. With `strict`, the marks of the vowels must be
  /// typed.
  private static func vietnameseSingleWord(_ word: String, strict: Bool) -> String {
    var marked = ""
    var strokeless = ""
    var bare = ""
    var hasStroke = false
    var hasVowelMark = false
    for scalar in word.unicodeScalars {
      if scalar == "đ" {
        hasStroke = true
        marked += "đ"
        strokeless += "d"
        bare += "d"
      } else if let (forms, base) = vietnameseMarkedForms(of: scalar) {
        hasVowelMark = true
        let alternatives = "(?:" + forms.joined(separator: "|") + ")"
        marked += alternatives
        strokeless += alternatives
        bare += NSRegularExpression.escapedPattern(for: base)
      } else {
        let letter = NSRegularExpression.escapedPattern(for: String(scalar))
        marked += letter
        strokeless += letter
        bare += letter
      }
    }
    var branches = [marked]
    if hasStroke && hasVowelMark { branches.append(strokeless) }
    if !strict && (hasStroke || hasVowelMark) { branches.append(bare) }
    return branches.count == 1 ? marked : "(?:" + branches.joined(separator: "|") + ")"
  }

  /// `phrase`, a word or words written in lowercase with their Vietnamese marks,
  /// as a pattern without groups that matches the phrase in every spelling
  /// ``vietnameseSingleWord(_:strict:)`` accepts for each of its words. A run of
  /// spaces in the phrase matches any run of white space.
  ///
  /// With `strict`, the vowels' marks must be typed. A word whose toneless
  /// spelling is another everyday word is written strict ("tư" for Wednesday is
  /// "tu" toneless, which is also "tự" in "thứ tự"; "mốt" is "mot", also "một").
  ///
  /// `gap` is the pattern between the words of a phrase. A look-behind needs a
  /// bounded one (`\s{1,3}`), since ICU rejects a look-behind that can match
  /// without limit.
  static func vietnameseWord(_ phrase: String, strict: Bool = false, gap: String = #"\s+"#) -> String {
    phrase.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace)
      .map { vietnameseSingleWord(String($0), strict: strict) }.joined(separator: gap)
  }

  /// `phrases` as the alternatives of a pattern without groups, longest first, so
  /// a phrase is never cut short by a shorter one that starts it. `gap` is as in
  /// ``vietnameseWord(_:strict:gap:)``.
  static func vietnameseAlternation(_ phrases: [String], strict: Bool = false, gap: String = #"\s+"#) -> String {
    let ordered = phrases.sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
    return "(?:" + ordered.map { vietnameseWord($0, strict: strict, gap: gap) }.joined(separator: "|") + ")"
  }

  /// A matched word or phrase as a reader looks it up: lowercased, with every
  /// tone mark and vowel mark removed, "đ" read as "d", and each run of white
  /// space as one space ("Thứ Hai" as "thu hai", "đêm nay" as "dem nay"). Every
  /// spelling a pattern accepts of a word has the same key.
  static func vietnameseKey(_ text: String) -> String {
    var folded = String.UnicodeScalarView()
    for scalar in text.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
      if scalar.properties.generalCategory == .nonspacingMark { continue }
      folded.append(scalar == "đ" ? "d" : scalar)
    }
    return String(folded).split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  /// The words of a matched phrase as typed, lowercased and composed, without
  /// the punctuation around them. A reader that must tell "tối" (evening) from
  /// "tới" (next) looks at these, which keep the tone marks the key drops.
  static func vietnameseTypedWords(_ phrase: String) -> [String] {
    phrase.lowercased().precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).map {
      String($0).trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?"))
    }
  }

  /// A set of Vietnamese words a reader compares a typed word against. A word
  /// typed with its marks, composed or decomposed, matches the set's word with
  /// the same marks, also when its "đ" is typed as "d"; a word typed with no mark
  /// at all matches the set's word toneless. A word typed with other marks
  /// matches none, so "Tuấn" (a name) is not "tuần" (week) while "Tuan" is.
  struct VietnameseWordSet: Sendable {
    private let marked: Set<String>
    private let plain: Set<String>

    /// The set of `words`, each written with its marks.
    init(_ words: [String]) {
      let composed = words.map { $0.precomposedStringWithCanonicalMapping }
      marked = Set(composed + composed.map { $0.replacingOccurrences(of: "đ", with: "d") })
      plain = Set(words.map { LorvexCaptureVocabulary.vietnameseKey($0) })
    }

    /// Whether `typed` is a word of the set.
    func contains(_ typed: String) -> Bool {
      let word = typed.lowercased()
      // Swift compares strings by canonical equivalence, so a decomposed spelling
      // is found among the composed words.
      return marked.contains(word) || (word.unicodeScalars.allSatisfy(\.isASCII) && plain.contains(word))
    }
  }

  // MARK: - Numbers as words

  /// The digits of the numbers 1 to 9 as their key spells them.
  private static let vietnameseDigitWords: [String: Int] = [
    "mot": 1, "hai": 2, "ba": 3, "bon": 4, "nam": 5, "sau": 6, "bay": 7, "tam": 8, "chin": 9,
  ]

  /// The numbers 1 to 99 spelled as words, as a pattern without groups: "ba",
  /// "mười", "mười lăm", "hai mươi", "bốn mươi lăm". "Lăm", "tư", and "mốt" follow
  /// ten or a multiple of ten only ("năm" after "mười" is no fifteen).
  static let vietnameseNumberWords: String = {
    let units = vietnameseAlternation(["một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"])
    let tens = vietnameseAlternation(["hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"])
    let afterTen = vietnameseAlternation(["một", "hai", "ba", "bốn", "lăm", "sáu", "bảy", "tám", "chín"])
    let afterTens = vietnameseAlternation([
      "mốt", "một", "hai", "ba", "bốn", "lăm", "năm", "sáu", "bảy", "tám", "chín",
    ])
    let four = vietnameseWord("tư", strict: true)
    let ten = vietnameseWord("mười")
    let tensWord = vietnameseWord("mươi")
    return #"(?:\#(tens)\s+\#(tensWord)(?:\s+(?:\#(afterTens)|\#(four)))?|\#(ten)\s+\#(afterTen)|\#(ten)|\#(units))"#
  }()

  /// The hours 1 to 12 spelled as words, as a pattern without groups.
  static let vietnameseHourWords = vietnameseAlternation([
    "mười hai", "mười một", "mười", "chín", "tám", "bảy", "sáu", "năm", "bốn", "ba", "hai", "một",
  ])

  /// The count a matched run of digits or number words names, from 1 to 99.
  static func vietnameseCount(_ text: String) -> Int? {
    if let digits = number(text) { return digits }
    let tokens = vietnameseKey(text).split(separator: " ").map(String.init)
    switch tokens.count {
    case 1:
      return tokens[0] == "muoi" ? 10 : vietnameseDigitWords[tokens[0]]
    case 2:
      if tokens[0] == "muoi" {
        // "Năm" after "mười" is not fifteen; "lăm" is.
        let unit = tokens[1] == "lam" ? 5 : (tokens[1] == "nam" ? nil : vietnameseDigitWords[tokens[1]])
        return unit.map { 10 + $0 }
      }
      guard tokens[1] == "muoi", let tens = vietnameseDigitWords[tokens[0]], tens >= 2 else { return nil }
      return tens * 10
    case 3:
      guard tokens[1] == "muoi", let tens = vietnameseDigitWords[tokens[0]], tens >= 2 else { return nil }
      let unit = tokens[2] == "lam" ? 5 : (tokens[2] == "tu" ? 4 : (tokens[2] == "mot" ? 1 : vietnameseDigitWords[tokens[2]]))
      return unit.map { tens * 10 + $0 }
    default:
      return nil
    }
  }
}
