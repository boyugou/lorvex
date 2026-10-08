import Foundation

extension LorvexCaptureVocabulary {
  /// Telugu, read for a user who reads Telugu in the Telugu script (India). A
  /// word needs a boundary of Telugu letters, signs, digits, and joiners on both
  /// sides (``teluguStart``), so "ఆరోజు" (that day) and "రేపటికల్లా" hold no
  /// planned day, and a hyphen between two Telugu words joins them. Telugu glues
  /// its case endings to the word ("సోమవారానికి", "15న", "5కి", "గంటలకు"), so
  /// each rule lists the endings it reads, and a word with any other ending is
  /// another word and stays in the title ("సోమవారపు మీటింగ్", "రేపటి పని"). A
  /// zero-width joiner or non-joiner typed after a virama or between a word and
  /// a listed ending changes nothing; one glued to the end of a finished word
  /// makes it part of a longer word, which stays in the title.
  ///
  /// The line is read in one form (``teluguForMatching(_:)``): the Telugu
  /// digits as Latin ones ("౫గంటలకు" is "5గంటలకు"). The vowel sign ై (U+0C48) is
  /// read typed as one sign or as the two signs it is made of (U+0C46 and
  /// U+0C56), a virama accepts joiners on either side, and ఉదయం and ఉదయము,
  /// శుక్రవారం and శుక్రవారము, అక్టోబర్ and అక్టోబరు, జులై and జూలై, తేదీ and
  /// తేది, ఐదు and అయిదు, and the other spellings people type are each one word.
  /// The title keeps what was typed. Telugu written in Latin letters ("repu
  /// udayam") is not read.
  ///
  /// English is read beside Telugu, so a detail that needs no Telugu word is
  /// left to English, which reads its own "5pm", "17:30", "30 min", or "2h".
  /// Telugu does not write a clock time with the letter h, so "2h" beside
  /// Telugu stays a length.
  ///
  /// Telugu names yesterday (నిన్న), the day before (మొన్న), tomorrow (రేపు),
  /// and the day after (ఎల్లుండి) with four different words, so no day word
  /// needs a guess about its direction and the past days are never read. A day
  /// phrase is still left unread when its line says the day is past or not the
  /// coming one: a past-tense form anywhere in the line (చేశాను, వెళ్లాను,
  /// జరిగింది, పంపాను, ముగిసింది, and the other listed forms: "రేపు మీటింగ్
  /// జరిగింది", "శుక్రవారం గడువు ముగిసింది"), or గత,
  /// పోయిన, మునుపటి, ఆ, ఆఖరి, చివరి, or an ordinal (మొదటి, రెండవ, మూడవ) just
  /// before it ("గత శుక్రవారం", "మొదటి శుక్రవారం"). A day in its genitive (-టి,
  /// -పు) or followed by నాటి is an attribute of a noun, not a plan ("రేపటి
  /// మీటింగ్", "సోమవారపు మీటింగ్", "శుక్రవారం నాటి మీటింగ్").
  ///
  /// A weekday is a day only with its full name ending in వారం: the short
  /// forms ఆది, సోమ, మంగళ, బుధ, గురు, శుక్ర, and శని are ordinary words,
  /// names, and planets, and so are the one-syllable forms the system writes.
  ///
  /// - Day: ఈరోజు, ఈ రోజు, ఇవాళ, ఇవ్వాళ, నేడు, రేపు, ఎల్లుండి, each maybe with
  ///   the emphatic ే ("రేపే"), the dative -కి or -కు ("ఈరోజుకి", "రేపటికి",
  ///   "ఎల్లుండికి": the day a task is planned for), or నుండి or నుంచి after it
  ///   ("రేపటి నుండి", "ఈరోజు నుండి": from that day on), and maybe with a part
  ///   of the day (ఉదయం, మధ్యాహ్నం, సాయంత్రం, రాత్రి, అర్ధరాత్రి, తెల్లవారుజామున,
  ///   each with its spellings and the endings -ాన్నే, -ాన, and -కి: "రేపు
  ///   ఉదయం", "ఈరోజు రాత్రి"), also with ఈ before it as one phrase for today
  ///   ("ఈ రాత్రి", "ఈ సాయంత్రం"); the weekday names (ఆదివారం, సోమవారం,
  ///   మంగళవారం, బుధవారం, గురువారం, శుక్రవారం, శనివారం), alone, with నాడు or
  ///   రోజున or రోజు after them, with the dative ("సోమవారానికి"), emphatic
  ///   ("సోమవారమే"), or with నుండి after them, or after ఈ (this week's), వచ్చే or
  ///   రాబోయే (the coming one), or తదుపరి, తర్వాతి, or తరువాతి (next week's, weeks
  ///   starting on Monday), with "వారం" between ("ఈ వారం శుక్రవారం", "వచ్చే
  ///   వారం సోమవారం": this and next week's), and maybe a part of the day after;
  ///   "వచ్చే వారం" and its likes alone (seven days ahead); "3 రోజుల్లో", "3 రోజుల
  ///   తర్వాత", "రెండు వారాల్లో", "1 నెల తర్వాత" (months counted on the
  ///   calendar); the weekend (వారాంతం, వీకెండ్, "శని ఆదివారాలు", "శనివారం మరియు
  ///   ఆదివారం"), alone or after ఈ, వచ్చే, రాబోయే, or తదుపరి; a date ("15
  ///   అక్టోబర్", "15వ తేదీ అక్టోబర్ 2026", "అక్టోబర్ 15", "అక్టోబర్ 15వ తేదీన",
  ///   "సోమవారం, 5 అక్టోబర్", "అక్టోబర్ 15న", "15వ తేదీన", "15న"; "15/10/2026",
  ///   "15.10.2026", "15-10-2026", and "15.10." in digits; "15/10" and "15.10"
  ///   only after తేదీ or before న, కి, కు, or నుండి), with నుండి, కోసం, or నాడు
  ///   after it. A weekday alone means the next such day, a full week ahead when
  ///   it names today, and "ఈ మంగళవారం" is today when it names today. "ఈ వారం"
  ///   alone names no single day and is not read. The weekend is the coming
  ///   Saturday (today on a Saturday or a Sunday) and, after తదుపరి, the
  ///   Saturday a week later. A date needs its day number beside the month name
  ///   (జనవరి, ఫిబ్రవరి, మార్చి, ఏప్రిల్, మే, జూన్, జులై, ఆగస్టు, సెప్టెంబర్,
  ///   అక్టోబర్, నవంబర్, డిసెంబర్, and the short forms the system writes next to
  ///   a day: జన, ఫిబ్ర, ఏప్రి, ఆగ, సెప్టెం, అక్టో, నవం, డిసెం, after a day
  ///   number only); a month alone, a date in digits with no label and no ending
  ///   ("5/10"), and a date the calendar lacks ("31 ఏప్రిల్") stay in the title.
  /// - Date range: "అక్టోబర్ 3 నుండి 5 వరకు", "3 నుండి 5 అక్టోబర్ వరకు", "3
  ///   అక్టోబర్ నుండి 5 అక్టోబర్ వరకు", "అక్టోబర్ 3-5", "3-5 అక్టోబర్", with నుంచి
  ///   for నుండి and a year after a month. వరకు, వరకూ, or దాకా follows the end and
  ///   may be left out when the end names its month. The first day is the planned
  ///   day and the last the due day, so another day phrase stays in the title. A
  ///   day written without its month takes the month of the other side, the end
  ///   must be after the start ("5 నుండి 3 అక్టోబర్" stays in the title whole), a
  ///   range with no month ("3 నుండి 5 వరకు") is never a range of days, and an end
  ///   without a month needs వరకు or a dash. A day alone opens a range joined by
  ///   a dash only when the dash touches both sides: "Sprint 12 - 20 మే" names a
  ///   sprint and a date. A range in the past tense stays in the title whole. A
  ///   span of weekdays ("సోమవారం నుండి బుధవారం వరకు", "శుక్రవారం నుండి సోమవారం")
  ///   plans the coming first day and is due on the first last day after it.
  ///   After ప్రతి or beside the words for every day it is a repeat instead, and
  ///   Monday to Friday with none of them stays in the title whole, since it is
  ///   a week of work as often as it is the working week.
  /// - Repeat: ప్రతిరోజు, ప్రతిరోజూ, ప్రతి రోజు, రోజూ, and those with a part of the
  ///   day ("ప్రతి ఉదయం", "రోజూ రాత్రి"), which keeps its part for an hour beside
  ///   it ("రోజూ ఉదయం 6 గంటలకు యోగా" is every day at 06:00); "ప్రతి వారం", "ప్రతి
  ///   నెల", "ప్రతి సంవత్సరం", "ప్రతి ఏడాది", "ప్రతి ఏటా"; "ప్రతి సోమవారం", "ప్రతి
  ///   సోమవారం మరియు గురువారం", "ప్రతి సోమవారం, బుధవారం, శుక్రవారం", "సోమవారాల్లో",
  ///   "ప్రతి వారం సోమవారం", "సోమవారం ప్రతి వారం"; "ప్రతి 2 రోజులకు", "ప్రతి 3 వారాలు",
  ///   "ప్రతి మూడు నెలలకు", "ప్రతి 5 సంవత్సరాలు", "2 రోజులకోసారి", "3 నెలలకు
  ///   ఒకసారి", "రోజు విడిచి రోజు" (every other day); "రోజుకు ఒకసారి", "వారానికి
  ///   ఒకసారి", "నెలకోసారి", "సంవత్సరానికి ఒకసారి"; "ప్రతి నెల 5వ తేదీన", "ప్రతి
  ///   నెల 5న"; "ప్రతి వారాంతం", "వారాంతాల్లో", "ప్రతి శనివారం మరియు ఆదివారం"; the
  ///   working days as "పనిరోజుల్లో", "ప్రతి పనిరోజు", or "పని దినాల్లో"; a span of
  ///   weekdays with ప్రతి or the words for every day ("ప్రతి సోమవారం నుండి
  ///   శుక్రవారం వరకు", "సోమవారం నుండి శుక్రవారం వరకు ప్రతిరోజూ"); and రోజువారీ,
  ///   వారంవారీ, నెలవారీ, or సంవత్సరంవారీ at the end of the line, before a colon
  ///   or comma, or with "ప్రాతిపదికన" or "గా", since they are ordinary adjectives
  ///   too ("రోజువారీ రిపోర్ట్" is a daily report). An interval shorter than a
  ///   day ("ప్రతి 2 గంటలకు"), and "3 వారాంతాల్లో" or "3 పనిరోజుల్లో" (a count of
  ///   weekends or workdays), are no repeat. ప్రతి is also the word for a rate,
  ///   so "ప్రతి రోజు 500 రూపాయలు" is read as a daily repeat.
  /// - Due: a day before వరకు, వరకూ, దాకా, లోగా, లోపు, లోపల, కల్లా, or నాటికి
  ///   ("శుక్రవారం వరకు", "శుక్రవారంలోగా", "రేపటి లోపు", "అక్టోబర్ 15 నాటికి",
  ///   "శుక్రవారానికల్లా", "ఈరోజులోగా", "ఈ రాత్రి వరకు"); after గడువు, గడువు
  ///   తేదీ, చివరి తేదీ, ఆఖరి తేదీ, or డెడ్‌లైన్ ("గడువు: శుక్రవారం", "గడువు తేదీ
  ///   అక్టోబర్ 15"); and before గడువు ("శుక్రవారం గడువు", the way the app writes
  ///   "Due Friday"). A day before a clock deadline ("శుక్రవారం సాయంత్రం 5
  ///   గంటలలోగా") is the due day, and the clock with its part of the day stays in
  ///   the title. "ఈరోజు వరకు" ("so far") is not read, nor is a day in a line
  ///   that says a deadline has passed ("గడువు మీరింది", "గడువు ముగిసింది",
  ///   "గడువు దాటింది"), which is a past-tense statement like the others.
  /// - Time: "5 గంటలకు", "5:30 గంటలకు", "ఐదు గంటలకు", "ఒంటి గంటకు" (1:00),
  ///   "ఐదున్నరకు" (5:30), "ఐదున్నర గంటలకు", "ఒంటిగంటన్నరకు" (1:30), "5 గంటల 30
  ///   నిమిషాలకు", "సాయంత్రం 5కి", "రాత్రి 8:30కి", "9:30కి", "3:30 PMకి", "సాయంత్రం
  ///   ఐదున్నర", "ఉదయం 9:30", each maybe after సరిగ్గా, ఖచ్చితంగా, సుమారు, or
  ///   దాదాపు. The hour counts with గంటలకు (or గంటకు after ఒంటి, or గంటలకి,
  ///   గంటలకే) or with a number and కి or కు beside something that makes it a
  ///   time (a part of the day, a colon, or AM or PM), since "5కి" alone may be a
  ///   count or a date; "గంటల సమయంలో", "గంటల ప్రాంతంలో", "గంటలప్పుడు", and "గంటల
  ///   నుండి" after the hour read too. A part of the day sets the hour and comes
  ///   before it ("ఉదయం 9 గంటలకు", "రాత్రి 10 గంటలకు", "సాయంత్రం 5 గంటలకు").
  ///   ఉదయం and తెల్లవారుజామున are the morning (12 is no time), మధ్యాహ్నం is noon
  ///   at 12 and the afternoon from 1 to 6, సాయంత్రం is the evening, and రాత్రి
  ///   runs past midnight: "రాత్రి 12 గంటలకు" is 00:00 of the next day, "రాత్రి 2
  ///   గంటలకు" is 02:00 of the next day, and "రాత్రి 8 గంటలకు" is 20:00.
  ///   "అర్ధరాత్రి" is the midnight that ends the day. An hour on the 12-hour
  ///   clock (1 to 12, no leading zero) written with no part of the day beside it
  ///   takes its half of the day from the one part of the day the line names
  ///   elsewhere: in its day phrase ("రేపు ఉదయం మీటింగ్ 6 గంటలకు" is 06:00), after
  ///   ప్రతి or రోజూ ("రోజూ ఉదయం 6 గంటలకు యోగా"), or in a noun ("రాత్రి భోజనం 8
  ///   గంటలకు" is 20:00). Two parts that differ leave the hour as it reads alone,
  ///   and an hour on the 24-hour clock (a leading zero, 0, or 13 and later) is
  ///   read as written. An hour from 1 to 6 with no part of the day anywhere in
  ///   the line is the afternoon, as in the other languages ("5 గంటలకు" is 17:00,
  ///   "7 గంటలకు" is 07:00), unless written with a leading zero ("06:30
  ///   గంటలకు"). A range: "9 నుండి 11 వరకు" with a part of the day or గంటల on
  ///   either side ("ఉదయం 9 నుండి 11 వరకు", "9 గంటల నుండి 11 గంటల వరకు", "మధ్యాహ్నం
  ///   2 నుండి సాయంత్రం 4 వరకు", "9-11 గంటలకు"), a range right after a part of
  ///   the day that a repeat or ఈ owns ("రోజూ ఉదయం 9 నుండి 11 వరకు", "ఈ సాయంత్రం
  ///   5 నుండి 7 వరకు"), and a range of colon times ("14:00 నుండి 16:00
  ///   వరకు"); "3 నుండి 5 వరకు" with none of these is a range of numbers, not of
  ///   hours. A clock time that is a bound stays in the title whole: "5 గంటల
  ///   లోపు", "సాయంత్రం 6 గంటలలోగా", "5 గంటలకల్లా", "5 గంటల వరకు", "18:00
  ///   వరకు", "3 PM లోపు", "5 గంటల తర్వాత", "5 గంటలకు ముందు". The clock quarters
  ///   ("పావు తక్కువ ఆరు") and a number before a percent sign, a currency sign, or a
  ///   currency word are never a time.
  /// - Length: "30 నిమిషాలు", "2 గంటలు", "1.5 గంటలు", "1 గంట 30 నిమిషాలు" (also
  ///   "1 గంట, 30 నిమిషాలు" and the system's "1 గం., 30 నిమి."), "అరగంట",
  ///   "పావు గంట" (15), "ముప్పావు గంట" (45), "గంటన్నర" (90), "రెండున్నర గంటలు",
  ///   "రెండు గంటలు", "ఇరవై నిమిషాలు", "గంటసేపు", each maybe after సుమారు,
  ///   దాదాపు, or అంచనా, and with పాటు or సేపు after the unit, or the unit in
  ///   its form before a noun ("30 నిమిషాల మీటింగ్" is a meeting of 30
  ///   minutes, "2 గంటల పాటు" is for 2 hours). An amount before తర్వాత,
  ///   క్రితం, ముందు, లోపు, లోగా, వరకు, or the like after the unit, or after
  ///   కనీసం, గరిష్టంగా, ప్రతి, or రోజుకు before it, names a moment, an interval,
  ///   or a bound, not a length ("2 గంటల తర్వాత", "ప్రతి 2 గంటలు", "రోజుకు 2
  ///   గంటలు"), and neither is a side of a range ("2 నుండి 3 గంటలు", "2-3 గంటలు"):
  ///   each stays whole in the title. An amount whose unit has any other ending
  ///   ("2 గంటల్లో", "30 నిమిషాలకు") is no length, and "గంట" alone is none.
  /// - Priority: అధిక ప్రాధాన్యత, సాధారణ ప్రాధాన్యత, తక్కువ ప్రాధాన్యత (also
  ///   అత్యధిక, ఎక్కువ, గరిష్ట, మధ్యస్థ, అల్ప, and కనిష్ట for the levels), each also
  ///   after the word ("ప్రాధాన్యత: అధికం"); అత్యవసరం, ముఖ్యం, అర్జెంట్, or
  ///   ముఖ్యమైనది at the end of the line, and the same words opening it before a
  ///   colon or comma ("అత్యవసరం: రిపోర్ట్ పంపండి"). These are ordinary words too,
  ///   so "ముఖ్యం కాదు" and "అత్యవసర విభాగం" stay in the title.
  static let telugu = LorvexCaptureVocabulary(
    readingForm: teluguForMatching,
    priority: [teluguRule(teluguPriorityPattern, read: teluguPriority)],
    dateRange: [
      teluguRule(teluguDateRangePattern, read: teluguDateRange),
      teluguRule(teluguWeekdayRangePattern, read: teluguWeekdayRange),
    ],
    keptInTitle: [
      teluguRule(teluguDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      teluguRule(teluguLengthPattern) { teluguDeclinesLength($0) ? true : nil },
    ],
    length: [teluguRule(teluguLengthPattern, read: teluguLength)],
    time: [
      teluguRule(teluguTimeRangePattern, read: teluguTimeRange),
      teluguRule(teluguColonTimeRangePattern, read: teluguTimeRange),
      teluguRule(teluguHourPattern, read: teluguHourTime),
      teluguRule(teluguHalfTimePattern, read: teluguHalfTime),
      teluguRule(teluguDativeTimePattern, read: teluguDativeTime),
      teluguRule(teluguColonTimePattern, read: teluguColonTime),
      teluguRule(teluguMidnightPattern) { _ in ClockTime(minutes: 0, isAfterMidnight: true) },
    ],
    repeats: teluguRepeatRules,
    due: [teluguRule(teluguDuePattern, read: teluguDue)],
    when: [teluguRule(teluguWhenPattern, read: teluguWhen)])

  // MARK: - Reading form and patterns

  /// The line with each Telugu digit (౦-౯, U+0C66-U+0C6F) read as an ASCII
  /// digit. Each replacement is one UTF-16 unit for one, so a match range in the
  /// result is the same range in `line`.
  static func teluguForMatching(_ line: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in line.unicodeScalars { scalars.append(teluguReading(of: scalar)) }
    return String(scalars)
  }

  private static func teluguReading(of scalar: Unicode.Scalar) -> Unicode.Scalar {
    switch scalar {
    case "\u{0C66}"..."\u{0C6F}": Unicode.Scalar(UInt8(truncatingIfNeeded: 0x30 + scalar.value - 0x0C66))
    default: scalar
    }
  }

  /// `text` as a reader compares a word: in canonical composed form (so a ై typed
  /// as ె and ౖ is the one sign) and without zero-width joiners. `text` is
  /// already in the reading form. Comparisons of Telugu text go through scalars
  /// or whole words: a `Character` is a grapheme cluster ("కి" is one), so
  /// `hasPrefix("క")` does not match "కిలో".
  static func teluguBare(_ text: String) -> String {
    var result = String.UnicodeScalarView()
    for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars where scalar != "\u{200C}" && scalar != "\u{200D}" {
      result.append(scalar)
    }
    return String(result)
  }

  /// A matched phrase as a reader compares it: as ``teluguBare(_:)`` leaves it,
  /// each run of spaces as one, hyphens read as spaces.
  static func teluguPhrase(_ text: String) -> String {
    normalizedPhrase(teluguBare(text))
  }

  /// A word written in a vocabulary table, as ``teluguPhrase(_:)`` leaves a
  /// matched word, whichever way the table spells it.
  static func teluguKey(_ word: String) -> String {
    teluguBare(teluguForMatching(word))
  }

  /// The same as ``teluguKey(_:)`` with its spaces left out, for a word the
  /// table writes in one word or two ("అర గంట" and "అరగంట").
  static func teluguCompactKey(_ word: String) -> String {
    teluguKey(word).replacingOccurrences(of: " ", with: "")
  }

  /// Whether the scalars of `key` start with the scalars of `prefix`. Both are
  /// in the form ``teluguKey(_:)`` leaves them.
  static func teluguHasPrefix(_ key: String, _ prefix: String) -> Bool {
    key.unicodeScalars.starts(with: prefix.unicodeScalars)
  }

  /// `pattern`, written in the composed letters of its words, ready to match a
  /// line in the reading form.
  ///
  /// A virama may have zero-width joiners on either side, the vowel sign ై also
  /// matches the two signs it is made of, and a quantifier that follows such a
  /// sign applies to the sign with its extras. A middle dot (·) marks the
  /// boundary between a word and an ending glued to it, where a zero-width
  /// joiner or non-joiner may have been typed. The pattern is read in canonical
  /// composed form, so a letter or sign typed there in any spelling is read
  /// like its base. Escapes and character sets pass through. A pattern is
  /// expanded once, by ``teluguRule(_:read:)``, never in parts that another
  /// pattern then embeds.
  static func telugu(_ pattern: String) -> String {
    let quantifiers: Set<Unicode.Scalar> = ["?", "*", "+", "{"]
    let joiners = #"[\x{200C}\x{200D}]{0,2}"#
    let scalars = Array(
      pattern.precomposedStringWithCanonicalMapping.unicodeScalars.filter { $0 != "\u{200C}" && $0 != "\u{200D}" })
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
        result.unicodeScalars.append(teluguReading(of: scalar))
      } else if scalar == "[" {
        isInSet = true
        result.unicodeScalars.append(scalar)
      } else if scalar == "\u{00B7}" {
        result += joiners
      } else {
        let reading = teluguReading(of: scalar)
        var unit = String(Character(reading))
        switch reading {
        case "\u{0C4D}":
          unit = joiners + unit + joiners
        case "\u{0C48}":
          unit = #"(?:\x{0C48}|\x{0C46}\x{0C56})"#
        default:
          break
        }
        let isQuantified = index + 1 < scalars.count && quantifiers.contains(scalars[index + 1])
        result += unit.count > 1 && isQuantified && !unit.hasPrefix("(?:") ? "(?:\(unit))" : unit
      }
    }
    return result
  }

  /// A rule whose `pattern` is written in composed letters (see
  /// ``telugu(_:)``).
  static func teluguRule<Value>(_ pattern: String, read: @escaping @Sendable (Match) -> Value?) -> Rule<Value> {
    Rule(pattern: telugu(pattern), read: read)
  }

  /// Whether `pattern`, written in composed letters, matches somewhere in
  /// `text`, which is in the reading form.
  static func teluguFinds(_ pattern: String, in text: String) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(telugu(pattern)) else { return false }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  /// `words` as the alternatives of a pattern, longest first (by scalars, so a
  /// word that a sign makes longer comes before the word it starts with) and
  /// without repeats, a space inside a word standing for any run of spaces.
  static func teluguAlternation(of words: [String]) -> String {
    let unique: [String] = Array(Set(words))
    let ordered = unique.sorted { (first: String, second: String) -> Bool in
      let firstCount = first.unicodeScalars.count
      let secondCount = second.unicodeScalars.count
      return firstCount != secondCount ? firstCount > secondCount : first < second
    }
    return ordered.map { $0.replacingOccurrences(of: " ", with: #"\s*"#) }.joined(separator: "|")
  }

  // MARK: - Boundaries and words around a detail

  /// A word boundary for words written in the Telugu script: no Telugu letter,
  /// vowel sign, virama, anusvara, visarga, joiner, or digit on that side, and no
  /// hyphen that joins it to another Telugu word.
  static let teluguStart =
    #"(?<![\p{Telugu}\p{M}\p{N}\x{200C}\x{200D}])(?<![\p{Telugu}\p{M}]-)"#
  static let teluguEnd =
    #"(?![\p{Telugu}\p{M}\p{N}\x{200C}\x{200D}])(?!-\p{Telugu})"#

  /// What may follow a clock time: no Telugu letter, vowel sign, digit, or colon
  /// (the word or the number goes on), no decimal fraction, no percent or
  /// currency sign or word with or without a space before it (the number is an
  /// amount: "20%", "500 రూపాయలు"), no dash before a digit (a range written with
  /// a dash and no గంటలకు is English's), and no AM or PM after it.
  static let teluguTimeEnd =
    #"(?![\p{Telugu}\p{M}\p{N}\x{200C}\x{200D}:]|[.,]\p{N}|\s*[%\p{Sc}]|\s*(?:రూపాయలు|రూపాయి|రూపాయ|డాలర్లు|డాలర్|పైసలు)\#(teluguEnd)|\s*[-–—]\s*\d)\#(noMeridiemAfter)"#

  /// What may follow a date: no Telugu letter, vowel sign, digit, or colon, no
  /// decimal fraction, and no hyphen that joins a Telugu word to it.
  static let teluguDateEnd = #"(?![\p{Telugu}\p{M}\p{N}\x{200C}\x{200D}:]|[.,]\p{N}|-\p{Telugu})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let teluguNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// The word just before `match` as a reader compares it, or nil when the
  /// match opens the line or punctuation comes first.
  static func teluguWordBefore(_ match: Match) -> String? {
    guard let word = wordBefore(match).map(teluguBare), !word.isEmpty else { return nil }
    return word
  }

  /// The words of `text`, as letters only and as ``teluguBare(_:)`` leaves
  /// them.
  static func teluguWords(in text: String) -> [String] {
    text.split(whereSeparator: { !$0.isLetter }).map { teluguBare(String($0)) }
  }

  /// The words and numbers of `text`, with each run of digits and each run of
  /// letters apart ("15న" is "15" and "న").
  static func teluguRuns(_ text: String) -> [String] {
    var runs: [String] = []
    var current = ""
    var isDigits = false
    for character in text {
      let isDigit = character.isNumber
      guard isDigit || character.isLetter else {
        if !current.isEmpty { runs.append(current) }
        current = ""
        continue
      }
      if !current.isEmpty, isDigit != isDigits {
        runs.append(current)
        current = ""
      }
      isDigits = isDigit
      current.append(character)
    }
    if !current.isEmpty { runs.append(current) }
    return runs
  }

  // MARK: - Counts

  /// The numerals one to twelve that stand before "గంటలకు" for an hour on the
  /// clock: "రెండు గంటలకు", "ఐదు గంటలకు", and ఒంటి for one ("ఒంటి గంటకు", Apple's
  /// word for one o'clock), in the spellings people type.
  private static let teluguHourWordSpellings: [(Int, [String])] = [
    (1, ["ఒంటి"]), (2, ["రెండు"]), (3, ["మూడు"]), (4, ["నాలుగు"]), (5, ["ఐదు", "అయిదు"]), (6, ["ఆరు"]), (7, ["ఏడు"]),
    (8, ["ఎనిమిది"]), (9, ["తొమ్మిది"]), (10, ["పది"]), (11, ["పదకొండు"]), (12, ["పన్నెండు"]),
  ]

  /// The hour words as keys.
  static let teluguHourWords: [String: Int] = {
    var words: [String: Int] = [:]
    for (value, spellings) in teluguHourWordSpellings {
      for word in spellings { words[teluguCompactKey(word)] = value }
    }
    return words
  }()

  /// The hour words as a pattern.
  static var teluguHourWordPattern: String {
    teluguAlternation(of: teluguHourWordSpellings.flatMap { $0.1 })
  }

  /// The words that name an hour and a half on the clock face: "ఐదున్నర" is
  /// 5:30, "ఎనిమిదిన్నర" 8:30, and "ఒంటి గంటన్నర" 1:30, as Apple's Telugu
  /// writes the half hours of its clock faces, with the hour they follow.
  private static let teluguHalfSpellings: [(Int, [String])] = [
    (1, ["ఒకటిన్నర", "ఒంటిగంటన్నర", "ఒంటి గంటన్నర"]), (2, ["రెండున్నర"]), (3, ["మూడున్నర"]), (4, ["నాలుగున్నర"]),
    (5, ["ఐదున్నర", "అయిదున్నర"]), (6, ["ఆరున్నర"]), (7, ["ఏడున్నర"]), (8, ["ఎనిమిదిన్నర"]), (9, ["తొమ్మిదిన్నర"]),
    (10, ["పదిన్నర"]), (11, ["పదకొండున్నర"]), (12, ["పన్నెండున్నర"]),
  ]

  /// The half-hour words as keys, each with the hour it follows.
  static let teluguHalfHours: [String: Int] = {
    var words: [String: Int] = [:]
    for (value, spellings) in teluguHalfSpellings {
      for word in spellings { words[teluguCompactKey(word)] = value }
    }
    return words
  }()

  /// The half-hour words as a pattern.
  static var teluguHalfWordPattern: String {
    teluguAlternation(of: teluguHalfSpellings.flatMap { $0.1 })
  }

  /// The numerals of an amount of hours, days, or weeks that stand before their
  /// noun ("మూడు గంటలు", "రెండు వారాలు", "ఒక గంట"): one to twelve, written out in
  /// full.
  private static let teluguAmountSpellings: [(Int, [String])] = [
    (1, ["ఒక", "ఒక్క"]), (2, ["రెండు"]), (3, ["మూడు"]), (4, ["నాలుగు"]), (5, ["ఐదు", "అయిదు"]), (6, ["ఆరు"]),
    (7, ["ఏడు"]), (8, ["ఎనిమిది"]), (9, ["తొమ్మిది"]), (10, ["పది"]), (11, ["పదకొండు"]), (12, ["పన్నెండు"]),
  ]

  /// The round numbers of an amount of minutes or days: fourteen to sixty.
  private static let teluguRoundSpellings: [(Int, [String])] = [
    (14, ["పద్నాలుగు", "పధ్నాలుగు"]), (15, ["పదిహేను"]), (20, ["ఇరవై"]), (25, ["ఇరవై ఐదు", "ఇరవై అయిదు"]),
    (30, ["ముప్పై"]), (40, ["నలభై"]), (45, ["నలభై ఐదు", "నలభై అయిదు"]), (50, ["యాభై", "ఏభై"]), (60, ["అరవై"]),
  ]

  /// The numerals of an amount, as keys.
  static let teluguCounts: [String: Int] = {
    var counts: [String: Int] = [:]
    for (value, spellings) in teluguAmountSpellings {
      for word in spellings { counts[teluguCompactKey(word)] = value }
    }
    return counts
  }()

  /// The numerals of an amount of minutes or days: the counts above and the
  /// round numbers up to sixty, as keys.
  static let teluguRoundCounts: [String: Int] = {
    var counts = teluguCounts
    for (value, spellings) in teluguRoundSpellings {
      for word in spellings { counts[teluguCompactKey(word)] = value }
    }
    return counts
  }()

  /// The numerals of an amount, as a pattern.
  static var teluguCountWords: String {
    teluguAlternation(of: teluguAmountSpellings.flatMap { $0.1 })
  }

  /// The numerals of an amount of minutes or days, as a pattern.
  static var teluguRoundCountWords: String {
    teluguAlternation(of: (teluguAmountSpellings + teluguRoundSpellings).flatMap { $0.1 })
  }

  // MARK: - Priority

  /// Group 1: a written priority, with its level before or after the word
  /// "ప్రాధాన్యత"; an urgent word has no group. A level word with "గల" or
  /// "కలిగిన" after the priority describes a noun ("అధిక ప్రాధాన్యత గల పనులు")
  /// and is no priority.
  private static var teluguPriorityPattern: String {
    let high = "అత్యధిక|అత్యున్నత|అధికం|అధికము|అధిక|ఎక్కువ|గరిష్ఠం|గరిష్టం|గరిష్ఠ|గరిష్ట|ఉన్నత"
    let medium = "మధ్యస్థం|మధ్యస్థము|మధ్యస్థ|మధ్యమ|మధ్యరకం|సాధారణం|సాధారణ|నార్మల్|మీడియం"
    let low = "తక్కువ|అత్యల్పం|అత్యల్ప|అల్పం|అల్ప|కనిష్ఠం|కనిష్టం|కనిష్ఠ|కనిష్ట"
    let level = "\(high)|\(medium)|\(low)"
    let word = "ప్రాధాన్యత"
    let urgent =
      #"(?:(?:అతి|చాలా|అత్యంత)\s+)?(?:అత్యవసరం|అత్యవసరము|అర్జెంట్|అర్జంట్|అర్జెంటు|ముఖ్యమైనది|ముఖ్యం|ముఖ్యము)"#
    let described = #"(?!\s+(?:గల|గలవి|కలిగిన|ఉన్న)\#(teluguEnd))"#
    return
      #"\#(teluguStart)((?:\#(level))\s*\#(word)|\#(word)\s*[:：]?\s*(?:\#(level)))\#(teluguEnd)\#(described)|(?<=\s)(?:\#(urgent))\#(teluguEnd)(?=\s*[।.!]?\s*$)|^\s*(?:\#(urgent))\#(teluguEnd)(?=\s*[:：,，])"#
  }

  private static func teluguPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1).map(teluguPhrase) else { return .p1 }
    let words = Set(teluguWords(in: phrase))
    let medium = ["మధ్యస్థం", "మధ్యస్థము", "మధ్యస్థ", "మధ్యమ", "మధ్యరకం", "సాధారణం", "సాధారణ", "నార్మల్", "మీడియం"]
    if !words.isDisjoint(with: medium.map(teluguKey)) { return .p2 }
    let low = ["తక్కువ", "అత్యల్పం", "అత్యల్ప", "అల్పం", "అల్ప", "కనిష్ఠం", "కనిష్టం", "కనిష్ఠ", "కనిష్ట"]
    if !words.isDisjoint(with: low.map(teluguKey)) { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "30 నిమిషాలు", "2 గంటలు", "1.5 గంటలు", "1 గంట 30 నిమిషాలు", "అరగంట",
  /// "పావు గంట", "ముప్పావు గంట", "గంటన్నర", "రెండున్నర గంటలు", "రెండు గంటలు",
  /// "ఇరవై నిమిషాలు", "గంటసేపు", each maybe after "సుమారు", "దాదాపు", or
  /// "అంచనా", and maybe with "పాటు" or "సేపు" after the unit, which goes with
  /// it ("2 గంటల పాటు" is for 2 hours). The unit may also stand in its form
  /// before a noun ("30 నిమిషాల మీటింగ్" is a meeting of 30 minutes). Groups: 1 a
  /// word that makes the length approximate; 2 a word that makes the amount a
  /// bound or a rate ("కనీసం 2 గంటలు", "ప్రతి 2 గంటలు", "రోజుకు 2 గంటలు"); 3 the
  /// hours of an amount with a unit and 4 its minutes; 5 minutes; 6 a length in
  /// words; 7 a word after the amount that makes it a moment, the past, or a
  /// bound ("2 గంటల తర్వాత", "2 గంటల లోపు"). A match with group 2 or 7 is no
  /// length: ``teluguLength(_:)`` declines it and a keep rule claims it, so the
  /// amount stays whole in the title. An amount followed by a word that makes it
  /// an hour of the clock ("5 గంటల సమయంలో") or that starts or ends a span ("5
  /// గంటల నుండి", "2 గంటల వరకు") is no length either, and neither are hours
  /// followed by minutes with an ending ("5 గంటల 30 నిమిషాలకు" is 5:30): they
  /// are left to the time rules, which read the time or keep the bound. Any
  /// other ending glued to the unit ("2 గంటల్లో", "30 నిమిషాలకు") leaves the
  /// unit unread. The amount may not follow a digit, a colon, a slash, or a
  /// separator ("1/2 గంట" is a fraction, not 2 hours), and it may not be a side
  /// of a range ("2-3 గంటలు", "2 నుండి 3 గంటలు", "5 నిమిషాలు నుండి 10
  /// నిమిషాలు"). The half and quarter hours may follow "ఒక" ("ఒక అర గంట",
  /// "ఒక పావు గంట"), which goes with them.
  static var teluguLengthPattern: String {
    let hourNoun = #"(?:గంటలు|గంటల|గంట|గం\.?)"#
    let minuteNoun = #"(?:నిమిషాలు|నిమిషాల|నిమిషం|నిమిషము|నిముషాలు|నిముషాల|నిముషం|నిముషము|నిమి\.?)"#
    let opener =
      #"(?:(?:(సుమారుగా|సుమారు|దాదాపుగా|దాదాపు|అంచనా)|(కనీసం|గరిష్టంగా|గరిష్ఠంగా|అత్యధికంగా|ప్రతి|రోజుకు|రోజుకి|వారానికి|నెలకు))\s+)?"#
    let boundaries = #"(?<![\p{N}:.,/])(?<!\p{N}\s?[-–—]\s?)"#
    let hours =
      #"(\d+(?:\.\d+)?)\s*\#(hourNoun)(?:,?\s+(?:(?:మరియు|&)\s+)?(\d{1,2})\s*\#(minuteNoun))?"#
    let minutes = #"(\d+)\s*\#(minuteNoun)"#
    let amount = teluguAlternation(of: teluguAmountSpellings.flatMap { $0.1 })
    let roundAmount = teluguRoundCountWords
    let words =
      #"((?:ఒక\s+)?(?:(?:అర|అర్ధ|అర్థ)\s*గంట|(?:ముప్పావు|పావు)\s*గంట)|(?<!ఒంటి\s)గంటన్నర|గంట\s*(?:సేపు|పాటు|పాటూ)|(?:\#(teluguHalfWordPattern))\s*\#(hourNoun)|(?:\#(amount))\s*\#(hourNoun)|(?:\#(roundAmount))\s*\#(minuteNoun))"#
    let ending = #"(?:\s*(?:పాటు|పాటూ|సేపు))?"#
    let minutesAt = #"\s+(?:\d{1,2}|\#(roundAmount))\s*(?:నిమిషాలకు|నిమిషాలకి|నిమిషాలకే|నిముషాలకు|నిముషాలకి)"#
    let notAnHour =
      #"(?!\s*(?:సమయంలో|సమయానికి|ప్రాంతంలో|ప్రాంతానికి|వేళకు|వేళలో|(?:నుండి|నుంచి|నించి|వరకు|వరకూ|దాకా)\#(teluguEnd))|\#(minutesAt))"#
    let trailing =
      #"(?:\s+(తర్వాత|తరువాత|క్రితం|ముందు|లోపు|లోగా|లోపల|కల్లా|కంటే|కన్నా|అనంతరం)\#(teluguEnd))?"#
    return
      #"\#(teluguStart)\#(opener)(?:\#(boundaries)(?:\#(hours)|\#(minutes))|\#(words))\#(ending)\#(teluguEnd)\#(notAnHour)(?!\s*[-–—]\s*\d)\#(trailing)"#
  }

  /// True for a match that is no length: a bound or a rate ("కనీసం 2 గంటలు",
  /// "రోజుకు 2 గంటలు"), a moment, the past, or a bound ("2 గంటల తర్వాత", "2
  /// గంటల లోపు"), or the end of a range of amounts ("2 నుండి 3 గంటలు").
  static func teluguDeclinesLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(7) != nil || teluguIsRangeEnd(match)
  }

  /// Whether the text before `match` ends with a number or a unit and "నుండి"
  /// or "నుంచి", which makes the amount the end of a range ("2 నుండి 3 గంటలు",
  /// "5 నిమిషాలు నుండి 10 నిమిషాలు").
  private static func teluguIsRangeEnd(_ match: Match) -> Bool {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return false }
    let before = String(match.source[..<start])
    return teluguFinds(#"(?:\d|నిమిషాలు|నిమిషాల|గంటలు|గంటల|గంట)\s+(?:నుండి|నుంచి|నించి)\s+$"#, in: before)
  }

  private static func teluguLength(_ match: Match) -> Int? {
    if teluguDeclinesLength(match) { return nil }
    if let hours = match.group(3).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(4).flatMap(number) ?? 0))
    }
    if let minutes = match.group(5).flatMap(number) { return taskLength(minutes: minutes) }
    guard let phrase = match.group(6).map(teluguPhrase) else { return nil }
    return teluguWordsLength(phrase.replacingOccurrences(of: " ", with: ""))
  }

  /// The minutes a length written in words names: `text` is a phrase as
  /// ``teluguPhrase(_:)`` leaves it with its spaces taken out, an amount word or
  /// a fraction word before a unit, where "ఒక" before a half or quarter hour
  /// ("ఒక అర గంట") adds nothing.
  private static func teluguWordsLength(_ text: String) -> Int? {
    let compact = text.replacingOccurrences(
      of: "^\(teluguCompactKey("ఒక"))(?=అర|పావు|ముప్పావు)", with: "", options: .regularExpression)
    switch compact {
    case teluguCompactKey("అరగంట"), teluguCompactKey("అర్ధగంట"), teluguCompactKey("అర్థగంట"): return 30
    case teluguCompactKey("పావుగంట"): return 15
    case teluguCompactKey("ముప్పావుగంట"): return 45
    case teluguCompactKey("గంటన్నర"): return 90
    default: break
    }
    if ["సేపు", "పాటు", "పాటూ"].contains(where: { compact.unicodeScalars.reversed().starts(with: teluguKey($0).unicodeScalars.reversed()) }) {
      return 60
    }
    let hourUnit = compact.replacingOccurrences(of: #"(?:గంటలు|గంటల|గంట)$"#, with: "", options: .regularExpression)
    if hourUnit != compact {
      if let half = teluguHalfHours[hourUnit] { return taskLength(minutes: half * 60 + 30) }
      return teluguCounts[hourUnit].flatMap { taskLength(minutes: $0 * 60) }
    }
    let minuteUnit = compact.replacingOccurrences(
      of: #"(?:నిమిషాలు|నిమిషాల|నిమిషం|నిమిషము|నిముషాలు|నిముషాల|నిముషం|నిముషము|నిమి)$"#, with: "", options: .regularExpression)
    guard minuteUnit != compact else { return nil }
    return teluguRoundCounts[minuteUnit].flatMap { taskLength(minutes: $0) }
  }
}
