import Foundation

extension LorvexCaptureVocabulary {
  /// Hindi, read for a user who reads Hindi in Devanagari. A word needs a
  /// boundary of Devanagari letters, signs, digits, and joiners on both sides
  /// (``devanagariStart``), so "आजकल" (nowadays) and "कलयुग" hold no day, and a
  /// hyphen between two Devanagari words joins them ("आज-कल"). The danda (।) is
  /// punctuation. Hindi writes its postpositions as separate words, so most
  /// readings are plain word matches, and the postposition that goes with a
  /// detail is read with it: को, से, पर, में, or के लिए after a day; पर, से, के
  /// लिए, के आसपास, or a possessive after a time ("5 बजे की मीटिंग"); के लिए, का,
  /// की, के, or तक after a length ("30 मिनट की मीटिंग").
  ///
  /// The line is read in one form (``hindiForMatching(_:)``): Devanagari digits
  /// as Latin ones ("५ बजे" is "5 बजे"), the precomposed nukta letters (क़ ख़ ग़
  /// ज़ ड़ ढ़ फ़ य़) as their base consonants, and the candrabindu as the anusvara,
  /// so "पाँच" and "पांच" are one word. A nukta typed as a separate sign after
  /// its consonant, and a zero-width joiner after a virama, are tolerated in
  /// every word, so "ज़रूरी" is one word however it is typed, and the words
  /// whose nasal conjunct is spelled two ways are read both ways ("सितंबर" and
  /// "सितम्बर", "घंटा" and "घण्टा", "तुरंत" and "तुरन्त"). The title keeps what
  /// was typed. Hindi written in Latin letters ("kal subah 9 baje") is not read.
  ///
  /// English is read beside Hindi, so a detail that needs no Hindi word is left
  /// to English, which reads its own "5pm", "17:30", "30 min", or "2h". Hindi
  /// does not write a clock time with the letter h, so "2h" beside Hindi stays a
  /// length.
  ///
  /// कल means "tomorrow" and also "yesterday", and परसों means "the day after
  /// tomorrow" and also "the day before yesterday". This vocabulary reads कल as
  /// tomorrow and परसों as the day after tomorrow and never reads a past day,
  /// because the app writes the past day "बीता कल". A day phrase is left
  /// unread when its line says the day is past or not coming: a past-tense form
  /// anywhere in the line (था, थी, थे, गया, गई, चुका, आया, हुआ, हुई: "कल मीटिंग
  /// थी"), or बीता, बीते, गुज़रा, पिछले, or पहले (the ordinal "first" as well)
  /// just before it ("बीता कल", "पिछले शुक्रवार", "पहले शुक्रवार"). The rule
  /// holds for आज and the weekdays too. "किया" is no past marker ("किया जाना है"
  /// is a future passive), so a past "कल मैंने फोन किया" is read as tomorrow.
  ///
  /// A weekday is a day only with its वार ending: the short stems सोम, मंगल,
  /// बुध, गुरु, शुक्र, शनि, and रवि are ordinary words or names. A day phrase
  /// that a possessive or "वाला" follows is an attribute of a noun, not a plan
  /// ("सोमवार की मीटिंग", "कल की रिपोर्ट"), and "कल रात का खाना" reads only कल.
  ///
  /// - Day: आज, कल, परसों, each maybe with a part of the day (सुबह, सवेरे,
  ///   तड़के, दोपहर, शाम, रात, देर रात: "आज रात", "कल सुबह", "आज की रात"; the
  ///   afternoon also as "दोपहर बाद" or "दोपहर के बाद"); a part that any other
  ///   बाद follows is no part of the phrase, so "कल शाम के बाद फोन करना" reads
  ///   only कल, and so does "कल दोपहर बाद की मीटिंग"; the
  ///   weekday names (रविवार or इतवार, सोमवार, मंगलवार, बुधवार, गुरुवार or
  ///   बृहस्पतिवार, शुक्रवार, शनिवार), alone or with को, or after इस (this
  ///   week's), अगले (next week's, weeks starting on Monday), or आने वाले ("इस
  ///   शुक्रवार", "अगले सोमवार", "आने वाले शुक्रवार को", "इस हफ़्ते शुक्रवार");
  ///   अगले हफ़्ते and अगले सप्ताह (seven days ahead); "3 दिन बाद", "तीन दिन
  ///   बाद", "2 हफ़्ते बाद", "एक हफ़्ते बाद", "1 महीने बाद" (months counted on
  ///   the calendar); the weekend, "वीकेंड", "सप्ताहांत", or "हफ़्ते के अंत",
  ///   alone or after इस or अगले; a date ("5 मई", "5 मई 2027", "तारीख 5 मई",
  ///   "सोमवार, 5 अक्टूबर"). A weekday alone means the next such day, a full
  ///   week ahead when it names today. "इस हफ़्ते" alone names no single day and
  ///   is not read. The weekend is the coming Saturday (today on a Saturday or a
  ///   Sunday) and, after अगले, the Saturday a week later. A date needs its day
  ///   number before the month name (जनवरी, फ़रवरी, मार्च, अप्रैल, मई, जून,
  ///   जुलाई, अगस्त, सितंबर, अक्टूबर, नवंबर, दिसंबर, in the spellings people
  ///   type); a month alone, a month before its day, a date written in digits
  ///   ("5/10"), a date the calendar lacks ("31 अप्रैल"), and the Vikram Samvat
  ///   months (चैत्र, वैशाख, ...) stay in the title. The emphatic ही or भी
  ///   after a day, or after its postposition, goes with it ("आज ही", "सोमवार
  ///   को ही", "कल से ही", "3 दिन बाद ही"); "आज ही की रिपोर्ट" is a noun's
  ///   attribute and is not read.
  /// - Date range: "3 से 5 मार्च", "3 मार्च से 5 मार्च तक", "30 जनवरी से 2
  ///   फ़रवरी तक", "3-5 मार्च", "3–5 मार्च", each maybe with a year after the
  ///   end, with "से लेकर", and with तक, के बीच, or के दौरान after the end. The
  ///   first day is the planned day and the last the due day, so another day
  ///   phrase stays in the title. A day written without its month takes the
  ///   month of the end, the end must be after the start ("5 से 3 मार्च" stays
  ///   in the title whole), and the end names a month, so "3 से 5" is never a
  ///   range of days. A day alone opens a range joined by a dash only when the
  ///   dash touches both sides: "Sprint 12 - 20 मार्च" names a sprint and a
  ///   date. A range in the past tense, or one that a possessive follows ("5 से
  ///   8 मई तक की छुट्टी"), may be an event the task only prepares for: it
  ///   stays in the title whole. A span of weekdays ("सोमवार से बुधवार तक",
  ///   "शुक्रवार से सोमवार") plans the coming first day and is due on the first
  ///   last day after it. After "हर" or beside the words for every day it is a
  ///   repeat instead, and Monday to Friday with none of them ("सोमवार से
  ///   शुक्रवार") stays in the title whole, since it is a week of work as often
  ///   as it is the working week.
  /// - Repeat: हर दिन, रोज़, रोज, रोज़ाना, प्रतिदिन, नित्य, and हर with a part
  ///   of the day (हर सुबह, हर शाम को, हर रात), which keeps its part for an hour
  ///   beside it ("हर सुबह 6 बजे योग" is every day at 06:00); हर
  ///   हफ़्ते, हर सप्ताह, हर महीने, हर साल, हर वर्ष (प्रत्येक and हरेक for हर);
  ///   हर सोमवार, हर सोमवार को, हर सोमवार और गुरुवार, हर सोमवार, बुधवार और
  ///   शुक्रवार, हर दूसरे सोमवार, हर हफ़्ते सोमवार को, सोमवार और गुरुवार को हर
  ///   हफ़्ते, सोमवारों को; हर 2 दिन, हर दो दिन, हर दूसरे दिन, हर 3 हफ़्ते, हर
  ///   दूसरे हफ़्ते, हर 3 महीने, हर 5 साल; सप्ताह में एक बार, महीने में एक
  ///   बार; हर महीने की 5 तारीख, हर महीने 5 तारीख को, हर महीने की पहली
  ///   तारीख, 5 तारीख को हर महीने; हर वीकेंड, हर सप्ताहांत, हर शनिवार और
  ///   रविवार; the working days as "हर कार्यदिवस", "कार्यदिवसों में", "हर
  ///   कामकाजी दिन", or a span of weekdays with हर or the words for every day
  ///   ("हर सोमवार से शुक्रवार", "सोमवार से शुक्रवार हर दिन"). An interval
  ///   shorter than a day ("हर 2 घंटे") is no repeat, and a cadence word that
  ///   makes an attribute of a noun is none ("रोज़ का काम", "हर साल की
  ///   रिपोर्ट"). "रोज़ा", "रोज़गार", and "रोज़ी" are other words.
  /// - Due: a day before तक, तलक, से पहले, के पहले, or से पूर्व ("शुक्रवार तक",
  ///   "कल शाम से पहले", "5 मई तक", "परसों तक"), or after अंतिम तिथि, आखिरी
  ///   तारीख, नियत तिथि, डेडलाइन, or समय-सीमा ("अंतिम तिथि: 5 मई", "डेडलाइन
  ///   शुक्रवार"). A day before a clock deadline ("शुक्रवार शाम 5 बजे तक") is
  ///   the due day and the clock stays in the title. "आज तक" ("so far") and "आज
  ///   से पहले" ("never before") are idioms and are not read, nor is a deadline
  ///   that a possessive follows ("शुक्रवार तक की रिपोर्ट"). A ही or भी after
  ///   the deadline word goes with it ("शुक्रवार तक ही").
  /// - Time: "5 बजे", "5:30 बजे", "5.30 बजे", "साढ़े 5 बजे" (5:30), "सवा 5 बजे"
  ///   (5:15), "पौने 6 बजे" (5:45), "डेढ़ बजे" (1:30), "ढाई बजे" (2:30), each
  ///   maybe after ठीक, करीब, लगभग, or तकरीबन. The hour may be a number word from एक to
  ///   बारह ("पाँच बजे", "साढ़े तीन बजे"); a number word without बजे is never an
  ///   hour. A part of the day sets the hour and may come before it ("सुबह 9
  ///   बजे", "शाम को 5 बजे", "रात के 10 बजे", and with ठीक, करीब, लगभग,
  ///   तकरीबन, or जल्दी between them: "सुबह ठीक 6 बजे") or after बजे ("9 बजे
  ///   सुबह", "10 बजे रात"; not before a possessive: "5 बजे शाम की चाय" is 5 PM
  ///   and keeps "शाम की चाय"). सुबह (also doubled, "सुबह-सुबह" with a hyphen or
  ///   a space), सवेरे, and तड़के are the morning (12 is no time), दोपहर is noon
  ///   at 12 and the afternoon from 1 to 6, शाम is the evening, and रात runs past
  ///   midnight: "रात 12 बजे" is 00:00 of the next day, "रात 2 बजे" is 02:00 of
  ///   the next day, and "रात 8 बजे" is 20:00. "आधी रात" is the midnight that
  ///   ends the day. An hour on the 12-hour clock (1 to 12, no leading zero)
  ///   written with no part of the day beside it takes its half of the day from
  ///   the one part of the day the line names elsewhere: in its day phrase
  ///   ("कल सुबह मीटिंग 6 बजे" is 06:00), after हर ("हर सुबह 6 बजे योग"), or in
  ///   a noun ("रात का खाना 8 बजे" is 20:00, "सुबह की सैर 6 बजे" is 06:00).
  ///   Two parts that differ leave the hour as it reads alone; a part that a
  ///   deadline word follows ("कल सुबह तक") and "आधी रात" are not counted; an
  ///   hour on the 24-hour clock (a leading zero, 0, or 13 and later) is read
  ///   as written. An hour from 1 to 6 with no part of the day anywhere in the
  ///   line is the afternoon, as in the other languages ("5 बजे" is 17:00, "7
  ///   बजे" is 07:00), unless written with a leading zero ("06:30 बजे"). A range: "3 से 5 बजे", "सुबह 9 से 11 बजे तक", "3 बजे से 5
  ///   बजे तक", "दो से चार बजे", "2-4 बजे", "14:00 से 16:00", "सुबह 9 बजे से शाम 5
  ///   बजे तक", each maybe with "से लेकर" and with तक or के बीच after it; the end
  ///   carries बजे, so "3 से 5" is no range. A clock time that is a bound stays
  ///   in the title whole: before तक or से पहले ("5 बजे तक", "शाम 5 बजे से
  ///   पहले", "18:00 तक"), के बाद, or के बीच, and so does "5 बजकर 30 मिनट". A
  ///   number before a percent sign, a currency sign, or a currency word is
  ///   never a time.
  /// - Length: "30 मिनट", "2 घंटे", "1.5 घंटे", "1 घंटा 30 मिनट", "आधा घंटा",
  ///   "पौन घंटा" (45 minutes), "सवा घंटा" (75), "डेढ़ घंटा", "ढाई घंटे", "साढ़े 3
  ///   घंटे", "पौने दो घंटे", "दो घंटे", "बीस मिनट", each maybe after लगभग,
  ///   करीब, or तकरीबन, in the singular or the plural ("1 घंटा", "2 घंटे", "2
  ///   घंटों"). An amount before बाद, पहले, में, or के भीतर, or after हर, "कम से
  ///   कम", or "दिन में", names a moment, an interval, or a bound, not a length
  ///   ("2 घंटे बाद", "1 घंटा पहले", "हर 2 घंटे", "2 घंटे के भीतर", "दिन में 2
  ///   घंटे"), and neither is a side of a range ("2 से 3 घंटे", "2-3 घंटे"):
  ///   each stays whole in the title. घंटा alone is no length ("घंटा भर").
  /// - Priority: उच्च प्राथमिकता, मध्यम प्राथमिकता, निम्न प्राथमिकता (also
  ///   उच्चतम, सर्वोच्च, ऊंची, सामान्य, साधारण, निम्नतम, निचली, and कम), each
  ///   also after the word ("प्राथमिकता: उच्च") and maybe followed by "से"
  ///   ("उच्च प्राथमिकता से भेजें"); ज़रूरी, अत्यावश्यक, अति आवश्यक, तुरंत, or
  ///   अर्जेंट (maybe after बहुत, अत्यंत, or बेहद) at the end of the line, and
  ///   the same words opening it before a colon or comma ("ज़रूरी: रिपोर्ट
  ///   भेजें"). ज़रूरी is an ordinary adjective too, so "ज़रूरी दवाइयाँ ख़रीदना"
  ///   and "रिपोर्ट भेजें ज़रूरी है" stay in the title, and so does "उच्च
  ///   प्राथमिकता वाले कार्य".
  static let hindi = LorvexCaptureVocabulary(
    readingForm: hindiForMatching,
    priority: [hindiRule(hindiPriorityPattern, read: hindiPriority)],
    dateRange: [
      hindiRule(hindiDateRangePattern, read: hindiDateRange),
      hindiRule(hindiWeekdayRangePattern, read: hindiWeekdayRange),
    ],
    keptInTitle: [
      hindiRule(hindiDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      hindiRule(hindiLengthPattern) { hindiDeclinesLength($0) ? true : nil },
      hindiRule(hindiBajkarPattern) { _ in true },
    ],
    length: [hindiRule(hindiLengthPattern, read: hindiLength)],
    time: [
      hindiRule(hindiTimeRangePattern, read: hindiTimeRange),
      hindiRule(hindiColonTimeRangePattern, read: hindiTimeRange),
      hindiRule(hindiTimePattern, read: hindiTime),
      hindiRule(hindiPartColonTimePattern, read: hindiPartColonTime),
      hindiRule(hindiMidnightPattern) { _ in ClockTime(minutes: 0, isAfterMidnight: true) },
    ],
    repeats: hindiRepeatRules,
    due: [hindiRule(hindiDuePattern, read: hindiDue)],
    when: [hindiRule(hindiWhenPattern, read: hindiWhen)])

  // MARK: - Reading form and patterns

  /// The line with each digit and letter read in one form: the Devanagari
  /// digits (०-९) as ASCII digits, the precomposed nukta letters (क़ ख़ ग़ ज़
  /// ड़ ढ़ फ़ य़) as their base consonants, and the candrabindu (ँ) as the
  /// anusvara (ं), so "पाँच" and "पांच" are one word. A nukta typed as a
  /// separate sign after its consonant stays where it was typed: a pattern,
  /// written in the base letters, tolerates it after every consonant that can
  /// carry one (``hindi(_:)``). Each replacement is one UTF-16 unit for one, so
  /// a match range in the result is the same range in `line`.
  static func hindiForMatching(_ line: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in line.unicodeScalars { scalars.append(hindiReading(of: scalar)) }
    return String(scalars)
  }

  private static func hindiReading(of scalar: Unicode.Scalar) -> Unicode.Scalar {
    switch scalar {
    case "\u{0966}"..."\u{096F}": Unicode.Scalar(UInt8(truncatingIfNeeded: 0x30 + scalar.value - 0x0966))
    case "\u{0958}": "\u{0915}"
    case "\u{0959}": "\u{0916}"
    case "\u{095A}": "\u{0917}"
    case "\u{095B}": "\u{091C}"
    case "\u{095C}": "\u{0921}"
    case "\u{095D}": "\u{0922}"
    case "\u{095E}": "\u{092B}"
    case "\u{095F}": "\u{092F}"
    case "\u{0901}": "\u{0902}"
    default: scalar
    }
  }

  /// `text` without its nukta signs and zero-width joiners: the letters of a
  /// matched word as a reader compares them. `text` is already in the reading
  /// form. Comparisons of Devanagari text go through scalars or whole words:
  /// a `Character` is a grapheme cluster ("घं" is one), so `hasPrefix("घ")`
  /// does not match "घंटा".
  static func hindiBare(_ text: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars where scalar != "\u{093C}" && scalar != "\u{200C}" && scalar != "\u{200D}" {
      scalars.append(scalar)
    }
    return String(scalars)
  }

  /// A matched phrase as a reader compares it: without nukta signs and
  /// joiners, each run of spaces as one, hyphens read as spaces.
  static func hindiPhrase(_ text: String) -> String {
    normalizedPhrase(hindiBare(text))
  }

  /// A word written in a vocabulary table, as ``hindiPhrase(_:)`` leaves a
  /// matched word, whichever way the table spells its nukta letters.
  static func hindiKey(_ word: String) -> String {
    hindiBare(hindiForMatching(word))
  }

  /// `pattern`, written in the base letters of its words, ready to match a
  /// line in the reading form: every consonant that can carry a nukta (क ख ग
  /// ज ड ढ फ य) may be followed by one, a virama may be followed by zero-width
  /// joiners, and a quantifier that follows such a letter applies to the
  /// letter with its extras. A nukta, joiner, or precomposed nukta letter typed
  /// in `pattern` is read like the base letter. Escapes and character sets pass
  /// through, the letters in a set read through the reading form. A pattern is
  /// expanded once, by ``hindiRule(_:read:)``, never in parts that another
  /// pattern then embeds.
  static func hindi(_ pattern: String) -> String {
    let quantifiers: Set<Unicode.Scalar> = ["?", "*", "+", "{"]
    let carriesNukta: Set<Unicode.Scalar> = [
      "\u{0915}", "\u{0916}", "\u{0917}", "\u{091C}", "\u{0921}", "\u{0922}", "\u{092B}", "\u{092F}",
    ]
    let scalars = Array(pattern.unicodeScalars.filter { $0 != "\u{093C}" && $0 != "\u{200C}" && $0 != "\u{200D}" })
    var result = ""
    var isEscaped = false
    var isInSet = false
    for (index, scalar) in scalars.enumerated() {
      if isEscaped {
        result.unicodeScalars.append(scalar)
        isEscaped = false
      } else if scalar == "\\" {
        result.unicodeScalars.append(scalar)
        isEscaped = true
      } else if isInSet {
        if scalar == "]" { isInSet = false }
        result.unicodeScalars.append(hindiReading(of: scalar))
      } else if scalar == "[" {
        isInSet = true
        result.unicodeScalars.append(scalar)
      } else {
        let reading = hindiReading(of: scalar)
        var extra = ""
        if carriesNukta.contains(reading) {
          extra = #"\x{093C}?"#
        } else if reading == "\u{094D}" {
          extra = #"[\x{200C}\x{200D}]{0,2}"#
        }
        let unit = String(Character(reading)) + extra
        let isQuantified = index + 1 < scalars.count && quantifiers.contains(scalars[index + 1])
        result += !extra.isEmpty && isQuantified ? "(?:\(unit))" : unit
      }
    }
    return result
  }

  /// A rule whose `pattern` is written in base letters (see ``hindi(_:)``).
  static func hindiRule<Value>(_ pattern: String, read: @escaping @Sendable (Match) -> Value?) -> Rule<Value> {
    Rule(pattern: hindi(pattern), read: read)
  }

  /// Whether `pattern`, written in base letters, matches somewhere in `text`,
  /// which is in the reading form.
  static func hindiFinds(_ pattern: String, in text: String) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(hindi(pattern)) else { return false }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  // MARK: - Boundaries and words around a detail

  /// A word boundary for words written in Devanagari: no Devanagari letter,
  /// vowel sign, virama, nukta, candrabindu, anusvara, joiner, or digit on that
  /// side, and no hyphen that joins it to another Devanagari word ("आज-कल" is
  /// one word, "nowadays"). The danda (।) is punctuation and a boundary.
  static let devanagariStart =
    #"(?<![\p{Devanagari}\p{M}\p{N}\x{200C}\x{200D}])(?<![\p{Devanagari}\p{M}]-)"#
  static let devanagariEnd =
    #"(?![\p{Devanagari}\p{M}\p{N}\x{200C}\x{200D}])(?!-\p{Devanagari})"#

  /// What may follow a clock time: no Devanagari letter, vowel sign, digit, or
  /// colon (the word or the number goes on), no decimal fraction, no percent
  /// or currency sign or word with or without a space before it (the number
  /// is an amount: "20%", "500 रुपये"), no dash before a digit (a range
  /// written with a dash and no बजे is English's), and no AM or PM after it.
  static let hindiTimeEnd =
    #"(?![\p{Devanagari}\p{M}\p{N}\x{200C}\x{200D}:]|[.,]\p{N}|\s*[%\p{Sc}]|\s*(?:रुपये|रुपए|रुपया|रु\.?|डॉलर|पैसे|पैसा)\#(devanagariEnd)|\s*[-–—]\s*\d)\#(noMeridiemAfter)"#

  /// What may follow a date: no Devanagari letter, vowel sign, digit, or
  /// colon, and no decimal fraction.
  static let hindiDateEnd = #"(?![\p{Devanagari}\p{M}\p{N}\x{200C}\x{200D}:]|[.,]\p{N})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let hindiNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// The word just before `match` as a reader compares it (without nukta
  /// signs), or nil when the match opens the line or punctuation comes first.
  static func hindiWordBefore(_ match: Match) -> String? {
    guard let word = wordBefore(match).map(hindiBare), !word.isEmpty else { return nil }
    return word
  }

  /// The words of `text`, as letters only and without nukta signs.
  static func hindiWords(in text: String) -> [String] {
    text.split(whereSeparator: { !$0.isLetter }).map { hindiBare(String($0)) }
  }

  // MARK: - Counts

  /// The numerals one to twelve, which stand before a counted noun and name an
  /// hour before बजे, keyed as ``hindiKey(_:)`` leaves them. The numeral six
  /// has several spellings.
  static let hindiCounts: [String: Int] = {
    let spellings: [(Int, [String])] = [
      (1, ["एक"]), (2, ["दो"]), (3, ["तीन"]), (4, ["चार"]), (5, ["पांच", "पाँच"]),
      (6, ["छह", "छः", "छे", "छै", "छ"]), (7, ["सात"]), (8, ["आठ"]), (9, ["नौ"]), (10, ["दस"]),
      (11, ["ग्यारह"]), (12, ["बारह"]),
    ]
    var counts: [String: Int] = [:]
    for (value, words) in spellings {
      for word in words { counts[hindiKey(word)] = value }
    }
    return counts
  }()

  /// The numerals of an amount of minutes or days: the counts above and the
  /// round numbers up to sixty.
  static let hindiRoundCounts: [String: Int] = {
    let spellings: [(Int, [String])] = [
      (15, ["पंद्रह", "पन्द्रह"]), (20, ["बीस"]), (25, ["पच्चीस"]), (30, ["तीस"]), (40, ["चालीस"]),
      (45, ["पैंतालीस", "पैतालीस"]), (50, ["पचास"]), (60, ["साठ"]),
    ]
    var counts = hindiCounts
    for (value, words) in spellings {
      for word in words { counts[hindiKey(word)] = value }
    }
    return counts
  }()

  /// The numerals that name an hour, as a pattern.
  static var hindiCountWords: String { alternation(of: Array(hindiCounts.keys)) }

  /// The numerals of an amount of minutes or days, as a pattern.
  static var hindiRoundCountWords: String { alternation(of: Array(hindiRoundCounts.keys)) }

  // MARK: - Priority

  /// Group 1: a written priority, with its level before or after the word
  /// "प्राथमिकता" and maybe "से" after it ("उच्च प्राथमिकता से भेजें"); an
  /// urgent word has no group. A level word with "वाला" after the priority
  /// describes a noun ("उच्च प्राथमिकता वाले कार्य") and is no priority.
  private static var hindiPriorityPattern: String {
    let level = "उच्चतम|सर्वोच्च|उच्च|ऊंची|मध्यम|सामान्य|साधारण|निम्नतम|निम्न|निचली|कम"
    let urgent = #"अत्यावश्यक|अति\s+आवश्यक|तुर(?:ं|न्)त|अर्जे(?:ं|न्)ट|जर[ूु]री"#
    let intensifier = #"(?:(?:बहुत|अत्य(?:ं|न्)त|बेहद)\s+)?"#
    return
      #"\#(devanagariStart)((?:\#(level))\s*प्राथमिकता|प्राथमिकता\s*[:：]?\s*(?:\#(level)))\#(devanagariEnd)(?:\s+से\#(devanagariEnd))?(?!\s+वाल(?:ा|ी|े|ों)\#(devanagariEnd))|(?<=\s)\#(intensifier)(?:\#(urgent))\#(devanagariEnd)(?=\s*[।.]?\s*$)|^\s*(?:\#(urgent))\#(devanagariEnd)(?=\s*[:：,，])"#
  }

  private static func hindiPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1).map(hindiPhrase) else { return .p1 }
    let words = Set(hindiWords(in: phrase))
    if !words.isDisjoint(with: ["मध्यम", "सामान्य", "साधारण"].map(hindiKey)) { return .p2 }
    if !words.isDisjoint(with: ["निम्न", "निम्नतम", "निचली", "कम"].map(hindiKey)) { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "30 मिनट", "2 घंटे", "1.5 घंटे", "1 घंटा 30 मिनट", "आधा घंटा", "डेढ़ घंटा",
  /// "ढाई घंटे", "सवा घंटा", "पौन घंटा", "साढ़े 3 घंटे", "पौने दो घंटे", "दो घंटे",
  /// "बीस मिनट", each maybe after "लगभग", "करीब", or "तकरीबन" and maybe followed
  /// by "के लिए", "का", "की", "के", or "तक", which go with it ("30 मिनट की
  /// मीटिंग" is a meeting of 30 minutes). Groups: 1 a word that makes the length approximate (लगभग,
  /// करीब, तकरीबन); 2 a word that makes the amount an interval, a bound, or a
  /// rate ("हर 2 घंटे", "कम से कम 2 घंटे", "दिन में 2 घंटे"); 3 the hours of an
  /// amount with a unit and 4 its minutes; 5 minutes; 6 a length in words; 7 a
  /// word after the amount that makes it a moment, the past, a bound, or a
  /// comparison ("2 घंटे बाद", "1 घंटा पहले", "2 घंटे के भीतर", "2 घंटे में", "2
  /// घंटे से ज़्यादा"). A match with group 2 or 7 is no length:
  /// ``hindiLength(_:)`` declines it and a keep rule claims it, so the amount
  /// stays whole in the title. The unit nouns are Devanagari, so an amount
  /// written with a Latin unit ("हर 2h") is left to English. The amount may not
  /// follow a digit, a colon, or a separator, and it may not be a side of a
  /// range ("2-3 घंटे", "2 से 3 घंटे", "5 मिनट से 10 मिनट").
  static var hindiLengthPattern: String {
    let hourNoun = "घ(?:ं|ण्|न्)ट(?:ा|े|ों)"
    let minuteNoun = "मिनि?ट(?:ों)?"
    let opener =
      #"(?:(?:(लगभग|करीब|तकरीबन)|(हर|प्रत्येक|हरेक|कम\s+से\s+कम|ज्यादा\s+से\s+ज्यादा|अधिकतम|न्यूनतम|(?:दिन|हफ्ते|सप्ताह|महीने|साल)\s+में))\s+)?"#
    let boundaries = #"(?<![\p{N}:.,])(?<!\p{N}\s?[-–—]\s?)"#
    let hours =
      #"(\d+(?:\.\d+)?)\s*(?:\#(hourNoun))(?:\s+(?:और\s+)?(\d{1,2})\s*(?:\#(minuteNoun)))?"#
    let minutes = #"(\d+)\s*(?:\#(minuteNoun))"#
    let words =
      #"(आध(?:ा|े)\s+\#(hourNoun)|(?:डेढ़|ढाई|अढाई|सवा|पौन)\s+\#(hourNoun)|(?:साढ़े|सवा|पौने)\s+(?:\d{1,2}|\#(hindiCountWords))\s+\#(hourNoun)|(?:\#(hindiCountWords))\s+\#(hourNoun)|(?:\#(hindiRoundCountWords))\s+\#(minuteNoun))"#
    let trailing =
      #"(?:\s+(?:(बाद|पहले|में|के\s+(?:बाद|पहले|भीतर|अंदर|अन्दर|दौरान|बीच)|से\s+(?:ज्यादा|अधिक|कम|पहले|बाद|ऊपर|नीचे))|(?:के\s+लिए|का|की|के|तक))\#(devanagariEnd))?"#
    return
      #"\#(devanagariStart)\#(opener)(?:\#(boundaries)(?:\#(hours)|\#(minutes))|\#(words))\#(devanagariEnd)(?!\s*[-–—]\s*\d|\s+से\s+\d)\#(trailing)"#
  }

  /// True for a match that is no length: an interval, a bound, or a rate ("हर
  /// 2 घंटे", "दिन में 2 घंटे"), a moment, the past, or a comparison ("2 घंटे
  /// बाद", "1 घंटा पहले"), or the end of a range of amounts ("2 से 3 घंटे").
  static func hindiDeclinesLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(7) != nil || hindiIsRangeEnd(match)
  }

  /// Whether the text before `match` ends with a number or a unit and "से",
  /// which makes the amount the end of a range ("2 से 3 घंटे", "5 मिनट से 10
  /// मिनट").
  private static func hindiIsRangeEnd(_ match: Match) -> Bool {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return false }
    let before = String(match.source[..<start])
    return hindiFinds(#"(?:\d|मिनट|मिनिट|घंटे|घंटा)\s+से\s+$"#, in: before)
  }

  private static func hindiLength(_ match: Match) -> Int? {
    if hindiDeclinesLength(match) { return nil }
    if let hours = match.group(3).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(4).flatMap(number) ?? 0))
    }
    if let minutes = match.group(5).flatMap(number) { return taskLength(minutes: minutes) }
    guard let phrase = match.group(6).map(hindiPhrase) else { return nil }
    let tokens = phrase.split(separator: " ").map(String.init)
    guard let unit = tokens.last else { return nil }
    // The hour noun begins with घ; the minute noun with म.
    let isHours = unit.unicodeScalars.first == "\u{0918}"
    switch tokens.count {
    case 2:
      switch tokens[0] {
      case "आधा", "आधे": return 30
      case hindiKey("डेढ़"): return 90
      case hindiKey("ढाई"), hindiKey("अढाई"): return 150
      case "सवा": return 75
      case "पौन": return 45
      default:
        guard let count = (isHours ? hindiCounts : hindiRoundCounts)[tokens[0]] else { return nil }
        return taskLength(minutes: isHours ? count * 60 : count)
      }
    case 3:
      guard let count = number(tokens[1]) ?? hindiCounts[tokens[1]], count >= 1 else { return nil }
      switch tokens[0] {
      case hindiKey("साढ़े"): return taskLength(minutes: count * 60 + 30)
      case "सवा": return taskLength(minutes: count * 60 + 15)
      case hindiKey("पौने"): return taskLength(minutes: count * 60 - 15)
      default: return nil
      }
    default:
      return nil
    }
  }

  /// "5 बजकर 30 मिनट", which names a clock time as a count of minutes past the
  /// hour. It is kept in the title whole, so its "30 मिनट" is not read as a
  /// length.
  static let hindiBajkarPattern =
    #"\#(devanagariStart)\d{1,2}\s+बजकर\s+\d{1,2}\s+मिनट(?:\s+पर)?\#(devanagariEnd)"#
}
