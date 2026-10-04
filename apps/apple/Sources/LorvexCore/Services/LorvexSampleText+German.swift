extension LorvexSampleText {
  /// The sample datasets in German. People are Jonas (Sam), Lukas (Alex), and
  /// Lena (Maya) in every dataset; product names (Zoom, Swift, GRPO, Apple)
  /// and Q3 stay as written. The offsite is a Teamklausur, and the car chore
  /// is the TÜV, the periodic vehicle inspection. Task titles are infinitive
  /// phrases, the way German to-do lists read; the briefings and reviews use
  /// first-person verbs that carry no gender.
  static let german: [String: String] = [
    // Tags.
    "work": "Arbeit",
    "planning": "Planung",
    "weekly": "wöchentlich",
    "home": "Zuhause",
    "urgent": "dringend",
    "engineering": "Entwicklung",
    "research": "Recherche",
    "someday": "irgendwann",

    // Lists.
    "Apple Native": "Apple-Ökosystem",
    "Apple ecosystem apps and gear to try":
      "Apps und Geräte aus dem Apple-Ökosystem zum Ausprobieren",
    "Work": "Arbeit",
    "Day job & deep work": "Tagesgeschäft & konzentriertes Arbeiten",
    "Personal": "Privat",
    "Reading": "Lesen",
    "Papers & books": "Paper & Bücher",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Agenda für die Teamklausur entwerfen",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Sessions einplanen, eine Keynote auswählen und Zeit für Workshops lassen.",
    "Confirm session topics with the leads":
      "Themen der Sessions mit den Verantwortlichen abstimmen",
    "Share the draft agenda for feedback": "Agendaentwurf für Feedback teilen",
    "Book the offsite venue": "Tagungsort für die Teamklausur buchen",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "Die beiden in die engere Wahl gekommenen Orte vergleichen und den reservieren, der zur Gruppe passt.",
    "Send the weekly status update": "Wöchentliches Status-Update senden",
    "Summarize progress, blockers, and next steps for the team.":
      "Fortschritte, Blocker und nächste Schritte für das Team zusammenfassen.",
    "Look into a standing-desk setup": "Höhenverstellbare Schreibtische recherchieren",
    "Keep this as a someday idea until the home office is sorted.":
      "Vorerst als Idee für irgendwann behalten, bis das Homeoffice eingerichtet ist.",
    "Pick the offsite dates": "Termine für die Teamklausur festlegen",
    "Cross-check the team calendar and lock the week.":
      "Mit dem Teamkalender abgleichen und die Woche fest einplanen.",
    "Order a second monitor": "Zweiten Monitor bestellen",
    "Dropped in favour of using the laptop display on the desk.":
      "Verworfen zugunsten des Laptop-Displays auf dem Schreibtisch.",
    "Renew the car registration": "Auto zum TÜV bringen",
    "Reply to Maya about the catering quote": "Lena zum Catering-Angebot antworten",
    "Review the Q3 budget draft": "Budgetentwurf für Q3 prüfen",
    "Outline the board deck": "Präsentation für das Board skizzieren",
    "Draft the hiring plan": "Recruiting-Plan entwerfen",
    "Reply to the investor update email": "E-Mail zum Investoren-Update beantworten",
    "Review the Q3 planning doc": "Q3-Planung durchgehen",
    "Refactor the sync layer": "Sync-Schicht refaktorieren",
    "Buy groceries for the week": "Lebensmittel für die Woche einkaufen",
    "Read the GRPO paper": "GRPO-Paper lesen",
    "Renew passport": "Reisepass verlängern",
    "Plan the spring offsite": "Teamklausur im Frühjahr planen",
    "Submit the weekly timesheet": "Wöchentliche Zeiterfassung einreichen",
    "Book the dentist appointment": "Zahnarzttermin vereinbaren",
    "Review the launch checklist": "Launch-Checkliste durchgehen",

    // Deferral notes.
    "The agenda comes first": "Zuerst die Agenda",
    "Groceries can wait for the evening": "Der Einkauf kann bis zum Abend warten",

    // Habits and their cues.
    "Daily Review": "Tagesrückblick",
    "End of day": "Am Ende des Tages",
    "Evening walk": "Abendspaziergang",
    "After dinner": "Nach dem Abendessen",
    "Morning run": "Morgenlauf",
    "After waking up": "Nach dem Aufwachen",
    "Read 30 minutes": "30 Minuten lesen",
    "Read 30 min": "30 Min. lesen",
    "Before bed": "Vor dem Schlafengehen",
    "Meditate": "Meditieren",
    "Mid-morning": "Am Vormittag",
    "Review the day": "Rückblick auf den Tag",
    "Evening": "Abends",
    "Evening journal": "Abendjournal",

    // Calendar events and locations.
    "Swift migration review": "Review der Swift-Migration",
    "Conference Room B": "Konferenzraum B",
    "Team standup": "Team-Daily",
    "1:1 with Sam": "1:1 mit Jonas",
    "Design review": "Design-Review",
    "Studio": "Studio",
    "Sprint planning": "Sprint-Planung",
    "Lunch with Sam": "Mittagessen mit Jonas",
    "1:1 with Alex": "1:1 mit Lukas",
    "Customer call": "Kundengespräch",
    "Dentist": "Zahnarzt",
    "Roadmap sync": "Roadmap-Abstimmung",
    "Morning gym": "Morgensport",
    "Demo day": "Demo-Tag",
    "Team offsite": "Teamklausur",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "Zuerst die Agenda der Teamklausur: Der Tagungsort lässt sich erst buchen, wenn sie steht, deshalb habe ich die Buchung auf morgen verschoben. Heute Nachmittag stehen zwei Meetings an.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "Zuerst die Q3-Planung durchgehen, solange sie noch frisch ist; die Refaktorierung der Sync-Schicht bekommt den langen Block vor dem Mittagessen.",
    "The launch checklist first; the status update after the design review.":
      "Zuerst die Launch-Checkliste; das Status-Update nach dem Design-Review.",

    // Memory.
    "notes_for_ai": "Notizen für die KI",
    "new_laptop": "Neuer Laptop",
    "work_rhythm": "Arbeitsrhythmus",
    "working_hours": "Arbeitszeiten",
    "manager": "Vorgesetzter",
    "writing_style": "Schreibstil",
    "current_focus": "Aktueller Fokus",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "Der Nutzer wägt für ein privates Nebenprojekt ein paar UI-Frameworks ab – technische Vorschläge frameworkneutral halten.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Vor dem Wechsel des Laptops die Datenbank und die Fotomediathek exportieren, damit beim Umzug nichts verloren geht.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Arbeitet vor dem Mittagessen konzentriert und hält die Nachmittage für Meetings und E-Mails frei.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "Kann sich von 9 bis 12 Uhr am besten konzentrieren; Vormittage für konzentriertes Arbeiten freihalten.",
    "Reports to Alex; weekly 1:1 on Mondays.": "Berichtet an Lukas; wöchentliches 1:1 montags.",
    "Prefers concise, direct updates — no filler.":
      "Bevorzugt knappe, direkte Updates – ohne Füllwörter.",
    "Shipping the Apple-native rewrite this quarter.":
      "Liefert in diesem Quartal die native Apple-Neuentwicklung aus.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "Woche durchgesehen und die Planung der Teamklausur für nächste Woche vorbereitet.",
    "Cleared the inbox and locked in the offsite dates.":
      "Eingang geleert und die Termine der Teamklausur festgelegt.",
    "Still waiting on venue quotes before booking.":
      "Warte noch auf die Angebote der Tagungsorte, bevor ich buche.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "Alle Besorgungen an einem Nachmittag zu bündeln hat den Rest der Woche freigemacht.",
    "Solid morning of deep work; shipped the planning review.":
      "Ein starker Vormittag mit konzentrierter Arbeit; die Prüfung des Planungsdokuments ist abgeschlossen.",
    "Unblocked the sync layer; cleared the investor email.":
      "Blockade in der Sync-Schicht gelöst; E-Mail an die Investoren erledigt.",
    "Waiting on design sign-off for the calendar grid.":
      "Warte auf die Design-Freigabe für das Kalenderraster.",
    "Batching reviews before noon keeps the afternoon open.":
      "Prüfungen vor dem Mittag zu bündeln hält den Nachmittag frei.",
    "Steady progress across tasks.": "Stetiger Fortschritt bei allen Aufgaben.",
    "Closed a few items.": "Ein paar Aufgaben abgeschlossen.",
  ]
}
