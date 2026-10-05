extension LorvexSampleText {
  /// The sample datasets in Bengali. People are অমিত (Sam), রাহুল (Alex), and
  /// মায়া (Maya) in every dataset; product names (Swift, GRPO, Apple) stay as
  /// written, and Q3 is written তৃতীয় ত্রৈমাসিক. The car chore is the গাড়ির
  /// বিমা, the vehicle insurance renewal. Task titles are noun phrases ending
  /// in the verbal noun (পাঠানো, করা), notes about the user use the honorific
  /// verb forms (করেন), and the briefings and reviews use verb forms that
  /// carry no gender, so no sentence depends on the speaker's gender.
  static let bengali: [String: String] = [
    // Tags.
    "work": "কাজ",
    "planning": "প্ল্যানিং",
    "weekly": "সাপ্তাহিক",
    "home": "বাড়ি",
    "urgent": "জরুরি",
    "engineering": "ইঞ্জিনিয়ারিং",
    "research": "গবেষণা",
    "someday": "কোনো একদিন",

    // Lists.
    "Apple Native": "Apple ইকোসিস্টেম",
    "Apple ecosystem apps and gear to try": "চেষ্টা করে দেখার মতো Apple ইকোসিস্টেমের অ্যাপ ও গ্যাজেট",
    "Work": "কাজ",
    "Day job & deep work": "মূল চাকরি ও গভীর মনোযোগের কাজ",
    "Personal": "ব্যক্তিগত",
    "Reading": "পড়া",
    "Papers & books": "গবেষণাপত্র ও বই",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "টিম অফসাইটের এজেন্ডার খসড়া তৈরি করা",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "সেশনের সময় ঠিক করা, একটি কিনোট বেছে নেওয়া এবং ছোট গ্রুপ আলোচনার জন্যও সময় রাখা।",
    "Confirm session topics with the leads": "টিম লিডদের সাথে সেশনের বিষয় নিশ্চিত করা",
    "Share the draft agenda for feedback": "ফিডব্যাকের জন্য এজেন্ডার খসড়া শেয়ার করা",
    "Book the offsite venue": "অফসাইটের জন্য ভেন্যু বুক করা",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "বাছাই করা দুটি ভেন্যুর তুলনা করে দলের জন্য উপযুক্তটি বুক করা।",
    "Send the weekly status update": "সাপ্তাহিক স্ট্যাটাস আপডেট পাঠানো",
    "Summarize progress, blockers, and next steps for the team.":
      "টিমের জন্য অগ্রগতি, বাধা ও পরবর্তী পদক্ষেপের সারসংক্ষেপ তৈরি করা।",
    "Look into a standing-desk setup": "স্ট্যান্ডিং ডেস্ক সেট আপ নিয়ে খোঁজখবর নেওয়া",
    "Keep this as a someday idea until the home office is sorted.":
      "হোম অফিস গোছানো না হওয়া পর্যন্ত এটি “কোনো একদিন” ভাবনা হিসাবেই থাকুক।",
    "Pick the offsite dates": "অফসাইটের তারিখ ঠিক করা",
    "Cross-check the team calendar and lock the week.":
      "টিমের ক্যালেন্ডার মিলিয়ে দেখে সপ্তাহটি চূড়ান্ত করা।",
    "Order a second monitor": "দ্বিতীয় একটি মনিটর অর্ডার করা",
    "Dropped in favour of using the laptop display on the desk.":
      "বাতিল; ডেস্কে ল্যাপটপের স্ক্রিনই ব্যবহার করা হবে।",
    "Renew the car registration": "গাড়ির বিমা নবায়ন করা",
    "Reply to Maya about the catering quote": "ক্যাটারিং কোটেশনের ব্যাপারে মায়াকে উত্তর দেওয়া",
    "Review the Q3 budget draft": "তৃতীয় ত্রৈমাসিকের বাজেটের খসড়া পর্যালোচনা করা",
    "Outline the board deck": "বোর্ড প্রেজেন্টেশনের রূপরেখা তৈরি করা",
    "Draft the hiring plan": "নিয়োগ পরিকল্পনার খসড়া তৈরি করা",
    "Reply to the investor update email": "বিনিয়োগকারীদের আপডেট ইমেলের উত্তর দেওয়া",
    "Review the Q3 planning doc": "তৃতীয় ত্রৈমাসিকের প্ল্যানিং ডকুমেন্ট পর্যালোচনা করা",
    "Refactor the sync layer": "সিঙ্ক লেয়ার রিফ্যাক্টর করা",
    "Buy groceries for the week": "সপ্তাহের বাজার করা",
    "Read the GRPO paper": "GRPO গবেষণাপত্র পড়া",
    "Renew passport": "পাসপোর্ট নবায়ন করা",
    "Plan the spring offsite": "বসন্তের অফসাইটের পরিকল্পনা করা",
    "Submit the weekly timesheet": "সাপ্তাহিক টাইমশিট জমা দেওয়া",
    "Book the dentist appointment": "ডেন্টিস্টের অ্যাপয়েন্টমেন্ট বুক করা",
    "Review the launch checklist": "লঞ্চ চেকলিস্ট পর্যালোচনা করা",

    // Deferral notes.
    "The agenda comes first": "আগে এজেন্ডা",
    "Groceries can wait for the evening": "বাজার সন্ধ্যা পর্যন্ত অপেক্ষা করতে পারে",

    // Habits and their cues.
    "Daily Review": "দৈনিক পর্যালোচনা",
    "End of day": "দিনের শেষে",
    "Evening walk": "সন্ধ্যার হাঁটা",
    "After dinner": "রাতের খাবারের পর",
    "Morning run": "সকালের দৌড়",
    "After waking up": "ঘুম থেকে ওঠার পর",
    "Read 30 minutes": "30 মিনিট পড়া",
    "Read 30 min": "30 মিনিট পড়া",
    "Before bed": "ঘুমানোর আগে",
    "Meditate": "ধ্যান করা",
    "Mid-morning": "দুপুরের আগে",
    "Review the day": "দিনের পর্যালোচনা",
    "Evening": "সন্ধ্যা",
    "Evening journal": "সন্ধ্যার ডায়েরি",

    // Calendar events and locations.
    "Swift migration review": "Swift মাইগ্রেশন রিভিউ",
    "Conference Room B": "কনফারেন্স রুম B",
    "Team standup": "টিম স্ট্যান্ডআপ",
    "1:1 with Sam": "অমিতের সাথে 1:1",
    "Design review": "ডিজাইন রিভিউ",
    "Studio": "স্টুডিও",
    "Sprint planning": "স্প্রিন্ট প্ল্যানিং",
    "Lunch with Sam": "অমিতের সাথে দুপুরের খাবার",
    "1:1 with Alex": "রাহুলের সাথে 1:1",
    "Customer call": "গ্রাহক কল",
    "Dentist": "ডেন্টিস্ট",
    "Roadmap sync": "রোডম্যাপ সিঙ্ক",
    "Morning gym": "সকালে জিম",
    "Demo day": "ডেমো ডে",
    "Team offsite": "টিম অফসাইট",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "আগে অফসাইটের এজেন্ডা: সেটি ঠিক না হওয়া পর্যন্ত ভেন্যু বুক করা যায় না, তাই বুকিং আগামীকালের জন্য সরিয়ে দিয়েছি। আজ বিকেলে দুটি মিটিং আছে।",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "আগে প্ল্যানিং রিভিউ, যতক্ষণ ডকুমেন্টটি মনে তাজা আছে; সিঙ্ক রিফ্যাক্টরের জন্য লাঞ্চের আগের লম্বা সময়টা রেখেছি।",
    "The launch checklist first; the status update after the design review.":
      "আগে লঞ্চ চেকলিস্ট; স্ট্যাটাস আপডেট ডিজাইন রিভিউয়ের পরে।",

    // Memory.
    "notes_for_ai": "AI-এর জন্য নোট",
    "new_laptop": "নতুন ল্যাপটপ",
    "work_rhythm": "কাজের ছন্দ",
    "working_hours": "কাজের সময়",
    "manager": "ম্যানেজার",
    "writing_style": "লেখার ধরন",
    "current_focus": "বর্তমান ফোকাস",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "ব্যবহারকারী একটি ব্যক্তিগত সাইড প্রজেক্টের জন্য কয়েকটি UI ফ্রেমওয়ার্ক তুলনা করছেন – প্রযুক্তিগত পরামর্শ যেন কোনো একটি ফ্রেমওয়ার্কের পক্ষে না যায়।",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "ল্যাপটপ বদলানোর আগে ডেটাবেস ও ছবির লাইব্রেরি এক্সপোর্ট করে নিন, যাতে স্থানান্তরের সময় কিছু হারিয়ে না যায়।",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "লাঞ্চের আগে গভীর মনোযোগের কাজ করেন; বিকেলের সময়টা মিটিং আর ইমেলের জন্য রাখেন।",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "সকাল 9টা থেকে দুপুর 12টা পর্যন্ত সবচেয়ে ভালো মনোযোগ থাকে; সকালের সময় গভীর মনোযোগের কাজের জন্য আলাদা রাখুন।",
    "Reports to Alex; weekly 1:1 on Mondays.":
      "রাহুলকে রিপোর্ট করেন; প্রতি সোমবার সাপ্তাহিক 1:1।",
    "Prefers concise, direct updates — no filler.":
      "সংক্ষিপ্ত ও সরাসরি আপডেট পছন্দ করেন – বাড়তি কথা ছাড়া।",
    "Shipping the Apple-native rewrite this quarter.":
      "এই ত্রৈমাসিকে Apple নেটিভ রিরাইট রিলিজ হওয়ার কথা।",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "সপ্তাহের পর্যালোচনা করেছি এবং আগামী সপ্তাহের অফসাইট প্ল্যানিং সাজিয়ে রেখেছি।",
    "Cleared the inbox and locked in the offsite dates.":
      "ইনবক্স খালি করেছি এবং অফসাইটের তারিখ চূড়ান্ত করেছি।",
    "Still waiting on venue quotes before booking.":
      "বুকিংয়ের আগে ভেন্যুর কোটেশনের অপেক্ষায় আছি।",
    "Batching errands into one afternoon freed up the rest of the week.":
      "সব টুকিটাকি কাজ এক দুপুরে সেরে ফেলায় সপ্তাহের বাকি সময়টা ফাঁকা হয়ে গেছে।",
    "Solid morning of deep work; shipped the planning review.":
      "সকালে চমৎকার গভীর মনোযোগের কাজ হয়েছে; প্ল্যানিং রিভিউ শেষ করেছি।",
    "Unblocked the sync layer; cleared the investor email.":
      "সিঙ্ক লেয়ারের বাধা সরিয়েছি; বিনিয়োগকারীদের ইমেলের উত্তর দিয়েছি।",
    "Waiting on design sign-off for the calendar grid.":
      "ক্যালেন্ডার গ্রিডের ডিজাইন অনুমোদনের অপেক্ষায় আছি।",
    "Batching reviews before noon keeps the afternoon open.":
      "দুপুরের আগে রিভিউগুলি একসাথে সেরে ফেললে বিকেলটা ফাঁকা থাকে।",
    "Steady progress across tasks.": "সব টাস্কে নিয়মিত অগ্রগতি।",
    "Closed a few items.": "কয়েকটি আইটেম শেষ করেছি।",
  ]
}
