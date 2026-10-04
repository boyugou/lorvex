extension LorvexSampleText {
  /// The sample datasets in Urdu. People are سمیر (Sam), عمران (Alex), and
  /// ثنا (Maya) in every dataset; product names (Zoom, Swift, GRPO, Apple)
  /// and the abbreviations AI and UI stay as written, and Q3 is written تیسری
  /// سہ ماہی. The team offsite is an آف سائٹ, and the car chore is the گاڑی کی
  /// رجسٹریشن کی تجدید. Notes about the user use the honorific plural, and
  /// the briefings and reviews use past-tense verbs that agree with their
  /// object, so no sentence depends on the speaker's gender. The Swift
  /// migration review is titled جائزہ: Swift پر منتقلی so the title starts
  /// with Urdu text and reads in order under a right-to-left base direction.
  static let urdu: [String: String] = [
    // Tags.
    "work": "کام",
    "planning": "منصوبہ بندی",
    "weekly": "ہفتہ وار",
    "home": "گھر",
    "urgent": "فوری",
    "engineering": "انجینئرنگ",
    "research": "تحقیق",
    "someday": "کسی دن",

    // Lists.
    "Apple Native": "ایکو سسٹم Apple",
    "Apple ecosystem apps and gear to try": "آزمانے کے لیے Apple ایکو سسٹم کی ایپس اور ڈیوائسز",
    "Work": "کام",
    "Day job & deep work": "ملازمت اور گہرا کام",
    "Personal": "ذاتی",
    "Reading": "مطالعہ",
    "Papers & books": "مقالات اور کتابیں",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "ٹیم آف سائٹ کے ایجنڈے کا مسودہ بنانا",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "سیشنز کا وقت طے کرنا، کلیدی خطاب چننا اور چھوٹے گروپس کی بحث کے لیے وقت رکھنا۔",
    "Confirm session topics with the leads": "ٹیم لیڈز سے سیشنز کے موضوعات کی تصدیق کرنا",
    "Share the draft agenda for feedback": "فیڈبیک کے لیے ایجنڈے کا مسودہ شیئر کرنا",
    "Book the offsite venue": "آف سائٹ کے لیے جگہ بک کرنا",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "چنی ہوئی دونوں جگہوں کا موازنہ کر کے گروپ کے لیے موزوں جگہ بک کرنا۔",
    "Send the weekly status update": "ہفتہ وار اسٹیٹس اپ ڈیٹ بھیجنا",
    "Summarize progress, blockers, and next steps for the team.":
      "ٹیم کے لیے پیش رفت، رکاوٹوں اور اگلے اقدامات کا خلاصہ تیار کرنا۔",
    "Look into a standing-desk setup": "کھڑے ہو کر کام کرنے والی میز کا سیٹ اپ دیکھنا",
    "Keep this as a someday idea until the home office is sorted.":
      "جب تک ہوم آفس تیار نہیں ہو جاتا، اسے \"کسی دن\" والا آئیڈیا ہی رہنے دیں۔",
    "Pick the offsite dates": "آف سائٹ کی تاریخیں طے کرنا",
    "Cross-check the team calendar and lock the week.": "ٹیم کے کیلنڈر سے ملا کر ہفتہ پکا کرنا۔",
    "Order a second monitor": "دوسرا مانیٹر منگوانا",
    "Dropped in favour of using the laptop display on the desk.":
      "منسوخ کیا؛ میز پر لیپ ٹاپ کی اسکرین ہی کافی ہے۔",
    "Renew the car registration": "گاڑی کی رجسٹریشن کی تجدید کروانا",
    "Reply to Maya about the catering quote": "کیٹرنگ کے کوٹیشن کے بارے میں ثنا کو جواب دینا",
    "Review the Q3 budget draft": "تیسری سہ ماہی کے بجٹ کے مسودے کا جائزہ لینا",
    "Outline the board deck": "بورڈ پریزنٹیشن کا خاکہ بنانا",
    "Draft the hiring plan": "بھرتی کے منصوبے کا مسودہ بنانا",
    "Reply to the investor update email": "سرمایہ کاروں کی اپ ڈیٹ والی ای میل کا جواب دینا",
    "Review the Q3 planning doc": "تیسری سہ ماہی کی منصوبہ بندی کی دستاویز کا جائزہ لینا",
    "Refactor the sync layer": "سنک لیئر کو ری فیکٹر کرنا",
    "Buy groceries for the week": "ہفتے بھر کا سودا سلف خریدنا",
    "Read the GRPO paper": "مقالہ GRPO پڑھنا",
    "Renew passport": "پاسپورٹ کی تجدید کروانا",
    "Plan the spring offsite": "بہار کے آف سائٹ کی منصوبہ بندی کرنا",
    "Submit the weekly timesheet": "ہفتہ وار ٹائم شیٹ جمع کرانا",
    "Book the dentist appointment": "دانتوں کے ڈاکٹر کا وقت لینا",
    "Review the launch checklist": "لانچ کی چیک لسٹ کا جائزہ لینا",

    // Deferral notes.
    "The agenda comes first": "پہلے ایجنڈا",
    "Groceries can wait for the evening": "سودا سلف شام تک رک سکتا ہے",

    // Habits and their cues.
    "Daily Review": "روزانہ جائزہ",
    "End of day": "دن کے آخر میں",
    "Evening walk": "شام کی چہل قدمی",
    "After dinner": "رات کے کھانے کے بعد",
    "Morning run": "صبح کی دوڑ",
    "After waking up": "جاگنے کے بعد",
    "Read 30 minutes": "30 منٹ مطالعہ",
    "Read 30 min": "30 منٹ مطالعہ",
    "Before bed": "سونے سے پہلے",
    "Meditate": "مراقبہ",
    "Mid-morning": "صبح کے وسط میں",
    "Review the day": "دن کا جائزہ",
    "Evening": "شام",
    "Evening journal": "شام کی ڈائری",

    // Calendar events and locations.
    "Swift migration review": "جائزہ: Swift پر منتقلی",
    "Conference Room B": "کانفرنس روم B",
    "Team standup": "ٹیم اسٹینڈ اپ",
    "1:1 with Sam": "سمیر کے ساتھ ون آن ون",
    "Design review": "ڈیزائن کا جائزہ",
    "Studio": "اسٹوڈیو",
    "Sprint planning": "اسپرنٹ کی منصوبہ بندی",
    "Lunch with Sam": "سمیر کے ساتھ لنچ",
    "1:1 with Alex": "عمران کے ساتھ ون آن ون",
    "Customer call": "کسٹمر کال",
    "Dentist": "دانتوں کا ڈاکٹر",
    "Roadmap sync": "روڈ میپ سنک",
    "Morning gym": "صبح جم",
    "Demo day": "ڈیمو ڈے",
    "Team offsite": "ٹیم آف سائٹ",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "سب سے پہلے آف سائٹ کا ایجنڈا: جب تک وہ طے نہیں ہوتا، جگہ بک نہیں ہو سکتی، اس لیے بکنگ کل تک کے لیے ملتوی کر دی ہے۔ آج دوپہر کے بعد دو میٹنگیں ہیں۔",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "پہلے منصوبہ بندی کا جائزہ، جب تک دستاویز ذہن میں تازہ ہے؛ سنک لیئر کی ری فیکٹرنگ کے لیے لنچ سے پہلے کا لمبا بلاک رکھا ہے۔",
    "The launch checklist first; the status update after the design review.":
      "پہلے لانچ کی چیک لسٹ؛ اسٹیٹس اپ ڈیٹ ڈیزائن کے جائزے کے بعد۔",

    // Memory.
    "notes_for_ai": "نوٹس برائے AI",
    "new_laptop": "نیا لیپ ٹاپ",
    "work_rhythm": "کام کی لے",
    "working_hours": "کام کے اوقات",
    "manager": "مینیجر",
    "writing_style": "لکھنے کا انداز",
    "current_focus": "موجودہ فوکس",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "صارف ایک ذاتی سائیڈ پروجیکٹ کے لیے چند UI فریم ورکس کا موازنہ کر رہے ہیں — تکنیکی تجاویز کسی ایک فریم ورک کے حق میں نہ ہوں۔",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "لیپ ٹاپ بدلنے سے پہلے ڈیٹا بیس اور فوٹو لائبریری ایکسپورٹ کر لیں، تاکہ منتقلی میں کچھ ضائع نہ ہو۔",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "گہرا کام لنچ سے پہلے کرتے ہیں؛ دوپہر کے بعد کا وقت میٹنگز اور ای میل کے لیے رکھتے ہیں۔",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "صبح 9 سے دوپہر 12 بجے تک سب سے اچھی توجہ رہتی ہے؛ صبح کا وقت گہرے کام کے لیے بچا کر رکھیں۔",
    "Reports to Alex; weekly 1:1 on Mondays.":
      "عمران کو رپورٹ کرتے ہیں؛ ہر پیر کو ہفتہ وار ون آن ون۔",
    "Prefers concise, direct updates — no filler.":
      "مختصر اور سیدھی اپ ڈیٹس پسند کرتے ہیں، بغیر لمبی تمہید کے۔",
    "Shipping the Apple-native rewrite this quarter.":
      "اس سہ ماہی میں Apple نیٹو ری رائٹ جاری ہونا ہے۔",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "ہفتے کا جائزہ لیا اور اگلے ہفتے کی آف سائٹ منصوبہ بندی ترتیب دے دی۔",
    "Cleared the inbox and locked in the offsite dates.":
      "ان باکس خالی کیا اور آف سائٹ کی تاریخیں پکی کر لیں۔",
    "Still waiting on venue quotes before booking.": "بکنگ سے پہلے جگہوں کے کوٹیشن کا انتظار ہے۔",
    "Batching errands into one afternoon freed up the rest of the week.":
      "سارے چھوٹے موٹے کام ایک ہی دوپہر میں نمٹانے سے باقی ہفتہ خالی ہو گیا۔",
    "Solid morning of deep work; shipped the planning review.":
      "صبح گہرے کام کے لیے اچھی رہی؛ منصوبہ بندی کا جائزہ مکمل ہو گیا۔",
    "Unblocked the sync layer; cleared the investor email.":
      "سنک لیئر کی رکاوٹ دور کی؛ سرمایہ کاروں کی ای میل کا جواب بھی دے دیا۔",
    "Waiting on design sign-off for the calendar grid.":
      "کیلنڈر گرڈ کے ڈیزائن کی منظوری کا انتظار ہے۔",
    "Batching reviews before noon keeps the afternoon open.":
      "جائزے دوپہر سے پہلے ایک ساتھ نمٹانے سے دوپہر کے بعد کا وقت خالی رہتا ہے۔",
    "Steady progress across tasks.": "تمام کاموں میں مسلسل پیش رفت۔",
    "Closed a few items.": "کچھ کام نمٹائے۔",
  ]
}
