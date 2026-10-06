extension LorvexSampleText {
  /// The sample datasets in Telugu. People are సాయి (Sam), అజయ్ (Alex), and
  /// మాయ (Maya) in every dataset; product names (Swift, GRPO, Apple) stay as
  /// written, and Q3 is written మూడో త్రైమాసిక, the third quarter. Task titles
  /// are noun phrases ending in the verbal noun (చేయడం, పంపడం) or in a loanword
  /// noun, notes about the user use the honorific plural (చేస్తారు), and the
  /// briefings and reviews speak in the first person (చేశాను), which Telugu
  /// verbs do not mark for gender. A loanword that ends in a virama takes a
  /// zero-width non-joiner before a case ending (టాస్క్‌లు, ఆఫ్‌సైట్‌ను).
  static let telugu: [String: String] = [
    // Tags.
    "work": "పని",
    "planning": "ప్లానింగ్",
    "weekly": "వారంవారీ",
    "home": "ఇల్లు",
    "urgent": "అత్యవసరం",
    "engineering": "ఇంజినీరింగ్",
    "research": "పరిశోధన",
    "someday": "ఏదో ఒక రోజు",

    // Lists.
    "Apple Native": "Apple ఎకోసిస్టమ్",
    "Apple ecosystem apps and gear to try":
      "ప్రయత్నించి చూడాల్సిన Apple ఎకోసిస్టమ్ యాప్‌లు, పరికరాలు",
    "Work": "పని",
    "Day job & deep work": "ఉద్యోగం & ఏకాగ్రతతో చేసే పని",
    "Personal": "వ్యక్తిగతం",
    "Reading": "చదవడం",
    "Papers & books": "పరిశోధన పత్రాలు & పుస్తకాలు",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "టీమ్ ఆఫ్‌సైట్ ఎజెండా డ్రాఫ్ట్ చేయడం",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "సెషన్‌లకు సమయం కేటాయించడం, కీనోట్ ఎంచుకోవడం, చిన్న గ్రూప్ చర్చలకూ సమయం ఉంచడం.",
    "Confirm session topics with the leads": "టీమ్ లీడ్‌లతో సెషన్ అంశాలను నిర్ధారించడం",
    "Share the draft agenda for feedback": "ఫీడ్‌బ్యాక్ కోసం ఎజెండా డ్రాఫ్ట్‌ను షేర్ చేయడం",
    "Book the offsite venue": "ఆఫ్‌సైట్ వేదికను బుక్ చేయడం",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "షార్ట్‌లిస్ట్ చేసిన రెండు వేదికలను పోల్చి, గ్రూప్‌కు సరిపోయేదాన్ని బుక్ చేయడం.",
    "Send the weekly status update": "వారంవారీ స్టేటస్ అప్‌డేట్ పంపడం",
    "Summarize progress, blockers, and next steps for the team.":
      "టీమ్ కోసం ప్రోగ్రెస్, అడ్డంకులు, తదుపరి దశలను సంగ్రహించడం.",
    "Look into a standing-desk setup": "స్టాండింగ్ డెస్క్ సెటప్ గురించి పరిశీలించడం",
    "Keep this as a someday idea until the home office is sorted.":
      "హోమ్ ఆఫీస్ సర్దుకునే వరకు దీన్ని ‘ఏదో ఒక రోజు’ ఆలోచనగా ఉంచండి.",
    "Pick the offsite dates": "ఆఫ్‌సైట్ తేదీలను ఎంచుకోవడం",
    "Cross-check the team calendar and lock the week.":
      "టీమ్ క్యాలెండర్‌ను సరిచూసి, వారాన్ని ఖరారు చేయడం.",
    "Order a second monitor": "రెండో మానిటర్‌ను ఆర్డర్ చేయడం",
    "Dropped in favour of using the laptop display on the desk.":
      "రద్దు చేసారు; డెస్క్ మీద ల్యాప్‌టాప్ స్క్రీన్‌నే వాడతారు.",
    "Renew the car registration": "కారు రిజిస్ట్రేషన్ రెన్యూవల్",
    "Reply to Maya about the catering quote": "క్యాటరింగ్ కోట్ గురించి మాయకు రిప్లై ఇవ్వడం",
    "Review the Q3 budget draft": "మూడో త్రైమాసిక బడ్జెట్ డ్రాఫ్ట్‌ను సమీక్షించడం",
    "Outline the board deck": "బోర్డ్ ప్రజెంటేషన్ రూపురేఖలు రాయడం",
    "Draft the hiring plan": "నియామక ప్రణాళిక డ్రాఫ్ట్ చేయడం",
    "Reply to the investor update email": "ఇన్వెస్టర్ అప్‌డేట్ ఇమెయిల్‌కు రిప్లై ఇవ్వడం",
    "Review the Q3 planning doc": "మూడో త్రైమాసిక ప్లానింగ్ డాక్యుమెంట్‌ను సమీక్షించడం",
    "Refactor the sync layer": "సింక్ లేయర్‌ను రీఫ్యాక్టర్ చేయడం",
    "Buy groceries for the week": "ఈ వారానికి కిరాణా సరుకులు కొనడం",
    "Read the GRPO paper": "GRPO పరిశోధన పత్రం చదవడం",
    "Renew passport": "పాస్‌పోర్ట్ రెన్యూవల్",
    "Plan the spring offsite": "వసంతకాల ఆఫ్‌సైట్‌ను ప్లాన్ చేయడం",
    "Submit the weekly timesheet": "వారంవారీ టైమ్‌షీట్ సమర్పించడం",
    "Book the dentist appointment": "డెంటిస్ట్ అపాయింట్‌మెంట్ బుక్ చేయడం",
    "Review the launch checklist": "లాంచ్ చెక్‌లిస్ట్‌ను సమీక్షించడం",

    // Deferral notes.
    "The agenda comes first": "ముందు ఎజెండా",
    "Groceries can wait for the evening": "కిరాణా సరుకులు సాయంత్రం వరకు ఆగవచ్చు",

    // Habits and their cues.
    "Daily Review": "రోజువారీ సమీక్ష",
    "End of day": "రోజు చివరలో",
    "Evening walk": "సాయంత్రం నడక",
    "After dinner": "రాత్రి భోజనం తర్వాత",
    "Morning run": "ఉదయం పరుగు",
    "After waking up": "నిద్ర లేచిన తర్వాత",
    "Read 30 minutes": "30 నిమిషాలు చదవడం",
    "Read 30 min": "30 నిమిషాలు చదవడం",
    "Before bed": "పడుకునే ముందు",
    "Meditate": "ధ్యానం",
    "Mid-morning": "ఉదయం మధ్యలో",
    "Review the day": "రోజు సమీక్ష",
    "Evening": "సాయంత్రం",
    "Evening journal": "సాయంత్రం జర్నల్",

    // Calendar events and locations.
    "Swift migration review": "Swift మైగ్రేషన్ సమీక్ష",
    "Conference Room B": "కాన్ఫరెన్స్ రూమ్ B",
    "Team standup": "టీమ్ స్టాండప్",
    "1:1 with Sam": "సాయితో 1:1",
    "Design review": "డిజైన్ సమీక్ష",
    "Studio": "స్టూడియో",
    "Sprint planning": "స్ప్రింట్ ప్లానింగ్",
    "Lunch with Sam": "సాయితో మధ్యాహ్న భోజనం",
    "1:1 with Alex": "అజయ్‌తో 1:1",
    "Customer call": "కస్టమర్ కాల్",
    "Dentist": "డెంటిస్ట్",
    "Roadmap sync": "రోడ్‌మ్యాప్ సింక్",
    "Morning gym": "ఉదయం జిమ్",
    "Demo day": "డెమో డే",
    "Team offsite": "టీమ్ ఆఫ్‌సైట్",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "ముందు ఆఫ్‌సైట్ ఎజెండా: అది ఖరారయ్యే వరకు వేదికను బుక్ చేయలేరు, అందుకే బుకింగ్‌ను రేపటికి మార్చాను. ఈరోజు మధ్యాహ్నం రెండు మీటింగ్‌లు ఉన్నాయి.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "డాక్యుమెంట్ ఇంకా గుర్తున్నప్పుడే ముందు ప్లానింగ్ సమీక్ష; లంచ్‌కు ముందున్న పెద్ద బ్లాక్‌ను సింక్ రీఫ్యాక్టర్‌కు కేటాయించాను.",
    "The launch checklist first; the status update after the design review.":
      "ముందు లాంచ్ చెక్‌లిస్ట్; స్టేటస్ అప్‌డేట్ డిజైన్ సమీక్ష తర్వాత.",

    // Memory.
    "notes_for_ai": "AI కోసం నోట్స్",
    "new_laptop": "కొత్త ల్యాప్‌టాప్",
    "work_rhythm": "పని తీరు",
    "working_hours": "పని వేళలు",
    "manager": "మేనేజర్",
    "writing_style": "రాసే శైలి",
    "current_focus": "ప్రస్తుత ఫోకస్",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "యూజర్ ఒక వ్యక్తిగత సైడ్ ప్రాజెక్ట్ కోసం కొన్ని UI ఫ్రేమ్‌వర్క్‌లను పోల్చి చూస్తున్నారు – టెక్ సూచనలు ఏ ఫ్రేమ్‌వర్క్‌కూ అనుకూలంగా ఉండకూడదు.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "ల్యాప్‌టాప్ మార్చే ముందు డేటాబేస్‌ను, ఫోటో లైబ్రరీని ఎక్స్‌పోర్ట్ చేయండి, అప్పుడు మార్పులో ఏదీ పోదు.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "లంచ్‌కు ముందు ఏకాగ్రతతో పని చేస్తారు; మధ్యాహ్నాలను మీటింగ్‌లు, ఇమెయిల్ కోసం ఉంచుతారు.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "ఉదయం 9 నుండి మధ్యాహ్నం 12 వరకు ఏకాగ్రత బాగా కుదురుతుంది; ఉదయం వేళలను ఏకాగ్రతతో చేసే పనికి కేటాయించండి.",
    "Reports to Alex; weekly 1:1 on Mondays.":
      "అజయ్‌కు రిపోర్ట్ చేస్తారు; ప్రతి సోమవారం వారంవారీ 1:1.",
    "Prefers concise, direct updates — no filler.":
      "సంక్షిప్తంగా, నేరుగా ఉండే అప్‌డేట్‌లను ఇష్టపడతారు – అనవసరమైన మాటలు వద్దు.",
    "Shipping the Apple-native rewrite this quarter.":
      "ఈ త్రైమాసికంలో Apple నేటివ్ రీరైట్‌ను విడుదల చేస్తున్నారు.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "వారాన్ని సమీక్షించి, వచ్చే వారం ఆఫ్‌సైట్ ప్లానింగ్‌ను సిద్ధం చేశాను.",
    "Cleared the inbox and locked in the offsite dates.":
      "ఇన్‌బాక్స్‌ను ఖాళీ చేసి, ఆఫ్‌సైట్ తేదీలను ఖరారు చేశాను.",
    "Still waiting on venue quotes before booking.":
      "బుక్ చేసే ముందు వేదిక కోట్‌ల కోసం ఇంకా ఎదురు చూస్తున్నాను.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "చిన్న పనులన్నీ ఒకే మధ్యాహ్నం పూర్తి చేయడంతో వారంలో మిగతా సమయం ఖాళీ అయింది.",
    "Solid morning of deep work; shipped the planning review.":
      "ఉదయం ఏకాగ్రతతో బాగా పని జరిగింది; ప్లానింగ్ సమీక్ష పూర్తి చేశాను.",
    "Unblocked the sync layer; cleared the investor email.":
      "సింక్ లేయర్‌లోని అడ్డంకిని తొలగించాను; ఇన్వెస్టర్ ఇమెయిల్‌కు రిప్లై ఇచ్చాను.",
    "Waiting on design sign-off for the calendar grid.":
      "క్యాలెండర్ గ్రిడ్ డిజైన్ ఆమోదం కోసం ఎదురు చూస్తున్నాను.",
    "Batching reviews before noon keeps the afternoon open.":
      "సమీక్షలన్నీ మధ్యాహ్నానికి ముందే పూర్తి చేస్తే మధ్యాహ్నం ఖాళీగా ఉంటుంది.",
    "Steady progress across tasks.": "టాస్క్‌లన్నింటిలో స్థిరమైన పురోగతి.",
    "Closed a few items.": "కొన్ని ఐటెమ్‌లను పూర్తి చేశాను.",
  ]
}
