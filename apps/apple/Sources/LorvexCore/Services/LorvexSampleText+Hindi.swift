extension LorvexSampleText {
  /// The sample datasets in Hindi. People are अमित (Sam), राहुल (Alex), and
  /// प्रिया (Maya) in every dataset; product names (Zoom, Swift, GRPO, Apple)
  /// stay as written, and Q3 is written तीसरी तिमाही. The car chore is the
  /// गाड़ी का बीमा, the vehicle insurance renewal. Notes about the user use the
  /// honorific plural, and the briefings and reviews use past-tense verbs that
  /// agree with their object, so no sentence depends on the speaker's gender.
  static let hindi: [String: String] = [
    // Tags.
    "work": "काम",
    "planning": "प्लानिंग",
    "weekly": "साप्ताहिक",
    "home": "घर",
    "urgent": "तुरंत",
    "engineering": "इंजीनियरिंग",
    "research": "रिसर्च",
    "someday": "किसी दिन",

    // Lists.
    "Apple Native": "Apple इकोसिस्टम",
    "Apple ecosystem apps and gear to try": "आज़माने के लिए Apple इकोसिस्टम के ऐप और गैजेट",
    "Work": "काम",
    "Day job & deep work": "मुख्य नौकरी और डीप वर्क",
    "Personal": "निजी",
    "Reading": "पढ़ना",
    "Papers & books": "रिसर्च पेपर और किताबें",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "टीम ऑफ़साइट के एजेंडा का ड्राफ़्ट बनाना",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "सेशन का समय बाँटना, कीनोट चुनना और छोटे ग्रुप की चर्चाओं के लिए भी समय रखना।",
    "Confirm session topics with the leads": "टीम लीड्स से सेशन के विषय पक्के करना",
    "Share the draft agenda for feedback": "एजेंडा का ड्राफ़्ट साझा करके सबसे फ़ीडबैक लेना",
    "Book the offsite venue": "ऑफ़साइट के लिए वेन्यू बुक करना",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "चुने हुए दोनों वेन्यू की तुलना करके टीम के हिसाब से सही वाला बुक करना।",
    "Send the weekly status update": "साप्ताहिक स्टेटस अपडेट भेजना",
    "Summarize progress, blockers, and next steps for the team.":
      "टीम के लिए प्रगति, बाधाओं और अगले कदमों का सार तैयार करना।",
    "Look into a standing-desk setup": "स्टैंडिंग डेस्क सेटअप के बारे में पता करना",
    "Keep this as a someday idea until the home office is sorted.":
      "होम ऑफ़िस सेट होने तक इसे “किसी दिन” वाला आइडिया ही रहने दें।",
    "Pick the offsite dates": "ऑफ़साइट की तारीख़ें तय करना",
    "Cross-check the team calendar and lock the week.":
      "टीम के कैलेंडर से मिलान करके हफ़्ता पक्का करना।",
    "Order a second monitor": "दूसरा मॉनिटर ऑर्डर करना",
    "Dropped in favour of using the laptop display on the desk.":
      "रद्द किया; डेस्क पर लैपटॉप की स्क्रीन से ही काम चल जाएगा।",
    "Renew the car registration": "गाड़ी का बीमा रिन्यू करवाना",
    "Reply to Maya about the catering quote": "कैटरिंग के कोटेशन के बारे में प्रिया को जवाब देना",
    "Review the Q3 budget draft": "तीसरी तिमाही के बजट ड्राफ़्ट की समीक्षा करना",
    "Outline the board deck": "बोर्ड प्रेज़ेंटेशन की रूपरेखा बनाना",
    "Draft the hiring plan": "भर्ती योजना का ड्राफ़्ट बनाना",
    "Reply to the investor update email": "निवेशकों के अपडेट वाले ईमेल का जवाब देना",
    "Review the Q3 planning doc": "तीसरी तिमाही के प्लानिंग डॉक्यूमेंट की समीक्षा करना",
    "Refactor the sync layer": "सिंक लेयर को रीफ़ैक्टर करना",
    "Buy groceries for the week": "हफ़्ते भर का राशन ख़रीदना",
    "Read the GRPO paper": "GRPO पेपर पढ़ना",
    "Renew passport": "पासपोर्ट रिन्यू करवाना",
    "Plan the spring offsite": "वसंत के ऑफ़साइट की प्लानिंग करना",
    "Submit the weekly timesheet": "साप्ताहिक टाइमशीट जमा करना",
    "Book the dentist appointment": "डेंटिस्ट का अपॉइंटमेंट लेना",
    "Review the launch checklist": "लॉन्च की चेकलिस्ट जाँचना",

    // Deferral notes.
    "The agenda comes first": "पहले एजेंडा",
    "Groceries can wait for the evening": "राशन शाम तक रुक सकता है",

    // Habits and their cues.
    "Daily Review": "दैनिक समीक्षा",
    "End of day": "दिन के अंत में",
    "Evening walk": "शाम की सैर",
    "After dinner": "रात के खाने के बाद",
    "Morning run": "सुबह की दौड़",
    "After waking up": "उठने के बाद",
    "Read 30 minutes": "30 मिनट पढ़ना",
    "Read 30 min": "30 मिनट पढ़ना",
    "Before bed": "सोने से पहले",
    "Meditate": "ध्यान करना",
    "Mid-morning": "दोपहर से पहले",
    "Review the day": "दिन की समीक्षा",
    "Evening": "शाम",
    "Evening journal": "शाम की डायरी",

    // Calendar events and locations.
    "Swift migration review": "Swift माइग्रेशन रिव्यू",
    "Conference Room B": "कॉन्फ़्रेंस रूम B",
    "Team standup": "टीम स्टैंडअप",
    "1:1 with Sam": "अमित के साथ 1:1",
    "Design review": "डिज़ाइन रिव्यू",
    "Studio": "स्टूडियो",
    "Sprint planning": "स्प्रिंट प्लानिंग",
    "Lunch with Sam": "अमित के साथ लंच",
    "1:1 with Alex": "राहुल के साथ 1:1",
    "Customer call": "कस्टमर कॉल",
    "Dentist": "डेंटिस्ट",
    "Roadmap sync": "रोडमैप सिंक",
    "Morning gym": "सुबह जिम",
    "Demo day": "डेमो डे",
    "Team offsite": "टीम ऑफ़साइट",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "सबसे पहले ऑफ़साइट का एजेंडा: जब तक वह तय नहीं होता, वेन्यू बुक नहीं हो सकता, इसलिए बुकिंग कल पर टाल दी है। आज दोपहर बाद दो मीटिंग हैं।",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "पहले प्लानिंग की समीक्षा, जब तक बातें दिमाग़ में ताज़ा हैं; सिंक रीफ़ैक्टर के लिए लंच से पहले का लंबा स्लॉट रखा है।",
    "The launch checklist first; the status update after the design review.":
      "पहले लॉन्च की चेकलिस्ट; स्टेटस अपडेट डिज़ाइन रिव्यू के बाद।",

    // Memory.
    "notes_for_ai": "AI के लिए नोट्स",
    "new_laptop": "नया लैपटॉप",
    "work_rhythm": "काम की लय",
    "working_hours": "काम के घंटे",
    "manager": "मैनेजर",
    "writing_style": "लिखने की शैली",
    "current_focus": "मौजूदा फ़ोकस",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "यूज़र एक निजी साइड प्रोजेक्ट के लिए कुछ UI फ़्रेमवर्क की तुलना कर रहे हैं — तकनीकी सुझाव किसी एक फ़्रेमवर्क के पक्ष में न हों।",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "लैपटॉप बदलने से पहले डेटाबेस और फ़ोटो लाइब्रेरी एक्सपोर्ट कर लें, ताकि ट्रांसफ़र में कुछ खो न जाए।",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "डीप वर्क लंच से पहले करते हैं; दोपहर बाद का समय मीटिंग और ईमेल के लिए रखते हैं।",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "सुबह 9 से दोपहर 12 बजे तक सबसे अच्छा फ़ोकस रहता है; सुबह का समय डीप वर्क के लिए बचाकर रखें।",
    "Reports to Alex; weekly 1:1 on Mondays.":
      "राहुल को रिपोर्ट करते हैं; हर सोमवार को साप्ताहिक 1:1।",
    "Prefers concise, direct updates — no filler.":
      "संक्षिप्त और सीधे अपडेट पसंद करते हैं, बिना लंबी भूमिका के।",
    "Shipping the Apple-native rewrite this quarter.":
      "इस तिमाही Apple नेटिव रीराइट रिलीज़ होना है।",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "हफ़्ते की समीक्षा की और अगले हफ़्ते की ऑफ़साइट प्लानिंग सेट कर ली।",
    "Cleared the inbox and locked in the offsite dates.":
      "इनबॉक्स ख़ाली किया और ऑफ़साइट की तारीख़ें पक्की कर लीं।",
    "Still waiting on venue quotes before booking.":
      "बुकिंग से पहले वेन्यू के कोटेशन का इंतज़ार है।",
    "Batching errands into one afternoon freed up the rest of the week.":
      "सारे छोटे-मोटे काम एक ही दोपहर में निपटा दिए, तो बाक़ी हफ़्ता ख़ाली हो गया।",
    "Solid morning of deep work; shipped the planning review.":
      "सुबह का डीप वर्क बढ़िया रहा; प्लानिंग की समीक्षा पूरी हो गई।",
    "Unblocked the sync layer; cleared the investor email.":
      "सिंक लेयर की बाधा दूर की; निवेशकों के ईमेल का जवाब भी दे दिया।",
    "Waiting on design sign-off for the calendar grid.":
      "कैलेंडर ग्रिड के डिज़ाइन की मंज़ूरी का इंतज़ार है।",
    "Batching reviews before noon keeps the afternoon open.":
      "समीक्षाएँ दोपहर से पहले एक साथ निपटाने से दोपहर बाद का समय ख़ाली रहता है।",
    "Steady progress across tasks.": "सभी कार्यों में लगातार प्रगति।",
    "Closed a few items.": "कुछ कार्य निपटाए।",
  ]
}
