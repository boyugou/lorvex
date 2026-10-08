import Foundation

extension LorvexCaptureVocabulary {
  /// Tamil, read for a user who reads Tamil in the Tamil script (India, Sri
  /// Lanka, Singapore, Malaysia). A word needs a boundary of Tamil letters,
  /// signs, digits, and joiners on both sides (``tamilStart``, ``tamilEnd``), so
  /// "நாளைய" (tomorrow's) and "இன்றைய" (today's) hold no planned day, and a
  /// hyphen between two Tamil words joins them. Tamil glues its case endings to
  /// the word ("திங்களுக்கு", "15க்கு", "மணிக்கு"), so each rule lists the
  /// endings it reads, and a word with any other ending is another word and
  /// stays in the title ("திங்கட்கிழமையின் கூட்டம்", "நாளைய கூட்டம்"). A
  /// zero-width joiner or non-joiner typed after a pulli or between a word and a
  /// listed ending changes nothing; one glued to the end of a finished word
  /// makes it part of a longer word, which stays in the title.
  ///
  /// The line is read in one form (``tamilForMatching(_:)``): the Tamil digits
  /// as Latin ones ("௫ மணிக்கு" is "5 மணிக்கு"). The vowel signs ொ, ோ, and ௌ
  /// and the letter ஔ are read typed as one character or as the parts they are
  /// made of, a pulli accepts joiners on either side, and the spellings people
  /// type for one word are each one word: மார்ச் and மார்ச்சு, ஆகஸ்ட் and
  /// ஆகஸ்டு, ஜூன் and ஜுன், பிப்ரவரி and பெப்ரவரி, ஐந்து and அஞ்சு, நான்கு and
  /// நாலு, இன்றைக்கு and இன்னைக்கு and இன்னிக்கு, நிமிடங்கள் and நிமிஷங்கள்,
  /// மணி நேரம் and மணிநேரம், சாயங்காலம் and சாயந்திரம், ராத்திரி and இராத்திரி,
  /// and the other spellings. The title keeps what was typed. Tamil written in
  /// Latin letters ("naalai") is not read.
  ///
  /// Tamil doubles the hard consonant க், ச், த், or ப் at the end of இந்த,
  /// அடுத்த, a dative in -க்கு, and "கழித்து" when the next word starts with
  /// the same consonant ("இந்தச் சனிக்கிழமை", "நாளைக்குத் தள்ளிவை", "ஒரு நாள்
  /// கழித்துத் திட்டமிடு"). The doubled consonant is read as part of the word it
  /// ends, and only before a word that starts with it; a word typed without it
  /// reads the same.
  ///
  /// English is read beside Tamil, so a detail that needs no Tamil word is left
  /// to English, which reads its own "5pm", "17:30", "30 min", or "2h". Tamil
  /// does not write a clock time with the letter h, so "2h" beside Tamil stays
  /// a length.
  ///
  /// Tamil names yesterday (நேற்று), the day before (முந்தாநாள்), tomorrow
  /// (நாளை), and the day after (நாளை மறுநாள்) with different words, so no day
  /// word needs a guess about its direction and the past days are never read.
  /// A day phrase is still left unread when its line says the day is past or
  /// not the coming one: a past-tense form anywhere in the line (செய்தேன்,
  /// சென்றோம், வந்தார், முடிந்தது, நடந்தது, and the other listed forms: "நாளை
  /// கூட்டம் நடந்தது", "வெள்ளிக்கிழமை காலக்கெடு முடிந்தது"), or கடந்த, சென்ற,
  /// போன, முந்தைய, அந்த, கடைசி, இறுதி, முதல், an ordinal (இரண்டாவது,
  /// மூன்றாவது, நான்காவது, ஐந்தாவது), ஒரு, ஒவ்வொரு, எந்த, or எல்லா just before
  /// it ("கடந்த வெள்ளிக்கிழமை", "முதல் வெள்ளிக்கிழமை"). A day in its genitive
  /// (-இன்) or its adjective form (-ய) is an attribute of a noun, not a plan
  /// ("நாளைய கூட்டம்", "திங்கட்கிழமையின் கூட்டம்"). "நாளை" is also a form of
  /// "நாள்" (day), so after a number or a determiner it is no tomorrow ("ஒரு
  /// நாளைக்கு 3 முறை").
  ///
  /// A weekday is read with its full name ending in கிழமை ("திங்கட்கிழமை"), its
  /// bare name ("திங்கள்"), or the short form with a period that the system
  /// writes ("திங்."). The bare names are also words for planets and metals
  /// (செவ்வாய், வெள்ளி, சனி, புதன், வியாழன்), so a bare name is a day only where
  /// no word for a planet, a god, silver goods, or the like follows ("செவ்வாய்
  /// கிரகம்", "வெள்ளி நகை", "சனி பகவான்"); the name with கிழமை is always a
  /// day. The one-letter forms the system writes for the shortest weekday names
  /// (ஞா, தி, செ, பு, வி, வெ, ச) are ordinary syllables and are not read, and
  /// சனி has no short form with a period.
  ///
  /// - Day: இன்று, இன்றைக்கு, இன்னைக்கு, இன்னிக்கு, நாளை, நாளை மறுநாள், and
  ///   இன்றிரவு (tonight), each maybe with the emphatic -ே ("இன்றே", "நாளையே"),
  ///   the dative -க்கு ("நாளைக்கு": the day a task is planned for), or "முதல்"
  ///   after it ("நாளை முதல்", "இன்றிலிருந்து", "நாளையிலிருந்து": from that day
  ///   on), and maybe with a part of the day (காலை, அதிகாலை, மதியம், பிற்பகல்,
  ///   மாலை, சாயங்காலம், இரவு, ராத்திரி, நள்ளிரவு, each with its spellings and its
  ///   locative -இல் and dative -க்கு: "நாளை காலை", "இன்று இரவு"), also with இந்த
  ///   before it as one phrase for today ("இந்த மாலை", "இந்த இரவு"); the weekday
  ///   names, alone, with அன்று after them or glued to them ("திங்கள் அன்று",
  ///   "திங்களன்று", "திங்கட்கிழமையன்று"), with the dative ("திங்களுக்கு",
  ///   "திங்கட்கிழமைக்கு"), the emphatic ("திங்கட்கிழமையே"), the locative
  ///   ("திங்கட்கிழமையில்"), or "முதல்" after them, or after இந்த (this week's),
  ///   வரும் or வருகிற (the coming one), or அடுத்த (next week's, weeks starting on
  ///   Monday), with "வாரம்" between ("இந்த வாரம் வெள்ளிக்கிழமை", "அடுத்த வாரம்
  ///   திங்கள்": this and next week's), and maybe a part of the day after;
  ///   "அடுத்த வாரம்", "வரும் வாரம்", and "வருகிற வாரம்" alone (seven days
  ///   ahead); "3 நாட்களில்", "3 நாட்கள் கழித்து", "10 நாட்களுக்குப் பிறகு",
  ///   "இரண்டு வாரங்களில்", "1 மாதம் கழித்து" (months counted on the calendar),
  ///   with the number in digits or in words; the weekend (வார இறுதி, வாரயிறுதி,
  ///   வீக்கெண்ட், "சனிக்கிழமை மற்றும் ஞாயிற்றுக்கிழமை", "சனி ஞாயிறு"), alone or
  ///   after இந்த, வரும், வருகிற, or அடுத்த; a date ("15 அக்டோபர்", "15ஆம் தேதி
  ///   அக்டோபர் 2026", "அக்டோபர் 15", "அக்டோபர் மாதம் 15ஆம் தேதி", "திங்கள், 5
  ///   அக்டோபர்", "தேதி 5 மே", "15 அக்."; "15ஆம் தேதி" and "15ஆம் தேதியன்று" for
  ///   the next such day of the month; "15/10/2026", "15.10.2026", "15-10-2026",
  ///   and "15.10." in digits; "15/10" and "15.10" only after தேதி or before க்கு,
  ///   இல், அன்று, or முதல்), with க்கு, இல், யில், யன்று, அன்று, or முதல் after it.
  ///   A weekday alone means the next such day, a full week ahead when it names
  ///   today, and "இந்த செவ்வாய்க்கிழமை" is today when it names today. "இந்த
  ///   வாரம்" alone names no single day and is not read. The weekend is the coming
  ///   Saturday (today on a Saturday or a Sunday) and, after அடுத்த, the Saturday
  ///   a week later. A counted amount after "முதல்", "இருந்து", கடந்த, சென்ற,
  ///   அடுத்த, முடிந்த, or a word of their kind counts from another event and
  ///   names no day ("கூட்டம் முடிந்த 3 நாட்களுக்குப் பிறகு", "கூட்டத்திலிருந்து
  ///   3 நாட்கள் கழித்து"). A date needs its day number beside the month name
  ///   (ஜனவரி, பிப்ரவரி, மார்ச், ஏப்ரல், மே, ஜூன், ஜூலை, ஆகஸ்ட், செப்டம்பர்,
  ///   அக்டோபர், நவம்பர், டிசம்பர், and the short forms the system writes with a
  ///   period: ஜன., பிப்., மார்., ஏப்., ஆக., செப்., அக்., நவ., டிச.); a month
  ///   alone, a short month with no period ("5 ஜன"), a month of the Tamil
  ///   calendar ("5 ஆடி"), a date in digits with no label and no ending ("5/10"),
  ///   and a date the calendar lacks ("31 ஏப்ரல்") stay in the title.
  /// - Date range: "3 முதல் 5 மார்ச்", "3 முதல் 5 மார்ச் வரை", "மார்ச் 3 முதல் 5
  ///   வரை", "3 மார்ச் முதல் 5 மார்ச் வரை", "மார்ச் 3-5", "3-5 மார்ச்", with a year
  ///   after a month. வரை, வரைக்கும், or வரையில் follows the end and may be left
  ///   out when the end names its month. The first day is the planned day and the
  ///   last the due day, so another day phrase stays in the title. A day written
  ///   without its month takes the month of the other side, the end must be after
  ///   the start ("5 முதல் 3 மார்ச்" stays in the title whole), a range with no
  ///   month ("3 முதல் 5") is never a range of days, and an end without a month
  ///   needs வரை or a dash. The end may carry க்கு or இல்; any other letter glued
  ///   to it leaves the line unread. A day alone opens a range joined by a dash
  ///   only when the dash touches both sides: "Sprint 12 - 20 மார்ச்" names a
  ///   sprint and a date. A range in the past tense stays in the title whole. A
  ///   span of weekdays ("திங்கள் முதல் புதன் வரை", "வெள்ளி முதல் திங்கள்") plans
  ///   the coming first day and is due on the first last day after it; "வரையிலான"
  ///   after it makes it an adjective ("திங்கள் முதல் புதன் வரையிலான விடுமுறை")
  ///   and leaves it unread. After ஒவ்வொரு or beside the words for every day it
  ///   is a repeat instead, and Monday to Friday with none of them stays in the
  ///   title whole, since it is a week of work as often as it is the working
  ///   week.
  /// - Repeat: தினமும், தினந்தோறும், நாள்தோறும், ஒவ்வொரு நாளும், and those with a
  ///   part of the day ("தினமும் காலை", "ஒவ்வொரு இரவு", "தினசரி மாலை"), which
  ///   keeps its part for an hour beside it ("தினமும் காலை 6 மணிக்கு யோகா" is
  ///   every day at 06:00); "ஒவ்வொரு வாரமும்", "ஒவ்வொரு மாதமும்", "ஒவ்வொரு
  ///   வருடமும்", "ஒவ்வொரு ஆண்டும்"; "வாரந்தோறும்", "மாதந்தோறும்",
  ///   "வருடந்தோறும்", "ஆண்டுதோறும்"; "ஒவ்வொரு திங்கட்கிழமை", "ஒவ்வொரு திங்கள்
  ///   மற்றும் வியாழன்", "ஒவ்வொரு திங்கள், புதன், வெள்ளி", "திங்கள்தோறும்",
  ///   "திங்கட்கிழமைகளில்", "ஒவ்வொரு வாரமும் திங்கள்", "திங்களும் ஒவ்வொரு
  ///   வாரமும்"; "ஒவ்வொரு 2 நாட்களுக்கும்", "ஒவ்வொரு 3 வாரங்கள்", "ஒவ்வொரு மூன்று
  ///   மாதங்களுக்கும்", "ஒவ்வொரு 5 வருடங்களுக்கும்", "ஒவ்வொரு இரண்டாவது நாளும்",
  ///   "2 நாட்களுக்கு ஒருமுறை", "3 மாதங்களுக்கு ஒரு முறை", "நாள் விட்டு நாள்" (every
  ///   other day); "நாளுக்கு ஒருமுறை", "வாரத்திற்கு ஒருமுறை", "மாதத்துக்கு
  ///   ஒருமுறை", "ஆண்டுக்கு ஒருமுறை"; "ஒவ்வொரு மாதமும் 5ஆம் தேதி", "மாதந்தோறும்
  ///   முதல் தேதி", "5ஆம் தேதி ஒவ்வொரு மாதமும்"; "ஒவ்வொரு வார இறுதியும்", "வார
  ///   இறுதிகளில்", "ஒவ்வொரு வீக்கெண்டும்", "சனி ஞாயிறுகளில்"; the working days as
  ///   "வேலை நாட்களில்", "வார நாட்களில்", "ஒவ்வொரு வேலை நாளும்", or "தினமும் வார
  ///   நாட்களில்"; a span of weekdays with ஒவ்வொரு or the words for every day
  ///   ("ஒவ்வொரு திங்கள் முதல் வெள்ளி வரை", "திங்கள் முதல் வெள்ளி வரை தினமும்");
  ///   and தினசரி, வாராந்திர, மாதாந்திர, or வருடாந்திர at the end of the line,
  ///   before a colon or comma, or with "அடிப்படையில்", since they are ordinary
  ///   adjectives too ("வாராந்திர அறிக்கை" is a weekly report). An interval
  ///   shorter than a day ("ஒவ்வொரு 2 மணி நேரத்திற்கும்"), a count of weekends,
  ///   workdays, or Mondays ("3 வார இறுதிகளில்", "3 திங்கட்கிழமைகளில்"), and the
  ///   second Monday ("ஒவ்வொரு இரண்டாவது திங்கட்கிழமை") are no repeat. ஒவ்வொரு
  ///   is also the word for a rate, so "ஒவ்வொரு நாளும் 500 ரூபாய்" is read as a
  ///   daily repeat.
  /// - Due: a day before வரை, வரைக்கும், or வரையில், or with க்குள் or க்குள்ளாக
  ///   glued to it ("வெள்ளிக்கிழமை வரை", "வெள்ளிக்கிழமைக்குள்", "நாளைக்குள்",
  ///   "5 மே வரை", "15ஆம் தேதிக்குள்", "இன்று இரவு வரை", "வெள்ளிக்கிழமை
  ///   மாலைக்குள்"); after காலக்கெடு, காலக்கெடு தேதி, கடைசி தேதி, இறுதி தேதி, கடைசி
  ///   நாள், இறுதி நாள், or டெட்லைன் ("காலக்கெடு: வெள்ளிக்கிழமை", "காலக்கெடு தேதி:
  ///   15 அக்டோபர்", "டெட்லைன் வெள்ளிக்கிழமை"); and before காலக்கெடு
  ///   ("வெள்ளிக்கிழமை காலக்கெடு", the way the app writes "Due Friday"). A day
  ///   before a clock deadline ("வெள்ளிக்கிழமை மாலை 5 மணிக்குள்") is the due
  ///   day, and the clock with its part of the day stays in the title. "இன்று
  ///   வரை" ("so far") is not read, nor is a day in a line that says a deadline
  ///   has passed ("காலக்கெடு முடிந்தது", "காலக்கெடு கடந்தது"), which is a
  ///   past-tense statement like the others.
  /// - Time: "5 மணிக்கு", "5:30 மணிக்கு", "ஐந்து மணிக்கு", "ஒரு மணிக்கு" (1:00),
  ///   "ஐந்தரைக்கு" (5:30), "ஐந்தரை மணிக்கு", "ஐந்தேகாலுக்கு" (5:15), "ஐந்தே
  ///   முக்காலுக்கு" (5:45), "ஐந்து முப்பது மணிக்கு" (5:30), "5 மணி 30
  ///   நிமிடத்திற்கு" (5:30), "மாலை 5க்கு", "இரவு 8:30க்கு", "3:30 PMக்கு", "மாலை
  ///   ஐந்தரை", "காலை 9:30", each maybe after சரியாக, துல்லியமாக, சுமார், or
  ///   கிட்டத்தட்ட. The hour counts with "மணி" (alone, or with க்கு, க்கே,
  ///   யளவில், or "முதல்" after it) or with a number and க்கு beside something
  ///   that makes it a time (a part of the day, a colon, or AM or PM), since
  ///   "5க்கு" alone may be a count or a date. The words for a half and a quarter
  ///   past an hour are also numbers ("ஐந்தரை கிலோ"), so they are a time only with
  ///   "மணி", an ending glued to them, or a part of the day. A part of the day
  ///   sets the hour and comes before it ("காலை 9 மணிக்கு", "இரவு 10 மணிக்கு",
  ///   "மாலை 5 மணிக்கு"). காலை and அதிகாலை are the morning (12 is no time),
  ///   மதியம் is noon at 12 and the afternoon from 1 to 6, மாலை is the evening,
  ///   and இரவு runs past midnight: "இரவு 12 மணிக்கு" is 00:00 of the next day,
  ///   "இரவு 2 மணிக்கு" is 02:00 of the next day, and "இரவு 8 மணிக்கு" is 20:00.
  ///   "நள்ளிரவு" is the midnight that ends the day, and so is the loanword
  ///   "மிட்நைட்" with an ending glued to it or with no Tamil word after it (the
  ///   system starts its colour names with it: "மிட்நைட் புளூ" is no time). An
  ///   hour on the 12-hour clock (1 to 12, no leading zero) written with no part
  ///   of the day beside it takes its half of the day from the one part of the
  ///   day the line names elsewhere: in its day phrase ("நாளை காலை கூட்டம் 6
  ///   மணிக்கு" is 06:00), after தினமும் or ஒவ்வொரு ("தினமும் காலை 6 மணிக்கு
  ///   யோகா"), or in a noun ("இரவு உணவு 8 மணிக்கு" is 20:00, "மதிய உணவு 1
  ///   மணிக்கு" is 13:00). Two parts that differ leave the hour as it reads
  ///   alone, and an hour on the 24-hour clock (a leading zero, 0, or 13 and
  ///   later) is read as written. An hour from 1 to 6 with no part of the day
  ///   anywhere in the line is the afternoon, as in the other languages ("5
  ///   மணிக்கு" is 17:00, "7 மணிக்கு" is 07:00), unless written with a leading
  ///   zero ("06:30 மணிக்கு"). A range:
  ///   "9 மணி முதல் 11 மணி வரை", "காலை 9 முதல் 11 வரை", "மதியம் 2 மணி முதல் மாலை
  ///   4 மணி வரை", "9-11 மணிக்கு", "14:00 முதல் 16:00 வரை", and a range right
  ///   after a part of the day that a repeat or இந்த owns ("தினமும் காலை 9 முதல்
  ///   11 வரை", "இந்த மாலை 5 முதல் 7 வரை"); "3 முதல் 5 வரை" with none of these
  ///   is a range of numbers, not of hours. A clock time that is a bound stays in
  ///   the title whole: "5 மணிக்குள்", "மாலை 6க்குள்", "5 மணிக்கெல்லாம்", "5 மணி
  ///   வரை", "18:00 வரை", "3 PMக்குள்", "5 மணிக்குப் பிறகு", "5 மணிக்கு முன்".
  ///   "5 மணி 30 நிமிடங்கள்" with no ending after the minutes may be a time or a
  ///   length and stays whole. A number before a percent sign, a currency sign,
  ///   or a currency word is never a time, and neither is a number after a slash
  ///   ("5/6 மணிக்கு"), which belongs to a fraction or a date.
  /// - Length: "30 நிமிடங்கள்", "2 மணி நேரம்", "1.5 மணி நேரம்", "1 மணி நேரம் 30
  ///   நிமிடங்கள்" (also "1 மணி நேரம், 30 நிமிடங்கள்", the minutes in words as
  ///   in "ஒரு மணி நேரம் முப்பது நிமிடங்கள்", and the system's "1 ம. 30 நிமி."
  ///   and "1 மணி, 30 நிமி"), "அரை மணி நேரம்" (30, also "ஒரு அரை மணி நேரம்"),
  ///   "கால் மணி நேரம்" (15), "முக்கால் மணி நேரம்" (45), "ஒன்றரை மணி நேரம்"
  ///   (90), "1 மற்றும் அரை மணிநேரம்" (90), "இரண்டரை மணி நேரம்", "இரண்டு மணி
  ///   நேரம்", "இருபது நிமிடங்கள்", each maybe after சுமார், கிட்டத்தட்ட, or
  ///   தோராயமாக, and with the unit in its dative ("2 மணி நேரத்திற்கு" is for 2
  ///   hours) or in its form before a noun ("30 நிமிட கூட்டம்" is a meeting of
  ///   30 minutes). An amount before கழித்து, முன், பிறகு, வரை, முதல், or the
  ///   like after the unit, or after குறைந்தது, அதிகபட்சம், ஒவ்வொரு, or "ஒரு
  ///   நாளைக்கு" before it, names a moment, an interval, or a bound, not a
  ///   length ("2 மணி நேரம் கழித்து", "ஒவ்வொரு 2 மணி நேரம்", "ஒரு நாளைக்கு 30
  ///   நிமிடங்கள்"), and neither is a side of a range ("2 முதல் 3 மணி நேரம்",
  ///   "5 நிமிடங்கள் முதல் 10 நிமிடங்கள்"): each stays whole in the title. "ஒரு
  ///   மணிநேரத்திற்கு" or "ஒரு நிமிடத்திற்கு" before a number or a placeholder
  ///   means "per hour" or "per minute" ("ஒரு மணிநேரத்திற்கு 5 மைல்கள்") and is
  ///   no length either. A number after a slash ("1/2 மணிநேரம்") belongs to a
  ///   fraction, an amount whose unit has any other ending ("2 மணி நேரத்தில்",
  ///   "30 நிமிடங்களில்") is no length, and "மணி" alone is none.
  /// - Priority: அதிக முன்னுரிமை, இயல்பான முன்னுரிமை, குறைந்த முன்னுரிமை (also
  ///   உயர், உயர்ந்த, அதிகபட்ச, உச்ச, நடுத்தர, மிதமான, சாதாரண, வழக்கமான,
  ///   மீடியம், நார்மல், குறைவான, குறைந்தபட்ச, and தாழ்ந்த for the levels),
  ///   each also after the word ("முன்னுரிமை: அதிகம்", "முன்னுரிமை: இயல்பு",
  ///   "முன்னுரிமை: குறைவு"); அவசரம், அவசரமாக, முக்கியம், முக்கியமானது, or
  ///   அர்ஜென்ட், maybe after மிகவும், மிக, or அதி, at the end of the line, and
  ///   the same words opening it before a colon or comma ("அவசரம்: அறிக்கையை
  ///   அனுப்பு"). These are ordinary words too, so "முக்கியம் இல்லை" and "அவசர
  ///   சிகிச்சை" stay in the title, and so does a level that describes a noun
  ///   ("அதிக முன்னுரிமை உள்ள பணிகள்").
  static let tamil = LorvexCaptureVocabulary(
    readingForm: tamilForMatching,
    priority: [tamilRule(tamilPriorityPattern, read: tamilPriority)],
    dateRange: [
      tamilRule(tamilDateRangePattern, read: tamilDateRange),
      tamilRule(tamilWeekdayRangePattern, read: tamilWeekdayRange),
    ],
    keptInTitle: [
      tamilRule(tamilDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      tamilRule(tamilLengthPattern) { tamilDeclinesLength($0) ? true : nil },
    ],
    length: [tamilRule(tamilLengthPattern, read: tamilLength)],
    time: [
      tamilRule(tamilTimeRangePattern, read: tamilTimeRange),
      tamilRule(tamilColonTimeRangePattern, read: tamilTimeRange),
      tamilRule(tamilHourPattern, read: tamilHourTime),
      tamilRule(tamilWordTimePattern, read: tamilWordTime),
      tamilRule(tamilDativeTimePattern, read: tamilDativeTime),
      tamilRule(tamilColonTimePattern, read: tamilColonTime),
      tamilRule(tamilMidnightPattern) { _ in ClockTime(minutes: 0, isAfterMidnight: true) },
    ],
    repeats: tamilRepeatRules,
    due: [tamilRule(tamilDuePattern, read: tamilDue)],
    when: [tamilRule(tamilWhenPattern, read: tamilWhen)])

  // MARK: - Reading form and patterns

  /// The line with each Tamil digit (௦-௯, U+0BE6-U+0BEF) read as an ASCII
  /// digit. Each replacement is one UTF-16 unit for one, so a match range in the
  /// result is the same range in `line`.
  static func tamilForMatching(_ line: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in line.unicodeScalars { scalars.append(tamilReading(of: scalar)) }
    return String(scalars)
  }

  private static func tamilReading(of scalar: Unicode.Scalar) -> Unicode.Scalar {
    switch scalar {
    case "\u{0BE6}"..."\u{0BEF}": Unicode.Scalar(UInt8(truncatingIfNeeded: 0x30 + scalar.value - 0x0BE6))
    default: scalar
    }
  }

  /// `text` as a reader compares a word: in canonical composed form (so a vowel
  /// sign typed as two signs is the one sign) and without zero-width joiners.
  /// `text` is already in the reading form. Comparisons of Tamil text go through
  /// scalars or whole words: a `Character` is a grapheme cluster ("கு" is one),
  /// so `hasPrefix("க")` does not match "குறைவு".
  static func tamilBare(_ text: String) -> String {
    var result = String.UnicodeScalarView()
    for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars where scalar != "\u{200C}" && scalar != "\u{200D}" {
      result.append(scalar)
    }
    return String(result)
  }

  /// A matched phrase as a reader compares it: as ``tamilBare(_:)`` leaves it,
  /// each run of spaces as one, hyphens read as spaces.
  static func tamilPhrase(_ text: String) -> String {
    normalizedPhrase(tamilBare(text))
  }

  /// A word written in a vocabulary table, as ``tamilPhrase(_:)`` leaves a
  /// matched word, whichever way the table spells it.
  static func tamilKey(_ word: String) -> String {
    tamilBare(tamilForMatching(word))
  }

  /// The same as ``tamilKey(_:)`` with its spaces left out, for a word the
  /// table writes in one word or two ("அரை மணி" and "அரைமணி").
  static func tamilCompactKey(_ word: String) -> String {
    tamilKey(word).replacingOccurrences(of: " ", with: "")
  }

  /// Whether the scalars of `key` start with the scalars of `prefix`. Both are
  /// in the form ``tamilKey(_:)`` leaves them.
  static func tamilHasPrefix(_ key: String, _ prefix: String) -> Bool {
    key.unicodeScalars.starts(with: prefix.unicodeScalars)
  }

  /// `pattern`, written in the composed letters of its words, ready to match a
  /// line in the reading form.
  ///
  /// A pulli (the virama ்) may have zero-width joiners on either side, each
  /// vowel sign and letter that Unicode composes from two parts (ொ, ோ, ௌ, ஔ)
  /// also matches the parts it is made of, and a quantifier that follows such a
  /// sign applies to the sign with its extras. A middle dot (·) marks the
  /// boundary between a word and an ending glued to it, where a zero-width
  /// joiner or non-joiner may have been typed. The pattern is read in canonical
  /// composed form, so a letter or sign typed there in any spelling is read
  /// like its base. Escapes and character sets pass through. A pattern is
  /// expanded once, by ``tamilRule(_:read:)``, never in parts that another
  /// pattern then embeds.
  static func tamil(_ pattern: String) -> String {
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
        result.unicodeScalars.append(tamilReading(of: scalar))
      } else if scalar == "[" {
        isInSet = true
        result.unicodeScalars.append(scalar)
      } else if scalar == "\u{00B7}" {
        result += joiners
      } else {
        let reading = tamilReading(of: scalar)
        var unit = String(Character(reading))
        switch reading {
        case "\u{0BCD}":
          unit = joiners + unit + joiners
        case "\u{0BCA}":
          unit = #"(?:\x{0BCA}|\x{0BC6}\x{0BBE})"#
        case "\u{0BCB}":
          unit = #"(?:\x{0BCB}|\x{0BC7}\x{0BBE})"#
        case "\u{0BCC}":
          unit = #"(?:\x{0BCC}|\x{0BC6}\x{0BD7})"#
        case "\u{0B94}":
          unit = #"(?:\x{0B94}|\x{0B92}\x{0BD7})"#
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
  /// ``tamil(_:)``).
  static func tamilRule<Value>(_ pattern: String, read: @escaping @Sendable (Match) -> Value?) -> Rule<Value> {
    Rule(pattern: tamil(pattern), read: read)
  }

  /// Whether `pattern`, written in composed letters, matches somewhere in
  /// `text`, which is in the reading form.
  static func tamilFinds(_ pattern: String, in text: String) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(tamil(pattern)) else { return false }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  /// `words` as the alternatives of a pattern, longest first (by scalars, so a
  /// word that a sign makes longer comes before the word it starts with) and
  /// without repeats, a space inside a word standing for any run of spaces.
  static func tamilAlternation(of words: [String]) -> String {
    let unique: [String] = Array(Set(words))
    let ordered = unique.sorted { (first: String, second: String) -> Bool in
      let firstCount = first.unicodeScalars.count
      let secondCount = second.unicodeScalars.count
      return firstCount != secondCount ? firstCount > secondCount : first < second
    }
    return ordered.map { $0.replacingOccurrences(of: " ", with: #"\s*"#) }.joined(separator: "|")
  }

  // MARK: - Boundaries and words around a detail

  /// A word boundary for words written in the Tamil script: no Tamil letter,
  /// vowel sign, pulli, joiner, or digit on that side, and no hyphen that joins
  /// it to another Tamil word.
  static let tamilStart =
    #"(?<![\p{Tamil}\p{M}\p{N}\x{200C}\x{200D}])(?<![\p{Tamil}\p{M}]-)"#
  static let tamilEnd =
    #"(?![\p{Tamil}\p{M}\p{N}\x{200C}\x{200D}])(?!-\p{Tamil})"#

  /// The words for a sum of money, which make a number before them an amount.
  private static let tamilCurrencyWords = #"(?:ரூபாய்கள்|ரூபாய்|ரூ|டாலர்கள்|டாலர்|யூரோ|பைசா|காசு)"#

  /// What may follow a clock time: no Tamil letter, vowel sign, digit, or colon
  /// (the word or the number goes on), no decimal fraction, no percent or
  /// currency sign or word with or without a space before it (the number is an
  /// amount: "20%", "500 ரூபாய்"), no dash before a digit (a range written with
  /// a dash and no மணிக்கு is English's), and no AM or PM after it.
  static let tamilTimeEnd =
    #"(?![\p{Tamil}\p{M}\p{N}\x{200C}\x{200D}:]|[.,]\p{N}|\s*[%\p{Sc}]|\s*\#(tamilCurrencyWords)\#(tamilEnd)|\s*[-–—]\s*\d)\#(noMeridiemAfter)"#

  /// What may follow a date: no Tamil letter, vowel sign, digit, or colon, no
  /// decimal fraction, and no hyphen that joins a Tamil word to it.
  static let tamilDateEnd = #"(?![\p{Tamil}\p{M}\p{N}\x{200C}\x{200D}:]|[.,]\p{N}|-\p{Tamil})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let tamilNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// The consonant a Tamil writer glues to the end of a word before a word
  /// that starts with the same consonant ("நாளைக்குத் தள்ளிவை", "இந்தச்
  /// சனிக்கிழமை", "நாளைக் காலை"), as a pattern that is empty when none is
  /// typed. Only க், ச், த், and ப் double, and the next word must start with
  /// the same letter, so an unrelated letter is never taken for it.
  static let tamilSandhi = #"(?:க்(?=\s+க)|ச்(?=\s+ச)|த்(?=\s+த)|ப்(?=\s+ப))?"#

  /// The word just before `match` as a reader compares it, or nil when the
  /// match opens the line or punctuation comes first.
  static func tamilWordBefore(_ match: Match) -> String? {
    guard let word = wordBefore(match).map(tamilBare), !word.isEmpty else { return nil }
    return word
  }

  /// Whether a digit comes right before `match`, with at most a space between.
  static func tamilFollowsNumber(_ match: Match) -> Bool {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return false }
    return match.source[..<start].reversed().drop(while: \.isWhitespace).first?.isNumber ?? false
  }

  /// The words of `text`, as letters only and as ``tamilBare(_:)`` leaves
  /// them.
  static func tamilWords(in text: String) -> [String] {
    text.split(whereSeparator: { !$0.isLetter }).map { tamilBare(String($0)) }
  }

  /// The words and numbers of `text`, with each run of digits and each run of
  /// letters apart ("15ஆம்" is "15" and "ஆம்").
  static func tamilRuns(_ text: String) -> [String] {
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

  /// The numerals one to twelve that stand before "மணி" for an hour on the
  /// clock: "இரண்டு மணிக்கு", "ஐந்து மணிக்கு", and ஒரு for one ("ஒரு மணிக்கு"),
  /// in the spellings people type, the spoken ones included ("ரெண்டு", "நாலு",
  /// "அஞ்சு").
  private static let tamilHourWordSpellings: [(Int, [String])] = [
    (1, ["ஒரு"]), (2, ["இரண்டு", "ரெண்டு"]), (3, ["மூன்று", "மூணு"]), (4, ["நான்கு", "நாலு"]), (5, ["ஐந்து", "அஞ்சு"]),
    (6, ["ஆறு"]), (7, ["ஏழு"]), (8, ["எட்டு"]), (9, ["ஒன்பது", "ஒம்பது"]), (10, ["பத்து"]),
    (11, ["பதினொரு", "பதினோரு", "பதினொன்று"]), (12, ["பன்னிரண்டு", "பன்னிரெண்டு"]),
  ]

  /// The hour words as keys.
  static let tamilHourWords: [String: Int] = {
    var words: [String: Int] = [:]
    for (value, spellings) in tamilHourWordSpellings {
      for word in spellings { words[tamilCompactKey(word)] = value }
    }
    return words
  }()

  /// The hour words as a pattern.
  static var tamilHourWordPattern: String {
    tamilAlternation(of: tamilHourWordSpellings.flatMap { $0.1 })
  }

  /// The counting forms one to twelve, which stand before "முப்பது" in the
  /// clock-face phrase ("ஐந்து முப்பது மணி" is 5:30) and are the hour words
  /// with ஒன்று for one.
  private static let tamilCountingSpellings: [(Int, [String])] = [
    (1, ["ஒன்று", "ஒண்ணு"]), (2, ["இரண்டு", "ரெண்டு"]), (3, ["மூன்று", "மூணு"]), (4, ["நான்கு", "நாலு"]),
    (5, ["ஐந்து", "அஞ்சு"]), (6, ["ஆறு"]), (7, ["ஏழு"]), (8, ["எட்டு"]), (9, ["ஒன்பது", "ஒம்பது"]), (10, ["பத்து"]),
    (11, ["பதினொன்று", "பதினொரு", "பதினோரு"]), (12, ["பன்னிரண்டு", "பன்னிரெண்டு"]),
  ]

  /// The counting forms as keys.
  static let tamilCountingWords: [String: Int] = {
    var words: [String: Int] = [:]
    for (value, spellings) in tamilCountingSpellings {
      for word in spellings { words[tamilCompactKey(word)] = value }
    }
    return words
  }()

  /// The counting forms as a pattern.
  static var tamilCountingWordPattern: String {
    tamilAlternation(of: tamilCountingSpellings.flatMap { $0.1 })
  }

  /// Each hour's word without its last vowel, which the words for a half, a
  /// quarter past, and three quarters past an hour are built on: "ஐந்த" for
  /// 5 gives "ஐந்தரை" (5:30), "ஐந்தேகால்" (5:15), and "ஐந்தே முக்கால்" (5:45).
  private static let tamilFractionBases: [(Int, [String])] = [
    (1, ["ஒன்ற", "ஒண்ண"]), (2, ["இரண்ட", "ரெண்ட"]), (3, ["மூன்ற", "மூண"]), (4, ["நான்க", "நால"]),
    (5, ["ஐந்த", "அஞ்ச"]), (6, ["ஆற"]), (7, ["ஏழ"]), (8, ["எட்ட"]), (9, ["ஒன்பத", "ஒம்பத"]), (10, ["பத்த"]),
    (11, ["பதினொன்ற"]), (12, ["பன்னிரண்ட", "பன்னிரெண்ட"]),
  ]

  /// The words for an hour and a half, a quarter past, and three quarters past,
  /// each with the hour and the minutes it names: "ஐந்தரை" is 5:30, "ஐந்தேகால்"
  /// 5:15, and "ஐந்தே முக்கால்" 5:45, the ways spoken Tamil tells the clock.
  static let tamilFractionSpellings: [(hour: Int, minute: Int, words: [String])] = {
    var rows: [(hour: Int, minute: Int, words: [String])] = []
    for (hour, bases) in tamilFractionBases {
      rows.append((hour, 30, bases.map { $0 + "ரை" }))
      rows.append((hour, 15, bases.map { $0 + "\u{0BC7}கால்" }))
      rows.append((hour, 45, bases.map { $0 + "\u{0BC7} முக்கால்" }))
    }
    return rows
  }()

  /// The half-hour, quarter, and three-quarter words as keys, each with its
  /// hour and minutes.
  static let tamilFractionTimes: [String: (hour: Int, minute: Int)] = {
    var words: [String: (hour: Int, minute: Int)] = [:]
    for row in tamilFractionSpellings {
      for word in row.words { words[tamilCompactKey(word)] = (row.hour, row.minute) }
    }
    return words
  }()

  /// The half-hour, quarter, and three-quarter words as a pattern.
  static var tamilFractionWordPattern: String {
    tamilAlternation(of: tamilFractionSpellings.flatMap { $0.words })
  }

  /// The half-hour words alone (without the quarters), which name a length when
  /// a unit follows ("ஒன்றரை மணி நேரம்" is 90 minutes), as a pattern.
  static var tamilHalfWordPattern: String {
    tamilAlternation(of: tamilFractionSpellings.filter { $0.minute == 30 }.flatMap { $0.words })
  }

  /// The numerals of an amount of hours, days, weeks, or months that stand
  /// before their noun ("மூன்று நாட்கள்", "இரு வாரங்கள்", "ஒரு மாதம்"): one to
  /// twelve, written out in full.
  private static let tamilAmountSpellings: [(Int, [String])] = [
    (1, ["ஒரு"]), (2, ["இரு", "இரண்டு", "ரெண்டு"]), (3, ["மூன்று", "மூணு"]), (4, ["நான்கு", "நாலு"]),
    (5, ["ஐந்து", "அஞ்சு"]), (6, ["ஆறு"]), (7, ["ஏழு"]), (8, ["எட்டு"]), (9, ["ஒன்பது", "ஒம்பது"]), (10, ["பத்து"]),
    (11, ["பதினொரு", "பதினோரு", "பதினொன்று"]), (12, ["பன்னிரண்டு", "பன்னிரெண்டு"]),
  ]

  /// The round numbers of an amount of minutes or days: fourteen to sixty.
  private static let tamilRoundSpellings: [(Int, [String])] = [
    (14, ["பதினான்கு"]), (15, ["பதினைந்து"]), (20, ["இருபது"]), (25, ["இருபத்தைந்து", "இருபத்து ஐந்து"]),
    (30, ["முப்பது"]), (40, ["நாற்பது"]), (45, ["நாற்பத்தைந்து", "நாற்பத்து ஐந்து"]), (50, ["ஐம்பது"]), (60, ["அறுபது"]),
  ]

  /// The numerals of an amount, as keys.
  static let tamilCounts: [String: Int] = {
    var counts: [String: Int] = [:]
    for (value, spellings) in tamilAmountSpellings {
      for word in spellings { counts[tamilCompactKey(word)] = value }
    }
    return counts
  }()

  /// The numerals of an amount of minutes or days: the counts above and the
  /// round numbers up to sixty, as keys.
  static let tamilRoundCounts: [String: Int] = {
    var counts = tamilCounts
    for (value, spellings) in tamilRoundSpellings {
      for word in spellings { counts[tamilCompactKey(word)] = value }
    }
    return counts
  }()

  /// The numerals of an amount, as a pattern.
  static var tamilCountWords: String {
    tamilAlternation(of: tamilAmountSpellings.flatMap { $0.1 })
  }

  /// The numerals of an amount of minutes or days, as a pattern.
  static var tamilRoundCountWords: String {
    tamilAlternation(of: (tamilAmountSpellings + tamilRoundSpellings).flatMap { $0.1 })
  }

  // MARK: - Priority

  /// Group 1: a written priority, with its level before or after the word
  /// "முன்னுரிமை"; an urgent word has no group. A level word with "உள்ள" or
  /// "கொண்ட" after the priority describes a noun ("அதிக முன்னுரிமை உள்ள
  /// பணிகள்") and is no priority.
  private static var tamilPriorityPattern: String {
    let high = "அதிகபட்சம்|அதிகபட்ச|அதிகம்|அதிக|உயர்ந்த|உயர்வு|உயர்|உச்ச|முதன்மை"
    let medium =
      "நடுத்தரமானது|நடுத்தரம்|நடுத்தர|மிதமானது|மிதமான|மிதம்|இயல்பானது|இயல்பான|இயல்பு|வழக்கமானது|வழக்கமான|சாதாரணம்|சாதாரண|மீடியம்|நார்மல்"
    let low = "குறைந்தபட்சம்|குறைந்தபட்ச|குறைந்த|குறைவான|குறைவு|தாழ்ந்த"
    let level = "\(high)|\(medium)|\(low)"
    let word = "முன்னுரிமை"
    let urgent =
      #"(?:(?:மிகவும்|மிக|அதி)\s+)?(?:அவசரமாக|அவசரம்|அர்ஜென்ட்|அர்ஜெண்ட்|அர்ஜன்ட்|முக்கியமானது|முக்கியம்)"#
    let described = #"(?!\s+(?:உள்ள|உள்ளவை|கொண்ட|கொண்டவை|உடைய)\#(tamilEnd))"#
    return
      #"\#(tamilStart)((?:\#(level))\s*\#(word)|\#(word)\s*[:：]?\s*(?:\#(level)))\#(tamilEnd)\#(described)|(?<=\s)(?:\#(urgent))\#(tamilEnd)(?=\s*[.!]?\s*$)|^\s*(?:\#(urgent))\#(tamilEnd)(?=\s*[:：,，])"#
  }

  private static func tamilPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1).map(tamilPhrase) else { return .p1 }
    let words = Set(tamilWords(in: phrase))
    let medium = [
      "நடுத்தரமானது", "நடுத்தரம்", "நடுத்தர", "மிதமானது", "மிதமான", "மிதம்", "இயல்பானது", "இயல்பான", "இயல்பு", "வழக்கமானது",
      "வழக்கமான", "சாதாரணம்", "சாதாரண", "மீடியம்", "நார்மல்",
    ]
    if !words.isDisjoint(with: medium.map(tamilKey)) { return .p2 }
    let low = ["குறைந்தபட்சம்", "குறைந்தபட்ச", "குறைந்த", "குறைவான", "குறைவு", "தாழ்ந்த"]
    if !words.isDisjoint(with: low.map(tamilKey)) { return .p3 }
    return .p1
  }
}
