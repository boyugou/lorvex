extension LorvexSampleText {
  /// The sample datasets in Persian. People are سامان (Sam), آرش (Alex), and
  /// مینا (Maya) in every dataset; product names (Zoom, Swift, GRPO, Apple)
  /// and the abbreviation UI stay as written, and Q3 is written سه‌ماهه سوم.
  /// The team offsite is a گردهمایی, and the car chore is the تمدید بیمه
  /// خودرو, the vehicle insurance renewal. Compounds and suffixes carry the
  /// zero-width non-joiner (U+200C) the app's Persian catalog uses, digits
  /// are ASCII and come back as Persian digits under a Persian locale, and
  /// Persian verbs do not inflect for gender, so no sentence depends on the
  /// speaker's.
  static let persian: [String: String] = [
    // Tags.
    "work": "کار",
    "planning": "برنامه‌ریزی",
    "weekly": "هفتگی",
    "home": "خانه",
    "urgent": "فوری",
    "engineering": "مهندسی",
    "research": "پژوهش",
    "someday": "شاید بعدها",

    // Lists.
    "Apple Native": "اکوسیستم Apple",
    "Apple ecosystem apps and gear to try":
      "برنامه‌ها و دستگاه‌های اکوسیستم Apple برای امتحان کردن",
    "Work": "کار",
    "Day job & deep work": "شغل اصلی و کار عمیق",
    "Personal": "شخصی",
    "Reading": "مطالعه",
    "Papers & books": "مقاله‌ها و کتاب‌ها",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "تهیه پیش‌نویس دستور کار گردهمایی تیم",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "تعیین زمان جلسه‌ها، انتخاب سخنرانی اصلی و در نظر گرفتن وقت برای گروه‌های کوچک بحث.",
    "Confirm session topics with the leads": "تأیید موضوع جلسه‌ها با سرپرستان تیم‌ها",
    "Share the draft agenda for feedback": "هم‌رسانی پیش‌نویس دستور کار برای دریافت بازخورد",
    "Book the offsite venue": "رزرو محل برگزاری گردهمایی",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "مقایسه دو مکان نهایی‌شده و رزرو مکانی که برای گروه مناسب‌تر است.",
    "Send the weekly status update": "ارسال گزارش وضعیت هفتگی",
    "Summarize progress, blockers, and next steps for the team.":
      "خلاصه‌ای از پیشرفت، موانع و گام‌های بعدی برای تیم.",
    "Look into a standing-desk setup": "بررسی راه‌اندازی میز ایستاده",
    "Keep this as a someday idea until the home office is sorted.":
      "تا آماده شدن دفتر کار خانگی، این فقط یک ایده «شاید بعدها» بماند.",
    "Pick the offsite dates": "انتخاب تاریخ‌های گردهمایی",
    "Cross-check the team calendar and lock the week.": "تطبیق با تقویم تیم و قطعی کردن هفته.",
    "Order a second monitor": "سفارش مانیتور دوم",
    "Dropped in favour of using the laptop display on the desk.":
      "لغو شد؛ نمایشگر لپ‌تاپ روی میز کافی است.",
    "Renew the car registration": "تمدید بیمه خودرو",
    "Reply to Maya about the catering quote": "پاسخ به مینا درباره برآورد هزینه پذیرایی",
    "Review the Q3 budget draft": "بازبینی پیش‌نویس بودجه سه‌ماهه سوم",
    "Outline the board deck": "تهیه طرح کلی اسلایدهای هیئت مدیره",
    "Draft the hiring plan": "تهیه پیش‌نویس برنامه استخدام",
    "Reply to the investor update email": "پاسخ به ایمیل به‌روزرسانی سرمایه‌گذاران",
    "Review the Q3 planning doc": "بازبینی سند برنامه‌ریزی سه‌ماهه سوم",
    "Refactor the sync layer": "بازآرایی لایه همگام‌سازی",
    "Buy groceries for the week": "خرید خواربار هفته",
    "Read the GRPO paper": "خواندن مقاله GRPO",
    "Renew passport": "تمدید پاسپورت",
    "Plan the spring offsite": "برنامه‌ریزی گردهمایی بهار",
    "Submit the weekly timesheet": "ارسال برگه ساعت کاری هفتگی",
    "Book the dentist appointment": "گرفتن وقت دندان‌پزشک",
    "Review the launch checklist": "بازبینی چک‌لیست راه‌اندازی",

    // Deferral notes.
    "The agenda comes first": "اول دستور کار",
    "Groceries can wait for the evening": "خرید خواربار می‌تواند تا عصر صبر کند",

    // Habits and their cues.
    "Daily Review": "مرور روزانه",
    "End of day": "پایان روز",
    "Evening walk": "پیاده‌روی عصر",
    "After dinner": "بعد از شام",
    "Morning run": "دویدن صبحگاهی",
    "After waking up": "بعد از بیدار شدن",
    "Read 30 minutes": "30 دقیقه مطالعه",
    "Read 30 min": "30 دقیقه مطالعه",
    "Before bed": "قبل از خواب",
    "Meditate": "مراقبه",
    "Mid-morning": "میانه صبح",
    "Review the day": "مرور روز",
    "Evening": "عصر",
    "Evening journal": "دفتر خاطرات عصر",

    // Calendar events and locations.
    "Swift migration review": "بازبینی مهاجرت به Swift",
    "Conference Room B": "اتاق کنفرانس B",
    "Team standup": "استندآپ تیم",
    "1:1 with Sam": "جلسه یک‌به‌یک با سامان",
    "Design review": "بازبینی طراحی",
    "Studio": "استودیو",
    "Sprint planning": "برنامه‌ریزی اسپرینت",
    "Lunch with Sam": "ناهار با سامان",
    "1:1 with Alex": "جلسه یک‌به‌یک با آرش",
    "Customer call": "تماس با مشتری",
    "Dentist": "دندان‌پزشک",
    "Roadmap sync": "هماهنگی نقشه راه",
    "Morning gym": "باشگاه صبح",
    "Demo day": "روز دمو",
    "Team offsite": "گردهمایی تیم",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "اول دستور کار گردهمایی: تا قطعی نشود، مکان را نمی‌توان رزرو کرد؛ برای همین رزرو را به فردا موکول کردم. بعدازظهر امروز دو جلسه دارید.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "اول بازبینی برنامه‌ریزی، تا وقتی سند هنوز در ذهن تازه است؛ بازآرایی لایه همگام‌سازی بازه طولانی پیش از ناهار را می‌گیرد.",
    "The launch checklist first; the status update after the design review.":
      "اول چک‌لیست راه‌اندازی؛ گزارش وضعیت بعد از بازبینی طراحی.",

    // Memory.
    "notes_for_ai": "یادداشت‌ها برای هوش مصنوعی",
    "new_laptop": "لپ‌تاپ جدید",
    "work_rhythm": "ریتم کاری",
    "working_hours": "ساعات کاری",
    "manager": "مدیر",
    "writing_style": "سبک نگارش",
    "current_focus": "تمرکز فعلی",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "کاربر برای یک پروژه جانبی شخصی در حال سنجیدن چند چارچوب UI است؛ پیشنهادهای فنی را نسبت به چارچوب بی‌طرف نگه دارید.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "پیش از تعویض لپ‌تاپ، پایگاه داده و کتابخانه عکس را صادر کنید تا چیزی در انتقال از بین نرود.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "کار عمیق پیش از ناهار؛ بعدازظهرها برای جلسه‌ها و ایمیل.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "بهترین تمرکز از 9 صبح تا 12 ظهر است؛ صبح‌ها را برای کار عمیق حفظ کنید.",
    "Reports to Alex; weekly 1:1 on Mondays.": "زیر نظر آرش؛ جلسه یک‌به‌یک هفتگی دوشنبه‌ها.",
    "Prefers concise, direct updates — no filler.":
      "به‌روزرسانی‌های کوتاه و مستقیم را ترجیح می‌دهد، بدون حاشیه‌روی.",
    "Shipping the Apple-native rewrite this quarter.": "انتشار بازنویسی بومی Apple در این سه‌ماهه.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "هفته را مرور کردم و برنامه‌ریزی گردهمایی هفته بعد را آماده کردم.",
    "Cleared the inbox and locked in the offsite dates.":
      "صندوق ورودی را خالی کردم و تاریخ‌های گردهمایی را قطعی کردم.",
    "Still waiting on venue quotes before booking.":
      "پیش از رزرو هنوز منتظر برآورد هزینه مکان‌ها هستم.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "انجام همه کارهای متفرقه در یک بعدازظهر، بقیه هفته را آزاد کرد.",
    "Solid morning of deep work; shipped the planning review.":
      "صبحی پربار با کار عمیق؛ بازبینی برنامه‌ریزی تمام شد.",
    "Unblocked the sync layer; cleared the investor email.":
      "مانع لایه همگام‌سازی برطرف شد؛ ایمیل سرمایه‌گذاران هم پاسخ داده شد.",
    "Waiting on design sign-off for the calendar grid.": "شبکه تقویم منتظر تأیید طراحی است.",
    "Batching reviews before noon keeps the afternoon open.":
      "انجام بازبینی‌ها به‌صورت یک‌جا پیش از ظهر، بعدازظهر را آزاد نگه می‌دارد.",
    "Steady progress across tasks.": "پیشرفت پیوسته در کارها.",
    "Closed a few items.": "چند مورد تمام شد.",
  ]
}
