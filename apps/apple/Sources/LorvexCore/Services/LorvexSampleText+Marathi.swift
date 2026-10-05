extension LorvexSampleText {
  /// The sample datasets in Marathi. People are सागर (Sam), अनिकेत (Alex), and
  /// माया (Maya) in every dataset; product names (Swift, GRPO, Apple) stay as
  /// written, and Q3 is written तिसरी तिमाही. The car chore is the गाडीचा
  /// विमा, the vehicle insurance renewal. Task titles are noun phrases ending
  /// in the infinitive (पाठवणे, करणे), notes about the user use the honorific
  /// plural (करतात), and the briefings and reviews use past-tense verbs that
  /// agree with their object, so no sentence depends on the speaker's gender.
  static let marathi: [String: String] = [
    // Tags.
    "work": "काम",
    "planning": "प्लॅनिंग",
    "weekly": "साप्ताहिक",
    "home": "घर",
    "urgent": "तातडीचे",
    "engineering": "इंजिनिअरिंग",
    "research": "संशोधन",
    "someday": "कधीतरी",

    // Lists.
    "Apple Native": "Apple इकोसिस्टम",
    "Apple ecosystem apps and gear to try":
      "वापरून पाहण्यासाठी Apple इकोसिस्टममधील ॲप्स आणि गॅजेट्स",
    "Work": "काम",
    "Day job & deep work": "मुख्य नोकरी आणि सखोल काम",
    "Personal": "वैयक्तिक",
    "Reading": "वाचन",
    "Papers & books": "शोधनिबंध आणि पुस्तके",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "टीम ऑफसाइटच्या अजेंड्याचा मसुदा तयार करणे",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "सत्रांसाठी वेळ ठरवणे, कीनोट निवडणे आणि लहान गटचर्चांसाठीही वेळ ठेवणे.",
    "Confirm session topics with the leads": "टीम लीडसोबत सत्रांचे विषय निश्चित करणे",
    "Share the draft agenda for feedback": "फीडबॅकसाठी अजेंड्याचा मसुदा शेअर करणे",
    "Book the offsite venue": "ऑफसाइटसाठी ठिकाण बुक करणे",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "निवडलेल्या दोन ठिकाणांची तुलना करून गटाला साजेसे ठिकाण बुक करणे.",
    "Send the weekly status update": "साप्ताहिक स्टेटस अपडेट पाठवणे",
    "Summarize progress, blockers, and next steps for the team.":
      "टीमसाठी प्रगती, अडथळे आणि पुढील पावलांचा सारांश तयार करणे.",
    "Look into a standing-desk setup": "स्टँडिंग डेस्क सेटअपबद्दल चौकशी करणे",
    "Keep this as a someday idea until the home office is sorted.":
      "होम ऑफिस नीट लागेपर्यंत ही ‘कधीतरी’ कल्पनाच राहू द्या.",
    "Pick the offsite dates": "ऑफसाइटच्या तारखा ठरवणे",
    "Cross-check the team calendar and lock the week.":
      "टीमची दिनदर्शिका पडताळून आठवडा पक्का करणे.",
    "Order a second monitor": "दुसरा मॉनिटर ऑर्डर करणे",
    "Dropped in favour of using the laptop display on the desk.":
      "रद्द केले; डेस्कवर लॅपटॉपची स्क्रीनच वापरणार.",
    "Renew the car registration": "गाडीच्या विम्याचे नूतनीकरण करणे",
    "Reply to Maya about the catering quote": "केटरिंगच्या कोटेशनबद्दल मायाला उत्तर देणे",
    "Review the Q3 budget draft": "तिसऱ्या तिमाहीच्या बजेटच्या मसुद्याचा आढावा घेणे",
    "Outline the board deck": "बोर्ड सादरीकरणाची रूपरेषा तयार करणे",
    "Draft the hiring plan": "भरतीच्या योजनेचा मसुदा तयार करणे",
    "Reply to the investor update email": "गुंतवणूकदारांच्या अपडेट ईमेलला उत्तर देणे",
    "Review the Q3 planning doc": "तिसऱ्या तिमाहीच्या प्लॅनिंग डॉक्युमेंटचा आढावा घेणे",
    "Refactor the sync layer": "सिंक लेयर रीफॅक्टर करणे",
    "Buy groceries for the week": "आठवड्याचा किराणा खरेदी करणे",
    "Read the GRPO paper": "GRPO शोधनिबंध वाचणे",
    "Renew passport": "पासपोर्ट नूतनीकरण करणे",
    "Plan the spring offsite": "वसंत ऋतूतील ऑफसाइटचे प्लॅनिंग करणे",
    "Submit the weekly timesheet": "साप्ताहिक टाइमशीट सादर करणे",
    "Book the dentist appointment": "दंतवैद्याची अपॉइंटमेंट बुक करणे",
    "Review the launch checklist": "लाँचच्या तपासणी यादीचा आढावा घेणे",

    // Deferral notes.
    "The agenda comes first": "आधी अजेंडा",
    "Groceries can wait for the evening": "किराणा संध्याकाळपर्यंत थांबू शकतो",

    // Habits and their cues.
    "Daily Review": "दैनिक आढावा",
    "End of day": "दिवसाच्या शेवटी",
    "Evening walk": "संध्याकाळचा फेरफटका",
    "After dinner": "रात्रीच्या जेवणानंतर",
    "Morning run": "सकाळची धाव",
    "After waking up": "झोपेतून उठल्यानंतर",
    "Read 30 minutes": "30 मिनिटे वाचन",
    "Read 30 min": "30 मिनिटे वाचन",
    "Before bed": "झोपण्यापूर्वी",
    "Meditate": "ध्यान करणे",
    "Mid-morning": "दुपारपूर्वी",
    "Review the day": "दिवसाचा आढावा",
    "Evening": "संध्याकाळ",
    "Evening journal": "संध्याकाळची डायरी",

    // Calendar events and locations.
    "Swift migration review": "Swift मायग्रेशन रिव्ह्यू",
    "Conference Room B": "कॉन्फरन्स रूम B",
    "Team standup": "टीम स्टँडअप",
    "1:1 with Sam": "सागरसोबत 1:1",
    "Design review": "डिझाइन रिव्ह्यू",
    "Studio": "स्टुडिओ",
    "Sprint planning": "स्प्रिंट प्लॅनिंग",
    "Lunch with Sam": "सागरसोबत दुपारचे जेवण",
    "1:1 with Alex": "अनिकेतसोबत 1:1",
    "Customer call": "ग्राहक कॉल",
    "Dentist": "दंतवैद्य",
    "Roadmap sync": "रोडमॅप सिंक",
    "Morning gym": "सकाळी जिम",
    "Demo day": "डेमो डे",
    "Team offsite": "टीम ऑफसाइट",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "आधी ऑफसाइटचा अजेंडा: तो ठरेपर्यंत ठिकाण बुक करता येत नाही, म्हणून बुकिंग उद्यावर ढकलले आहे. आज दुपारी दोन मीटिंग आहेत.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "आधी प्लॅनिंगचा आढावा, डॉक्युमेंट ताजे असतानाच; सिंक रीफॅक्टरसाठी लंचआधीचा मोठा स्लॉट ठेवला आहे.",
    "The launch checklist first; the status update after the design review.":
      "आधी लाँचची तपासणी यादी; स्टेटस अपडेट डिझाइन रिव्ह्यूनंतर.",

    // Memory.
    "notes_for_ai": "AI साठी नोट्स",
    "new_laptop": "नवीन लॅपटॉप",
    "work_rhythm": "कामाची लय",
    "working_hours": "कामाचे तास",
    "manager": "मॅनेजर",
    "writing_style": "लेखनशैली",
    "current_focus": "सध्याचा फोकस",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "वापरकर्ते एका वैयक्तिक साइड प्रोजेक्टसाठी काही UI फ्रेमवर्कची तुलना करत आहेत – तांत्रिक सूचना कोणत्याही एका फ्रेमवर्कच्या बाजूने नसाव्यात.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "लॅपटॉप बदलण्यापूर्वी डेटाबेस आणि फोटो लायब्ररी एक्सपोर्ट करून घ्या, म्हणजे स्थलांतरात काहीही हरवणार नाही.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "लंचआधी सखोल काम करतात; दुपारचा वेळ मीटिंग आणि ईमेलसाठी ठेवतात.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "सकाळी 9 ते दुपारी 12 वाजेपर्यंत सर्वाधिक एकाग्रता असते; सकाळची वेळ सखोल कामासाठी राखून ठेवा.",
    "Reports to Alex; weekly 1:1 on Mondays.":
      "अनिकेतला रिपोर्ट करतात; दर सोमवारी साप्ताहिक 1:1.",
    "Prefers concise, direct updates — no filler.":
      "संक्षिप्त आणि थेट अपडेट पसंत करतात – उगाच लांबण नको.",
    "Shipping the Apple-native rewrite this quarter.":
      "या तिमाहीत Apple नेटिव्ह रीराइट रिलीज करायचे आहे.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "आठवड्याचा आढावा घेतला आणि पुढच्या आठवड्याचे ऑफसाइट प्लॅनिंग ठरवले.",
    "Cleared the inbox and locked in the offsite dates.":
      "इनबॉक्स रिकामा केला आणि ऑफसाइटच्या तारखा पक्क्या केल्या.",
    "Still waiting on venue quotes before booking.":
      "बुकिंगपूर्वी ठिकाणांच्या कोटेशनची प्रतीक्षा आहे.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "सगळी किरकोळ कामे एकाच दुपारी उरकल्यामुळे आठवड्याचा उर्वरित वेळ मोकळा झाला.",
    "Solid morning of deep work; shipped the planning review.":
      "सकाळी सखोल काम उत्तम झाले; प्लॅनिंगचा आढावा पूर्ण केला.",
    "Unblocked the sync layer; cleared the investor email.":
      "सिंक लेयरमधील अडथळा दूर केला; गुंतवणूकदारांच्या ईमेलला उत्तर दिले.",
    "Waiting on design sign-off for the calendar grid.":
      "दिनदर्शिका ग्रिडच्या डिझाइन मंजुरीची प्रतीक्षा आहे.",
    "Batching reviews before noon keeps the afternoon open.":
      "दुपारपूर्वी सर्व आढावे एकत्र उरकल्याने दुपारनंतरचा वेळ मोकळा राहतो.",
    "Steady progress across tasks.": "सर्व कार्यांमध्ये सातत्याने प्रगती.",
    "Closed a few items.": "काही आयटम पूर्ण केले.",
  ]
}
