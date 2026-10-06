extension LorvexSampleText {
  /// The sample datasets in Tamil. People are சரண் (Sam), அருண் (Alex), and
  /// மாயா (Maya) in every dataset; product names (Swift, GRPO, Apple) stay as
  /// written, and Q3 is written மூன்றாம் காலாண்டு, the third quarter. Task
  /// titles are noun phrases ending in the verbal noun (செய்தல், அனுப்புதல்),
  /// notes about the user use the honorific third person (செய்கிறார்), and the
  /// briefings and reviews speak in the first person (செய்தேன்), which Tamil
  /// verbs do not mark for gender.
  static let tamil: [String: String] = [
    // Tags.
    "work": "வேலை",
    "planning": "திட்டமிடல்",
    "weekly": "வாரந்தோறும்",
    "home": "வீடு",
    "urgent": "அவசரம்",
    "engineering": "பொறியியல்",
    "research": "ஆராய்ச்சி",
    "someday": "என்றாவது ஒரு நாள்",

    // Lists.
    "Apple Native": "Apple சூழலமைப்பு",
    "Apple ecosystem apps and gear to try":
      "முயன்று பார்க்க வேண்டிய Apple சூழலமைப்புச் செயலிகளும் சாதனங்களும்",
    "Work": "வேலை",
    "Day job & deep work": "முழுநேர வேலை & ஆழ்ந்த வேலை",
    "Personal": "தனிப்பட்டவை",
    "Reading": "வாசிப்பு",
    "Papers & books": "ஆய்வுக் கட்டுரைகளும் புத்தகங்களும்",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "குழு ஆஃப்சைட் நிகழ்ச்சி நிரல் வரைவைத் தயாரித்தல்",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "அமர்வுகளுக்கு நேரம் ஒதுக்கி, முக்கிய உரையைத் தேர்ந்தெடுத்து, சிறு குழு விவாதங்களுக்கும் நேரம் விடவும்.",
    "Confirm session topics with the leads": "குழுத் தலைவர்களுடன் அமர்வுத் தலைப்புகளை உறுதிசெய்தல்",
    "Share the draft agenda for feedback": "கருத்துகளுக்காக நிகழ்ச்சி நிரல் வரைவைப் பகிர்தல்",
    "Book the offsite venue": "ஆஃப்சைட் இடத்தை முன்பதிவு செய்தல்",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "தேர்வுப் பட்டியலில் உள்ள இரண்டு இடங்களை ஒப்பிட்டு, குழுவுக்குப் பொருத்தமானதை முன்பதிவு செய்தல்.",
    "Send the weekly status update": "வாராந்தர நிலைப் புதுப்பிப்பை அனுப்புதல்",
    "Summarize progress, blockers, and next steps for the team.":
      "குழுவுக்காக முன்னேற்றம், தடைகள், அடுத்த படிகளைச் சுருக்கமாக எழுதுதல்.",
    "Look into a standing-desk setup": "நின்றபடி வேலை செய்யும் மேசை அமைப்பைப் பற்றி விசாரித்தல்",
    "Keep this as a someday idea until the home office is sorted.":
      "வீட்டு அலுவலகம் தயாராகும் வரை இதை ‘என்றாவது ஒரு நாள்’ யோசனையாக வைத்திருக்கவும்.",
    "Pick the offsite dates": "ஆஃப்சைட் தேதிகளைத் தேர்ந்தெடுத்தல்",
    "Cross-check the team calendar and lock the week.":
      "குழு கேலண்டரைச் சரிபார்த்து, வாரத்தை உறுதிசெய்தல்.",
    "Order a second monitor": "இரண்டாவது மானிட்டரை ஆர்டர் செய்தல்",
    "Dropped in favour of using the laptop display on the desk.":
      "ரத்துசெய்யப்பட்டது; மேசையில் லேப்டாப் திரையையே பயன்படுத்துவார்.",
    "Renew the car registration": "காரின் பதிவைப் புதுப்பித்தல்",
    "Reply to Maya about the catering quote": "கேட்டரிங் விலைப்புள்ளி பற்றி மாயாவுக்குப் பதிலளித்தல்",
    "Review the Q3 budget draft": "மூன்றாம் காலாண்டு பட்ஜெட் வரைவை மதிப்பாய்வு செய்தல்",
    "Outline the board deck": "இயக்குநர் குழு விளக்கக்காட்சியின் வரைவுரையைத் தயாரித்தல்",
    "Draft the hiring plan": "ஆட்சேர்ப்புத் திட்டத்தை வரைதல்",
    "Reply to the investor update email": "முதலீட்டாளர் புதுப்பிப்பு மின்னஞ்சலுக்குப் பதிலளித்தல்",
    "Review the Q3 planning doc": "மூன்றாம் காலாண்டு திட்டமிடல் ஆவணத்தை மதிப்பாய்வு செய்தல்",
    "Refactor the sync layer": "ஒத்திசைவு லேயரை ரீஃபேக்டர் செய்தல்",
    "Buy groceries for the week": "இந்த வாரத்துக்கான மளிகைப் பொருட்களை வாங்குதல்",
    "Read the GRPO paper": "GRPO ஆய்வுக் கட்டுரையைப் படித்தல்",
    "Renew passport": "பாஸ்போர்ட் புதுப்பித்தல்",
    "Plan the spring offsite": "வசந்தகால ஆஃப்சைட்டைத் திட்டமிடுதல்",
    "Submit the weekly timesheet": "வாராந்தர நேரப் பதிவேட்டைச் சமர்ப்பித்தல்",
    "Book the dentist appointment": "பல் மருத்துவர் சந்திப்பை முன்பதிவு செய்தல்",
    "Review the launch checklist": "வெளியீட்டுச் சரிபார்ப்புப் பட்டியலை மதிப்பாய்வு செய்தல்",

    // Deferral notes.
    "The agenda comes first": "முதலில் நிகழ்ச்சி நிரல்",
    "Groceries can wait for the evening": "மளிகைப் பொருட்களை மாலை வரை தள்ளிப்போடலாம்",

    // Habits and their cues.
    "Daily Review": "தினசரி மீள்பார்வை",
    "End of day": "நாளின் இறுதியில்",
    "Evening walk": "மாலை நடை",
    "After dinner": "இரவு உணவுக்குப் பிறகு",
    "Morning run": "காலை ஓட்டம்",
    "After waking up": "தூங்கி எழுந்த பிறகு",
    "Read 30 minutes": "30 நிமிடம் வாசிப்பு",
    "Read 30 min": "30 நிமிடம் வாசிப்பு",
    "Before bed": "தூங்கச் செல்லும் முன்",
    "Meditate": "தியானம்",
    "Mid-morning": "முற்பகல்",
    "Review the day": "நாள் மீள்பார்வை",
    "Evening": "மாலை",
    "Evening journal": "மாலை ஜர்னல்",

    // Calendar events and locations.
    "Swift migration review": "Swift மைக்ரேஷன் மதிப்பாய்வு",
    "Conference Room B": "கான்ஃபரன்ஸ் அறை B",
    "Team standup": "குழு ஸ்டாண்டப்",
    "1:1 with Sam": "சரணுடன் 1:1",
    "Design review": "வடிவமைப்பு மதிப்பாய்வு",
    "Studio": "ஸ்டுடியோ",
    "Sprint planning": "ஸ்பிரின்ட் திட்டமிடல்",
    "Lunch with Sam": "சரணுடன் மதிய உணவு",
    "1:1 with Alex": "அருணுடன் 1:1",
    "Customer call": "வாடிக்கையாளர் அழைப்பு",
    "Dentist": "பல் மருத்துவர்",
    "Roadmap sync": "ரோட்மேப் ஒத்திசைவு",
    "Morning gym": "காலை ஜிம்",
    "Demo day": "டெமோ நாள்",
    "Team offsite": "குழு ஆஃப்சைட்",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "முதலில் ஆஃப்சைட் நிகழ்ச்சி நிரல்: அது உறுதியாகும் வரை இடத்தை முன்பதிவு செய்ய முடியாது, அதனால் முன்பதிவை நாளைக்கு மாற்றிவிட்டேன். இன்று மதியம் இரண்டு மீட்டிங்குகள் உள்ளன.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "ஆவணம் இன்னும் நினைவில் இருக்கும்போதே முதலில் திட்டமிடல் மதிப்பாய்வு; மதிய உணவுக்கு முன் உள்ள நீண்ட நேரத் தொகுதியை ஒத்திசைவு ரீஃபேக்டருக்கு ஒதுக்கியுள்ளேன்.",
    "The launch checklist first; the status update after the design review.":
      "முதலில் வெளியீட்டுச் சரிபார்ப்புப் பட்டியல்; நிலைப் புதுப்பிப்பு வடிவமைப்பு மதிப்பாய்வுக்குப் பிறகு.",

    // Memory.
    "notes_for_ai": "AIக்கான குறிப்புகள்",
    "new_laptop": "புதிய லேப்டாப்",
    "work_rhythm": "வேலை முறை",
    "working_hours": "வேலை நேரம்",
    "manager": "மேலாளர்",
    "writing_style": "எழுத்து நடை",
    "current_focus": "தற்போதைய கவனம்",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "பயனர் ஒரு தனிப்பட்ட பக்கத் திட்டப்பணிக்காகச் சில UI ஃப்ரேம்வொர்க்குகளை ஒப்பிட்டுப் பார்க்கிறார் – தொழில்நுட்பப் பரிந்துரைகள் எந்த ஃப்ரேம்வொர்க்கையும் சாராமல் இருக்க வேண்டும்.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "லேப்டாப்பை மாற்றுவதற்கு முன் தரவுத்தளத்தையும் புகைப்பட லைப்ரரியையும் எக்ஸ்போர்ட் செய்யவும்; அப்போது இடமாற்றத்தில் எதுவும் தொலையாது.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "மதிய உணவுக்கு முன் ஆழ்ந்த வேலை செய்கிறார்; பிற்பகலைக் கூட்டங்களுக்கும் மின்னஞ்சலுக்கும் ஒதுக்குகிறார்.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "காலை 9 முதல் மதியம் 12 வரை நன்றாகக் கவனம் செலுத்த முடியும்; காலை நேரத்தை ஆழ்ந்த வேலைக்காக ஒதுக்கி வைக்கவும்.",
    "Reports to Alex; weekly 1:1 on Mondays.":
      "அருணிடம் அறிக்கை அளிக்கிறார்; திங்கள்தோறும் வாராந்தர 1:1.",
    "Prefers concise, direct updates — no filler.":
      "சுருக்கமான, நேரடியான புதுப்பிப்புகளை விரும்புகிறார் – தேவையற்ற பேச்சு வேண்டாம்.",
    "Shipping the Apple-native rewrite this quarter.":
      "இந்தக் காலாண்டில் Apple நேட்டிவ் மறுஎழுத்துப் பதிப்பை வெளியிடுகிறார்.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "வாரத்தை மீள்பார்வை செய்து, அடுத்த வாரத்தின் ஆஃப்சைட் திட்டமிடலை ஒழுங்குபடுத்தினேன்.",
    "Cleared the inbox and locked in the offsite dates.":
      "இன்பாக்ஸைக் காலியாக்கி, ஆஃப்சைட் தேதிகளை உறுதிசெய்தேன்.",
    "Still waiting on venue quotes before booking.":
      "முன்பதிவுக்கு முன் இடங்களின் விலைப்புள்ளிகளுக்காக இன்னும் காத்திருக்கிறேன்.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "சிறு வேலைகளை ஒரே பிற்பகலில் முடித்ததால் வாரத்தின் மீதி நேரம் காலியானது.",
    "Solid morning of deep work; shipped the planning review.":
      "காலையில் ஆழ்ந்த வேலை சிறப்பாக நடந்தது; திட்டமிடல் மதிப்பாய்வை முடித்தேன்.",
    "Unblocked the sync layer; cleared the investor email.":
      "ஒத்திசைவு லேயரின் தடையை நீக்கினேன்; முதலீட்டாளர் மின்னஞ்சலுக்குப் பதிலளித்தேன்.",
    "Waiting on design sign-off for the calendar grid.":
      "கேலண்டர் கிரிட்டின் வடிவமைப்பு ஒப்புதலுக்காகக் காத்திருக்கிறேன்.",
    "Batching reviews before noon keeps the afternoon open.":
      "மதிப்பாய்வுகளை மதியத்துக்கு முன் ஒன்றாக முடித்தால் பிற்பகல் காலியாக இருக்கும்.",
    "Steady progress across tasks.": "அனைத்துப் பணிகளிலும் சீரான முன்னேற்றம்.",
    "Closed a few items.": "சில ஐட்டங்களை முடித்தேன்.",
  ]
}
