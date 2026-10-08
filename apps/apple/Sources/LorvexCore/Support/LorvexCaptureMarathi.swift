import Foundation

extension LorvexCaptureVocabulary {
  /// Marathi, read for a user who reads Marathi in Devanagari. A word needs a
  /// boundary of Devanagari letters, signs, digits, and joiners on both sides
  /// (``devanagariStart``), so "आजकाल" (nowadays) and "उद्यान" (garden) hold no
  /// day, and a hyphen between two Devanagari words joins them. The danda (।)
  /// is punctuation. Marathi glues its case endings and postpositions to the
  /// word ("उद्याला", "सोमवारी", "शुक्रवारपर्यंत", "5 वाजताची"), so each rule
  /// lists the endings it reads, and a word with any other ending is another
  /// word and stays in the title ("उद्यादेखील", "सोमवारची मीटिंग"). A zero-width
  /// joiner or non-joiner typed before a listed ending changes nothing.
  ///
  /// The line is read in one form (``marathiForMatching(_:)``): Devanagari
  /// digits as Latin ones ("५ वाजता" is "5 वाजता"), the precomposed nukta
  /// letters as their base consonants, the candrabindu as the anusvara, the
  /// eyelash ra (ऱ) as ra, and the candra o (ऑ) as aa, so "पाँच" and "पांच" are
  /// one word, and "ऑगस्ट" and "आगस्ट" are one word. A nukta typed as a
  /// separate sign after its consonant, and a zero-width joiner after a
  /// virama, are tolerated in every word, so "दुसऱ्या" is one word however it
  /// is typed (ऱ, र with a nukta, or र with a virama before the ya), and the
  /// words whose nasal conjunct is spelled two ways are read both ways
  /// ("सप्टेंबर" and "सप्टेम्बर", "पंधरा" and "पन्धरा", "वीकेंड" and
  /// "वीकेन्ड"). The title keeps what was typed. Marathi written in Latin
  /// letters ("udya sakali") is not read.
  ///
  /// English is read beside Marathi, so a detail that needs no Marathi word is
  /// left to English, which reads its own "5pm", "17:30", "30 min", or "2h".
  /// Marathi does not write a clock time with the letter h, so "2h" beside
  /// Marathi stays a length.
  ///
  /// परवा means "the day after tomorrow" and also "the day before yesterday",
  /// and काल means "yesterday". This vocabulary reads परवा as the day after
  /// tomorrow and never reads काल or any other past day. A day phrase is left
  /// unread when its line says the day is past or not coming: a past-tense
  /// form anywhere in the line (होता, होती, होते, गेला, झाला, आला and their
  /// other genders and numbers: "उद्या मीटिंग होती"), or गेल्या, मागील,
  /// मागच्या, or an ordinal (पहिल्या, दुसऱ्या, तिसऱ्या, चौथ्या, पाचव्या,
  /// शेवटच्या) just before it ("गेल्या शुक्रवारी", "पहिल्या शुक्रवारी"). The
  /// rule holds for आज and the weekdays too. "केले" is no past marker ("केले
  /// जाईल" is a future passive), and neither is "आले", which is also the word
  /// for ginger.
  ///
  /// A weekday is a day only with its full name ending in वार: the short
  /// stems रवि, सोम, मंगळ, बुध, गुरु, शुक्र, and शनि are ordinary words or names,
  /// and so are the one-letter forms the system writes. A day phrase that a
  /// genitive follows (चा, ची, चे, च्या) is an attribute of a noun, not a
  /// plan ("सोमवारची मीटिंग", "उद्याची मीटिंग"), and "उद्या रात्रीचे जेवण" reads
  /// only उद्या.
  ///
  /// - Day: आज, उद्या, परवा, each maybe with a part of the day (सकाळी, दुपारी,
  ///   संध्याकाळी, सायंकाळी, रात्री, पहाटे: "आज रात्री", "उद्या सकाळी") or with
  ///   the ending च, ला, पासून, or साठी ("उद्याच", "उद्यापासून"); the weekday
  ///   names (रविवार, सोमवार, मंगळवार, बुधवार, गुरुवार or गुरूवार, शुक्रवार,
  ///   शनिवार), alone or with the ending ी (with च), ला, पासून, or साठी, or
  ///   after या or ह्या (this week's), पुढच्या or पुढील (next week's, weeks
  ///   starting on Monday), or येत्या, येणाऱ्या, or आगामी (the coming one),
  ///   with "आठवड्यात" between ("पुढच्या आठवड्यात शुक्रवारी") and maybe a part
  ///   of the day after; "पुढच्या आठवड्यात" alone (seven days ahead); "3
  ///   दिवसांनी", "तीन दिवसांनंतर", "एका दिवसाने", "2 आठवड्यांनी", "1
  ///   महिन्याने" (months counted on the calendar); the weekend, "वीकेंड",
  ///   "आठवडा अखेर", "आठवड्याच्या शेवटी", or "शनिवार-रविवार", alone or after या,
  ///   ह्या, पुढच्या, or येत्या; a date ("5 मे", "5 मे 2027", "तारीख 5 मे",
  ///   "दिनांक: 5 मे", "सोमवार, 5 ऑक्टोबर", "5 मे रोजी", "5 मेला", "15
  ///   तारखेला"; "15/10/2026", "15.10.2026", "15-10-2026", and "15.10." in
  ///   digits; "15/10" and "15.10" only after तारीख or दिनांक or before ला,
  ///   पासून, साठी, or रोजी). A weekday alone means the next such day, a full
  ///   week ahead when it names today, and "या मंगळवारी" is today when it
  ///   names today. "या आठवड्यात" alone names no single day and is not read.
  ///   The weekend is the coming Saturday (today on a Saturday or a Sunday)
  ///   and, after पुढच्या, the Saturday a week later. A date needs its day
  ///   number before the month name (जानेवारी, फेब्रुवारी, मार्च, एप्रिल, मे,
  ///   जून, जुलै, ऑगस्ट, सप्टेंबर, ऑक्टोबर, नोव्हेंबर, डिसेंबर, in the spellings
  ///   people type, and the short forms the system writes next to a day: जाने,
  ///   फेब्रु, एप्रि, ऑग, सप्टें, ऑक्टो, नोव्हें, डिसें, with or without a dot);
  ///   a month alone, a month before its day, a date in digits with no label
  ///   and no ending ("5/10"), a date the calendar lacks ("31 एप्रिल"), and the
  ///   months of the Marathi calendar (चैत्र, श्रावण, कार्तिक, ...) stay in
  ///   the title.
  /// - Date range: "3 ते 5 मार्च", "3 मार्च ते 5 मार्च", "3 मार्चपासून 5
  ///   मार्चपर्यंत", "30 जानेवारी ते 2 फेब्रुवारी", "3-5 मार्च", "3–5 मार्च",
  ///   each maybe with a year after a month and with पर्यंत or "दरम्यान" after
  ///   the end. The first day is the planned day and the last the due day, so
  ///   another day phrase stays in the title. A day written without its month
  ///   takes the month of the end, the end must be after the start ("5 ते 3
  ///   मार्च" stays in the title whole), and the end names a month, so "3 ते
  ///   5" is never a range of days. A day alone opens a range joined by a dash
  ///   only when the dash touches both sides: "Sprint 12 - 20 मार्च" names a
  ///   sprint and a date. A range in the past tense, or one that a genitive
  ///   follows ("5 ते 8 मेची सुट्टी"), may be an event the task only prepares
  ///   for: it stays in the title whole. A span of weekdays ("सोमवार ते
  ///   बुधवार", "शुक्रवार ते सोमवार", "सोमवारपासून बुधवारपर्यंत") plans the
  ///   coming first day and is due on the first last day after it. After दर or
  ///   beside the words for every day it is a repeat instead, and Monday to
  ///   Friday with none of them ("सोमवार ते शुक्रवार") stays in the title
  ///   whole, since it is a week of work as often as it is the working week.
  /// - Repeat: दररोज, रोज, नित्य, "दर दिवशी", "प्रत्येक दिवस", and दर, रोज, or
  ///   प्रत्येक with a part of the day ("रोज सकाळी", "दर संध्याकाळी", "दर
  ///   रात्री"), which keeps its part for an hour beside it ("रोज सकाळी 6
  ///   वाजता योग" is every day at 06:00); "दर आठवड्याला", "दर महिन्याला",
  ///   "दरमहा", "दरवर्षी", "दर वर्षी", "प्रत्येक आठवडा", "प्रत्येक महिना",
  ///   "प्रत्येक वर्षी"; "दर सोमवारी", "दर सोमवार", "दर सोमवारी आणि गुरुवारी",
  ///   "दर सोमवार, बुधवार आणि शुक्रवार", "दर दुसऱ्या सोमवारी", "दर
  ///   आठवड्याला सोमवारी", "सोमवारी आणि गुरुवारी दर आठवड्याला"; "दर 2
  ///   दिवसांनी", "दर दोन आठवड्यांनी", "दर 3 महिन्यांनी", "दर 5 वर्षांनी", "प्रत्येक
  ///   2 आठवडे", "दर दुसऱ्या दिवशी", "प्रत्येक इतर दिवशी"; "दिवसातून एकदा",
  ///   "आठवड्यातून एकदा", "महिन्यातून एकदा", "वर्षातून एकदा"; "दिवसाआड",
  ///   "आठवड्याआड", "महिन्याआड", "वर्षाआड"; "दर महिन्याच्या 5 तारखेला", "दरमहा 5
  ///   तारखेला", "दर महिन्याच्या पहिल्या तारखेला", "5 तारखेला दर महिन्याला"; "दर
  ///   वीकेंडला", "दर शनिवार-रविवारी"; the working days as "कामाच्या दिवशी",
  ///   "कामाच्या दिवसांत", or a span of weekdays with दर or the words for every day
  ///   ("दर सोमवार ते शुक्रवार", "सोमवार ते शुक्रवार दररोज"). An interval shorter
  ///   than a day ("दर 2 तासांनी") is no repeat, and a cadence word that
  ///   makes an attribute of a noun is none ("रोजचे काम", "दर महिन्याचा
  ///   खर्च"). "रोजा", "रोजगार", "रोजनिशी", and "रोजी" are other words. दर is
  ///   also the word for a rate, so "दर दिवस 500 रुपये" is read as a daily
  ///   repeat.
  /// - Due: a day before पर्यंत, पूर्वी, आधी, or अगोदर, glued or after a space,
  ///   or before "च्या आधी" ("शुक्रवारपर्यंत", "शुक्रवारच्या आधी", "उद्या
  ///   संध्याकाळपर्यंत", "5 मेपर्यंत", "परवापर्यंत"), after अंतिम, शेवटची,
  ///   शेवटचा, or शेवटचे with तारीख, दिनांक, or मुदत, after "देय तारीख", "देय
  ///   दिनांक", "देय:", or डेडलाइन ("अंतिम तारीख: 5 मे", "डेडलाइन शुक्रवार"),
  ///   or before "देय" ("शुक्रवारी देय", "5 मे रोजी देय", "आज देय"). A day
  ///   before a clock deadline ("शुक्रवारी संध्याकाळी 5 वाजेपर्यंत") is the due
  ///   day, and the clock with its part of the day stays in the title.
  ///   "आजपर्यंत" ("so far") is not read, nor is a deadline that a genitive
  ///   follows ("शुक्रवारपर्यंतचा रिपोर्ट").
  /// - Time: "5 वाजता", "5:30 वाजता", "5.30 वाजता", "साडेपाच वाजता" (5:30),
  ///   "सव्वापाच वाजता" (5:15), "पावणेसहा वाजता" (5:45), "दीड वाजता" (1:30),
  ///   "अडीच वाजता" (2:30), each maybe after ठीक, साधारण, सुमारे, जवळपास, or
  ///   अंदाजे, and with a genitive glued to वाजता that goes with it ("5
  ///   वाजताची मीटिंग"). A fraction word may stand apart from its hour ("साडे
  ///   पाच", "साडे 5"). The hour may be a number word from एक to बारा ("पाच
  ///   वाजता"); a number word without वाजता is never an hour. The ending ला
  ///   glued to a fraction or to दीड or अडीच is a time ("साडेतीनला", "दीडला"),
  ///   and glued to any other hour only after a part of the day ("संध्याकाळी
  ///   सहाला", "सकाळी 7 ला"). AM or PM after the hour is the system's own
  ///   writing ("3:30 PM वाजता"). A part of the day sets the hour and comes
  ///   before it ("सकाळी 9 वाजता", "संध्याकाळच्या 6 वाजता", and with ठीक, सुमारे,
  ///   or लवकर between them: "सकाळी लवकर 6 वाजता"); a part after वाजता is not
  ///   read. सकाळी and पहाटे are the morning (12 is no time), दुपारी is noon at
  ///   12 and the afternoon from 1 to 6, संध्याकाळी and सायंकाळी are the
  ///   evening, and रात्री runs past midnight: "रात्री 12 वाजता" is 00:00 of
  ///   the next day, "रात्री 2 वाजता" is 02:00 of the next day, and "रात्री 8
  ///   वाजता" is 20:00. "मध्यरात्री" is the midnight that ends the day. A part of the
  ///   day with a colon time and no वाजता ("संध्याकाळी 5:30", "रात्री 10.30") is
  ///   a time too. An hour on the 12-hour clock (1 to 12, no leading zero)
  ///   written with no part of the day beside it takes its half of the day from
  ///   the one part of the day the line names elsewhere: in its day phrase
  ///   ("उद्या सकाळी मीटिंग 6 वाजता" is 06:00), after दर, रोज, or प्रत्येक ("रोज
  ///   सकाळी 6 वाजता योग"), or in a noun ("रात्रीचे जेवण 8 वाजता" is 20:00,
  ///   "सकाळची सैर 6 वाजता" is 06:00). Two parts that differ leave the hour as it
  ///   reads alone, and an hour on the 24-hour clock (a leading zero, 0, or 13
  ///   and later) is read as written. An hour from 1 to 6 with no part of the
  ///   day anywhere in the line is the afternoon, as in the other languages ("5
  ///   वाजता" is 17:00, "7 वाजता" is 07:00), unless written with a leading zero
  ///   ("06:30 वाजता"). A range: "3 ते 5 वाजता", "सकाळी 9 ते 11 वाजता", "3
  ///   वाजेपासून 5 वाजेपर्यंत", "दोन ते चार वाजता", "2-4 वाजता", "14:00 ते 16:00",
  ///   "सकाळी 9 वाजेपासून संध्याकाळी 5 वाजेपर्यंत"; the end carries वाजता or
  ///   वाजेपर्यंत, so "3 ते 5" is no range. A clock time that is a bound stays
  ///   in the title whole: "5 वाजेपर्यंत", "संध्याकाळी 5 वाजेपूर्वी", "5
  ///   वाजण्यापूर्वी", "5 वाजल्यानंतर", "18:00 पर्यंत", "3 PM पर्यंत". A number
  ///   before a percent sign, a currency sign, or a currency word is never a
  ///   time.
  /// - Length: "30 मिनिटे", "30 मिनिटं", "2 तास", "1.5 तास", "1 तास 30 मिनिटे",
  ///   "अर्धा तास", "पाऊण तास" (45 minutes), "सव्वा तास" (75), "दीड तास",
  ///   "अडीच तास", "साडेतीन तास", "पावणेदोन तास", "दोन तास", "वीस मिनिटे", each
  ///   maybe after सुमारे, साधारण, जवळपास, or अंदाजे, in the singular or the
  ///   plural, and with a genitive or साठी glued to the unit that goes with it
  ///   ("30 मिनिटांची मीटिंग" is a meeting of 30 minutes, "2 तासांसाठी" is for 2
  ///   hours). An amount before आत, आधी, अगोदर, नंतर, पूर्वी, or दरम्यान, or
  ///   after दर, प्रत्येक, किमान, "कमीत कमी", "जास्तीत जास्त", or "दिवसातून",
  ///   names a moment, an interval, or a bound, not a length ("2 तास आधी", "दर 2
  ///   तास", "2 तासांच्या आत", "दिवसातून 2 तास"), and neither is a side of a range
  ///   ("2 ते 3 तास", "2-3 तास"): each stays whole in the title. An amount
  ///   whose unit has any other ending ("2 तासांनी", "30 मिनिटांमध्ये") is no
  ///   length, and "तास" alone is none.
  /// - Priority: उच्च प्राधान्य, मध्यम प्राधान्य, निम्न प्राधान्य (also
  ///   उच्चतम, सर्वोच्च, जास्त, सामान्य, साधारण, निम्नतम, कमी, and "सर्वात कमी",
  ///   and प्राथमिकता for प्राधान्य), each also after the word ("प्राधान्य:
  ///   उच्च") and maybe followed by "ाने" ("उच्च प्राधान्याने"); तातडीचे,
  ///   अत्यावश्यक, अर्जंट, ताबडतोब, or महत्त्वाचे (with the endings of the
  ///   other genders and numbers; maybe after खूप, अतिशय, अत्यंत, फारच, or
  ///   फार) at the end of the line, and the same words opening it before a
  ///   colon or comma ("तातडीचे: रिपोर्ट पाठवा"). These are ordinary
  ///   adjectives too, so "तातडीची औषधे आणणे" and "रिपोर्ट पाठवा तातडीचे आहे"
  ///   stay in the title, and so does "उच्च प्राधान्य असलेली कामे".
  static let marathi = marathiVocabulary(besideHindi: false)

  /// Marathi for a user who reads Hindi too. Marathi and Hindi share some words
  /// (आज, the weekday names, मार्च and जून, वीकेंड, प्रत्येक, रोज, नित्य,
  /// "उच्च", "उच्च प्राथमिकता"), and Hindi writes the words that go with them
  /// as separate words ("आज की रात", "सोमवार को", "प्रत्येक सोमवार को", "उच्च
  /// प्राथमिकता से"), which Marathi would leave behind in the title if it took
  /// the shared word alone. Here Marathi leaves a priority, a date range, a
  /// repeat, or a day to Hindi whenever such a Hindi word follows it
  /// (``marathiHindiAfter``), and a weekday whenever one of Hindi's words for
  /// "this", "next", or "coming" stands before it (``marathiHindiBefore``). The
  /// words only Marathi has ("उद्या", "वाजता", "दर सोमवारी") are read as ever,
  /// and a line that names a day in both languages is read by Marathi, which
  /// is tried first.
  static let marathiBesideHindi = marathiVocabulary(besideHindi: true)

  private static func marathiVocabulary(besideHindi: Bool) -> LorvexCaptureVocabulary {
    LorvexCaptureVocabulary(
      readingForm: marathiForMatching,
      priority: [
        marathiRule(marathiGuarded(marathiPriorityPattern, besideHindi: besideHindi), read: marathiPriority)
      ],
      dateRange: [
        marathiRule(marathiGuarded(marathiDateRangePattern, besideHindi: besideHindi), read: marathiDateRange),
        marathiRule(marathiWeekdayRangePattern, read: marathiWeekdayRange),
      ],
      keptInTitle: [
        marathiRule(marathiDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
        marathiRule(marathiLengthPattern) { marathiDeclinesLength($0) ? true : nil },
      ],
      length: [marathiRule(marathiLengthPattern, read: marathiLength)],
      time: [
        marathiRule(marathiTimeRangePattern, read: marathiTimeRange),
        marathiRule(marathiColonTimeRangePattern, read: marathiTimeRange),
        marathiRule(marathiTimePattern, read: marathiTime),
        marathiRule(marathiAtHourPattern, read: marathiAtHour),
        marathiRule(marathiPartColonTimePattern, read: marathiPartColonTime),
        marathiRule(marathiMidnightPattern) { _ in ClockTime(minutes: 0, isAfterMidnight: true) },
      ],
      repeats: marathiRepeatRules(besideHindi: besideHindi),
      due: [marathiRule(marathiDuePattern, read: marathiDue)],
      when: [marathiRule(marathiWhenPattern(besideHindi: besideHindi), read: marathiWhen)])
  }

  /// `pattern` with a lookahead after it that fails where a Hindi word follows
  /// (``marathiHindiAfter``), when `besideHindi`: the phrase is Hindi's to read
  /// or to leave. The alternatives of `pattern` all take the lookahead.
  static func marathiGuarded(_ pattern: String, besideHindi: Bool) -> String {
    besideHindi ? "(?:\(pattern))\(marathiHindiAfter)" : pattern
  }

  // MARK: - Reading form and patterns

  /// The line with each digit and letter read in one form: the Devanagari
  /// digits (०-९) as ASCII digits, the precomposed nukta letters (क़ ख़ ग़ ज़
  /// ड़ ढ़ फ़ य़) as their base consonants, the candrabindu (ँ) as the anusvara
  /// (ं), the eyelash ra (ऱ) as ra (र), and the candra o (ऑ) as aa (आ), so
  /// "ऑगस्ट" and "आगस्ट" are one word. A nukta typed as a separate sign stays
  /// where it was typed: a pattern, written in the base letters, tolerates it
  /// after every consonant that can carry one (``marathi(_:)``). Each
  /// replacement is one UTF-16 unit for one, so a match range in the result is
  /// the same range in `line`.
  static func marathiForMatching(_ line: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in line.unicodeScalars { scalars.append(marathiReading(of: scalar)) }
    return String(scalars)
  }

  private static func marathiReading(of scalar: Unicode.Scalar) -> Unicode.Scalar {
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
    case "\u{0931}": "\u{0930}"
    case "\u{0911}": "\u{0906}"
    default: scalar
    }
  }

  /// The consonants that name a nasal sound: ङ ञ ण न म. Before a stop
  /// consonant (क to भ, the nasals themselves left out), each is written
  /// either as the anusvara or as itself with a virama ("सप्टेंबर" and
  /// "सप्टेम्बर", "पंधरा" and "पन्धरा"). Before a semivowel, a sibilant, or ह it
  /// is part of a conjunct that the anusvara does not stand for ("महिन्या",
  /// "म्हणून").
  private static let marathiNasals: Set<Unicode.Scalar> = ["\u{0919}", "\u{091E}", "\u{0923}", "\u{0928}", "\u{092E}"]

  /// Whether `scalar` is a stop consonant, क to भ without the nasals.
  private static func marathiIsStop(_ scalar: Unicode.Scalar) -> Bool {
    (0x0915...0x092D).contains(scalar.value) && !marathiNasals.contains(scalar)
  }

  /// `text` as a reader compares a word: without its nukta signs and
  /// zero-width joiners, and with a nasal consonant and virama before a stop
  /// consonant read as the anusvara. `text` is already in the reading form.
  /// Comparisons of Devanagari text go through scalars or whole words: a
  /// `Character` is a grapheme cluster ("घं" is one), so `hasPrefix("घ")` does
  /// not match "घंटा".
  static func marathiBare(_ text: String) -> String {
    let scalars = Array(
      text.unicodeScalars.filter { $0 != "\u{093C}" && $0 != "\u{200C}" && $0 != "\u{200D}" })
    var result = String.UnicodeScalarView()
    var index = 0
    while index < scalars.count {
      if index + 2 < scalars.count, marathiNasals.contains(scalars[index]), scalars[index + 1] == "\u{094D}",
        marathiIsStop(scalars[index + 2])
      {
        result.append("\u{0902}")
        index += 2
      } else {
        result.append(scalars[index])
        index += 1
      }
    }
    return String(result)
  }

  /// A matched phrase as a reader compares it: as ``marathiBare(_:)`` leaves
  /// it, each run of spaces as one, hyphens read as spaces.
  static func marathiPhrase(_ text: String) -> String {
    normalizedPhrase(marathiBare(text))
  }

  /// A word written in a vocabulary table, as ``marathiPhrase(_:)`` leaves a
  /// matched word, whichever way the table spells it.
  static func marathiKey(_ word: String) -> String {
    marathiBare(marathiForMatching(word))
  }

  /// Whether the scalars of `key` start with the scalars of `prefix`. Both are
  /// in the form ``marathiKey(_:)`` leaves them.
  static func marathiHasPrefix(_ key: String, _ prefix: String) -> Bool {
    key.unicodeScalars.starts(with: prefix.unicodeScalars)
  }

  /// `pattern`, written in the base letters of its words, ready to match a
  /// line in the reading form.
  ///
  /// A consonant that can carry a nukta (क ख ग ज ड ढ फ य, and र for the
  /// eyelash ra typed as a base letter and a nukta) may be followed by one, a
  /// virama may be followed by zero-width joiners, an anusvara also matches a
  /// nasal consonant with a virama ("सप्टेंबर" matches "सप्टेम्बर"), and a
  /// quantifier that follows such a letter applies to the letter with its
  /// extras. A middle dot (·) marks the boundary between a word and an ending
  /// glued to it, where a zero-width joiner or non-joiner may have been typed.
  /// A nukta, joiner, or precomposed nukta letter typed in `pattern` is read like
  /// the base letter. Escapes and character sets pass through, the letters in
  /// a set read through the reading form. A pattern is expanded once, by
  /// ``marathiRule(_:read:)``, never in parts that another pattern then
  /// embeds.
  static func marathi(_ pattern: String) -> String {
    let quantifiers: Set<Unicode.Scalar> = ["?", "*", "+", "{"]
    let carriesNukta: Set<Unicode.Scalar> = [
      "\u{0915}", "\u{0916}", "\u{0917}", "\u{091C}", "\u{0921}", "\u{0922}", "\u{092B}", "\u{092F}", "\u{0930}",
    ]
    let joiners = #"[\x{200C}\x{200D}]{0,2}"#
    let nasalConsonants = #"[\x{0919}\x{091E}\x{0923}\x{0928}\x{092E}]"#
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
        result.unicodeScalars.append(marathiReading(of: scalar))
      } else if scalar == "[" {
        isInSet = true
        result.unicodeScalars.append(scalar)
      } else if scalar == "\u{00B7}" {
        result += joiners
      } else {
        let reading = marathiReading(of: scalar)
        var unit = String(Character(reading))
        if carriesNukta.contains(reading) {
          unit += #"\x{093C}?"#
        } else if reading == "\u{094D}" {
          unit += joiners
        } else if reading == "\u{0902}" {
          unit = "(?:\u{0902}|\(nasalConsonants)\u{094D}\(joiners))"
        }
        let isQuantified = index + 1 < scalars.count && quantifiers.contains(scalars[index + 1])
        result += unit.count > 1 && isQuantified && !unit.hasPrefix("(?:") ? "(?:\(unit))" : unit
      }
    }
    return result
  }

  /// A rule whose `pattern` is written in base letters (see ``marathi(_:)``).
  static func marathiRule<Value>(_ pattern: String, read: @escaping @Sendable (Match) -> Value?) -> Rule<Value> {
    Rule(pattern: marathi(pattern), read: read)
  }

  /// Whether `pattern`, written in base letters, matches somewhere in `text`,
  /// which is in the reading form.
  static func marathiFinds(_ pattern: String, in text: String) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(marathi(pattern)) else { return false }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  // MARK: - Boundaries and words around a detail

  /// What may follow a clock time: no Devanagari letter, vowel sign, digit, or
  /// colon (the word or the number goes on), no decimal fraction, no percent
  /// or currency sign or word with or without a space before it (the number
  /// is an amount: "20%", "500 रुपये"), no dash before a digit (a range
  /// written with a dash and no वाजता is English's), and no AM or PM after it.
  static let marathiTimeEnd =
    #"(?![\p{Devanagari}\p{M}\p{N}\x{200C}\x{200D}:]|[.,]\p{N}|\s*[%\p{Sc}]|\s*(?:रुपये|रुपया|रु\.?|डॉलर|पैसे)\#(devanagariEnd)|\s*[-–—]\s*\d)\#(noMeridiemAfter)"#

  /// What may follow a date: no Devanagari letter, vowel sign, digit, or
  /// colon, and no decimal fraction.
  static let marathiDateEnd = #"(?![\p{Devanagari}\p{M}\p{N}\x{200C}\x{200D}:]|[.,]\p{N})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let marathiNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// The word just before `match` as a reader compares it, or nil when the
  /// match opens the line or punctuation comes first.
  static func marathiWordBefore(_ match: Match) -> String? {
    guard let word = wordBefore(match).map(marathiBare), !word.isEmpty else { return nil }
    return word
  }

  /// The words of `text`, as letters only and as ``marathiBare(_:)`` leaves
  /// them.
  static func marathiWords(in text: String) -> [String] {
    text.split(whereSeparator: { !$0.isLetter }).map { marathiBare(String($0)) }
  }

  // MARK: - Counts

  /// The numerals one to twelve, which stand before a counted noun and name an
  /// hour before वाजता, keyed as ``marathiKey(_:)`` leaves them.
  static let marathiCounts: [String: Int] = {
    let spellings: [(Int, [String])] = [
      (1, ["एक"]), (2, ["दोन"]), (3, ["तीन"]), (4, ["चार"]), (5, ["पाच", "पांच"]), (6, ["सहा"]), (7, ["सात"]),
      (8, ["आठ"]), (9, ["नऊ"]), (10, ["दहा"]), (11, ["अकरा"]), (12, ["बारा"]),
    ]
    var counts: [String: Int] = [:]
    for (value, words) in spellings {
      for word in words { counts[marathiKey(word)] = value }
    }
    return counts
  }()

  /// The numerals of an amount of minutes or days: the counts above and the
  /// round numbers up to sixty.
  static let marathiRoundCounts: [String: Int] = {
    let spellings: [(Int, [String])] = [
      (15, ["पंधरा"]), (20, ["वीस"]), (25, ["पंचवीस"]), (30, ["तीस"]), (40, ["चाळीस"]), (45, ["पंचेचाळीस"]),
      (50, ["पन्नास"]), (60, ["साठ"]),
    ]
    var counts = marathiCounts
    for (value, words) in spellings {
      for word in words { counts[marathiKey(word)] = value }
    }
    return counts
  }()

  /// The numerals that name an hour, as a pattern.
  static var marathiCountWords: String { alternation(of: Array(marathiCounts.keys)) }

  /// The numerals of an amount of minutes or days, as a pattern.
  static var marathiRoundCountWords: String { alternation(of: Array(marathiRoundCounts.keys)) }

  // MARK: - Priority

  /// Group 1: a written priority, with its level before or after the word
  /// "प्राधान्य" or "प्राथमिकता" and maybe "ाने" glued to it ("उच्च प्राधान्याने");
  /// an urgent word has no group. A level word with "असलेले" or "असणारे" after
  /// the priority describes a noun ("उच्च प्राधान्य असलेली कामे") and is no
  /// priority.
  private static var marathiPriorityPattern: String {
    let level = #"सर्वोच्च|उच्चतम|उच्च|जास्त|मध्यम|माध्यम|सामान्य|साधारण|सर्वात\s+कमी|निम्नतम|निम्न|कमी"#
    let word = "प्राधान्य|प्राथमिकता"
    let urgent =
      #"तातडी(?:चा|ची|चे|च्या|ने)?|अत्यावश्यक|अर्जे?ंट|ताबडतोब|महत्(?:त्)?वाच(?:ा|ी|े)"#
    let intensifier = #"(?:(?:खूप|अतिशय|अत्यंत|फारच|फार)\s+)?"#
    let described = #"(?!\s+(?:असले(?:ली|ले|ला|ल्या)|असणा(?:री|रे|रा|र्या))\#(devanagariEnd))"#
    return
      #"\#(devanagariStart)((?:\#(level))\s*(?:\#(word))|(?:\#(word))\s*[:：]?\s*(?:\#(level)))(?:·ाने)?\#(devanagariEnd)\#(described)|(?<=\s)\#(intensifier)(?:\#(urgent))\#(devanagariEnd)(?=\s*[।.!]?\s*$)|^\s*(?:\#(urgent))\#(devanagariEnd)(?=\s*[:：,，])"#
  }

  private static func marathiPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1).map(marathiPhrase) else { return .p1 }
    let words = Set(marathiWords(in: phrase))
    if !words.isDisjoint(with: ["मध्यम", "माध्यम", "सामान्य", "साधारण"].map(marathiKey)) { return .p2 }
    if !words.isDisjoint(with: ["निम्न", "निम्नतम", "कमी"].map(marathiKey)) { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "30 मिनिटे", "2 तास", "1.5 तास", "1 तास 30 मिनिटे", "अर्धा तास", "दीड तास",
  /// "अडीच तास", "सव्वा तास", "पाऊण तास", "साडेतीन तास", "पावणेदोन तास", "दोन
  /// तास", "वीस मिनिटे", each maybe after "सुमारे", "साधारण", "जवळपास", or
  /// "अंदाजे", in the singular or the plural ("1 मिनिट", "30 मिनिटे", "30
  /// मिनिटं"), and maybe with a genitive or "साठी" glued to the unit, which goes
  /// with it ("30 मिनिटांची मीटिंग" is a meeting of 30 minutes, "2 तासांसाठी" is
  /// for 2 hours). Groups: 1 a word that makes the length approximate; 2 a word
  /// that makes the amount a bound or a rate ("किमान 2 तास", "दर 2 तास",
  /// "दिवसातून 2 तास"); 3 the hours of an amount with a unit and 4 its minutes; 5 minutes;
  /// 6 a length in words; 7 a word after the amount that makes it a moment, the
  /// past, or a bound ("2 तासांच्या आत", "2 तास आधी"). A match with group 2 or
  /// 7 is no length: ``marathiLength(_:)`` declines it and a keep rule claims
  /// it, so the amount stays whole in the title. Any other ending glued to
  /// the unit ("2 तासांनी", "30 मिनिटांमध्ये") leaves the unit unread. The amount
  /// may not follow a digit, a colon, or a separator, and it may not be a side
  /// of a range ("2-3 तास", "2 ते 3 तास", "5 मिनिटे ते 10 मिनिटे").
  static var marathiLengthPattern: String {
    let ending = #"(?:ां|ा)·(?:चा|ची|चे|च्या|साठी)"#
    let hourNoun = #"तास(?:\#(ending))?"#
    let minuteNoun = #"मिन[िी]ट(?:\#(ending)|े|ं)?"#
    let opener =
      #"(?:(?:(सुमारे|साधारण|जवळपास|अंदाजे)|(किमान|कमीत\s*कमी|जास्तीत\s*जास्त|कमाल|दर|प्रत्येक|(?:दिवसा|आठवड्या|महिन्या|वर्षा)तून))\s+)?"#
    let boundaries = #"(?<![\p{N}:.,])(?<!\p{N}\s?[-–—]\s?)"#
    let hours =
      #"(\d+(?:\.\d+)?)\s*\#(hourNoun)(?:\s+(?:आणि\s+)?(\d{1,2})\s*\#(minuteNoun))?"#
    let minutes = #"(\d+)\s*\#(minuteNoun)"#
    let words =
      #"(अर्धा\s+\#(hourNoun)|अर्ध्या\s+तासा·(?:चा|ची|चे|च्या|साठी)|(?:द[िी]ड|अड[िी]च|सव्वा|पा[ऊउ]ण)\s+\#(hourNoun)|(?:साडे|सव्वा|पावणे)\s*(?:\d{1,2}|\#(marathiCountWords))\s+\#(hourNoun)|(?:\#(marathiCountWords))\s+\#(hourNoun)|(?:\#(marathiRoundCountWords))\s+\#(minuteNoun))"#
    let trailing = #"(?:\s+(आत|आधी|अगोदर|नंतर|पूर्वी|दरम्यान)\#(devanagariEnd))?"#
    return
      #"\#(devanagariStart)\#(opener)(?:\#(boundaries)(?:\#(hours)|\#(minutes))|\#(words))\#(devanagariEnd)(?!\s*[-–—]\s*\d|\s+ते\s+\d)\#(trailing)"#
  }

  /// True for a match that is no length: a bound or a rate ("किमान 2 तास",
  /// "दिवसातून 2 तास"), a moment, the past, or a bound ("2 तास आधी"), or the
  /// end of a range of amounts ("2 ते 3 तास").
  static func marathiDeclinesLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(7) != nil || marathiIsRangeEnd(match)
  }

  /// Whether the text before `match` ends with a number or a unit and "ते",
  /// which makes the amount the end of a range ("2 ते 3 तास", "5 मिनिटे ते 10
  /// मिनिटे").
  private static func marathiIsRangeEnd(_ match: Match) -> Bool {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return false }
    let before = String(match.source[..<start])
    return marathiFinds(#"(?:\d|मिन[िी]ट\p{M}*|तास\p{M}*)\s+ते\s+$"#, in: before)
  }

  private static func marathiLength(_ match: Match) -> Int? {
    if marathiDeclinesLength(match) { return nil }
    if let hours = match.group(3).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(4).flatMap(number) ?? 0))
    }
    if let minutes = match.group(5).flatMap(number) { return taskLength(minutes: minutes) }
    guard let phrase = match.group(6).map(marathiPhrase) else { return nil }
    let tokens = phrase.split(separator: " ").map(String.init)
    guard let unit = tokens.last, tokens.count >= 2 else { return nil }
    let isHours = marathiHasPrefix(unit, marathiKey("तास"))
    let amount = tokens.dropLast().joined()
    if isHours {
      switch amount {
      case marathiKey("अर्धा"), marathiKey("अर्ध्या"): return 30
      case marathiKey("दीड"), marathiKey("दिड"): return 90
      case marathiKey("अडीच"), marathiKey("अडिच"): return 150
      case marathiKey("सव्वा"): return 75
      case marathiKey("पाऊण"), marathiKey("पाउण"): return 45
      default: break
      }
      guard let (fraction, count) = marathiFraction(of: amount) else {
        return marathiCounts[amount].flatMap { taskLength(minutes: $0 * 60) }
      }
      switch fraction {
      case marathiKey("साडे"): return taskLength(minutes: count * 60 + 30)
      case marathiKey("सव्वा"): return taskLength(minutes: count * 60 + 15)
      default: return taskLength(minutes: count * 60 - 15)
      }
    }
    return marathiRoundCounts[amount].flatMap { taskLength(minutes: $0) }
  }

  /// The fraction word and the hour count of an amount such as "साडेतीन" or
  /// "सव्वादोन" (one word, as ``marathiKey(_:)`` leaves it), or nil when `text`
  /// is no fraction word followed by a count of 1 to 12.
  static func marathiFraction(of text: String) -> (fraction: String, count: Int)? {
    for fraction in ["साडे", "सव्वा", "पावणे"].map(marathiKey) where marathiHasPrefix(text, fraction) {
      let rest = String(text.unicodeScalars.dropFirst(fraction.unicodeScalars.count))
      guard let count = number(rest) ?? marathiCounts[rest], (1...12).contains(count) else { return nil }
      return (fraction, count)
    }
    return nil
  }
}
