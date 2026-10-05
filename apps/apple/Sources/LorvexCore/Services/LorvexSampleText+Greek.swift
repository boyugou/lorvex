extension LorvexSampleText {
  /// The sample datasets in Greek. People are Νίκος (Sam), Αλέξης (Alex), and
  /// Μάγια (Maya) in every dataset, in the case each sentence needs; product
  /// names (Zoom, Swift, GRPO, Apple) and Q3 stay as written. The team offsite
  /// is a συνάντηση εκτός γραφείου, and the car chore is the ΚΤΕΟ, the periodic
  /// vehicle inspection. Task titles are verbal nouns, the way Greek to-do lists
  /// read; the reviews use first-person past-tense verbs, which Greek does not
  /// inflect for gender. The semicolon, which is Greek's question mark, never
  /// separates clauses, and the app's own terms (Εισερχόμενα, συγχρονισμός,
  /// λίστα ελέγχου) are the ones its catalogs use.
  static let greek: [String: String] = [
    // Tags.
    "work": "δουλειά",
    "planning": "προγραμματισμός",
    "weekly": "εβδομαδιαία",
    "home": "σπίτι",
    "urgent": "επείγον",
    "engineering": "ανάπτυξη",
    "research": "έρευνα",
    "someday": "κάποτε",

    // Lists.
    "Apple Native": "Οικοσύστημα Apple",
    "Apple ecosystem apps and gear to try":
      "Εφαρμογές και συσκευές του οικοσυστήματος Apple για δοκιμή",
    "Work": "Δουλειά",
    "Day job & deep work": "Βασική δουλειά και βαθιά εργασία",
    "Personal": "Προσωπικά",
    "Reading": "Διάβασμα",
    "Papers & books": "Επιστημονικά άρθρα και βιβλία",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Σύνταξη ατζέντας για τη συνάντηση εκτός γραφείου",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Προγραμματισμός συνεδριών, επιλογή κεντρικού ομιλητή και χρόνος για ομάδες εργασίας.",
    "Confirm session topics with the leads":
      "Επιβεβαίωση θεμάτων των συνεδριών με τους υπευθύνους",
    "Share the draft agenda for feedback":
      "Κοινοποίηση του προσχεδίου της ατζέντας για σχόλια",
    "Book the offsite venue": "Κράτηση χώρου για τη συνάντηση",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "Σύγκριση των δύο χώρων της τελικής λίστας και κράτηση αυτού που ταιριάζει στην ομάδα.",
    "Send the weekly status update": "Αποστολή της εβδομαδιαίας ενημέρωσης κατάστασης",
    "Summarize progress, blockers, and next steps for the team.":
      "Σύνοψη προόδου, εμποδίων και επόμενων βημάτων για την ομάδα.",
    "Look into a standing-desk setup": "Διερεύνηση για γραφείο όρθιας εργασίας",
    "Keep this as a someday idea until the home office is sorted.":
      "Παραμένει ιδέα για κάποτε μέχρι να οργανωθεί το γραφείο στο σπίτι.",
    "Pick the offsite dates": "Επιλογή ημερομηνιών για τη συνάντηση",
    "Cross-check the team calendar and lock the week.":
      "Έλεγχος με το ημερολόγιο της ομάδας και κλείδωμα της εβδομάδας.",
    "Order a second monitor": "Παραγγελία δεύτερης οθόνης",
    "Dropped in favour of using the laptop display on the desk.":
      "Ακυρώθηκε υπέρ της χρήσης της οθόνης του λάπτοπ στο γραφείο.",
    "Renew the car registration": "Ανανέωση ΚΤΕΟ αυτοκινήτου",
    "Reply to Maya about the catering quote":
      "Απάντηση στη Μάγια για την προσφορά του catering",
    "Review the Q3 budget draft": "Έλεγχος του προσχεδίου προϋπολογισμού για το Q3",
    "Outline the board deck": "Διάρθρωση της παρουσίασης για το διοικητικό συμβούλιο",
    "Draft the hiring plan": "Σύνταξη σχεδίου προσλήψεων",
    "Reply to the investor update email": "Απάντηση στο email ενημέρωσης επενδυτών",
    "Review the Q3 planning doc": "Έλεγχος του εγγράφου σχεδιασμού για το Q3",
    "Refactor the sync layer": "Αναδόμηση του επιπέδου συγχρονισμού",
    "Buy groceries for the week": "Αγορά τροφίμων για την εβδομάδα",
    "Read the GRPO paper": "Ανάγνωση της δημοσίευσης για το GRPO",
    "Renew passport": "Ανανέωση διαβατηρίου",
    "Plan the spring offsite": "Σχεδιασμός συνάντησης εκτός γραφείου για την άνοιξη",
    "Submit the weekly timesheet": "Υποβολή του εβδομαδιαίου δελτίου ωρών",
    "Book the dentist appointment": "Κλείσιμο ραντεβού με τον οδοντίατρο",
    "Review the launch checklist": "Έλεγχος της λίστας ελέγχου για την κυκλοφορία",

    // Deferral notes.
    "The agenda comes first": "Πρώτα η ατζέντα",
    "Groceries can wait for the evening": "Τα ψώνια μπορούν να περιμένουν μέχρι το βράδυ",

    // Habits and their cues.
    "Daily Review": "Ημερήσια ανασκόπηση",
    "End of day": "Στο τέλος της ημέρας",
    "Evening walk": "Βραδινός περίπατος",
    "After dinner": "Μετά το δείπνο",
    "Morning run": "Πρωινό τρέξιμο",
    "After waking up": "Μετά το ξύπνημα",
    "Read 30 minutes": "Διάβασμα 30 λεπτών",
    "Read 30 min": "Διάβασμα 30 λ.",
    "Before bed": "Πριν τον ύπνο",
    "Meditate": "Διαλογισμός",
    "Mid-morning": "Στα μέσα του πρωινού",
    "Review the day": "Ανασκόπηση της ημέρας",
    "Evening": "Βράδυ",
    "Evening journal": "Βραδινές σημειώσεις",

    // Calendar events and locations.
    "Swift migration review": "Ανασκόπηση μετάβασης στο Swift",
    "Conference Room B": "Αίθουσα συσκέψεων B",
    "Team standup": "Καθημερινή σύσκεψη ομάδας",
    "1:1 with Sam": "1:1 με τον Νίκο",
    "Design review": "Ανασκόπηση σχεδίασης",
    "Studio": "Στούντιο",
    "Sprint planning": "Σχεδιασμός sprint",
    "Lunch with Sam": "Μεσημεριανό με τον Νίκο",
    "1:1 with Alex": "1:1 με τον Αλέξη",
    "Customer call": "Κλήση με πελάτη",
    "Dentist": "Οδοντίατρος",
    "Roadmap sync": "Συντονισμός για το roadmap",
    "Morning gym": "Πρωινό γυμναστήριο",
    "Demo day": "Ημέρα επίδειξης",
    "Team offsite": "Συνάντηση ομάδας εκτός γραφείου",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "Πρώτα η ατζέντα της συνάντησης: ο χώρος δεν μπορεί να κρατηθεί πριν οριστικοποιηθεί, γι’ αυτό μετέφερα την κράτηση για αύριο. Δύο συσκέψεις σήμερα το απόγευμα.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "Πρώτα ο έλεγχος του σχεδιασμού όσο το έγγραφο είναι φρέσκο, και η αναδόμηση του επιπέδου συγχρονισμού παίρνει το μεγάλο μπλοκ πριν το μεσημεριανό.",
    "The launch checklist first; the status update after the design review.":
      "Πρώτα η λίστα ελέγχου για την κυκλοφορία, και η ενημέρωση κατάστασης μετά την ανασκόπηση σχεδίασης.",

    // Memory.
    "notes_for_ai": "Σημειώσεις για την AI",
    "new_laptop": "Νέο λάπτοπ",
    "work_rhythm": "Ρυθμός εργασίας",
    "working_hours": "Ώρες εργασίας",
    "manager": "Προϊστάμενος",
    "writing_style": "Ύφος γραφής",
    "current_focus": "Τρέχουσα εστίαση",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "Ο χρήστης σκέφτεται μερικά frameworks UI για ένα προσωπικό παράπλευρο project — οι τεχνικές προτάσεις να μην ευνοούν κάποιο framework.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Πριν αλλάξεις λάπτοπ, εξήγαγε τη βάση δεδομένων και τη βιβλιοθήκη φωτογραφιών, ώστε να μη χαθεί τίποτα κατά τη μεταφορά.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Κάνει βαθιά εργασία πριν το μεσημεριανό και κρατά τα απογεύματα για συσκέψεις και email.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "Συγκεντρώνεται καλύτερα από τις 9:00 έως τις 12:00. Φύλαξε τα πρωινά για βαθιά εργασία.",
    "Reports to Alex; weekly 1:1 on Mondays.":
      "Αναφέρεται στον Αλέξη, με εβδομαδιαίο 1:1 τις Δευτέρες.",
    "Prefers concise, direct updates — no filler.":
      "Προτιμά σύντομες, άμεσες ενημερώσεις — χωρίς περιττά λόγια.",
    "Shipping the Apple-native rewrite this quarter.":
      "Κυκλοφορεί αυτό το τρίμηνο τη νέα, εξ ολοκλήρου native έκδοση για Apple.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "Ανασκόπησα την εβδομάδα και ετοίμασα τον σχεδιασμό της συνάντησης της επόμενης εβδομάδας.",
    "Cleared the inbox and locked in the offsite dates.":
      "Άδειασα τα Εισερχόμενα και κλείδωσα τις ημερομηνίες της συνάντησης.",
    "Still waiting on venue quotes before booking.":
      "Περιμένω ακόμη τις προσφορές των χώρων πριν κάνω κράτηση.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "Η συγκέντρωση των θεμάτων σε ένα απόγευμα ελευθέρωσε την υπόλοιπη εβδομάδα.",
    "Solid morning of deep work; shipped the planning review.":
      "Δυνατό πρωινό βαθιάς εργασίας, και ολοκλήρωσα τον έλεγχο του σχεδιασμού.",
    "Unblocked the sync layer; cleared the investor email.":
      "Ξεμπλόκαρα το επίπεδο συγχρονισμού και απάντησα στο email των επενδυτών.",
    "Waiting on design sign-off for the calendar grid.":
      "Περιμένω την έγκριση σχεδίασης για το πλέγμα του ημερολογίου.",
    "Batching reviews before noon keeps the afternoon open.":
      "Η ομαδοποίηση των ελέγχων πριν το μεσημέρι κρατά το απόγευμα ελεύθερο.",
    "Steady progress across tasks.": "Σταθερή πρόοδος σε όλες τις εργασίες.",
    "Closed a few items.": "Έκλεισα μερικά θέματα.",
  ]
}
