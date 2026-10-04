extension LorvexSampleText {
  /// The sample datasets in Dutch. People are Daan (Sam), Bram (Alex), and
  /// Sanne (Maya) in every dataset; product names (Zoom, Swift, GRPO, Apple)
  /// and Q3 stay as written. The offsite is a teamheidag, and the car chore
  /// is the APK, the periodic vehicle inspection. Task titles are infinitive
  /// phrases, the way Dutch to-do lists read.
  static let dutch: [String: String] = [
    // Tags.
    "work": "werk",
    "planning": "planning",
    "weekly": "wekelijks",
    "home": "thuis",
    "urgent": "urgent",
    "engineering": "development",
    "research": "onderzoek",
    "someday": "ooit",

    // Lists.
    "Apple Native": "Apple-ecosysteem",
    "Apple ecosystem apps and gear to try":
      "Apps en apparaten uit het Apple-ecosysteem om uit te proberen",
    "Work": "Werk",
    "Day job & deep work": "Dagelijks werk & geconcentreerd werken",
    "Personal": "Persoonlijk",
    "Reading": "Lezen",
    "Papers & books": "Artikelen & boeken",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Agenda voor de teamheidag opstellen",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Sessies inplannen, een keynote kiezen en ruimte laten voor werksessies.",
    "Confirm session topics with the leads": "Sessieonderwerpen afstemmen met de teamleads",
    "Share the draft agenda for feedback": "Conceptagenda delen voor feedback",
    "Book the offsite venue": "Locatie voor de teamheidag boeken",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "De twee geselecteerde locaties vergelijken en de locatie reserveren die bij de groep past.",
    "Send the weekly status update": "Wekelijkse statusupdate versturen",
    "Summarize progress, blockers, and next steps for the team.":
      "Voortgang, blokkades en volgende stappen voor het team samenvatten.",
    "Look into a standing-desk setup": "Zit-sta-bureaus uitzoeken",
    "Keep this as a someday idea until the home office is sorted.":
      "Voorlopig bewaren als idee voor ooit, totdat de thuiswerkplek is ingericht.",
    "Pick the offsite dates": "Data voor de teamheidag kiezen",
    "Cross-check the team calendar and lock the week.":
      "De teamagenda controleren en de week vastzetten.",
    "Order a second monitor": "Tweede monitor bestellen",
    "Dropped in favour of using the laptop display on the desk.":
      "Geschrapt ten gunste van het laptopscherm op het bureau.",
    "Renew the car registration": "APK voor de auto regelen",
    "Reply to Maya about the catering quote": "Sanne antwoorden over de offerte van de catering",
    "Review the Q3 budget draft": "Conceptbudget voor Q3 nakijken",
    "Outline the board deck": "Presentatie voor het bestuur schetsen",
    "Draft the hiring plan": "Wervingsplan opstellen",
    "Reply to the investor update email": "De e-mail met de investeerdersupdate beantwoorden",
    "Review the Q3 planning doc": "Q3-plan doornemen",
    "Refactor the sync layer": "Synclaag refactoren",
    "Buy groceries for the week": "Boodschappen voor de week doen",
    "Read the GRPO paper": "Het GRPO-artikel lezen",
    "Renew passport": "Paspoort verlengen",
    "Plan the spring offsite": "Teamheidag in het voorjaar plannen",
    "Submit the weekly timesheet": "Wekelijkse urenstaat indienen",
    "Book the dentist appointment": "Tandartsafspraak maken",
    "Review the launch checklist": "Checklist voor de lancering doornemen",

    // Deferral notes.
    "The agenda comes first": "Eerst de agenda",
    "Groceries can wait for the evening": "De boodschappen kunnen tot vanavond wachten",

    // Habits and their cues.
    "Daily Review": "Dagterugblik",
    "End of day": "Aan het einde van de dag",
    "Evening walk": "Avondwandeling",
    "After dinner": "Na het avondeten",
    "Morning run": "Ochtendloop",
    "After waking up": "Na het wakker worden",
    "Read 30 minutes": "30 minuten lezen",
    "Read 30 min": "30 min lezen",
    "Before bed": "Voor het slapengaan",
    "Meditate": "Mediteren",
    "Mid-morning": "Halverwege de ochtend",
    "Review the day": "Terugblik op de dag",
    "Evening": "’s Avonds",
    "Evening journal": "Avonddagboek",

    // Calendar events and locations.
    "Swift migration review": "Review van de Swift-migratie",
    "Conference Room B": "Vergaderruimte B",
    "Team standup": "Stand-up van het team",
    "1:1 with Sam": "1-op-1 met Daan",
    "Design review": "Designreview",
    "Studio": "Studio",
    "Sprint planning": "Sprintplanning",
    "Lunch with Sam": "Lunch met Daan",
    "1:1 with Alex": "1-op-1 met Bram",
    "Customer call": "Klantgesprek",
    "Dentist": "Tandarts",
    "Roadmap sync": "Roadmapoverleg",
    "Morning gym": "Ochtendsport",
    "Demo day": "Demodag",
    "Team offsite": "Teamheidag",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "Eerst de agenda van de teamheidag: de locatie kan pas worden geboekt als die vaststaat, dus ik heb de boeking naar morgen verplaatst. Vanmiddag zijn er twee vergaderingen.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "Eerst het doornemen van het Q3-plan, nu het nog vers is; de refactoring van de synclaag krijgt het lange blok voor de lunch.",
    "The launch checklist first; the status update after the design review.":
      "Eerst de checklist voor de lancering; de statusupdate na de designreview.",

    // Memory.
    "notes_for_ai": "Notities voor de AI",
    "new_laptop": "Nieuwe laptop",
    "work_rhythm": "Werkritme",
    "working_hours": "Werktijden",
    "manager": "Leidinggevende",
    "writing_style": "Schrijfstijl",
    "current_focus": "Huidige focus",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "De gebruiker overweegt een paar UI-frameworks voor een persoonlijk nevenproject – technische suggesties framework-neutraal houden.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Bij het overstappen op een andere laptop eerst de database en de fotobibliotheek exporteren, zodat er niets verloren gaat.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Werkt geconcentreerd voor de lunch en houdt de middagen vrij voor vergaderingen en e-mail.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "Concentreert zich het best van 9 tot 12 uur; ochtenden vrijhouden voor geconcentreerd werk.",
    "Reports to Alex; weekly 1:1 on Mondays.": "Rapporteert aan Bram; wekelijks 1-op-1 op maandag.",
    "Prefers concise, direct updates — no filler.":
      "Geeft de voorkeur aan beknopte, directe updates – zonder omhaal.",
    "Shipping the Apple-native rewrite this quarter.":
      "Levert dit kwartaal de Apple-native herschrijving op.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "De week doorgenomen en de planning voor de heidag van volgende week voorbereid.",
    "Cleared the inbox and locked in the offsite dates.":
      "Inkomend leeggemaakt en de data voor de heidag vastgelegd.",
    "Still waiting on venue quotes before booking.":
      "Ik wacht nog op offertes van de locaties voordat ik boek.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "Alle klusjes op één middag bundelen maakte de rest van de week vrij.",
    "Solid morning of deep work; shipped the planning review.":
      "Een sterke ochtend geconcentreerd werk; het Q3-plan is doorgenomen.",
    "Unblocked the sync layer; cleared the investor email.":
      "De blokkade in de synclaag opgelost; de e-mail aan de investeerders afgehandeld.",
    "Waiting on design sign-off for the calendar grid.":
      "Wachten op de designgoedkeuring voor het kalenderraster.",
    "Batching reviews before noon keeps the afternoon open.":
      "Alle reviews vóór de middag bundelen houdt de middag vrij.",
    "Steady progress across tasks.": "Gestage voortgang bij alle taken.",
    "Closed a few items.": "Een paar taken afgerond.",
  ]
}
