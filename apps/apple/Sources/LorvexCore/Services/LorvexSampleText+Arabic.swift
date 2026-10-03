extension LorvexSampleText {
  /// The sample datasets in Arabic. People are سامي (Sam), خالد (Alex), and
  /// مريم (Maya) in every dataset; product names (Zoom, Swift, GRPO, Apple)
  /// and the UI abbreviation stay as written, digits stay Western as in the
  /// app's Arabic catalog, and Q3 is written الربع الثالث. The team offsite is
  /// a ملتقى, and the car chore is the تجديد ترخيص السيارة, the vehicle license
  /// renewal. Notes about the user are noun phrases wherever the English omits
  /// the subject, so they avoid gendered verb forms.
  static let arabic: [String: String] = [
    // Tags.
    "work": "عمل",
    "planning": "تخطيط",
    "weekly": "أسبوعي",
    "home": "منزل",
    "urgent": "عاجل",
    "engineering": "هندسة",
    "research": "أبحاث",
    "someday": "لاحقًا",

    // Lists.
    "Apple Native": "منظومة Apple",
    "Apple ecosystem apps and gear to try": "تطبيقات وأجهزة من منظومة Apple أريد تجربتها",
    "Work": "العمل",
    "Day job & deep work": "الوظيفة والعمل العميق",
    "Personal": "شخصي",
    "Reading": "القراءة",
    "Papers & books": "أوراق بحثية وكتب",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "إعداد مسودة جدول أعمال ملتقى الفريق",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "توزيع الجلسات على الوقت، واختيار الكلمة الرئيسية، وترك وقت لمجموعات النقاش الصغيرة.",
    "Confirm session topics with the leads": "تأكيد مواضيع الجلسات مع مسؤولي الفرق",
    "Share the draft agenda for feedback": "مشاركة مسودة جدول الأعمال لجمع الملاحظات",
    "Book the offsite venue": "حجز مكان الملتقى",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "مقارنة المكانين المرشحين وحجز الأنسب للفريق.",
    "Send the weekly status update": "إرسال تقرير التقدم الأسبوعي",
    "Summarize progress, blockers, and next steps for the team.":
      "تلخيص التقدم والعقبات والخطوات التالية للفريق.",
    "Look into a standing-desk setup": "البحث عن مكتب للعمل وقوفًا",
    "Keep this as a someday idea until the home office is sorted.":
      "تبقى فكرة مؤجلة إلى أن يجهز مكتب المنزل.",
    "Pick the offsite dates": "تحديد تواريخ الملتقى",
    "Cross-check the team calendar and lock the week.": "مطابقة تقويم الفريق وتثبيت الأسبوع.",
    "Order a second monitor": "طلب شاشة ثانية",
    "Dropped in favour of using the laptop display on the desk.":
      "تم إلغاء الطلب لأن شاشة اللابتوب على المكتب تكفي.",
    "Renew the car registration": "تجديد ترخيص السيارة",
    "Reply to Maya about the catering quote": "الرد على مريم بشأن عرض سعر تقديم الطعام",
    "Review the Q3 budget draft": "مراجعة مسودة ميزانية الربع الثالث",
    "Outline the board deck": "وضع هيكل العرض التقديمي لمجلس الإدارة",
    "Draft the hiring plan": "إعداد خطة التوظيف",
    "Reply to the investor update email": "الرد على رسالة تحديث المستثمرين",
    "Review the Q3 planning doc": "مراجعة مستند تخطيط الربع الثالث",
    "Refactor the sync layer": "إعادة هيكلة طبقة المزامنة",
    "Buy groceries for the week": "شراء مواد البقالة للأسبوع",
    "Read the GRPO paper": "قراءة ورقة GRPO البحثية",
    "Renew passport": "تجديد جواز السفر",
    "Plan the spring offsite": "التخطيط لملتقى الربيع",
    "Submit the weekly timesheet": "تسليم كشف ساعات العمل الأسبوعي",
    "Book the dentist appointment": "حجز موعد طبيب الأسنان",
    "Review the launch checklist": "مراجعة قائمة التحقق للإطلاق",

    // Deferral notes.
    "The agenda comes first": "جدول الأعمال أولًا",
    "Groceries can wait for the evening": "يمكن تأجيل البقالة إلى المساء",

    // Habits and their cues.
    "Daily Review": "المراجعة اليومية",
    "End of day": "نهاية اليوم",
    "Evening walk": "المشي المسائي",
    "After dinner": "بعد العشاء",
    "Morning run": "الجري الصباحي",
    "After waking up": "بعد الاستيقاظ",
    "Read 30 minutes": "القراءة 30 دقيقة",
    "Read 30 min": "القراءة 30 د",
    "Before bed": "قبل النوم",
    "Meditate": "التأمل",
    "Mid-morning": "منتصف الصباح",
    "Review the day": "مراجعة اليوم",
    "Evening": "المساء",
    "Evening journal": "يوميات المساء",

    // Calendar events and locations.
    "Swift migration review": "مراجعة الانتقال إلى Swift",
    "Conference Room B": "قاعة الاجتماعات B",
    "Team standup": "الاجتماع اليومي للفريق",
    "1:1 with Sam": "اجتماع فردي مع سامي",
    "Design review": "مراجعة التصميم",
    "Studio": "الاستوديو",
    "Sprint planning": "تخطيط السبرنت",
    "Lunch with Sam": "غداء مع سامي",
    "1:1 with Alex": "اجتماع فردي مع خالد",
    "Customer call": "مكالمة مع عميل",
    "Dentist": "طبيب الأسنان",
    "Roadmap sync": "اجتماع خريطة الطريق",
    "Morning gym": "الجيم صباحًا",
    "Demo day": "يوم العرض التوضيحي",
    "Team offsite": "ملتقى الفريق",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "جدول أعمال الملتقى أولًا: لا يمكن حجز المكان قبل اعتماد الجدول، لذلك نقلت الحجز إلى الغد. وهناك اجتماعان بعد ظهر اليوم.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "مراجعة التخطيط أولًا ما دام المستند حاضرًا في الذهن؛ وتحصل إعادة هيكلة طبقة المزامنة على الفترة الطويلة قبل الغداء.",
    "The launch checklist first; the status update after the design review.":
      "قائمة التحقق للإطلاق أولًا؛ وتقرير التقدم بعد مراجعة التصميم.",

    // Memory.
    "notes_for_ai": "ملاحظات للذكاء الاصطناعي",
    "new_laptop": "لابتوب جديد",
    "work_rhythm": "إيقاع العمل",
    "working_hours": "ساعات العمل",
    "manager": "المدير",
    "writing_style": "أسلوب الكتابة",
    "current_focus": "التركيز الحالي",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "المستخدم يقارن بين عدة أطر عمل UI لمشروع جانبي شخصي؛ اجعل أي اقتراحات تقنية محايدة تجاه أطر العمل.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "قبل تغيير اللابتوب، صدّر قاعدة البيانات ومكتبة الصور حتى لا يضيع شيء أثناء النقل.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "العمل العميق قبل الغداء، وما بعد الظهر للاجتماعات والبريد الإلكتروني.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "أفضل تركيز يكون من 9 صباحًا إلى 12 ظهرًا؛ احم الصباح للعمل العميق.",
    "Reports to Alex; weekly 1:1 on Mondays.":
      "المدير المباشر: خالد؛ واجتماع فردي أسبوعي كل يوم اثنين.",
    "Prefers concise, direct updates — no filler.": "تُفضَّل التحديثات الموجزة والمباشرة، بلا حشو.",
    "Shipping the Apple-native rewrite this quarter.":
      "إطلاق النسخة الأصلية المعاد كتابتها لمنصات Apple هذا الربع.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "راجعت الأسبوع ورتبت التحضير للملتقى خلال الأسبوع القادم.",
    "Cleared the inbox and locked in the offsite dates.": "أفرغت الوارد وحسمت مواعيد الملتقى.",
    "Still waiting on venue quotes before booking.": "ما زلت أنتظر عروض أسعار الأماكن قبل الحجز.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "جمع المشاوير في فترة بعد ظهر واحدة حرر بقية الأسبوع.",
    "Solid morning of deep work; shipped the planning review.":
      "صباح منتج من العمل العميق؛ أنجزت مراجعة التخطيط.",
    "Unblocked the sync layer; cleared the investor email.":
      "أزلت العقبة أمام طبقة المزامنة؛ وأجبت على رسالة المستثمرين.",
    "Waiting on design sign-off for the calendar grid.": "شبكة التقويم بانتظار اعتماد التصميم.",
    "Batching reviews before noon keeps the afternoon open.":
      "جمع المراجعات قبل الظهر يبقي فترة ما بعد الظهر فارغة.",
    "Steady progress across tasks.": "تقدم ثابت في المهام.",
    "Closed a few items.": "أنجزت عدة بنود.",
  ]
}
